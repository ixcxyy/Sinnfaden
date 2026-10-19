import SwiftUI
import KlarCore

extension CoachResponse {
    /// The new wording a change produced (joined target segments).
    func text(for change: PromptChange) -> String {
        segments.filter { change.targetSegmentIDs.contains($0.id) }.map(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Mind map

/// Your goal in the centre, every change as a branch. Branches draw themselves,
/// the map leans gently against the cursor, a click opens the "why".
struct ChangeMindmap: View {
    let response: CoachResponse
    let original: String
    @State private var drawn = false
    @State private var selected: String?
    @State private var hover: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Node: Identifiable {
        let id: String
        let eyebrow: String
        let title: String
        let open: Bool
    }

    private var nodes: [Node] {
        let changes = response.changes.prefix(8).map { Node(id: $0.id, eyebrow: $0.category.uppercased(), title: $0.title, open: false) }
        let unknowns = response.unknowns.prefix(max(0, 10 - changes.count)).enumerated().map {
            Node(id: "unknown-\($0.offset)", eyebrow: "OFFEN", title: $0.element, open: true)
        }
        return changes + unknowns
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeometryReader { geo in
                let size = geo.size
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let items = nodes
                ZStack {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, node in
                        Branch(from: center, to: position(index, count: items.count, size: size))
                            .trim(from: 0, to: drawn ? 1 : 0)
                            .stroke(node.open ? Color.sinnMuted.opacity(0.35) : Color.sinnAnnotation.opacity(selected == node.id ? 0.8 : 0.35),
                                    style: StrokeStyle(lineWidth: selected == node.id ? 3 : 2, lineCap: .round, dash: node.open ? [5, 6] : []))
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.7).delay(0.15 + Double(index) * 0.09), value: drawn)
                    }
                    centerNode.position(center).offset(parallax(depth: 0.4, size: size))
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, node in
                        nodeView(node)
                            .position(position(index, count: items.count, size: size))
                            .offset(parallax(depth: 1, size: size))
                            .scaleEffect(drawn || reduceMotion ? 1 : 0.5)
                            .opacity(drawn ? 1 : 0)
                            .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.68).delay(0.45 + Double(index) * 0.09), value: drawn)
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.8), value: hover)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let point) = phase { hover = point } else { hover = nil }
                }
            }
            .frame(height: 430)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.ultraThinMaterial).opacity(0.6)
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.9)))
            }
            detail
        }
        .onAppear { drawn = true }
    }

    private func position(_ index: Int, count: Int, size: CGSize) -> CGPoint {
        let angle = Double.pi + Double(index) * 2 * .pi / Double(max(count, 1)) + (count == 2 ? 0 : -0.35)
        let rx = max(120, size.width / 2 - 112), ry = max(90, size.height / 2 - 52)
        return CGPoint(x: size.width / 2 + CGFloat(cos(angle)) * rx, y: size.height / 2 + CGFloat(sin(angle)) * ry)
    }

    private func parallax(depth: CGFloat, size: CGSize) -> CGSize {
        guard let hover, !reduceMotion else { return .zero }
        return CGSize(width: (hover.x - size.width / 2) * -0.025 * depth, height: (hover.y - size.height / 2) * -0.025 * depth)
    }

    private var centerNode: some View {
        VStack(spacing: 6) {
            SinnfadenMark(color: .white, weight: 1.2).frame(width: 22, height: 22)
            Text("Dein Ziel").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            Text(original.prefix(70) + (original.count > 70 ? "…" : ""))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center).lineLimit(3)
        }
        .padding(16)
        .frame(width: 190)
        .background(LinearGradient(colors: [Color(red: 0.25, green: 0.55, blue: 1), Color.sinnAnnotation], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.sinnAnnotation.opacity(0.4), radius: 22, y: 10)
        .scaleEffect(drawn || reduceMotion ? 1 : 0.4)
        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.62), value: drawn)
    }

    private func nodeView(_ node: Node) -> some View {
        let isSelected = selected == node.id
        let dimmed = selected != nil && !isSelected
        return Button {
            guard !node.open else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { selected = isSelected ? nil : node.id }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(node.eyebrow).font(.system(size: 9, weight: .bold)).tracking(1.2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : node.open ? Color.sinnMuted : Color.sinnAnnotation)
                Text(node.title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.sinnInk)
                    .lineLimit(3).multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(width: 178, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
                if isSelected { shape.fill(Color.sinnAnnotation) } else { shape.fill(.regularMaterial).overlay(shape.fill(Color.white.opacity(0.5))) }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(node.open ? Color.sinnMuted.opacity(0.4) : Color.white, style: StrokeStyle(lineWidth: 1, dash: node.open ? [4, 4] : []))
            }
            .shadow(color: Color.black.opacity(isSelected ? 0.18 : 0.07), radius: isSelected ? 18 : 10, y: isSelected ? 10 : 4)
            .scaleEffect(isSelected ? 1.06 : 1)
            .opacity(dimmed ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(node.open ? "Offene Angabe: \(node.title)" : "Änderung: \(node.title)")
    }

    @ViewBuilder private var detail: some View {
        if let id = selected, let change = response.changes.first(where: { $0.id == id }) {
            ChangeDetailCard(response: response, change: change)
                .id(id)
                .transition(.opacity.combined(with: .offset(y: 10)))
        } else {
            Label("Klick auf einen Zweig, um das Warum zu sehen.", systemImage: "hand.tap")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color.sinnMuted)
                .padding(.horizontal, 6)
        }
    }
}

private struct Branch: Shape {
    let from: CGPoint
    let to: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: from)
        let mid = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        let dx = to.x - from.x, dy = to.y - from.y
        p.addQuadCurve(to: to, control: CGPoint(x: mid.x - dy * 0.18, y: mid.y + dx * 0.18))
        return p
    }
}

struct ChangeDetailCard: View {
    let response: CoachResponse
    let change: PromptChange
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(change.title).font(SinnType.title(20))
            Text(change.explanation).font(.system(size: 15)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            BeforeAfter(before: change.originalText, after: response.text(for: change))
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 22, elevated: true)
    }
}

struct BeforeAfter: View {
    let before: String?
    let after: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let before, !before.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("VORHER").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(Color.sinnMuted).frame(width: 56, alignment: .leading)
                    Text(before).font(.system(size: 14)).foregroundStyle(Color.sinnMuted).strikethrough(color: Color.sinnMuted.opacity(0.5))
                }
            }
            if !after.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("JETZT").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(Color.sinnAnnotation).frame(width: 56, alignment: .leading)
                    Text(after).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.sinnAnnotation)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.sinnAnnotationWash, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }
}

// MARK: - Grid

struct ChangeGrid: View {
    let response: CoachResponse
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
            ForEach(Array(response.changes.enumerated()), id: \.element.id) { index, change in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(change.category.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(Color.sinnAnnotation)
                        Spacer()
                        Text("\(index + 1)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Color.sinnAnnotation, in: Circle())
                    }
                    Text(change.title).font(.system(size: 16, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(change.explanation).font(.system(size: 13)).foregroundStyle(Color.sinnMuted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    BeforeAfter(before: change.originalText, after: response.text(for: change))
                }
                .padding(18).frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                .cardSurface(radius: 22)
                .sinnReveal(index)
            }
            ForEach(Array(response.unknowns.enumerated()), id: \.offset) { index, unknown in
                Label(unknown, systemImage: "questionmark.circle")
                    .font(.system(size: 13)).foregroundStyle(Color.sinnMuted)
                    .padding(18).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.sinnMuted.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
                    .sinnReveal(response.changes.count + index)
            }
        }
    }
}

// MARK: - Step by step

/// One change at a time. Progress never starts empty: step one is already lit.
struct StepByStep: View {
    let response: CoachResponse
    var onPractice: () -> Void
    @State private var index = 0
    @State private var direction: CGFloat = 1
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let steps = response.changes
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { step in
                    Capsule().fill(step <= index || finished ? Color.sinnAnnotation : Color.sinnStructure)
                        .frame(height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: index)
                }
            }
            if finished {
                completion(count: steps.count).transition(.scale(scale: 0.9).combined(with: .opacity))
            } else if steps.indices.contains(index) {
                stepCard(steps[index], number: index + 1, total: steps.count)
                    .id(index)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: reduceMotion ? 0 : 70 * direction)),
                                            removal: .opacity.combined(with: .offset(x: reduceMotion ? 0 : -70 * direction))))
                HStack {
                    Button { go(-1) } label: { Label("Zurück", systemImage: "chevron.left") }
                        .buttonStyle(SecondaryButtonStyle()).disabled(index == 0)
                    Spacer()
                    Button {
                        if index == steps.count - 1 { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { finished = true } } else { go(1) }
                    } label: {
                        Label(index == steps.count - 1 ? "Fertig" : "Weiter", systemImage: index == steps.count - 1 ? "checkmark" : "chevron.right")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private func go(_ delta: Int) {
        direction = CGFloat(delta)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.85)) { index += delta }
    }

    private func stepCard(_ change: PromptChange, number: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SCHRITT \(number) VON \(total) · \(change.category.uppercased())")
                .font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(Color.sinnAnnotation)
            Text(change.title).font(SinnType.display(30)).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
            BeforeAfter(before: change.originalText, after: response.text(for: change))
            VStack(alignment: .leading, spacing: 6) {
                Text("WARUM").font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(Color.sinnMuted)
                Text(change.explanation).font(.system(size: 16)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(26).frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 28, elevated: true)
    }

    private func completion(count: Int) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(Color.sinnAnnotation)
                .symbolEffect(.bounce, value: finished)
            Text("Du kennst jetzt alle \(count) Änderungen.").font(SinnType.title(24))
            Text("Probier eine davon gleich selbst aus. So bleibt es hängen.").font(.system(size: 15)).foregroundStyle(Color.sinnMuted)
            HStack(spacing: 10) {
                Button { withAnimation { finished = false; index = 0 } } label: { Label("Nochmal ansehen", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(SecondaryButtonStyle())
                Button(action: onPractice) { Label("Selbst ausprobieren", systemImage: "leaf") }
                    .buttonStyle(PrimaryButtonStyle())
            }.padding(.top, 4)
        }
        .padding(32).frame(maxWidth: .infinity)
        .cardSurface(radius: 28, elevated: true)
    }
}
