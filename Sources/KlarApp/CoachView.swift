import SwiftUI
import KlarCore

/// The writing place: a calm start with one input, a send moment, then a split view
/// that explains the result three ways (map, grid, step by step).
struct CoachView: View {
    @ObservedObject var model: AppModel
    let greetingName: String
    let wide: Bool
    @State private var inputFocused = false
    @State private var editorHeight: CGFloat = 0
    @State private var editor = PromptEditorHandle()
    @State private var launch: WordLaunch?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let examples = [
        PromptExample(id: 0, title: "E-Mail schreiben", icon: "envelope", text: "Hilf mir, eine freundliche E-Mail zu schreiben, um einen Termin zu verschieben."),
        PromptExample(id: 1, title: "Etwas verstehen", icon: "lightbulb", text: "Erkläre mir, wie ein Regenbogen entsteht."),
        PromptExample(id: 2, title: "Etwas planen", icon: "calendar", text: "Hilf mir, meinen Umzug zu planen. Ich ziehe am 15. November um.")
    ]

    var body: some View {
        ZStack {
            if model.busy {
                // With flying words the stage appears at once: the words must match the editor
                // in the very first frame. The result arrives as the body flattens and fades.
                SendingView(message: model.progressMessage, validating: model.phase == .validating, draft: model.draft, launch: launch, cancel: model.cancel)
                    .transition(.asymmetric(insertion: launch == nil ? .opacity.animation(.easeOut(duration: 0.2)) : .identity,
                                            removal: reduceMotion ? .opacity.animation(.easeOut(duration: 0.15))
                                                : .modifier(active: Unfold(amount: 1), identity: Unfold(amount: 0)).animation(.easeIn(duration: 0.26))))
            } else if let response = model.response {
                ResultSplit(model: model, response: response, wide: wide)
                    .transition(.opacity.animation(.easeOut(duration: 0.28).delay(0.06)))
            } else {
                hero
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 20)).animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.6, dampingFraction: 0.86)),
                                            removal: reduceMotion ? .opacity : .modifier(active: SuckedIn(amount: 1), identity: SuckedIn(amount: 0)).animation(.easeOut(duration: 0.34))))
            }
        }
        // Each transition carries its own animation. A blanket animation on the state switch
        // would also animate the first layout of hosted AppKit text and strand it off its slot.
        .onChange(of: model.busy) { _, busy in if !busy { launch = nil } }
    }

    /// Captures where every typed word sits, then sends. The words leave from exactly there.
    private func send() {
        guard model.canSubmit else { return }
        if !reduceMotion {
            launch = WordLaunch(words: editor.capturedWords(), fontSize: model.fontSize + 2, start: Date())
            editor.setTextHidden(true)
        }
        // The request starts right away; the animation never delays it.
        model.improve()
        if !model.busy { launch = nil; editor.setTextHidden(false) }
    }

    private var stateKey: Int { model.busy ? 1 : model.response == nil ? 0 : 2 }

    // MARK: - Calm start

    private var hero: some View {
        VStack(spacing: 26) {
            VStack(spacing: 12) {
                Text(greetingName.isEmpty ? "Hallo." : "Hallo, \(greetingName).")
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(Color.sinnMuted)
                    .sinnReveal(0)
                Text("Was hast du vor?")
                    .font(SinnType.display(56)).tracking(-2)
                    .sinnReveal(1)
                Text("Schreib es in deinen Worten. Sinnfaden macht daraus einen klaren Prompt und zeigt dir, warum.")
                    .font(.system(size: 17)).foregroundStyle(Color.sinnMuted)
                    .multilineTextAlignment(.center).frame(maxWidth: 560)
                    .sinnReveal(2)
            }
            inputBubble.sinnReveal(3).zIndex(1)
            ExampleChips(examples: Self.examples, absorbed: !model.draft.isEmpty, gap: 26) { example in
                model.draft = example.text; inputFocused = true
            }
            .sinnReveal(4)
            notices.frame(maxWidth: 720)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .onAppear { DispatchQueue.main.async { inputFocused = true } }
    }

    private var inputBubble: some View {
        VStack(alignment: .leading, spacing: 14) {
            PromptEditor(text: $model.draft, focused: $inputFocused, contentHeight: $editorHeight,
                         placeholder: "Zum Beispiel: Ich möchte eine freundliche E-Mail schreiben …",
                         fontSize: model.fontSize + 2, textHidden: launch != nil, handle: editor)
                // Grows with the text: two lines at rest, up to about eight before it scrolls.
                .frame(height: min(240, max(72, editorHeight + 4)))
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: editorHeight)
                .padding(.top, 4)
            HStack(spacing: 12) {
                Text("⌘ ↵ zum Senden").font(.system(size: 12)).foregroundStyle(Color.sinnMuted).accessibilityHidden(true)
                Spacer()
                Button { send() } label: {
                    HStack(spacing: 9) { Text("Prompt verbessern"); Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)) }
                        .font(.system(size: 15, weight: .semibold)).padding(.horizontal, 4)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!model.canSubmit)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(22)
        .frame(maxWidth: 720)
        .cardSurface(radius: 30, elevated: true)
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.sinnAnnotation.opacity(inputFocused ? 0.4 : 0), lineWidth: 1.5)
                .shadow(color: Color.sinnAnnotation.opacity(inputFocused ? 0.22 : 0), radius: 18)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : SinnMotion.selection, value: inputFocused)
    }

    @ViewBuilder private var notices: some View {
        if let storageError = model.storageError { CoachNotice(text: storageError, symbol: "externaldrive.badge.exclamationmark") }
        if model.isDemo { CoachNotice(text: "Beispielmodus: Sinnfaden zeigt eine lokal hinterlegte Antwort. Es wird keine KI-Anfrage gesendet.", symbol: "info.circle") }
        if model.draft.utf16.count > CoachValidator.maximumInputLength { CoachNotice(text: "Dein Text ist für einen einzelnen Versuch zu lang. Teile ihn bitte in kleinere Abschnitte.", symbol: "info.circle") }
        if let error = model.errorMessage { CoachNotice(text: error, symbol: "exclamationmark.circle") }
    }
}

struct CoachNotice: View {
    let text: String
    let symbol: String
    var body: some View {
        Label(text, systemImage: symbol).font(.system(size: 13)).lineSpacing(3)
            .foregroundStyle(Color.sinnMuted)
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .textSelection(.enabled)
    }
}

// MARK: - Send moment

/// While the AI works: liquid matter circles, touches and separates; three honest
/// stages show what is happening.
struct SendingView: View {
    let message: String
    let validating: Bool
    let draft: String
    var launch: WordLaunch?
    let cancel: () -> Void
    @State private var captionsVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 34) {
            GatheringStage(launch: launch, checking: validating, size: 340)
                .frame(height: 380)
            VStack(spacing: 14) {
                Text(message.isEmpty ? "Wird gesendet …" : message)
                    .font(.system(size: 20, weight: .semibold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: message)
                // Only the two states the app actually knows: the answer is being written, or it
                // has arrived and is being checked locally.
                HStack(spacing: 8) {
                    stage("Vorschlag entsteht", done: validating, active: !validating)
                    stage("Prüfen", done: false, active: validating)
                }
                Text("„\(draft.prefix(90))\(draft.count > 90 ? "…" : "")“")
                    .font(.system(size: 13)).foregroundStyle(Color.sinnMuted).lineLimit(2)
                    .frame(maxWidth: 460)
                Button("Abbrechen", action: cancel).buttonStyle(SecondaryButtonStyle()).padding(.top, 6)
            }
            // Status and cancel are there from the first frame; they fade in quickly and never move.
            .opacity(captionsVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0.1 : 0.22)) { captionsVisible = true } }
    }

    private func stage(_ title: String, done: Bool, active: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : active ? "circle.dotted" : "circle")
                .symbolEffect(.pulse, isActive: active && !reduceMotion)
            Text(title)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(done ? Color.sinnAnnotation : active ? Color.sinnInk : Color.sinnMuted)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(active ? Color.sinnAnnotation.opacity(0.4) : Color.white.opacity(0.8)))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: done)
    }
}

// MARK: - Result split

private enum ResultLens: String, CaseIterable, Identifiable {
    case map, grid, steps
    var id: String { rawValue }
    var title: String {
        switch self { case .map: "Mindmap"; case .grid: "Raster"; case .steps: "Schritt für Schritt" }
    }
    var symbol: String {
        switch self { case .map: "point.3.connected.trianglepath.dotted"; case .grid: "square.grid.2x2"; case .steps: "list.number" }
    }
}

struct ResultSplit: View {
    @ObservedObject var model: AppModel
    let response: CoachResponse
    let wide: Bool
    private var lens: ResultLens { ResultLens(rawValue: model.insightMode) ?? .map }
    @State private var appeared = false
    @State private var showOriginal = false
    @Namespace private var tabs
    @Namespace private var sheetToggle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let split = wide && showsExplain
        let layout = split ? AnyLayout(HStackLayout(alignment: .top, spacing: 22)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
        VStack(alignment: .leading, spacing: 22) {
            header
            if let error = model.storageError { CoachNotice(text: error, symbol: "externaldrive.badge.exclamationmark") }
            if let error = model.errorMessage { CoachNotice(text: error, symbol: "exclamationmark.circle") }
            if let error = model.promptUseError { CoachNotice(text: error, symbol: "exclamationmark.circle") }
            layout {
                // No appear animation here: it would animate the column's first layout too, and
                // the hosted native text would stay where that animation started.
                promptColumn
                    .frame(maxWidth: split ? 520 : .infinity, alignment: .leading)
                if showsExplain {
                    explainColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .scaleEffect(appeared || reduceMotion ? 1 : 1.18, anchor: .leading)
                        .blur(radius: appeared || reduceMotion ? 0 : 16)
                        .opacity(appeared ? 1 : 0)
                        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.85, dampingFraction: 0.86).delay(0.12), value: appeared)
                }
            }
        }
        // Without a second column the result reads as one calm centred sheet, not a half-empty page.
        .frame(maxWidth: showsExplain ? .infinity : 760, alignment: .leading)
        .frame(maxWidth: .infinity)
        .onAppear { appeared = true }
    }

    /// The right column exists when there is something to explain or to fill in.
    private var showsExplain: Bool {
        response.status != .needs_clarification && (!response.changes.isEmpty || (!response.inputs.isEmpty && model.solutionRevealed && !model.manuallyEdited))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                statusChip
                Text(response.status == .needs_clarification ? "Eine kurze Rückfrage" : response.status == .already_good ? "Dein Prompt passt schon." : "Dein klarer Prompt.")
                    .font(SinnType.display(40)).tracking(-1.4)
                Text(response.coachMessage).font(.system(size: 16)).foregroundStyle(Color.sinnMuted)
                    .lineSpacing(3).frame(maxWidth: 680, alignment: .leading)
            }
            Spacer()
            Button { model.newPrompt() } label: { Label("Neuer Prompt", systemImage: "plus") }
                .buttonStyle(SecondaryButtonStyle())
        }
        .sinnReveal(0)
    }

    private var statusChip: some View {
        let (symbol, text, tint): (String, String, Color) = {
            switch response.status {
            case .improved:
                let count = response.changes.count
                return ("sparkles", count == 1 ? "Verbessert · 1 Änderung" : "Verbessert · \(count) Änderungen", Color.sinnAnnotation)
            case .already_good: return ("checkmark.seal.fill", "Schon klar formuliert", Color.green)
            case .needs_clarification: return ("questionmark.bubble.fill", "Eine Angabe fehlt", Color.orange)
            }
        }()
        return Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(tint.opacity(0.1), in: Capsule())
    }

    // MARK: Prompt column

    private var promptColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !(wide && showsExplain) { inputsForm }
            VStack(alignment: .leading, spacing: 0) {
                // No opacity or transition around the native text, and the bar shares its stack:
                // AppKit hosts otherwise land at a stale position above their slot.
                VStack(alignment: .leading, spacing: 16) {
                    sheetBar
                    if showOriginal {
                        Text(model.submittedOriginal.isEmpty ? model.draft : model.submittedOriginal)
                            .font(.system(size: model.fontSize)).lineSpacing(6).foregroundStyle(Color.sinnMuted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        promptContent
                    }
                }
                .padding(22)
                if showsActions {
                    actionBar
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: 28, elevated: true)
            if response.status != .needs_clarification, model.solutionRevealed, let exercise = response.exercise {
                PracticeCard(model: model, exercise: exercise)
            }
        }
    }

    private var showsActions: Bool {
        response.status != .needs_clarification && (model.solutionRevealed || response.exercise == nil)
    }

    /// Before/after in one place: your words and the improved prompt share the same sheet.
    private var sheetBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach([false, true], id: \.self) { original in
                    Button { showOriginal = original } label: {
                        Text(original ? "Deine Worte" : "Verbessert")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(showOriginal == original ? Color.white : Color.sinnInk)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background {
                                if showOriginal == original {
                                    Capsule().fill(Color.sinnInk).matchedGeometryEffect(id: "sheet", in: sheetToggle)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.sinnStructure.opacity(0.8), in: Capsule())
            // Only an improved prompt has a "before" worth switching to.
            .disabled(response.status != .improved)
            .opacity(response.status == .improved ? 1 : 0)
            Spacer()
            if model.manuallyEdited { Text("Bearbeitet").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.sinnMuted) }
            if !showOriginal && !response.changes.isEmpty && !model.editing && !model.manuallyEdited {
                Label("Blaue Stellen erklären sich", systemImage: "cursorarrow.rays")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.sinnAnnotation)
            }
        }
    }

    /// The things you do with the prompt, together at the bottom edge of the sheet.
    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HandoffButton(service: model.handoff, prompt: model.visiblePrompt, expanded: true)
                .disabled(!model.canUsePrompt)
            HStack(spacing: 8) {
                SheetAction(symbol: model.copied ? "checkmark" : "doc.on.doc", title: model.copied ? "Kopiert" : "Kopieren") { model.copyPrompt() }
                    .disabled(!model.canUsePrompt)
                SheetAction(symbol: model.editing ? "checkmark" : "pencil", title: model.editing ? "Fertig" : "Bearbeiten") {
                    if model.editing { model.editing = false } else { model.beginEditing() }
                }
                SheetAction(symbol: "bookmark", title: "Vorlage") { model.saveVisibleRecipe() }
                    .disabled(!model.canUsePrompt)
            }
            HandoffStatus(service: model.handoff, prompt: model.visiblePrompt)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(Color.sinnStructure.opacity(0.45))
        .overlay(alignment: .top) { Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1) }
    }

    @ViewBuilder private var promptContent: some View {
        if response.status == .needs_clarification, let question = response.clarification {
            Text(question.question).font(.system(size: 21, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            TextField("Deine Ergänzung", text: $model.clarificationAnswer, axis: .vertical)
                .textFieldStyle(SinnFieldStyle()).font(.system(size: model.fontSize)).lineLimit(2...5)
            HStack {
                if question.optional { Button("Diese Angabe überspringen") { model.improve(clarification: true, skip: true) }.buttonStyle(.plain).foregroundStyle(Color.sinnMuted) }
                Spacer()
                Button { model.improve(clarification: true) } label: { Label("Ergänzung übernehmen", systemImage: "arrow.right") }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.clarificationAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } else if !model.solutionRevealed, let exercise = response.exercise {
            Text("Du kannst die hilfreiche Angabe zuerst selbst ergänzen. Der Vorschlag bleibt bis dahin verdeckt.")
                .font(.system(size: 14)).foregroundStyle(Color.sinnMuted)
            PracticeCard(model: model, exercise: exercise)
            Button("Vorschlag ansehen") { model.revealSolution() }.buttonStyle(SecondaryButtonStyle())
        } else {
            if model.editing {
                TextEditor(text: $model.editedPrompt).font(.system(size: model.fontSize)).lineSpacing(5)
                    .frame(minHeight: 170).sinnEditorSurface()
                    .accessibilityLabel("Vorschlag selbst bearbeiten")
                    .onChange(of: model.editedPrompt) { _, _ in model.updateEditedPrompt() }
                Text("Beim Ändern werden die bisherigen Markierungen aufgehoben.").font(.system(size: 12)).foregroundStyle(Color.sinnMuted)
            } else if model.manuallyEdited {
                Text(model.editedPrompt).font(.system(size: model.fontSize)).lineSpacing(6).textSelection(.enabled)
            } else {
                AnnotatedPromptView(response: model.displayedResponse ?? response, fontSize: model.fontSize, onHelpUsed: { model.exerciseHelp = true }, onCompare: { model.compare($0) })
                if !model.openRequiredInputs.isEmpty {
                    Label("Noch offen: " + model.openRequiredInputs.map(\.label).joined(separator: ", "), systemImage: "exclamationmark.circle")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Color.orange)
                        .transition(.opacity)
                }
            }
            if !response.unknowns.isEmpty {
                Label(response.unknowns.joined(separator: " · "), systemImage: "questionmark.circle")
                    .font(.system(size: 12)).foregroundStyle(Color.sinnMuted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Explanation column

    /// Fields first on the right, so the prompt on the left stays in view and fills live.
    @ViewBuilder private var inputsForm: some View {
        if response.status != .needs_clarification, model.solutionRevealed, !response.inputs.isEmpty, !model.manuallyEdited {
            PromptInputsForm(model: model, inputs: response.inputs)
        }
    }

    private var explainColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            if wide { inputsForm }
            if !response.changes.isEmpty { lensPicker }
        }
    }

    private var lensPicker: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 4) {
                ForEach(ResultLens.allCases) { item in
                    Button { withAnimation(SinnMotion.selection) { model.insightMode = item.rawValue } } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(lens == item ? Color.white : Color.sinnInk)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background {
                                if lens == item {
                                    Capsule().fill(Color.sinnInk).matchedGeometryEffect(id: "tab", in: tabs)
                                }
                            }
                            .contentShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
            .padding(5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.8)))
            Group {
                switch lens {
                case .map: ChangeMindmap(response: response, original: model.submittedOriginal)
                case .grid: ChangeGrid(response: response)
                case .steps: StepByStep(response: response, onPractice: { model.showExercise = true })
                }
            }
            .id(lens)
            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .offset(y: 12)), removal: .opacity))
        }
    }
}

/// Voluntary practice, shared by the reveal gate and the result.
struct PracticeCard: View {
    @ObservedObject var model: AppModel
    let exercise: CoachExercise
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button { withAnimation(SinnMotion.reveal) { model.showExercise.toggle() }; model.phase = model.showExercise ? .practicing : .showingResult } label: {
                HStack(spacing: 10) {
                    Image(systemName: "leaf").foregroundStyle(Color.sinnAnnotation)
                    Text("Selbst ausprobieren").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("Freiwillig").font(.system(size: 11)).foregroundStyle(Color.sinnMuted)
                    Image(systemName: model.showExercise ? "chevron.up" : "chevron.down").font(.system(size: 10))
                }
            }.buttonStyle(.plain)
            if model.showExercise {
                Text(exercise.question).font(.system(size: 15)).lineSpacing(4)
                TextField("Deine eigene Antwort", text: $model.exerciseAnswer, axis: .vertical)
                    .textFieldStyle(SinnFieldStyle()).font(.system(size: 16)).lineLimit(2...5)
                    .onChange(of: model.exerciseAnswer) { _, _ in model.exerciseFeedback = "" }
                HStack {
                    Button("Hilfe einblenden") { model.exerciseHelp = true }.buttonStyle(.plain).foregroundStyle(Color.sinnAnnotation)
                    Spacer()
                    Button("Versuch prüfen") { model.submitPractice() }.buttonStyle(PrimaryButtonStyle())
                        .disabled(model.exerciseAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.exerciseFeedback.isEmpty)
                }.font(.system(size: 12))
                if model.exerciseHelp { Text("Überlege: Was soll ChatGPT danach genauer wissen? Eine konkrete Angabe genügt.").font(.system(size: 13)).foregroundStyle(Color.sinnMuted) }
                if !model.exerciseFeedback.isEmpty { Text(model.exerciseFeedback).font(.system(size: 14)).lineSpacing(4).padding(.top, 4) }
            }
        }.padding(20).cardSurface(radius: 22)
    }
}

/// The start page steps back while its words leave: a slight recession toward the gathering
/// point and a fade. Restrained, so the words stay the event.
private struct SuckedIn: ViewModifier {
    let amount: CGFloat
    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.04 * amount, anchor: UnitPoint(x: 0.5, y: 0.45))
            .blur(radius: 5 * amount)
            .opacity(Double(1 - amount))
    }
}

/// The settled body flattens a little and fades as the result takes its place.
private struct Unfold: ViewModifier {
    let amount: CGFloat
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1 + 0.06 * amount, y: 1 - 0.12 * amount, anchor: .center)
            .opacity(Double(1 - amount))
    }
}

/// A quiet secondary action on the prompt sheet: icon and short word, lifts on hover.
private struct SheetAction: View {
    let symbol: String
    let title: String
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.sinnInk)
            .padding(.horizontal, 12).frame(maxWidth: .infinity).frame(height: 40)
            .background(Color.white.opacity(hovered ? 1 : 0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.black.opacity(hovered ? 0.1 : 0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(SinnMotion.hover) { hovered = inside } }
        .help(title)
    }
}
