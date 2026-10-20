import AppKit
import SwiftUI

/// Per-run randomness for the send and loading motion. Every request gets its own seed, so no
/// two runs look alike; `--animation-seed=N` makes runs reproducible (N, N+1, N+2, …).
enum AnimationSeed {
    private static var runs: UInt64 = 0

    static func next() -> UInt64 {
        defer { runs += 1 }
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--animation-seed=") }),
           let base = UInt64(argument.dropFirst("--animation-seed=".count)) {
            return base &+ runs
        }
        return UInt64.random(in: 1...UInt64.max)
    }

    /// Stateless, uniform 0…1 for (seed, index, salt): the same inputs always give the same value.
    static func unit(_ seed: UInt64, _ index: Int, _ salt: UInt64) -> Double {
        var z = seed &+ UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }

    static func range(_ seed: UInt64, _ index: Int, _ salt: UInt64, _ lower: Double, _ upper: Double) -> Double {
        lower + (upper - lower) * unit(seed, index, salt)
    }
}

/// The words you sent, captured at their exact place in the editor, and when they left.
/// Neighbouring words on one line travel together as one piece of material, and the number of
/// pieces is bounded, so the choreography keeps its length and never animates hundreds of views.
struct WordLaunch: Equatable {
    let words: [CapturedWord]
    let fontSize: CGFloat
    let start: Date
    let seed: UInt64

    static let maximumPieces = 24
    /// Phase A (0–120 ms): everything lifts and aligns together, still in place.
    static let lift = 0.12
    /// Phase B (100–300 ms): pieces detach in reading order with overlapping stagger.
    static let detachStart = 0.10
    static let detachSpan = 0.20
    /// Phase C: each piece's path; it touches the body at `WordVortex.contactProgress`,
    /// so the last contact lands before ~700 ms. Phase D (to ~950 ms) is the body settling.
    static let flight = 0.44

    init(words: [CapturedWord], fontSize: CGFloat, start: Date, seed: UInt64 = AnimationSeed.next()) {
        self.words = Self.grouped(words)
        self.fontSize = fontSize
        self.start = start
        self.seed = seed
    }

    /// When piece `index` detaches (seconds after the send).
    func delay(_ index: Int) -> Double {
        let order = words.count > 1 ? Double(index) / Double(words.count - 1) : 0
        let jitter = (AnimationSeed.unit(seed, index, 1) - 0.5) * 0.04
        return min(Self.detachStart + Self.detachSpan, max(Self.detachStart, Self.detachStart + Self.detachSpan * order + jitter))
    }
    var duration: Double { words.indices.map { delay($0) }.max().map { $0 + Self.flight } ?? 0 }
    /// When piece `index` touches the body (reference-date seconds).
    func arrival(_ index: Int) -> TimeInterval { start.timeIntervalSinceReferenceDate + delay(index) + Self.flight * WordVortex.contactProgress }

    /// Lift height of this run (2–4 pt) and how strongly its paths bow (0.75–1.25).
    var liftHeight: CGFloat { CGFloat(AnimationSeed.range(seed, 0, 2, 2, 4)) }
    var bendScale: CGFloat { CGFloat(AnimationSeed.range(seed, 0, 3, 0.75, 1.25)) }
    /// Where on the body the stream converges: a few points off-centre, different per run.
    var convergence: CGVector {
        let angle = AnimationSeed.range(seed, 0, 4, 0, 2 * .pi), radius = AnimationSeed.range(seed, 0, 5, 4, 14)
        return CGVector(dx: cos(angle) * radius, dy: sin(angle) * radius * 0.6)
    }

    static func grouped(_ words: [CapturedWord]) -> [CapturedWord] {
        // Neighbours share a piece even in short prompts; long prompts are bounded.
        let size = max(words.count > 8 ? 2 : 1, Int((Double(words.count) / Double(maximumPieces)).rounded(.up)))
        guard size > 1 else { return words }
        var pieces: [CapturedWord] = []
        var current: [CapturedWord] = []
        func flush() {
            guard let first = current.first else { return }
            let frame = current.dropFirst().reduce(first.frame) { $0.union($1.frame) }
            pieces.append(CapturedWord(id: pieces.count, text: current.map(\.text).joined(separator: " "), frame: frame,
                                       fragments: current.flatMap(\.sourceFragments)))
            current.removeAll()
        }
        for word in words {
            if let last = current.last, abs(last.frame.midY - word.frame.midY) > 2 || current.count >= size { flush() }
            current.append(word)
        }
        flush()
        // Line breaks can still leave more pieces than allowed: merge the shortest neighbours.
        while pieces.count > maximumPieces {
            let index = pieces.indices.dropLast().min { pieces[$0].text.count + pieces[$0 + 1].text.count < pieces[$1].text.count + pieces[$1 + 1].text.count } ?? 0
            let merged = CapturedWord(id: index, text: pieces[index].text + " " + pieces[index + 1].text,
                                      frame: pieces[index].frame.union(pieces[index + 1].frame),
                                      fragments: pieces[index].sourceFragments + pieces[index + 1].sourceFragments)
            pieces.replaceSubrange(index...index + 1, with: [merged])
        }
        return pieces.enumerated().map { CapturedWord(id: $0.offset, text: $0.element.text, frame: $0.element.frame,
                                                      fragments: $0.element.sourceFragments) }
    }
}

/// One word piece on its way into the body.
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
    /// How far the drop is drawn out behind itself (1 = round, ~2.4 = a thread).
    let stretch: CGFloat
    let direction: CGVector
    let progress: CGFloat
}

enum WordVortex {
    /// Share of the path at which a drop meets the body's edge.
    static let contactProgress = 0.9

    /// Lift and align together, detach, then a smooth curve from a related family toward the
    /// body. The letters stay recognizable for half the way; then text → mask → drop → thread.
    static func state(for word: CapturedWord, index: Int, launch: WordLaunch, elapsed: Double, origin: CGPoint, target: CGPoint) -> FlyingWord {
        let raw = (elapsed - launch.delay(index)) / WordLaunch.flight
        let t = CGFloat(min(1, max(0, raw)))
        let start = CGPoint(x: word.frame.midX - origin.x, y: word.frame.midY - origin.y)
        // Phase A: the whole text rises a few points together before anything leaves.
        let rise = -launch.liftHeight * smooth(CGFloat(elapsed / WordLaunch.lift))
        let landing = CGPoint(x: target.x + launch.convergence.dx, y: target.y + launch.convergence.dy)
        // Accelerating into the body: gathered, not thrown.
        let u = 0.4 * smooth(t) + 0.6 * t * t
        let from = CGPoint(x: start.x, y: start.y + rise)
        let bend = bendFor(start: start, target: landing) * launch.bendScale * CGFloat(AnimationSeed.range(launch.seed, index, 6, 0.85, 1.15))
        let point = bezier(from: from, to: landing, bend: bend, u: u)
        let ahead = bezier(from: from, to: landing, bend: bend, u: min(1, u + 0.02))
        let direction = normalized(CGVector(dx: ahead.x - point.x, dy: ahead.y - point.y))
        let transform = smooth((t - 0.5) / 0.3)
        let heading = atan2(direction.dy, direction.dx)
        let rotation = Double(max(-0.12, min(0.12, sin(heading) * 0.1))) * 180 / .pi * Double(1 - transform) * Double(smooth(t / 0.3))
        let dropIn = smooth((t - 0.5) / 0.16)
        let dropOut = raw >= 1 ? 0 : 1 - smooth((t - 0.94) / 0.06)
        // The drop draws out into a thread as it speeds up, then the neck to the body takes it.
        let stretch = 1 + 1.4 * smooth((t - 0.6) / 0.25)
        return FlyingWord(text: word.text,
                          center: point,
                          rotation: rotation,
                          textOpacity: Double(1 - smooth((t - 0.56) / 0.2)),
                          dissolve: transform,
                          dissolveFromTrailing: landing.x < start.x,
                          tint: smooth((t - 0.3) / 0.35),
                          drop: min(10, word.frame.height * 0.34) * dropIn * dropOut,
                          stretch: stretch,
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

    /// The liquid beads of one drop: a head and a tapering thread behind it.
    static func beads(for word: FlyingWord, offset: CGPoint) -> [LiquidBlob] {
        guard word.drop > 0.5 else { return [] }
        let head = CGPoint(x: word.center.x - offset.x, y: word.center.y - offset.y)
        var beads = [LiquidBlob(center: head, radius: word.drop)]
        let spacing = word.drop * 0.8 * word.stretch
        for (step, scale) in [0.66, 0.46, 0.3].enumerated() where word.stretch > 1 + CGFloat(step) * 0.3 {
            let distance = spacing * CGFloat(step + 1)
            beads.append(LiquidBlob(center: CGPoint(x: head.x - word.direction.dx * distance, y: head.y - word.direction.dy * distance),
                                    radius: word.drop * CGFloat(scale)))
        }
        return beads
    }
}

/// The send stage: the written words lift, leave their lines in groups, gather along related
/// curves, soften into drops and threads and merge into the body through a narrow liquid neck.
/// The body bulges locally where they land and continues straight into its loading motion.
struct GatheringStage: View {
    let launch: WordLaunch?
    let checking: Bool
    var size: CGFloat = 340
    /// Set when the answer arrived early: the remaining flight plays faster instead of being cut.
    var hurryFrom: Date? = nil
    /// Without flying words (Reduce Motion, nothing captured) the body still varies per run.
    var seed: UInt64 = 1
    @State private var settled = false
    @ObservedObject private var visibility = AppVisibility.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let hurryRate = 3.0

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let target = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            if let launch, !reduceMotion, !launch.words.isEmpty {
                if settled {
                    // A window can be hidden before the final animation frame. Explicitly
                    // render the end state instead of freezing an old TimelineView timestamp.
                    let words = launch.words.enumerated().map { WordVortex.state(for: $0.element, index: $0.offset, launch: launch, elapsed: launch.duration, origin: origin, target: target) }
                    stage(words: words, launch: launch, target: target)
                } else {
                    TimelineView(.animation(minimumInterval: nil, paused: !visibility.isVisible)) { timeline in
                        let elapsed = Self.elapsed(at: timeline.date, launch: launch, hurryFrom: hurryFrom)
                        let words = launch.words.enumerated().map { WordVortex.state(for: $0.element, index: $0.offset, launch: launch, elapsed: elapsed, origin: origin, target: target) }
                        stage(words: words, launch: launch, target: target)
                    }
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

    /// Choreography time: real time, or time-lapse from the moment the answer arrived.
    static func elapsed(at date: Date, launch: WordLaunch, hurryFrom: Date?) -> Double {
        let real = date.timeIntervalSince(launch.start)
        guard let hurryFrom else { return real }
        let before = hurryFrom.timeIntervalSince(launch.start)
        return before + max(0, real - before) * hurryRate
    }

    /// How much longer the stage needs once the answer is there (seconds, never negative):
    /// the last drop still lands, at triple speed.
    static func remaining(_ launch: WordLaunch, answerAt: Date) -> Double {
        guard !launch.words.isEmpty else { return 0 }
        let elapsed = answerAt.timeIntervalSince(launch.start)
        let end = launch.delay(launch.words.count - 1) + WordLaunch.flight * WordVortex.contactProgress + 0.12
        return max(0, (end - elapsed) / hurryRate)
    }

    private func stage(words: [FlyingWord], launch: WordLaunch?, target: CGPoint) -> some View {
        let arrived = words.isEmpty ? 1 : CGFloat(words.filter { $0.progress >= CGFloat(WordVortex.contactProgress) }.count) / CGFloat(words.count)
        let incoming = words.isEmpty ? 1 : words.map { min(1, $0.progress) }.reduce(0, +) / CGFloat(words.count)
        let growth = words.isEmpty ? 1 : 0.18 + 0.82 * WordVortex.smooth(0.35 * incoming + 0.65 * arrived)
        let local = CGPoint(x: target.x - size / 2, y: target.y - size / 2)
        let drops = words.flatMap { WordVortex.beads(for: $0, offset: local) }
        var impacts: [LiquidImpact] = []
        var lastArrival: TimeInterval?
        if let launch {
            for index in launch.words.indices where index < words.count {
                // The drop arrives along its final heading: the body gives way there, then bulges.
                let heading = words[index].direction
                impacts.append(LiquidImpact(angle: atan2(-heading.dy, -heading.dx), time: launch.arrival(index), strength: launch.words.count > 12 ? 0.6 : 1))
                lastArrival = max(lastArrival ?? 0, launch.arrival(index))
            }
        }
        return ZStack {
            LiquidMind(checking: checking, size: size, growth: growth, gather: drops, impacts: impacts, settleAt: lastArrival,
                       variation: LiquidVariation(seed: launch?.seed ?? seed))
                .frame(width: size, height: size)
                .position(target)
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                if word.textOpacity > 0.01, let piece = launch?.words[index] {
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(piece.sourceFragments.enumerated()), id: \.offset) { _, fragment in
                            Text(fragment.text)
                                .fixedSize()
                                .position(x: fragment.frame.midX - piece.frame.minX,
                                          y: fragment.frame.midY - piece.frame.minY)
                        }
                    }
                        .frame(width: piece.frame.width, height: piece.frame.height)
                        .font(.system(size: launch?.fontSize ?? 19))
                        .foregroundStyle(WordVortex.tint(word.tint))
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

/// Whether any app window is on screen. Motion pauses while nothing of it is visible.
@MainActor
final class AppVisibility: ObservableObject {
    static let shared = AppVisibility()
    @Published private(set) var isVisible = true
    private var observer: NSObjectProtocol?

    private init() {
        update()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.update() }
        }
    }

    private func update() {
        let visible = NSApp.map { $0.occlusionState.contains(.visible) } ?? true
        if visible != isVisible { isVisible = visible }
    }
}
