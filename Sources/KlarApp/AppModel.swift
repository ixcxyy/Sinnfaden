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
            // Every orange placeholder gets a field, also in answers stored before this rule.
            if let current = response {
                let covered = current.coveringPlaceholders()
                if covered != current { response = covered; return }
            }
            guard oldValue != response else { return }
            focusedInputID = nil
            copyNeedsInputs = false
            copiedWithOpenPlaceholders = false
            // Smart default: fields start with values that follow from the user's own words.
            restoreInputValues()
        }
    }
    /// Answers to the generated fields, keyed by input id.
    @Published var inputValues: [String: String] = [:] {
        didSet {
            guard !restoringInputValues, oldValue != inputValues else { return }
            if !updatingInputSelections {
                inputSelections = inputSelections.filter { oldValue[$0.key] == inputValues[$0.key] }
            }
            copied = false
            copiedWithOpenPlaceholders = false
            if copyNeedsInputs && openPlaceholders.isEmpty { copyNeedsInputs = false }
            let previousPrompt = displayedResponse?.prompt
            refreshDisplayedResponse()
            // Keep an untouched editor in sync with the visible form. Comparing its
            // actual text also protects typing whose SwiftUI notification is still pending.
            if editing, !manuallyEdited, let previousPrompt, editedPrompt == previousPrompt {
                editedPrompt = displayedResponse?.prompt ?? ""
            }
            saveCurrent()
        }
    }
    @Published private(set) var inputSelections: [String: [String]] = [:]
    /// Filled once per field change, with the original template retained on overflow.
    @Published private(set) var displayedResponse: CoachResponse?
    @Published private(set) var inputExpansionError: String?
    var promptUseError: String? { manuallyEdited ? nil : inputExpansionError }
    var canUsePrompt: Bool { promptUseError == nil && !visiblePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Orange placeholders without a value yet. Shown, focusable, and guarded before copying.
    var openPlaceholders: [String] {
        guard !manuallyEdited, let response else { return [] }
        return response.unfilledPlaceholders(with: inputValues)
    }
    /// The field the page should focus next (set by a click on an orange placeholder).
    @Published var focusedInputID: String?
    /// A copy or hand-off was stopped because placeholders are still open.
    @Published var copyNeedsInputs = false
    /// The last copy deliberately kept open placeholders.
    @Published var copiedWithOpenPlaceholders = false

    func focusInput(placeholder: String) {
        guard let input = response?.inputs.first(where: { $0.placeholder == placeholder }) else { return }
        let expected = response
        focusedInputID = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.response == expected else { return }
            self.focusedInputID = input.id
        }
    }

    func focusFirstOpenInput() {
        guard let first = openPlaceholders.first else { return }
        focusInput(placeholder: first)
    }

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
    private var updatingInputSelections = false
    private var task: Task<Void, Never>?
    private var activeAttempt: UUID?
    private var currentEntry: HistoryEntry?
    private var observedAccount = "local"
    // Failed writes survive navigation, but never cross account boundaries.
    private var pendingEntries: [String: [UUID: HistoryEntry]] = [:]
    private var pendingDrafts: [String: String] = [:]
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
            draft = CommandLine.arguments.contains("--demo-meal") ? DemoContent.mealOriginal : DemoContent.original
            phase = .ready
        }
    }

    var busy: Bool { phase == .generating || phase == .validating }
    var visiblePrompt: String { manuallyEdited || editing ? editedPrompt : (displayedResponse?.prompt ?? "") }
    var canSubmit: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.utf16.count <= CoachValidator.maximumInputLength && !busy }

    private func restoreInputValues(_ saved: [String: String]? = nil, selections: [String: [String]]? = nil) {
        restoringInputValues = true
        defer { restoringInputValues = false }
        inputValues = saved ?? response?.suggestedInputValues ?? [:]
        inputSelections = selections ?? [:]
        refreshDisplayedResponse()
    }

    private func refreshDisplayedResponse() {
        guard let response else { displayedResponse = nil; inputExpansionError = nil; return }
        do {
            displayedResponse = try response.filled(with: inputValues)
            inputExpansionError = nil
        } catch {
            displayedResponse = response
            inputExpansionError = error.localizedDescription
        }
    }

    func selectedOptions(for input: PromptInput) -> Set<String>? {
        guard input.kind == .multi_choice else { return nil }
        return PromptChoiceInput.selected(in: inputValues[input.id] ?? "", options: input.options, saved: inputSelections[input.id])
    }

    func toggleOption(_ option: String, for input: PromptInput) {
        guard response?.inputs.contains(input) == true, input.kind == .multi_choice,
              input.options.contains(option), var selected = selectedOptions(for: input) else { return }
        if selected.contains(option) { selected.remove(option) } else { selected.insert(option) }
        let ordered = input.options.filter { selected.contains($0) }
        inputSelections[input.id] = ordered
        updatingInputSelections = true
        defer { updatingInputSelections = false }
        let value = ordered.joined(separator: PromptChoiceInput.separator)
        if inputValues[input.id] == value { saveCurrent() }
        else { inputValues[input.id] = value }
    }

    private func synchronizeAccount() {
        let account = isDemo ? "demonstration" : (connection.accountID ?? "local")
        switchStorageAccount(to: account)
    }

    func switchStorageAccount(to account: String) {
        guard observedAccount != account else { return }
        let anonymousDraft = observedAccount == "local" ? draft : nil
        cancel()
        flushPendingSaves()
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
        store = nil; draft = ""; history = []
        do {
            let next = try HistoryStore(accountID: account, baseURL: storageBaseURL)
            let savedDraft = try next.loadDraft()
            let savedEntries = try next.entries()
            draft = savedDraft
            history = savedEntries
            store = next
        } catch { diagnostics.record(error, area: .history) }
        if let pending = pendingDrafts[account] { draft = pending }
        for entry in (pendingEntries[account] ?? [:]).values { upsertHistory(entry) }
        loadingStore = false
        flushPendingSaves()
    }

    private func persistDraft() {
        pendingDrafts[observedAccount] = draft
        if let store {
            do {
                try store.saveDraft(draft)
                pendingDrafts.removeValue(forKey: observedAccount)
            } catch { diagnostics.record(error, area: .history) }
        }
        updateStorageWarning()
    }

    func flushPendingSaves() {
        if let store {
            if let draft = pendingDrafts[observedAccount] {
                do {
                    try store.saveDraft(draft)
                    pendingDrafts.removeValue(forKey: observedAccount)
                } catch { diagnostics.record(error, area: .history) }
            }
            for entry in (pendingEntries[observedAccount] ?? [:]).values {
                persistEntry(entry, in: store)
            }
        }
        updateStorageWarning()
    }

    private func updateStorageWarning() {
        if store == nil {
            storageError = "Deine lokalen Daten konnten nicht geöffnet werden. Sie wurden nicht überschrieben. Exportiere deine neuen Texte vor dem Schließen."
        } else if pendingDrafts[observedAccount] != nil || pendingEntries[observedAccount]?.isEmpty == false {
            storageError = "Einige Texte sind noch nicht lokal gespeichert. Sie bleiben während dieser Sitzung erhalten. Exportiere deinen Verlauf vor dem Schließen."
        } else if !pendingDrafts.isEmpty || !pendingEntries.isEmpty {
            storageError = "In einem anderen Konto sind noch Texte ungespeichert. Wechsle dorthin und exportiere sie vor dem Schließen."
        } else { storageError = nil }
    }

    private func upsertHistory(_ entry: HistoryEntry) {
        if let index = history.firstIndex(where: { $0.id == entry.id }) { history[index] = entry }
        else {
            history.append(entry)
            history.sort { $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt }
        }
    }

    private func persistEntry(_ entry: HistoryEntry, in store: HistoryStore) {
        do {
            try store.save(entry)
            pendingEntries[observedAccount]?.removeValue(forKey: entry.id)
            if pendingEntries[observedAccount]?.isEmpty == true { pendingEntries.removeValue(forKey: observedAccount) }
        } catch { diagnostics.record(error, area: .history) }
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
                    return try await self.connection.generate(instructions: instructions + "\nLernangebot: " + learningInstruction, input: prompt, model: requestModel) { [weak self] count in
                        guard count > 0 else { return }
                        Task { @MainActor in
                            guard let self, self.activeAttempt == id, self.connection.accountID == requestAccount,
                                  self.phase == .generating, self.progressMessage == "Dein Vorschlag entsteht …" else { return }
                            self.progressMessage = "Die Antwort kommt an. Dein Prompt wird fertiggestellt …"
                        }
                    }
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
                self.presentCoachResult(result)
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

    /// Shared by connected generation and the local demo so they expose the same result.
    func presentCoachResult(_ result: CoachResponse) {
        response = result
        editedPrompt = result.prompt
        // Building a prompt is the primary action. Practice stays available below it,
        // never as a prerequisite for seeing, filling, editing or copying the result.
        solutionRevealed = result.status != .needs_clarification
        showExercise = false
        exerciseHelp = result.status == .improved && result.exercise != nil
        phase = result.status == .needs_clarification ? .clarifying : .showingResult
        // Store what is shown (with a field for every placeholder), so typed values are saved.
        currentEntry?.response = response
        currentEntry?.outcome = result.status.rawValue
        saveCurrent()
    }

    /// Demo only: plays the same stages with the bundled example response. No request is sent.
    private func runDemo() {
        task?.cancel()
        let id = UUID()
        activeAttempt = id
        submittedOriginal = draft
        errorMessage = nil; response = nil; editing = false; manuallyEdited = false
        showExercise = false; exerciseAnswer = ""; exerciseFeedback = ""; exerciseHelp = false
        copied = false; clarificationAnswer = ""; solutionRevealed = false
        phase = .generating; progressMessage = "Dein Anliegen wird gelesen …"
        // A demo attempt owns its history and practice just like a connected request.
        currentEntry = HistoryEntry(id: id, original: submittedOriginal, outcome: "generating")
        saveCurrent()
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
                : CommandLine.arguments.contains("--demo-meal") ? DemoContent.mealResponse : DemoContent.response
            self.presentCoachResult(result)
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
        guard let response, !manuallyEdited, canUsePrompt else { return }
        learning.prepareComparison(original: submittedOriginal, response: response, change: change, inputValues: inputValues); page = .laboratory
    }

    func saveVisibleRecipe() {
        guard canUsePrompt else { return }
        learning.createRecipe(from: visiblePrompt); page = .recipes
    }

    /// Copies the usable prompt. With open placeholders it first leads to the missing field;
    /// `allowOpen` is the explicit, clearly labelled copy that keeps them.
    func copyPrompt(allowOpen: Bool = false) {
        guard canUsePrompt else { return }
        if !allowOpen && !openPlaceholders.isEmpty {
            copyNeedsInputs = true
            focusFirstOpenInput()
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(visiblePrompt, forType: .string)
        copiedWithOpenPlaceholders = !openPlaceholders.isEmpty
        copyNeedsInputs = false
        copied = true
    }

    /// Hand-off to ChatGPT follows the same rule as copying.
    func mayHandOff() -> Bool {
        guard !openPlaceholders.isEmpty else { copyNeedsInputs = false; return true }
        copyNeedsInputs = true
        focusFirstOpenInput()
        return false
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
        let copiedProposal = LearningFeedback.matchesExample(exerciseAnswer, example: visiblePrompt)
            || LearningFeedback.matchesExample(exerciseAnswer, example: response?.prompt ?? "")
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
                let archivedDraft = HistoryEntry(original: draft, outcome: "draft")
                try store.save(archivedDraft)
                upsertHistory(archivedDraft)
            } catch {
                storageError = "Dein aktueller Entwurf konnte nicht gesichert werden. Er bleibt geöffnet."
                return
            }
        }
        cancel()
        // A row captured before a failed save may be stale; the recovery copy is authoritative.
        let entry = pendingEntries[observedAccount]?[entry.id] ?? entry
        currentEntry = entry; draft = entry.original; submittedOriginal = entry.original
        response = entry.response
        // Older answers gain fields for bare placeholders; the entry follows, so values save.
        currentEntry?.response = response
        // Equal responses can belong to different history entries with different answers.
        restoreInputValues(entry.inputValues, selections: entry.inputSelections)
        editedPrompt = entry.editedPrompt ?? displayedResponse?.prompt ?? ""
        manuallyEdited = entry.editedPrompt != nil; editing = false; copied = false; solutionRevealed = true
        showExercise = false; exerciseAnswer = ""; exerciseFeedback = ""
        // History shows the worked solution immediately, just like choosing “Vorschlag ansehen”.
        exerciseHelp = entry.response?.status == .improved && entry.response?.exercise != nil
        errorMessage = nil; clarificationAnswer = ""
        phase = entry.response?.status == .needs_clarification ? .clarifying : (entry.response == nil ? .ready : .showingResult)
        page = .coach
    }

    func saveCurrent() {
        if let response, currentEntry?.response == response {
            currentEntry?.inputValues = inputValues
            currentEntry?.inputSelections = inputSelections
        }
        guard let entry = currentEntry else { return }
        pendingEntries[observedAccount, default: [:]][entry.id] = entry
        // Retain edits even if SQLite fails, without decoding history on every keystroke.
        upsertHistory(entry)
        if let store { persistEntry(entry, in: store) }
        updateStorageWarning()
    }

    func deleteHistory() {
        guard let store else { storageError = "Der lokale Verlauf ist nicht zugänglich und konnte nicht gelöscht werden."; return }
        cancel()
        do {
            try store.deleteAll()
            pendingEntries.removeValue(forKey: observedAccount)
            pendingDrafts.removeValue(forKey: observedAccount)
            history = []; newPrompt()
        }
        catch { storageError = "Der Verlauf konnte nicht vollständig gelöscht werden." }
    }

    func exportHistory() {
        let data: Data
        do { data = try historyExportData() }
        catch { storageError = "Der Export konnte nicht vorbereitet werden."; return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Sinnfaden-Verlauf.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try data.write(to: url, options: .atomic) }
        catch { storageError = "Der Export konnte nicht gespeichert werden." }
    }

    func historyExportData() throws -> Data {
        flushPendingSaves()
        return try HistoryStore.exportData(draft: draft, entries: history, includesCompleteStoredHistory: store != nil)
    }
}
