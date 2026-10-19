import SwiftUI

struct PromptExample: Identifiable {
    let id: Int
    let title: String
    let icon: String
    let text: String
}

/// Example chips under the input. As soon as you type they melt into milk drops and are
/// drawn up into the card, one after another, with a liquid neck; empty the field and they
/// drip back out and swell into chips again. The row keeps its height, so nothing jumps.
struct ExampleChips: View {
    let examples: [PromptExample]
    let absorbed: Bool
    /// Distance from the top of the chip row up to the card's bottom edge.
    let gap: CGFloat
    let pick: (PromptExample) -> Void
    @State private var frames: [Int: CGRect] = [:]
    @State private var changedAt = Date.distantPast
    @State private var running = false
    @State private var hovered: Int?
    /// After the drops are gone the empty row folds away; it opens again before they return.
    @State private var collapsed: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Milk colour shared by the resting chip and its liquid body, so the hand-over is invisible.
    static let milk = Color(red: 0.948, green: 0.958, blue: 0.978)
    private let margin: CGFloat = 60
    private let reach: CGFloat = 36

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !running)) { timeline in
            let progress = progresses(now: timeline.date)
            ZStack(alignment: .top) {
                if progress.values.contains(where: { $0 > 0.001 }) && !progress.values.allSatisfy({ $0 >= 0.999 }) {
                    liquid(progress)
                }
                HStack(spacing: 10) {
                    ForEach(examples) { example in
                        chip(example, progress: progress[example.id] ?? (absorbed ? 1 : 0))
                    }
                }
            }
        }
        .coordinateSpace(name: "chips")
        .frame(height: (collapsed ?? absorbed) ? 0 : nil, alignment: .top)
        .onPreferenceChange(ChipFrameKey.self) { frames = $0 }
        .onChange(of: absorbed) { _, isAbsorbed in
            let fold = Animation.spring(response: 0.5, dampingFraction: 0.9)
            guard !reduceMotion else { withAnimation(fold) { collapsed = isAbsorbed }; return }
            if isAbsorbed {
                changedAt = Date()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                    if absorbed { withAnimation(fold) { collapsed = true } }
                }
            } else {
                // Make room first, then let the drops fall out into it.
                let wasFolded = collapsed ?? true
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { collapsed = false }
                changedAt = Date().addingTimeInterval(wasFolded ? 0.18 : 0)
            }
            running = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { if Date().timeIntervalSince(changedAt) >= 1.6 { running = false } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHidden(absorbed)
    }

    // MARK: - Timing

    private func progresses(now: Date) -> [Int: CGFloat] {
        let elapsed = now.timeIntervalSince(changedAt)
        let middle = Double(examples.count - 1) / 2
        var result: [Int: CGFloat] = [:]
        for (index, example) in examples.enumerated() {
            if reduceMotion { result[example.id] = absorbed ? 1 : 0; continue }
            // The middle drop goes first, the outer ones follow like a pulled thread.
            let delay = abs(Double(index) - middle) * 0.09
            let value = Self.spring(elapsed - delay, response: absorbed ? 0.78 : 0.9, damping: absorbed ? 0.92 : 0.72)
            result[example.id] = absorbed ? min(1, value) : max(0, 1 - value)
        }
        return result
    }

    private static func spring(_ t: Double, response: Double, damping: Double) -> CGFloat {
        guard t > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        if damping >= 1 { return CGFloat(1 - exp(-omega * t) * (1 + omega * t)) }
        let decay = exp(-damping * omega * t)
        let frequency = omega * sqrt(1 - damping * damping)
        return CGFloat(1 - decay * (cos(frequency * t) + damping * omega / frequency * sin(frequency * t)))
    }

    private static func ease(_ x: CGFloat) -> CGFloat { let t = min(1, max(0, x)); return t * t * (3 - 2 * t) }

    // MARK: - Chip

    private func chip(_ example: PromptExample, progress: CGFloat) -> some View {
        let isHovered = hovered == example.id && progress == 0
        return Button { pick(example) } label: {
            Label(example.title, systemImage: example.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.sinnInk)
                .opacity(Double(1 - Self.ease(progress / 0.22)))
                .padding(.horizontal, 16).padding(.vertical, 11)
                .frame(minHeight: 42)
                .background {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(isHovered ? Color.white : Self.milk)
                        .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous).strokeBorder(Color.white.opacity(0.95)))
                        .shadow(color: Color.black.opacity(isHovered ? 0.1 : 0.04), radius: isHovered ? 10 : 4, y: isHovered ? 4 : 2)
                        // The liquid body takes over the moment the melt begins.
                        .opacity(progress > 0.001 ? 0 : 1)
                }
                .contentShape(Capsule())
                .offset(y: isHovered && !reduceMotion ? -2 : 0)
                .animation(SinnMotion.hover, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? example.id : (hovered == example.id ? nil : hovered) }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: ChipFrameKey.self, value: [example.id: geometry.frame(in: .named("chips"))])
        })
        .allowsHitTesting(progress < 0.05)
        .accessibilityLabel("Beispiel: " + example.title)
    }

    // MARK: - Liquid

    private func liquid(_ progress: [Int: CGFloat]) -> some View {
        let union = frames.values.reduce(CGRect.null) { $0.union($1) }
        let bounds = union.isNull ? CGRect(x: 0, y: 0, width: 400, height: 42) : union
        let top = gap + reach + 10
        let size = CGSize(width: bounds.width + margin * 2, height: bounds.height + top + 30)
        let shift = CGPoint(x: margin - bounds.minX, y: top)
        let cardCenter = bounds.midX
        let shapes: [CGRect] = examples.compactMap { example -> CGRect? in
            guard let frame = frames[example.id] else { return nil }
            let p = progress[example.id] ?? 0
            // Melt: the pill rounds into a drop. Rise: the drop stretches and is pulled up.
            let melt = Self.ease(p / 0.42)
            let rise = Self.ease((p - 0.28) / 0.72)
            let stretch = sin(.pi * rise)
            let diameter = frame.height * 0.86
            var width = frame.width + (diameter - frame.width) * melt
            var height = frame.height + (diameter - frame.height) * melt
            let shrink = 1 - 0.45 * rise
            width *= shrink * (1 - 0.18 * stretch)
            height *= shrink * (1 + 0.42 * stretch)
            let x = frame.midX + (cardCenter - frame.midX) * 0.28 * rise
            let y = frame.midY + (-gap - 6 - frame.midY) * rise
            return CGRect(x: x - width / 2 + shift.x, y: y - height / 2 + shift.y, width: width, height: height)
        }
        // A hidden reservoir just inside the card's lower edge: drops reaching it grow a neck.
        let reservoir = CGRect(x: bounds.minX + shift.x - 10, y: shift.y - gap - reach, width: bounds.width + 20, height: reach - 1)
        let goo = Canvas { context, _ in
            context.addFilter(.alphaThreshold(min: 0.5, color: .white))
            context.addFilter(.blur(radius: 9))
            context.drawLayer { layer in
                layer.fill(Path(roundedRect: reservoir, cornerRadius: 18), with: .color(.white))
                for shape in shapes {
                    layer.fill(Path(roundedRect: shape.insetBy(dx: -3, dy: -3), cornerRadius: min(shape.width, shape.height) / 2 + 3), with: .color(.white))
                }
            }
        }
        // Glassy milk: lit from above, a cool blue floor, so the drops read against the light page.
        return ZStack {
            LinearGradient(colors: [Color.white, Self.milk, Color(red: 0.83, green: 0.89, blue: 0.99)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.sinnAnnotation.opacity(0.16), .clear], center: .bottom, startRadius: 0, endRadius: size.height * 0.6)
        }
        .frame(width: size.width, height: size.height)
        .mask(goo)
        .shadow(color: Color(red: 0.1, green: 0.25, blue: 0.6).opacity(0.16), radius: 7, y: 4)
        .offset(x: bounds.minX - margin, y: -top)
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ChipFrameKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue()) { $1 } }
}
