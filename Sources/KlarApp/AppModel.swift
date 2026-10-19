import SwiftUI
import AppKit
import Combine
import KlarCore
import os

@MainActor
final class AppModel: ObservableObject {
    enum Phase: String { case disconnected, ready, clarifying, generating, validating, showingResult, practicing, interrupted, error }
    enum Page { case coach, history, laboratory, lessons, followUp, recipes }
    @Published var draft = "" { didSet { if !loadingStore { persistDraft() } } }
    @Published var phase: Phase = .disconnected
    @Published var page: Page = .coach
    @Published var showSettings = false
    /// Last chosen explanation view (map, grid, steps) and the navigation dial state.
    @Published var insightMode = "map"
    @Published var dockOpen = false
    @Published var response: CoachResponse? {
        didSet {
            guard oldValue != response else { return }
            // Smart default: fields start with values that follow from the user's own words.
            restoreInputValues()
        }
    }
    /// Answers to the generated fields, keyed by input id.
    @Published var inputValues: [String: String] = [:] {
        didSet {
            guard !restoringInputValues, oldValue != inputValues else { return }
            copied = false
            saveCurrent()
        }
    }
    /// The suggestion with every answered placeholder filled in.
    var displayedResponse: CoachResponse? { response.map { $0.filled(with: inputValues) } }
    var openRequiredInputs: [PromptInput] {
        (response?.inputs ?? []).filter { $0.required && (inputValues[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    @Published var submittedOriginal = ""
    @Published var editedPrompt = ""
    @Published var editing = false
    @Published var manuallyEdited = false
    @Published var clarificationAnswer = ""
    @Published var exerciseAnswer = ""
    @Published var exerciseFeedback = ""
    @Published var exerciseHelp = false
    @Published var showExercise = false
    @Published var solutionRevealed = false
    @Published var copied = false
    @Published var errorMessage: String?
    @Published var storageError: String?
    @Published var progressMessage = ""
    @Published var history: [HistoryEntry] = []
    @Published var fontSize: Double = UserDefaults.standard.object(forKey: "sinnfadenFontSize") as? Double ?? 17 { didSet { UserDefaults.standard.set(fontSize, forKey: "sinnfadenFontSize") } }
    let connection: ConnectionManager
    let learning: LearningWorkspace
    let diagnostics: DiagnosticsController
    let updates: UpdateController
    let handoff = ChatGPTHandoff()
    let isDemo: Bool
    private var store: HistoryStore?
    private let storageBaseURL: URL?
    private var loadingStore = false
    private var restoringInputValues = false
    private var task: Task<Void, Never>?
    private var activeAttempt: UUID?
    private var currentEntry: HistoryEntry?
    private var observedAccount = "local"
    private var subscriptions = Set<AnyCancellable>()
    private static let log = Logger(subsystem: "at.klar.promptcoach", category: "coach")

    init(isDemo: Bool = CommandLine.arguments.contains("--demo"), storageBaseURL: URL? = nil, connection suppliedConnection: ConnectionManager? = nil) {
        self.isDemo = isDemo
        self.storageBaseURL = storageBaseURL
        diagnostics = DiagnosticsController(isDemo: isDemo, storageBaseURL: storageBaseURL)
        updates = UpdateController(isDemo: isDemo)
        connection = suppliedConnection ?? ConnectionManager(restore: !isDemo)
        learning = LearningWorkspace(connection: connection, isDemo: isDemo, storageBaseURL: storageBaseURL)
        connection.onFailure = { [weak diagnostics] error in diagnostics?.record(error, area: .connection) }
        learning.onFailure = { [weak diagnostics] error, area in diagnostics?.record(error, area: area) }
        openStore(account: isDemo ? "demonstration" : "local")
        connection.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.objectWillChange.send()
                self.synchronizeAccount()
            }
        }.store(in: &subscriptions)
        if isDemo {
            // The demo starts like a real session: your words are ready, nothing is sent.
            draft = DemoContent.original
            phase = .ready
        }
    }

    var busy: Bool { phase == .generating || phase == .validating }
    var visiblePrompt: String { manuallyEdited || editing ? editedPrompt : (displayedResponse?.prompt ?? "") }
    var canSubmit: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.utf16.count <= CoachValidator.maximumInputLength && !busy }

    private func restoreInputValues(_ saved: [String: String]? = nil) {
        restoringInputValues = true
        defer { restoringInputValues = false }
        inputValues = saved ?? response?.suggestedInputValues ?? [:]
    }

    private func synchronizeAccount() {
        let account = isDemo ? "demonstration" : (connection.accountID ?? "local")
        guard observedAccount != account else { return }
        let anonymousDraft = observedAccount == "local" ? draft : nil
        cancel()
        response = nil; editedPrompt = ""; submittedOriginal = ""; currentEntry = nil
        showExercise = false; exerciseAnswer = ""; exerciseFeedback = ""; errorMessage = nil
        openStore(account: account)
        if draft.isEmpty, let anonymousDraft, !anonymousDraft.isEmpty { draft = anonymousDraft }
        phase = connection.canGenerate ? .ready : .disconnected
    }

    private func openStore(account: String) {
        observedAccount = account
        learning.switchAccount(account)
        loadingStore = true
        defer { loadingStore = false }
        store = nil; draft = ""; history = []
        do {
            let next = try HistoryStore(accountID: account, baseURL: storageBaseURL)
            draft = try next.loadDraft()
            history = try next.entries()
            store = next
            storageError = nil
        } catch { diagnostics.record(error, area: .history); storageError = "Deine lokalen Daten konnten nicht geöffnet werden. Sie wurden nicht überschrieben." }
    }

    private func persistDraft() {
        do { try store?.saveDraft(draft) }
        catch { diagnostics.record(error, area: .history); storageError = "Dein Entwurf konnte nicht lokal gespeichert werden. Bitte kopiere ihn, bevor du Sinnfaden schließt." }
    }

    func improve(clarification: Bool = false, skip: Bool = false) {
        guard canSubmit else { return }
        if isDemo { runDemo(); return }
        guard connection.canGenerate else { showSettings = true; return }
        var input = draft
        if clarification {
            let answer = skip ? "Diese optionale Angabe möchte ich offenlassen. Nutze einen erkennbaren Platzhalter." : clarificationAnswer
            guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            input = submittedOriginal + "\n\nRückfrage: " + (response?.clarification?.question ?? "") + "\nMeine Ergänzung: " + answer
        }
        guard input.utf16.count <= CoachValidator.maximumInputLength else {
            errorMessage = "Dein Prompt mit Ergänzung ist zu lang. Kürze ihn bitte vor dem nächsten Versuch. Deine Eingabe bleibt erhalten."
            return
        }
        // The composed text remains visible and is the exact input for any later retry.
        if clarification { draft = input }
        task?.cancel()
        let id = UUID()
        activeAttempt = id
        submittedOriginal = input
        errorMessage = nil; response = nil; editing = false; manuallyEdited = false
        showExercise = false; exerciseAnswer = ""; exerciseFeedback = ""; exerciseHelp = false
        copied = false; clarificationAnswer = ""; solutionRevealed = false
        phase = .generating; progressMessage = "Dein Anliegen wird gelesen …"
        currentEntry = HistoryEntry(id: id, original: input, outcome: "generating")
        saveCurrent()
        let original = input
        let requestAccount = connection.accountID
        let requestModel = connection.selectedModel
        let stage = LearningProgress.stage(for: history.flatMap(\.practiceAttempts))
        let learningInstruction: String
        switch stage {
        case .example, .addDetail: learningInstruction = "Biete nach dem erklärten Beispiel eine freiwillige Übung an: eine relevante Angabe selbst ergänzen."
        case .newPrompt: learningInstruction = "Es gab eigene Übungsversuche. Biete freiwillig eine vergleichbare neue Anfrage zum selbst Formulieren an. Das ist kein Nachweis von Beherrschung."
        case .transfer: learningInstruction = "Es gab mehrere eigene Versuche. Biete freiwillig an, denselben Grundgedanken auf einen anderen Kontext zu übertragen. Hilfe bleibt verfügbar; behaupte keinen Lernerfolg."
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await CoachPipeline.run(original: original, generate: { @MainActor [weak self] instructions, prompt in
                    guard let self, self.activeAttempt == id, self.connection.accountID == requestAccount else { throw CancellationError() }
                    return try await self.connection.generate(instructions: instructions + "\nLernangebot: " + learningInstruction, input: prompt, model: requestModel) { _ in }
                }, onStage: { [weak self] stage in
                    Task { @MainActor in
                        guard let self, self.activeAttempt == id, self.connection.accountID == requestAccount else { return }
                        switch stage {
                        case .requesting:
                            self.phase = .generating
                            self.progressMessage = "Dein Vorschlag entsteht …"
                        case .validating:
                            self.phase = .validating
                            self.progressMessage = "Vorschlag und Erklärungen werden geprüft …"
                        case .repairing:
                            self.phase = .generating
                            self.progressMessage = "Das Antwortformat war ungültig. Ein einmaliger Reparaturversuch läuft …"
                            self.currentEntry?.outcome = "format_repair_requested"
                            self.saveCurrent()
                        }
                    }
                })
                try Task.checkCancellation()
                guard self.activeAttempt == id, self.connection.accountID == requestAccount else { return }
                self.response = result; self.editedPrompt = result.prompt
                self.solutionRevealed = result.exercise == nil || result.status == .already_good
                self.showExercise = result.exercise != nil
                self.phase = result.status == .needs_clarification ? .clarifying : .showingResult
                self.currentEntry?.response = result
                self.currentEntry?.outcome = result.status.rawValue
                self.saveCurrent()
                self.activeAttempt = nil
            } catch {
                guard self.activeAttempt == id, self.connection.accountID == requestAccount else { return }
                self.diagnostics.record(error, area: .coach)
                self.activeAttempt = nil
                if error is CancellationError || (error as? ProviderFailure)?.kind == .interrupted || (error as? ProviderFailure)?.kind == .cancelled {
                    self.phase = .interrupted
                    self.errorMessage = "Abgebrochen. Dein Entwurf bleibt erhalten."
                    self.currentEntry?.outcome = "interrupted"
                } else {
                    // Diagnosis without prompt content: kind, code and the local validation reason.
                    let failure = error as? ProviderFailure
                    Self.log.error("Coach request failed: kind=\(failure?.kind.rawValue ?? "validation-or-local", privacy: .public) status=\(failure?.status ?? 0, privacy: .public)")
                    self.phase = .error
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Der Vorschlag konnte nicht fertiggestellt werden. Dein Entwurf bleibt erhalten. Bitte versuche es erneut."
                    self.currentEntry?.outcome = "error"
                }
                self.saveCurrent()
            }
        }
    }

    /// Demo only: plays the same stages with the bundled example response. No request is sent.
    private func runDemo() {
        task?.cancel()
        let id = UUID()
        activeAttempt = id
        submittedOriginal = draft
        errorMessage = nil; response = nil; editing = false; manuallyEdited = false
        showExercise = false; exerciseAnswer = ""; exerciseFeedback = ""; copied = false
        phase = .generating; progressMessage = "Dein Anliegen wird gelesen …"
        task = Task { [weak self] in
            let steps: [(UInt64, Phase, String)] = [(1_100, .generating, "Dein Vorschlag entsteht …"), (1_200, .validating, "Vorschlag und Erklärungen werden geprüft …")]
            for (delay, phase, message) in steps {
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
                guard let self, self.activeAttempt == id, !Task.isCancelled else { return }
                self.phase = phase; self.progressMessage = message
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard let self, self.activeAttempt == id, !Task.isCancelled else { return }
            // `--demo-good` plays the "already clear" outcome (with an exercise) for layout checks.
            let result = CommandLine.arguments.contains("--demo-good")
                ? CoachResponse(status: .already_good, coachMessage: "Dein Prompt ist schon klar. Du kannst ihn so verwenden.",
                                segments: [PromptSegment(id: "s1", text: self.submittedOriginal)],
                                exercise: CoachExercise(id: "ex1", question: "Wie würdest du eine ähnliche Anfrage für eine freundliche Absage formulieren?", category: "Transfer"))
                : DemoContent.response
            self.response = result
            self.editedPrompt = result.prompt
            self.solutionRevealed = true
            self.phase = .showingResult
            self.activeAttempt = nil
        }
    }

    func cancel() {
        if activeAttempt != nil {
            activeAttempt = nil; task?.cancel(); task = nil
            phase = .interrupted
            progressMessage = ""
            currentEntry?.outcome = "interrupted"
            saveCurrent()
        }
    }

    func revealSolution() { solutionRevealed = true; exerciseHelp = true; showExercise = false }

    func compare(_ change: PromptChange) {
        guard let response, !manuallyEdited else { return }
        learning.prepareComparison(original: submittedOriginal, response: response, change: change); page = .laboratory
    }

    func saveVisibleRecipe() { learning.createRecipe(from: visiblePrompt); page = .recipes }

    func copyPrompt() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(visiblePrompt, forType: .string)
        copied = true
    }

    func beginEditing() { editedPrompt = visiblePrompt; editing = true; copied = false }
    func updateEditedPrompt() {
        manuallyEdited = editedPrompt != displayedResponse?.prompt
        copied = false
        currentEntry?.editedPrompt = manuallyEdited ? editedPrompt : nil
        saveCurrent()
    }

    func submitPractice() {
        guard let exercise = response?.exercise, !exerciseAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let answer = exerciseAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        let copiedProposal = answer == visiblePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            || answer == response?.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let usedHelp = exerciseHelp || copiedProposal
        exerciseFeedback = copiedProposal
            ? "Deine Antwort entspricht dem Vorschlag. Dieser Versuch zählt als unterstützt. Probiere für einen eigenen Versuch eine passende Angabe in deinen Worten."
            : LearningFeedback.evaluate(answer: exerciseAnswer, exercise: exercise, usedHelp: usedHelp)
        let attempt = PracticeAttempt(answer: exerciseAnswer, feedback: exerciseFeedback, helpUsed: usedHelp, principleID: exercise.category)
        if currentEntry == nil { currentEntry = HistoryEntry(original: submittedOriginal, response: response, outcome: "practice") }
        currentEntry?.practiceAttempts.append(attempt)
        saveCurrent()
    }

    func newPrompt() {
        cancel(); response = nil; editedPrompt = ""; editing = false; manuallyEdited = false
        currentEntry = nil; submittedOriginal = ""; errorMessage = nil; showExercise = false
        exerciseAnswer = ""; exerciseFeedback = ""; clarificationAnswer = ""; copied = false
        draft = ""; page = .coach
        phase = connection.canGenerate ? .ready : .disconnected
    }

    func select(_ entry: HistoryEntry) {
        // Keep an unsent current draft recoverable when a different history item is opened.
        if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           draft != entry.original, draft != currentEntry?.original {
            guard let store else { storageError = "Dein aktueller Entwurf kann nicht gesichert werden und bleibt geöffnet."; return }
            do {
                try store.save(HistoryEntry(original: draft, outcome: "draft"))
                history = try store.entries()
            } catch {
                storageError = "Dein aktueller Entwurf konnte nicht gesichert werden. Er bleibt geöffnet."
                return
            }
        }
        cancel(); currentEntry = entry; draft = entry.original; submittedOriginal = entry.original
        response = entry.response
        // Equal responses can belong to different history entries with different answers.
        restoreInputValues(entry.inputValues)
        editedPrompt = entry.editedPrompt ?? displayedResponse?.prompt ?? ""
        manuallyEdited = entry.editedPrompt != nil; editing = false; copied = false; solutionRevealed = true
        showExercise = false; exerciseAnswer = ""; exerciseFeedback = ""; exerciseHelp = false
        errorMessage = nil; clarificationAnswer = ""
        phase = entry.response?.status == .needs_clarification ? .clarifying : (entry.response == nil ? .ready : .showingResult)
        page = .coach
    }

    func saveCurrent() {
        if let response, currentEntry?.response == response { currentEntry?.inputValues = inputValues }
        guard let entry = currentEntry else { return }
        guard let store else { storageError = "Dieser Eintrag kann nur im Fenster bleiben. Bitte kopiere deinen Text vor dem Schließen."; return }
        do {
            try store.save(entry)
            // Editing a field should not decode the entire history on every keystroke.
            if let index = history.firstIndex(where: { $0.id == entry.id }) { history[index] = entry }
            else {
                history.append(entry)
                history.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt }
            }
        }
        catch { storageError = "Dieser Eintrag konnte nicht gespeichert werden. Dein Text bleibt im Fenster erhalten." }
    }

    func deleteHistory() {
        guard let store else { storageError = "Der lokale Verlauf ist nicht zugänglich und konnte nicht gelöscht werden."; return }
        cancel()
        do { try store.deleteAll(); history = []; newPrompt() }
        catch { storageError = "Der Verlauf konnte nicht vollständig gelöscht werden." }
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Sinnfaden-Verlauf.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { guard let data = try store?.exportData() else { return }; try data.write(to: url, options: .atomic) }
        catch { storageError = "Der Export konnte nicht gespeichert werden." }
    }
}
