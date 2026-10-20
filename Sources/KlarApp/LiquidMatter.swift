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

/// The thinking moment: one softly suspended body of the learning blue. It breathes slowly,
/// a few regions of fullness travel around its contour, its weight shifts by a few points and
/// a calm light moves inside it. Word drops merge into it and leave small local dents.
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
    @State private var checkingChangedAt: TimeInterval = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                matter(time: 0)
            } else {
                TimelineView(.animation) { timeline in
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

    private func outline(_ t: TimeInterval) -> (path: Path, center: CGPoint, radius: CGFloat) {
        let calm = calm(t)
        let breathe = 0.028 * sin(t * 2 * .pi / 3.9)
        var dip: CGFloat = 0
        if let settleAt, t > settleAt, t < settleAt + 0.55 { dip = 0.035 * CGFloat(sin(.pi * (t - settleAt) / 0.55)) }
        let radius = size * 0.25 * (0.34 + 0.66 * max(0, growth)) * (1 - 0.03 * calm) * (1 - dip)
        // The weight drifts a few points; the outline answers a moment later (see `lag`).
        let drift = CGPoint(x: 3.2 * sin(t * 0.21) * (1 - 0.5 * calm), y: 2.6 * cos(t * 0.17 + 1.1) * (1 - 0.5 * calm))
        let lagged = CGPoint(x: 3.2 * sin((t - 0.6) * 0.21), y: 2.6 * cos((t - 0.6) * 0.17 + 1.1))
        let lag = CGPoint(x: drift.x - lagged.x, y: drift.y - lagged.y)
        let center = CGPoint(x: size / 2 + drift.x, y: size / 2 + drift.y)
        let amplitude = 1 - 0.45 * calm
        var path = Path()
        let steps = 120
        for step in 0...steps {
            let theta = Double(step) / Double(steps) * 2 * .pi
            // Broad regions of fullness travelling slowly around the body.
            var r = 1 + breathe
            r += amplitude * (0.042 * sin(2 * theta - 0.31 * t + 0.4) + 0.028 * sin(3 * theta + 0.23 * t + 1.9) + 0.011 * sin(4 * theta - 0.47 * t))
            // A little fuller below: it hangs, it does not float like a balloon.
            r += 0.018 * max(0, sin(theta))
            for impact in impacts { r += Self.contact(impact, theta: theta, now: t) }
            let direction = CGPoint(x: cos(theta), y: sin(theta))
            let trailing = -(direction.x * lag.x + direction.y * lag.y) * 0.6
            let point = CGPoint(x: center.x + direction.x * (radius * CGFloat(r) + trailing),
                                y: center.y + direction.y * (radius * CGFloat(r) + trailing))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return (path, center, radius)
    }

    /// Indentation at the contact point, a gentle outward give, then recovery (~0.8 s).
    private static func contact(_ impact: LiquidImpact, theta: Double, now: TimeInterval) -> Double {
        let age = now - impact.time
        guard age > 0, age < 0.85 else { return 0 }
        var delta = theta - impact.angle
        delta = atan2(sin(delta), cos(delta))
        let reach = exp(-(delta * delta) / (2 * 0.32 * 0.32))
        let response = age < 0.16 ? -sin(.pi * age / 0.16) : 0.55 * sin(.pi * (age - 0.16) / 0.42) * exp(-(age - 0.16) / 0.3)
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
                for blob in gather {
                    layer.fill(Path(ellipseIn: CGRect(x: blob.center.x - blob.radius, y: blob.center.y - blob.radius,
                                                      width: blob.radius * 2, height: blob.radius * 2)), with: .color(.white))
                }
            }
        }
        let r = shape.radius
        let c = shape.center
        let unit = UnitPoint(x: c.x / size, y: c.y / size)
        // The light circles slowly (about 11 s per turn) and stays in the upper half.
        let lightAngle = t * 2 * .pi / 11
        let light = UnitPoint(x: (c.x + CGFloat(cos(lightAngle)) * r * 0.32) / size, y: (c.y - r * 0.38 + CGFloat(sin(lightAngle)) * r * 0.12) / size)
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
