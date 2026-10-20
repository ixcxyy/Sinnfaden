import SwiftUI

/// The words you sent, captured at their exact place in the editor, and when they left.
/// Long prompts travel as a bounded number of word groups (neighbours on the same line),
/// so the choreography keeps its length and never animates hundreds of views.
struct WordLaunch: Equatable {
    let words: [CapturedWord]
    let fontSize: CGFloat
    let start: Date

    static let maximumPieces = 34
    /// Each piece's own journey: lift, path, transformation.
    static let flight = 0.56
    /// The reading-order stagger is capped, so long prompts do not queue up.
    static let staggerStep = 0.017
    static let staggerCap = 0.20
    static let release = 0.07

    init(words: [CapturedWord], fontSize: CGFloat, start: Date) {
        self.words = Self.grouped(words)
        self.fontSize = fontSize
        self.start = start
    }

    func delay(_ index: Int) -> Double {
        Self.release + min(Self.staggerCap, Double(index) * Self.staggerStep) + Self.noise(index) * 0.012
    }
    var duration: Double { words.indices.map { delay($0) }.max().map { $0 + Self.flight } ?? 0 }
    /// When piece `index` touches the body (reference-date seconds).
    func arrival(_ index: Int) -> TimeInterval { start.timeIntervalSinceReferenceDate + delay(index) + Self.flight * WordVortex.contactProgress }

    static func noise(_ index: Int) -> Double {
        let value = sin(Double(index) * 12.9898 + 78.233) * 43758.5453
        return value - floor(value)
    }

    private static func grouped(_ words: [CapturedWord]) -> [CapturedWord] {
        guard words.count > maximumPieces else { return words }
        let size = Int((Double(words.count) / Double(maximumPieces)).rounded(.up))
        var pieces: [CapturedWord] = []
        var current: [CapturedWord] = []
        func flush() {
            guard let first = current.first else { return }
            let frame = current.dropFirst().reduce(first.frame) { $0.union($1.frame) }
            pieces.append(CapturedWord(id: pieces.count, text: current.map(\.text).joined(separator: " "), frame: frame))
            current.removeAll()
        }
        for word in words {
            if let last = current.last, abs(last.frame.midY - word.frame.midY) > 2 || current.count >= size { flush() }
            current.append(word)
        }
        flush()
        return pieces
    }
}

/// One word (or group) on its way into the body.
struct FlyingWord {
    let text: String
    let center: CGPoint
    let rotation: Double
    let textOpacity: Double
    /// 0…1: how far the soft mask has dissolved the letters.
    let dissolve: CGFloat
    let dissolveFromTrailing: Bool
    let tint: CGFloat
    let drop: CGFloat
    let direction: CGVector
    let progress: CGFloat
}

enum WordVortex {
    /// Share of the path at which a drop meets the body's edge.
    static let contactProgress = 0.9

    /// Lift a few points, then a smooth curve from a related family toward the body. The
    /// letters stay recognizable for most of the way; only the last third transforms.
    static func state(for word: CapturedWord, index: Int, launch: WordLaunch, elapsed: Double, origin: CGPoint, target: CGPoint) -> FlyingWord {
        let raw = (elapsed - launch.delay(index)) / WordLaunch.flight
        let t = CGFloat(min(1, max(0, raw)))
        let start = CGPoint(x: word.frame.midX - origin.x, y: word.frame.midY - origin.y)
        let lift: CGFloat = 0.14
        let rise = -3 * smooth(t / lift)
        let s = max(0, (t - lift) / (1 - lift))
        // Accelerating into the body: gathered, not thrown.
        let u = 0.45 * smooth(s) + 0.55 * s * s
        let from = CGPoint(x: start.x, y: start.y + rise)
        let point = bezier(from: from, to: target, bend: bendFor(start: start, target: target), u: u)
        let ahead = bezier(from: from, to: target, bend: bendFor(start: start, target: target), u: min(1, u + 0.02))
        let direction = normalized(CGVector(dx: ahead.x - point.x, dy: ahead.y - point.y))
        let transform = smooth((s - 0.6) / 0.3)
        let heading = atan2(direction.dy, direction.dx)
        let rotation = Double(max(-0.14, min(0.14, sin(heading) * 0.12))) * 180 / .pi * Double(1 - transform) * Double(smooth(s / 0.3))
        let dropIn = smooth((s - 0.62) / 0.16)
        let dropOut = t >= 1 ? 0 : 1 - smooth((s - 0.94) / 0.06)
        return FlyingWord(text: word.text,
                          center: point,
                          rotation: rotation,
                          textOpacity: Double(1 - smooth((s - 0.72) / 0.2)),
                          dissolve: transform,
                          dissolveFromTrailing: target.x < start.x,
                          tint: smooth((s - 0.45) / 0.35),
                          drop: min(10, word.frame.height * 0.36) * dropIn * dropOut,
                          direction: direction,
                          progress: CGFloat(max(0, min(1, raw))))
    }

    /// Related curves: each bows away from the body's vertical axis by an amount that grows
    /// with distance, so words from the left and right swing in from their own side.
    private static func bendFor(start: CGPoint, target: CGPoint) -> CGFloat {
        let distance = hypot(target.x - start.x, target.y - start.y)
        let side: CGFloat = start.x < target.x ? -1 : 1
        return side * min(90, max(16, distance * 0.2))
    }

    private static func bezier(from a: CGPoint, to b: CGPoint, bend: CGFloat, u: CGFloat) -> CGPoint {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let along = normalized(CGVector(dx: b.x - a.x, dy: b.y - a.y))
        let control = CGPoint(x: mid.x - along.dy * bend, y: mid.y + along.dx * bend - abs(bend) * 0.35)
        let v = 1 - u
        return CGPoint(x: v * v * a.x + 2 * v * u * control.x + u * u * b.x,
                       y: v * v * a.y + 2 * v * u * control.y + u * u * b.y)
    }

    private static func normalized(_ v: CGVector) -> CGVector {
        let length = hypot(v.dx, v.dy)
        return length > 0.0001 ? CGVector(dx: v.dx / length, dy: v.dy / length) : CGVector(dx: 0, dy: 1)
    }

    static func smooth(_ x: CGFloat) -> CGFloat { let t = min(1, max(0, x)); return t * t * (3 - 2 * t) }

    static func tint(_ amount: CGFloat) -> Color {
        // Ink to the body's blue: the words become its material on the way in.
        let ink = (0.098, 0.098, 0.106), blue = (0.10, 0.42, 0.90)
        let a = Double(amount)
        return Color(red: ink.0 + (blue.0 - ink.0) * a, green: ink.1 + (blue.1 - ink.1) * a, blue: ink.2 + (blue.2 - ink.2) * a)
    }
}

/// The send stage: the written words leave their lines, gather along related curves,
/// soften into drops and merge into the body, which grows and answers each arrival with a
/// small local dent. The body then continues straight into its idle motion.
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
                    stage(words: words, launch: launch, target: target)
                }
            } else {
                stage(words: [], launch: nil, target: target)
            }
        }
        .onAppear {
            guard let launch else { settled = true; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + launch.duration + 0.4) { settled = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func stage(words: [FlyingWord], launch: WordLaunch?, target: CGPoint) -> some View {
        let arrived = words.isEmpty ? 1 : CGFloat(words.filter { $0.progress >= CGFloat(WordVortex.contactProgress) }.count) / CGFloat(words.count)
        let incoming = words.isEmpty ? 1 : words.map { min(1, $0.progress) }.reduce(0, +) / CGFloat(words.count)
        let growth = words.isEmpty ? 1 : 0.18 + 0.82 * WordVortex.smooth(0.35 * incoming + 0.65 * arrived)
        let local = CGPoint(x: target.x - size / 2, y: target.y - size / 2)
        var drops: [LiquidBlob] = []
        for word in words where word.drop > 0.5 {
            let center = CGPoint(x: word.center.x - local.x, y: word.center.y - local.y)
            drops.append(LiquidBlob(center: center, radius: word.drop))
            // A shorter trailing bead stretches the drop along its motion.
            drops.append(LiquidBlob(center: CGPoint(x: center.x - word.direction.dx * word.drop * 0.95, y: center.y - word.direction.dy * word.drop * 0.95),
                                    radius: word.drop * 0.62))
        }
        var impacts: [LiquidImpact] = []
        var lastArrival: TimeInterval?
        if let launch {
            for (index, word) in launch.words.enumerated() where index < words.count {
                // The drop arrives along its final heading: dent where it actually touches.
                let heading = words[index].direction
                impacts.append(LiquidImpact(angle: atan2(-heading.dy, -heading.dx), time: launch.arrival(index), strength: launch.words.count > 12 ? 0.6 : 1))
                lastArrival = max(lastArrival ?? 0, launch.arrival(index))
                _ = word
            }
        }
        return ZStack {
            LiquidMind(checking: checking, size: size, growth: growth, gather: drops, impacts: impacts, settleAt: lastArrival)
                .frame(width: size, height: size)
                .position(target)
            ForEach(Array(words.enumerated()), id: \.offset) { _, word in
                if word.textOpacity > 0.01 {
                    Text(word.text)
                        .font(.system(size: launch?.fontSize ?? 19))
                        .foregroundStyle(WordVortex.tint(word.tint))
                        .fixedSize()
                        // Letters dissolve through a soft edge that travels across the word.
                        .mask {
                            LinearGradient(stops: [.init(color: .white, location: 0),
                                                   .init(color: .white, location: max(0, 1 - 1.3 * word.dissolve)),
                                                   .init(color: .clear, location: max(0.02, 1.25 - 1.3 * word.dissolve))],
                                           startPoint: word.dissolveFromTrailing ? .trailing : .leading,
                                           endPoint: word.dissolveFromTrailing ? .leading : .trailing)
                        }
                        .rotationEffect(.degrees(word.rotation))
                        .opacity(word.textOpacity)
                        .position(word.center)
                }
            }
        }
    }
}
