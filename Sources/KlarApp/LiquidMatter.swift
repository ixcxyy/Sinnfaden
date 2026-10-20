import SwiftUI

/// One metaball: a circle in the liquid layer.
struct LiquidBlob {
    var center: CGPoint
    var radius: CGFloat
}

/// Liquid layer: blurred circles cut at half alpha, so nearby blobs melt together
/// and pull apart with a soft neck. Used for thinking and for the navigation dial.
struct GooeyBlobs: View {
    let blobs: [LiquidBlob]
    var softness: CGFloat = 16
    var body: some View {
        Canvas { context, _ in
            context.addFilter(.alphaThreshold(min: 0.5, color: .white))
            context.addFilter(.blur(radius: softness))
            context.drawLayer { layer in
                for blob in blobs {
                    layer.fill(Path(ellipseIn: CGRect(x: blob.center.x - blob.radius, y: blob.center.y - blob.radius,
                                                      width: blob.radius * 2, height: blob.radius * 2)), with: .color(.white))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A word drop meeting the body: where on the contour and when (reference-date seconds).
struct LiquidImpact {
    var angle: Double
    var time: TimeInterval
    var strength: CGFloat = 1
}

/// The character of one loading run, drawn from its seed: no two requests move alike, and a
/// fixed seed reproduces a run exactly. Every amount stays within calm bounds.
struct LiquidVariation: Equatable {
    struct Region: Equatable { var lobes: Int; var amplitude: Double; var speed: Double; var phase: Double }

    /// 2–4 broad regions of fullness travelling around the contour.
    let regions: [Region]
    /// Breathing depth (2–4 % of the radius) and period.
    let breathe: Double
    let breathePeriod: Double
    /// A slight lasting asymmetry: fuller toward one side.
    let leanAmount: Double
    let leanAngle: Double
    /// The centre of weight drifts a few points along its own slow figure.
    let drift: CGSize
    let driftSpeed: CGSize
    let driftPhase: Double
    /// The inner light's path: period, direction and width of its ellipse.
    let lightPeriod: Double
    let lightDirection: Double
    let lightWidth: Double
    let lightStart: Double
    /// Occasional outgrowth: first one, interval between them and reach (share of the radius).
    let outgrowthFirst: Double
    let outgrowthInterval: Double
    let outgrowthReach: Double
    let seed: UInt64

    init(seed: UInt64) {
        func r(_ salt: UInt64, _ lower: Double, _ upper: Double, index: Int = 0) -> Double { AnimationSeed.range(seed, index, salt, lower, upper) }
        self.seed = seed
        let count = 2 + Int(r(10, 0, 2.999))
        // Broad regions only: few lobes, and the more lobes the gentler (no corners).
        let lobeChoices = [2, 3, 4]
        let firstLobe = Int(r(11, 0, 2.999))
        let drawn = (0..<count).map { index -> Region in
            let lobes = lobeChoices[(firstLobe + index) % lobeChoices.count]
            return Region(lobes: lobes,
                   amplitude: r(12, 0.016, 0.042, index: index) / Double(index + 1).squareRoot() * (lobes >= 4 ? 0.55 : 1),
                   speed: (r(13, 0, 1, index: index) < 0.5 ? -1 : 1) * r(14, 0.12, 0.42, index: index),
                   phase: r(15, 0, 2 * .pi, index: index))
        }
        // Together the regions never deform more than the calm original (~8 % of the radius).
        let total = drawn.map(\.amplitude).reduce(0, +)
        let scale = min(1, 0.08 / max(total, 0.0001))
        regions = drawn.map { Region(lobes: $0.lobes, amplitude: $0.amplitude * scale, speed: $0.speed, phase: $0.phase) }
        breathe = r(16, 0.02, 0.04)
        breathePeriod = r(17, 3.4, 4.6)
        leanAmount = r(18, 0.008, 0.024)
        leanAngle = r(19, 0, 2 * .pi)
        drift = CGSize(width: r(20, 2, 4.5), height: r(21, 1.5, 3.5))
        driftSpeed = CGSize(width: r(22, 0.14, 0.26), height: r(23, 0.12, 0.22))
        driftPhase = r(24, 0, 2 * .pi)
        lightPeriod = r(25, 9, 14)
        lightDirection = r(26, 0, 1) < 0.5 ? -1 : 1
        lightWidth = r(27, 0.24, 0.38)
        lightStart = r(28, 0, 2 * .pi)
        outgrowthFirst = r(29, 2.5, 4.5)
        outgrowthInterval = r(30, 5.5, 8.5)
        outgrowthReach = r(31, 0.10, 0.16)
    }

    /// Life of the outgrowth active at `age` seconds into the run: where it reaches and how far
    /// (0 = merged back). It forms, stretches, then flows back in (~2.4 s).
    func outgrowth(at age: Double) -> (angle: Double, extent: Double)? {
        guard age > outgrowthFirst else { return nil }
        let index = Int((age - outgrowthFirst) / outgrowthInterval)
        let local = age - outgrowthFirst - Double(index) * outgrowthInterval
        let life = 2.4
        guard local < life else { return nil }
        let form = Double(WordVortex.smooth(CGFloat(local / 0.7)))
        let back = Double(WordVortex.smooth(CGFloat((local - 1.3) / 1.1)))
        return (AnimationSeed.range(seed, index, 32, 0, 2 * .pi), form * (1 - back))
    }
}

/// The thinking moment: one softly suspended body of the learning blue. It breathes slowly,
/// broad regions of fullness travel around its contour, its weight shifts by a few points, a
/// calm light moves inside it and now and then it reaches out a little and flows back. Word
/// drops merge into it and leave local bulges. Each run's character comes from its seed.
/// While the answer is being checked it becomes a little more compact and ordered.
struct LiquidMind: View {
    var checking = false
    var size: CGFloat = 300
    /// 0…1: how much liquid has gathered so far (the send moment fills it word by word).
    var growth: CGFloat = 1
    /// Extra drops in local coordinates, e.g. words that are about to be absorbed.
    var gather: [LiquidBlob] = []
    /// Contact responses of arriving drops.
    var impacts: [LiquidImpact] = []
    /// When the last drop arrived: one soft compression and recovery.
    var settleAt: TimeInterval?
    var variation = LiquidVariation(seed: 1)
    @State private var checkingChangedAt: TimeInterval = 0
    @State private var startedAt: TimeInterval = Date().timeIntervalSinceReferenceDate
    @ObservedObject private var visibility = AppVisibility.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                matter(time: 0)
            } else {
                // No frames are drawn while the window is hidden or covered.
                TimelineView(.animation(minimumInterval: nil, paused: !visibility.isVisible)) { timeline in
                    matter(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .onChange(of: checking) { _, _ in checkingChangedAt = Date().timeIntervalSinceReferenceDate }
    }

    // MARK: Shape

    /// 0 while generating, 1 while checking, blended over ~0.9 s so the change is continuous.
    private func calm(_ t: TimeInterval) -> CGFloat {
        let blend = checkingChangedAt == 0 ? 1 : WordVortex.smooth(CGFloat((t - checkingChangedAt) / 0.9))
        return checking ? blend : 1 - blend
    }

    private func outline(_ t: TimeInterval) -> (path: Path, center: CGPoint, radius: CGFloat, reach: (point: CGPoint, radius: CGFloat)?) {
        let v = variation
        let calm = calm(t)
        let breathe = v.breathe * sin(t * 2 * .pi / v.breathePeriod)
        var dip: CGFloat = 0
        if let settleAt, t > settleAt, t < settleAt + 0.35 { dip = 0.03 * CGFloat(sin(.pi * (t - settleAt) / 0.35)) }
        let radius = size * 0.25 * (0.34 + 0.66 * max(0, growth)) * (1 - 0.03 * calm) * (1 - dip)
        // The weight drifts a few points; the outline answers a moment later (see `lag`).
        func weight(_ time: Double) -> CGPoint {
            CGPoint(x: v.drift.width * sin(time * v.driftSpeed.width + v.driftPhase),
                    y: v.drift.height * cos(time * v.driftSpeed.height + v.driftPhase * 0.7))
        }
        let quiet = 1 - 0.5 * calm
        let now = weight(t), before = weight(t - 0.6)
        let lag = CGPoint(x: now.x - before.x, y: now.y - before.y)
        // The centre itself stays calm: only the weight shifts, by a few points.
        let center = CGPoint(x: size / 2 + now.x * quiet, y: size / 2 + now.y * quiet)
        let amplitude = 1 - 0.45 * calm
        let age = t - startedAt
        let reachOut = calm > 0.5 ? nil : v.outgrowth(at: age)
        var path = Path()
        let steps = 140
        for step in 0...steps {
            let theta = Double(step) / Double(steps) * 2 * .pi
            var r = 1 + breathe
            // Broad regions of fullness travelling slowly around the body.
            for region in v.regions {
                r += amplitude * region.amplitude * sin(Double(region.lobes) * theta + region.speed * t + region.phase)
            }
            // A lasting lean toward one side, and a little fuller below: it hangs, it does not float.
            r += v.leanAmount * cos(theta - v.leanAngle) + 0.016 * max(0, sin(theta))
            for impact in impacts { r += Self.contact(impact, theta: theta, now: t) }
            if let reachOut {
                var delta = theta - reachOut.angle
                delta = atan2(sin(delta), cos(delta))
                // Narrows as it stretches: a reach, not a bump.
                let width = 0.42 - 0.16 * reachOut.extent
                r += v.outgrowthReach * reachOut.extent * exp(-(delta * delta) / (2 * width * width)) * Double(1 - 0.6 * calm)
            }
            let direction = CGPoint(x: cos(theta), y: sin(theta))
            let trailing = -(direction.x * lag.x + direction.y * lag.y) * 0.6
            let point = CGPoint(x: center.x + direction.x * (radius * CGFloat(r) + trailing),
                                y: center.y + direction.y * (radius * CGFloat(r) + trailing))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        // A small bead at the end of the reach, still joined to the body by the liquid neck.
        var reach: (point: CGPoint, radius: CGFloat)?
        if let reachOut, reachOut.extent > 0.05 {
            let distance = radius * (1 + CGFloat(v.outgrowthReach * reachOut.extent) * 1.6)
            reach = (CGPoint(x: center.x + CGFloat(cos(reachOut.angle)) * distance, y: center.y + CGFloat(sin(reachOut.angle)) * distance),
                     radius * 0.11 * CGFloat(reachOut.extent))
        }
        return (path, center, radius, reach)
    }

    /// Where a drop lands the body first gives way briefly, then swells out locally and settles.
    private static func contact(_ impact: LiquidImpact, theta: Double, now: TimeInterval) -> Double {
        let age = now - impact.time
        guard age > 0, age < 0.75 else { return 0 }
        var delta = theta - impact.angle
        delta = atan2(sin(delta), cos(delta))
        let reach = exp(-(delta * delta) / (2 * 0.3 * 0.3))
        let response = age < 0.09 ? -0.45 * sin(.pi * age / 0.09) : 0.9 * sin(.pi * min(1, (age - 0.09) / 0.36)) * exp(-(age - 0.09) / 0.32)
        return 0.05 * Double(impact.strength) * reach * response
    }

    // MARK: Material

    private func matter(time t: TimeInterval) -> some View {
        let shape = outline(t)
        let softness = size * 0.022
        let liquid = Canvas { context, _ in
            context.addFilter(.alphaThreshold(min: 0.5, color: .white))
            context.addFilter(.blur(radius: softness))
            context.drawLayer { layer in
                layer.fill(shape.path, with: .color(.white))
                for blob in gather + (shape.reach.map { [LiquidBlob(center: $0.point, radius: $0.radius)] } ?? []) {
                    layer.fill(Path(ellipseIn: CGRect(x: blob.center.x - blob.radius, y: blob.center.y - blob.radius,
                                                      width: blob.radius * 2, height: blob.radius * 2)), with: .color(.white))
                }
            }
        }
        let r = shape.radius
        let c = shape.center
        let unit = UnitPoint(x: c.x / size, y: c.y / size)
        // The light travels its own slow ellipse in the upper half (period and direction per run).
        let v = variation
        let lightAngle = v.lightStart + v.lightDirection * t * 2 * .pi / v.lightPeriod
        let light = UnitPoint(x: (c.x + CGFloat(cos(lightAngle)) * r * CGFloat(v.lightWidth)) / size,
                              y: (c.y - r * 0.38 + CGFloat(sin(lightAngle)) * r * 0.12) / size)
        return ZStack {
            // Soft contact shadow: suspended, not glued.
            Ellipse().fill(Color(red: 0.05, green: 0.15, blue: 0.4).opacity(0.10))
                .frame(width: r * 1.7, height: r * 0.34)
                .blur(radius: r * 0.16)
                .position(x: c.x, y: c.y + r * 1.22)
            // A faint halo from the same shape, so it sits in the milky page.
            Color.sinnAnnotation.opacity(0.22).mask(liquid).blur(radius: r * 0.28)
            ZStack {
                // Stable, deeper centre; slightly lighter toward the edge.
                RadialGradient(colors: [Color(red: 0.06, green: 0.36, blue: 0.84), Color(red: 0.16, green: 0.48, blue: 0.95), Color(red: 0.50, green: 0.72, blue: 1.0)],
                               center: unit, startRadius: 0, endRadius: r * 1.15)
                // Floor shading for weight.
                LinearGradient(colors: [.clear, Color(red: 0.02, green: 0.13, blue: 0.40).opacity(0.28)], startPoint: .center, endPoint: .bottom)
                // A calm, moving internal light.
                RadialGradient(colors: [Color.white.opacity(0.42), Color.white.opacity(0)], center: light, startRadius: 0, endRadius: r * 0.75)
            }
            .mask(liquid)
            // Faint edge highlight along the real contour.
            shape.path.stroke(Color.white.opacity(0.32), lineWidth: 1.2)
                .blur(radius: 0.6)
                .mask(liquid)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
