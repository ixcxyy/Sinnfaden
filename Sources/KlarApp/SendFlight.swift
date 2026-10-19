import SwiftUI

/// The words you sent, captured at their exact place in the editor, and when they left.
struct WordLaunch: Equatable {
    let words: [CapturedWord]
    let fontSize: CGFloat
    let start: Date

    static let flight = 1.05

    func delay(_ index: Int) -> Double {
        // Reading order with a little irregularity, like grains loosening from a surface.
        min(0.55, Double(index) * 0.024) + Self.noise(index) * 0.07
    }
    var duration: Double { words.indices.map { delay($0) }.max().map { $0 + Self.flight } ?? 0 }

    static func noise(_ index: Int) -> Double {
        let value = sin(Double(index) * 12.9898 + 78.233) * 43758.5453
        return value - floor(value)
    }
}

/// One word on its way into the bubble.
struct FlyingWord {
    let text: String
    let center: CGPoint
    let scale: CGFloat
    let rotation: Double
    let blur: CGFloat
    let textOpacity: Double
    let tint: CGFloat
    let drop: CGFloat
    let progress: CGFloat
}

enum WordVortex {
    /// Anticipation (the word lifts off its line), then a spiral that tightens and speeds up.
    static func state(for word: CapturedWord, index: Int, launch: WordLaunch, elapsed: Double, origin: CGPoint, target: CGPoint) -> FlyingWord {
        let t = CGFloat(min(1, max(0, (elapsed - launch.delay(index)) / WordLaunch.flight)))
        let lift: CGFloat = 0.16
        let e: CGFloat = t < lift ? -0.05 * sin(.pi * t / lift) : pow((t - lift) / (1 - lift), 1.75)
        let start = CGPoint(x: word.frame.midX - origin.x, y: word.frame.midY - origin.y)
        let dx = start.x - target.x, dy = start.y - target.y
        let radius = hypot(dx, dy) * (1 - e)
        let spin: CGFloat = 1.25 + 0.35 * CGFloat(WordLaunch.noise(index + 7))
        let angle = atan2(dy, dx) + spin * max(0, e) * (1.15 - 0.15 * max(0, e))
        let center = CGPoint(x: target.x + cos(angle) * radius, y: target.y + sin(angle) * radius)
        let hop = t < lift ? -6 * sin(.pi * t / lift) : 0
        let fade = 1 - smooth((e - 0.72) / 0.2)
        let dropIn = smooth((e - 0.55) / 0.2)
        let dropOut = 1 - 0.65 * smooth((e - 0.9) / 0.1)
        return FlyingWord(text: word.text,
                          center: CGPoint(x: center.x, y: center.y + hop),
                          scale: 1 - 0.72 * max(0, e),
                          rotation: Double(spin * max(0, e)) * 40,
                          blur: 3.5 * max(0, e),
                          textOpacity: Double(fade),
                          tint: smooth(e / 0.6),
                          drop: word.frame.height * 0.42 * dropIn * dropOut * (t >= 1 ? 0 : 1),
                          progress: max(0, e))
    }

    static func smooth(_ x: CGFloat) -> CGFloat { let t = min(1, max(0, x)); return t * t * (3 - 2 * t) }

    static func tint(_ amount: CGFloat) -> Color {
        // Ink to annotation blue: the words become Sinnfaden's liquid on the way in.
        let ink = (0.098, 0.098, 0.106), blue = (0.031, 0.392, 0.851)
        let a = Double(amount)
        return Color(red: ink.0 + (blue.0 - ink.0) * a, green: ink.1 + (blue.1 - ink.1) * a, blue: ink.2 + (blue.2 - ink.2) * a)
    }
}

/// The send stage: words spiral in, turn into drops and merge into a bubble that forms and
/// swells with every word it swallows. A pressure ring marks the last one landing.
struct GatheringStage: View {
    let launch: WordLaunch?
    let checking: Bool
    var size: CGFloat = 340
    @State private var settled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let target = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            if let launch, !reduceMotion, !launch.words.isEmpty {
                TimelineView(.animation(minimumInterval: nil, paused: settled)) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(launch.start)
                    let words = launch.words.enumerated().map { WordVortex.state(for: $0.element, index: $0.offset, launch: launch, elapsed: elapsed, origin: origin, target: target) }
                    stage(words: words, elapsed: elapsed, landing: launch.duration - 0.12, target: target)
                }
            } else {
                stage(words: [], elapsed: 99, landing: -10, target: target)
            }
        }
        .onAppear {
            guard let launch else { settled = true; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + launch.duration + 1.4) { settled = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stage(words: [FlyingWord], elapsed: Double, landing: Double, target: CGPoint) -> some View {
        let gathered = words.isEmpty ? 1 : words.map { min(1, $0.progress) }.reduce(0, +) / CGFloat(words.count)
        let growth = 0.06 + 0.94 * WordVortex.smooth(gathered * 1.08)
        let local = CGPoint(x: target.x - size / 2, y: target.y - size / 2)
        let drops = words.filter { $0.drop > 0.5 }.map { LiquidBlob(center: CGPoint(x: $0.center.x - local.x, y: $0.center.y - local.y), radius: $0.drop) }
        return ZStack {
            pressureRing(elapsed - landing, target: target, delay: 0)
            pressureRing(elapsed - landing, target: target, delay: 0.14)
            LiquidMind(checking: checking, size: size, growth: growth, gather: drops)
                .frame(width: size, height: size)
                .position(target)
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                if word.textOpacity > 0.01 {
                    Text(word.text)
                        .font(.system(size: launchFont, weight: .medium))
                        .foregroundStyle(WordVortex.tint(word.tint))
                        .fixedSize()
                        .scaleEffect(word.scale)
                        .rotationEffect(.degrees(word.rotation))
                        .blur(radius: word.blur)
                        .opacity(word.textOpacity)
                        .position(word.center)
                }
            }
        }
    }

    private var launchFont: CGFloat { launch?.fontSize ?? 19 }

    @ViewBuilder private func pressureRing(_ since: Double, target: CGPoint, delay: Double) -> some View {
        let p = CGFloat((since - delay) / 0.95)
        if p > 0 && p < 1 {
            let eased = 1 - pow(1 - p, 3)
            Circle()
                .strokeBorder(Color.sinnAnnotation.opacity(Double(0.42 * (1 - p))), lineWidth: 1.5 + 7 * (1 - p))
                .frame(width: size * (0.55 + 1.1 * eased), height: size * (0.55 + 1.1 * eased))
                .blur(radius: 2 + 6 * p)
                .position(target)
        }
    }
}
