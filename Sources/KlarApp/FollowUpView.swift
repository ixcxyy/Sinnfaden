import SwiftUI
import KlarCore

/// "Antwort verfeinern": paste the answer, say in one line what is missing, get the next
/// request for ChatGPT. A three-step strip shows where you are; the composer is the one
/// dominant card until the follow-up prompt exists, then the result takes over.
///
/// The result hosts native AppKit text (`AnnotatedPromptView`), so neither card gets an
/// opacity/offset reveal or transition: SwiftUI would strand the AppKit view mid-animation.
struct FollowUpView: View {
    @ObservedObject var model: LearningWorkspace
    @ObservedObject var handoff: ChatGPTHandoff
    let fontSize: Double
    var onCompare: (String, CoachResponse, PromptChange) -> Void
    var onRecipe: (String) -> Void

    /// Concrete wishes as a starting point; the vague ones ("besser") trigger a question.
    static let wishes = ["Kürzer und knapper", "Einfacher erklärt", "Mit konkreten Beispielen", "Als Liste mit nächsten Schritten", "Freundlicher im Ton"]

    private var draft: FollowUpDraft { model.state.followUp }
    private var hasAnswer: Bool { !draft.answer.isBlank }
    private var hasWish: Bool { !draft.desiredChange.isBlank }
    private var result: CoachResponse? {
        guard let generated = draft.generated, generated.status != .needs_clarification else { return nil }
        return generated
    }

    var body: some View {
        if let storageError = model.storageError { LearningNotice(text: storageError) }
        LearningPageHeader(eyebrow: "Im Gespräch bleiben", title: "Antwort verfeinern",
                           subtitle: "Die erste Antwort passt noch nicht ganz? Füge sie ein und sag in einem Satz, was fehlt. Sinnfaden formt daraus deinen nächsten Auftrag an ChatGPT.")
        progressStrip.sinnReveal(1)
        composer
        if let error = model.errorMessage { LearningNotice(text: error) }
        if let response = result { resultCard(response) }
    }

    // MARK: Progress

    private var progressStrip: some View {
        let steps = [("Antwort einfügen", hasAnswer), ("Wunsch nennen", hasWish), ("Folgeprompt erhalten", result != nil)]
        let current = steps.firstIndex { !$0.1 } ?? steps.count
        return HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(step.1 ? Color.sinnAnnotation : index == current ? Color.sinnInk : Color.sinnChrome)
                        if step.1 { Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)) }
                        else { Text("\(index + 1)").font(.system(size: 10, weight: .bold)) }
                    }
                    .foregroundStyle(.white).frame(width: 20, height: 20)
                    Text(step.0).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(step.1 || index == current ? Color.sinnInk : Color.sinnMuted)
                }
                if index < steps.count - 1 {
                    Capsule().fill(step.1 ? Color.sinnAnnotation.opacity(0.5) : Color.sinnChrome.opacity(0.7))
                        .frame(height: 2).frame(maxWidth: .infinity).padding(.horizontal, 12)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(Color.white.opacity(0.6), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.05)))
        .accessibilityElement(children: .combine)
        .animation(SinnMotion.selection, value: current)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                StepHeading(number: 1, title: "Die Antwort, die du erhalten hast", done: hasAnswer)
                TextEditor(text: Binding(get: { model.state.followUp.answer }, set: { model.state.followUp.answer = $0; model.followUpInputChanged() }))
                    .font(.system(size: fontSize)).scrollContentBackground(.hidden).frame(minHeight: 150)
                    .accessibilityLabel("Vorliegende KI-Antwort").disabled(model.followUpBusy).sinnEditorSurface()
                    .overlay(alignment: .topLeading) {
                        if !hasAnswer {
                            Text("Hier die Antwort von ChatGPT einfügen (⌘V). Ein relevanter Ausschnitt reicht.")
                                .font(.system(size: fontSize)).foregroundStyle(Color.sinnMuted.opacity(0.8))
                                .padding(.horizontal, 13).padding(.vertical, 8).allowsHitTesting(false)
                        }
                    }
                Label("Du entscheidest, was du einfügst. Sinnfaden liest keine ChatGPT-Unterhaltungen aus.", systemImage: "lock")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.sinnMuted)
            }
            VStack(alignment: .leading, spacing: 10) {
                StepHeading(number: 2, title: "Was soll anders werden?", done: hasWish)
                FlowLayout(spacing: 8) {
                    ForEach(Self.wishes, id: \.self) { wish in wishChip(wish) }
                }
                TextField("Oder in deinen Worten, z. B. „Mir fehlen Preise und Öffnungszeiten“", text: Binding(get: { model.state.followUp.desiredChange }, set: { model.state.followUp.desiredChange = $0; model.followUpInputChanged() }), axis: .vertical)
                    .textFieldStyle(SinnFieldStyle()).font(.system(size: fontSize)).lineLimit(2...4).disabled(model.followUpBusy)
            }
            DisclosureGroup {
                TextField("Was du ursprünglich gefragt hast", text: Binding(get: { model.state.followUp.sourcePrompt }, set: { model.state.followUp.sourcePrompt = $0; model.followUpInputChanged() }), axis: .vertical)
                    .textFieldStyle(SinnFieldStyle()).lineLimit(2...5).padding(.top, 8).disabled(model.followUpBusy)
            } label: {
                Label("Ursprünglicher Prompt (freiwillig, hilft beim Bezug)", systemImage: "text.quote").font(.system(size: 13, weight: .medium))
            }
            .tint(Color.sinnInk)
            actionArea
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 28, elevated: result == nil)
    }

    private func wishChip(_ wish: String) -> some View {
        let selected = model.state.followUp.desiredChange == wish
        return Button {
            model.state.followUp.desiredChange = selected ? "" : wish
            model.followUpInputChanged()
        } label: {
            HStack(spacing: 5) {
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                Text(wish).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white : Color.sinnInk)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(selected ? Color.sinnAnnotation : Color.white, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Color.black.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.followUpBusy)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var actionArea: some View {
        if !model.followUpQuestion.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionEyebrow(text: "Kurze Rückfrage", tint: .sinnAnnotation)
                Text(model.followUpQuestion).font(.system(size: 17, weight: .medium)).lineSpacing(3)
                TextField("Deine Ergänzung", text: $model.state.followUp.clarificationAnswer, axis: .vertical)
                    .textFieldStyle(SinnFieldStyle()).lineLimit(2...4)
                HStack(spacing: 14) {
                    Button { model.generateFollowUp() } label: { Label("Weiter", systemImage: "arrow.right") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(model.state.followUp.clarificationAnswer.isEmpty)
                    Button("Als Platzhalter offenlassen") { model.generateFollowUp(leavingOpen: true) }
                        .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sinnMuted)
                }
            }
            .padding(18)
            .background(Color.sinnAnnotationWash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if model.followUpBusy {
            HStack(spacing: 12) {
                ThreadLoader(width: 80)
                Text("Dein Folgeprompt entsteht …").font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Abbrechen") { model.cancelFollowUp() }.buttonStyle(SecondaryButtonStyle())
            }
        } else if draft.generated?.status != .improved && draft.generated?.status != .already_good {
            HStack(spacing: 14) {
                Button { model.generateFollowUp() } label: { Label("Folgeprompt erstellen", systemImage: "arrow.turn.down.right") }
                    .buttonStyle(PrimaryButtonStyle()).disabled(draft.answer.isEmpty)
                Text(hasAnswer ? (hasWish ? "Bereit. Ein Klick genügt." : "Ohne Wunsch fragt Sinnfaden kurz nach.") : "Füge zuerst eine Antwort ein.")
                    .font(.system(size: 12)).foregroundStyle(Color.sinnMuted)
            }
        }
    }

    // MARK: Result

    private func resultCard(_ response: CoachResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionEyebrow(text: "Dein Folgeprompt", tint: .sinnAnnotation)
                    Text("Bereit für ChatGPT").font(SinnType.title(26)).tracking(-0.3)
                }
                Spacer()
                if hasWish { StatusPill(text: draft.desiredChange, symbol: "target", tint: .sinnAnnotation).lineLimit(1) }
            }
            Text(response.coachMessage).font(.system(size: 14)).foregroundStyle(Color.sinnMuted).lineSpacing(3)
            if model.followUpEditing {
                TextEditor(text: Binding(get: { model.visibleFollowUp }, set: { model.state.followUp.editedPrompt = $0 }))
                    .font(.system(size: fontSize)).scrollContentBackground(.hidden).frame(minHeight: 170)
                    .accessibilityLabel("Folgeprompt bearbeiten").disabled(model.followUpBusy).sinnEditorSurface()
            } else if let edited = draft.editedPrompt, edited != response.prompt {
                Text(edited).font(.system(size: fontSize)).lineSpacing(5).textSelection(.enabled)
                Text("Von dir bearbeitet. Frühere Markierungen sind aufgehoben.").font(.system(size: 12)).foregroundStyle(Color.sinnMuted)
            } else {
                AnnotatedPromptView(response: response, fontSize: fontSize, onHelpUsed: {}, onCompare: { onCompare(draft.generatedOriginal, response, $0) })
            }
            HStack(spacing: 18) {
                HandoffButton(service: handoff, prompt: model.visibleFollowUp)
                Spacer()
                resultAction(model.followUpEditing ? "Fertig" : "Bearbeiten", symbol: model.followUpEditing ? "checkmark" : "pencil") { model.followUpEditing.toggle() }
                    .disabled(model.followUpBusy)
                resultAction("Als Vorlage", symbol: "square.stack") { onRecipe(model.visibleFollowUp) }
                resultAction("Neu erstellen", symbol: "arrow.clockwise") { model.generateFollowUp() }
                    .disabled(model.followUpBusy)
            }
            HandoffStatus(service: handoff, prompt: model.visibleFollowUp)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 28, elevated: true)
    }

    private func resultAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.sinnInk.opacity(0.75))
    }
}
