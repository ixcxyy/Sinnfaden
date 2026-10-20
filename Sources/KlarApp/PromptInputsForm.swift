import SwiftUI
import KlarCore

/// The fields Sinnfaden built for this prompt. Answering them up front means ChatGPT
/// can start right away instead of asking back. The prompt updates live.
struct PromptInputsForm: View {
    @ObservedObject var model: AppModel
    let inputs: [PromptInput]
    /// Inside the prompt sheet, right under the text it completes: no card of its own.
    var embedded = false
    @State private var built = false
    @State private var flashID: String?
    @FocusState private var focus: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var answered: Int {
        inputs.filter { !(model.inputValues[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var body: some View {
        if embedded {
            fields
                .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            fields
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(radius: 28, elevated: true)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [Color.sinnAnnotation.opacity(0.45), Color.sinnAnnotation.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                        .allowsHitTesting(false)
                }
        }
    }

    private var title: String {
        model.promptUseError != nil ? "Kürze eine Angabe, damit dein Prompt passt." : answered == inputs.count ? "Alles drin – dein Prompt ist komplett." : "Noch \(inputs.count - answered) \(inputs.count - answered == 1 ? "Angabe" : "Angaben"), dann ist alles drin"
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: embedded ? 14 : 18) {
            if embedded {
                HStack(spacing: 8) {
                    ProgressRing(progress: inputs.isEmpty ? 1 : Double(answered) / Double(inputs.count))
                        .frame(width: 18, height: 18)
                    Text(title).font(.system(size: 13, weight: .semibold))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: answered)
                }
            } else {
            HStack(spacing: 14) {
                ProgressRing(progress: inputs.isEmpty ? 1 : Double(answered) / Double(inputs.count))
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.25), value: answered)
                    Label("Sinnfaden hat diese Felder für deinen Prompt gebaut", systemImage: "sparkles")
                        .font(.system(size: 12)).foregroundStyle(Color.sinnMuted)
                }
            }
            }
            ForEach(Array(inputs.enumerated()), id: \.element.id) { index, input in
                InputFieldRow(input: input, value: binding(for: input), selectedOptions: model.selectedOptions(for: input),
                              toggleOption: { model.toggleOption($0, for: input) }, focus: $focus,
                              flashing: flashID == input.id)
                    .id("input-" + input.id)
                    .opacity(built ? 1 : 0)
                    .offset(y: built || reduceMotion ? 0 : 14)
                    .blur(radius: built || reduceMotion ? 0 : 8)
                    .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.55, dampingFraction: 0.8).delay(0.25 + Double(index) * 0.11), value: built)
            }
        }
        .onAppear { built = true }
        // A click on an orange placeholder (or a stopped copy) leads straight to its field.
        .onChange(of: model.focusedInputID) { _, id in
            guard let id else { return }
            focus = id
            withAnimation(.easeOut(duration: 0.2)) { flashID = id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { if flashID == id { withAnimation(.easeOut(duration: 0.5)) { flashID = nil } } }
        }
    }

    private func binding(for input: PromptInput) -> Binding<String> {
        Binding(get: { model.inputValues[input.id] ?? "" }, set: { model.inputValues[input.id] = $0 })
    }
}

/// Goal-gradient ring: fills as answers come in.
private struct ProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.sinnStructure, lineWidth: 5)
            Circle().trim(from: 0, to: max(0.04, progress))
                .stroke(Color.sinnAnnotation, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.75), value: progress)
            Image(systemName: progress >= 1 ? "checkmark" : "list.bullet")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(progress >= 1 ? Color.sinnAnnotation : Color.sinnMuted)
                .contentTransition(.symbolEffect(.replace))
        }
    }
}

private struct InputFieldRow: View {
    let input: PromptInput
    @Binding var value: String
    let selectedOptions: Set<String>?
    var toggleOption: (String) -> Void
    var focus: FocusState<String?>.Binding
    var flashing = false
    @State private var date = Date()
    @FocusState private var editingDateText: Bool
    @FocusState private var editingChoiceText: Bool

    private var filled: Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hint: String { input.placeholder.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: filled ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(filled ? Color.sinnAnnotation : Color.sinnMuted.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: filled)
                Text(input.label).font(.system(size: 14, weight: .semibold))
                if input.required {
                    Text("wichtig").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.sinnAnnotation)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Color.sinnAnnotationWash, in: Capsule())
                }
                Spacer()
            }
            control
            Text(input.why).font(.system(size: 12)).foregroundStyle(Color.sinnMuted).fixedSize(horizontal: false, vertical: true)
        }
        // The flash marks the row around it without moving anything.
        .background(Color.orange.opacity(flashing ? 0.10 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous).inset(by: -8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(input.label)
    }

    @ViewBuilder private var control: some View {
        switch input.kind {
        case .text:
            TextField(hint, text: $value).textFieldStyle(SinnFieldStyle())
                .focused(focus, equals: input.id)
        case .long_text:
            // Lists (ingredients, steps) need real lines: Return starts a new one.
            ZStack(alignment: .topLeading) {
                if value.isEmpty {
                    Text(hint).foregroundStyle(Color.sinnMuted.opacity(0.7)).padding(.horizontal, 14).padding(.vertical, 11)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $value)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .frame(minHeight: 66, maxHeight: 150)
                    .focused(focus, equals: input.id)
            }
            .font(.system(size: 14))
            .background(Color.sinnStructure.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.sinnInk.opacity(0.08)))
            .accessibilityLabel(input.label)
        case .choice:
            ChipFlow(options: input.options, selected: Set([value]), multiple: false) { option in
                value = value == option ? "" : option
            }
        case .multi_choice:
            if let selectedOptions, !editingChoiceText {
                ChipFlow(options: input.options, selected: selectedOptions, multiple: true, toggle: toggleOption)
            } else {
                TextField(hint, text: $value, axis: .vertical).textFieldStyle(SinnFieldStyle()).lineLimit(2...5)
                    .focused($editingChoiceText)
            }
        case .scale:
            ScalePicker(options: input.options, value: $value)
        case .number:
            HStack(spacing: 12) {
                TextField("Zahl", text: $value).textFieldStyle(SinnFieldStyle()).frame(width: 120)
                    .focused(focus, equals: input.id)
                Stepper("", value: Binding(get: { PromptNumberInput.stepperValue(from: value) }, set: { value = PromptNumberInput.text(for: $0) }), in: 0...10_000)
                    .labelsHidden()
            }
        case .date:
            if editingDateText || PromptDateInput.requiresTextEntry(for: value) {
                TextField(hint, text: $value).textFieldStyle(SinnFieldStyle())
                    .focused($editingDateText)
            } else {
                DatePicker("", selection: Binding(get: { PromptDateInput.selection(from: value, fallback: date) }, set: { date = $0; value = PromptDateInput.text(for: $0) }), displayedComponents: .date)
                    .datePickerStyle(.field).labelsHidden()
            }
        }
    }
}

/// Wrapping row of choice chips with a springy press.
private struct ChipFlow: View {
    let options: [String]
    let selected: Set<String>
    let multiple: Bool
    let toggle: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(PromptChoiceInput.uniqueOptions(options), id: \.self) { option in
                let isOn = selected.contains(option)
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) { toggle(option) } } label: {
                    HStack(spacing: 6) {
                        if isOn {
                            Image(systemName: multiple ? "checkmark" : "circle.fill").font(.system(size: multiple ? 10 : 6, weight: .bold))
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(option)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOn ? Color.white : Color.sinnInk)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(isOn ? AnyShapeStyle(Color.sinnAnnotation) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                    .overlay(Capsule().strokeBorder(isOn ? Color.clear : Color.black.opacity(0.08)))
                    .shadow(color: Color.sinnAnnotation.opacity(isOn ? 0.3 : 0), radius: 8, y: 3)
                    .scaleEffect(isOn ? 1.03 : 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// Ordered choices on a track; a knob slides to the chosen step.
private struct ScalePicker: View {
    let options: [String]
    @Binding var value: String
    @Namespace private var knob
    var body: some View {
        HStack(spacing: 0) {
            ForEach(PromptChoiceInput.uniqueOptions(options), id: \.self) { option in
                Button { withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) { value = option } } label: {
                    Text(option)
                        .font(.system(size: 13, weight: value == option ? .semibold : .medium))
                        .foregroundStyle(value == option ? Color.white : Color.sinnInk)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background {
                            if value == option {
                                Capsule().fill(Color.sinnAnnotation).matchedGeometryEffect(id: "knob", in: knob)
                                    .shadow(color: Color.sinnAnnotation.opacity(0.35), radius: 8, y: 3)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(value == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.sinnStructure.opacity(0.7), in: Capsule())
    }
}

/// Minimal wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; maxX = max(maxX, x - spacing); rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(width, maxX), height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}
