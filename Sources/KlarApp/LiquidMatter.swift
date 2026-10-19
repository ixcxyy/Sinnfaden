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

/// The thinking moment: drops of light circle a common centre, reach for each other,
/// merge and separate again. Faster and brighter while the answer is being checked.
struct LiquidMind: View {
    var checking = false
    var size: CGFloat = 300
    /// 0…1: how much liquid has gathered so far (the send moment fills it word by word).
    var growth: CGFloat = 1
    /// Extra drops in local coordinates, e.g. words that are about to be absorbed.
    var gather: [LiquidBlob] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            matter(time: 2.0)
        } else {
            TimelineView(.animation) { timeline in
                matter(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func blobs(_ t: Double) -> [LiquidBlob] {
        let c = CGPoint(x: size / 2, y: size / 2)
        let speed = checking ? 1.35 : 1.0
        let g = max(0.001, growth)
        var result = [LiquidBlob(center: c, radius: size * CGFloat(0.12 + 0.012 * sin(t * 2.1)) * (0.35 + 0.65 * g))]
        let seeds: [(orbit: Double, speed: Double, radius: Double, phase: Double)] = [
            (0.25, 0.9, 0.075, 0.0), (0.29, -0.7, 0.064, 1.4), (0.21, 1.25, 0.052, 2.6),
            (0.31, 0.55, 0.082, 3.9), (0.26, -1.05, 0.058, 5.0), (0.34, 0.8, 0.044, 0.7), (0.23, -0.45, 0.066, 4.3)
        ]
        let tilt = t * 0.25 * speed
        for (index, seed) in seeds.enumerated() {
            let angle = t * seed.speed * speed + seed.phase
            // Orbits breathe in and out: drops touch the core, stretch away, return.
            let breathe = 1 + 0.42 * sin(t * (0.8 + Double(index) * 0.13) * speed + seed.phase * 1.7)
            let orbit = seed.orbit * breathe * Double(size) * Double(g)
            let x = cos(angle) * orbit, y = sin(angle) * orbit * 0.78
            let rotated = CGPoint(x: c.x + CGFloat(x * cos(tilt) - y * sin(tilt)), y: c.y + CGFloat(x * sin(tilt) + y * cos(tilt)))
            let radius = seed.radius * Double(size) * (1 + 0.18 * sin(t * 1.9 + Double(index)))
            result.append(LiquidBlob(center: rotated, radius: CGFloat(radius) * g))
        }
        return result + gather
    }

    private func matter(time t: Double) -> some View {
        let liquid = blobs(t)
        let shape = GooeyBlobs(blobs: liquid, softness: size * 0.06)
        let highlight = GooeyBlobs(blobs: liquid.map { LiquidBlob(center: CGPoint(x: $0.center.x - $0.radius * 0.28, y: $0.center.y - $0.radius * 0.34), radius: $0.radius * 0.5) },
                                   softness: size * 0.04)
        return ZStack {
            // Outer glow takes its shape from the same liquid.
            LinearGradient(colors: [Color.sinnAnnotation, Color(red: 0.4, green: 0.85, blue: 1)], startPoint: .top, endPoint: .bottom)
                .mask(shape).blur(radius: size * 0.09).opacity(checking ? 0.75 : 0.55)
            AngularGradient(colors: [Color(red: 0.36, green: 0.62, blue: 1), Color.sinnAnnotation, Color(red: 0.48, green: 0.42, blue: 0.98),
                                     Color(red: 0.35, green: 0.88, blue: 1), Color(red: 0.36, green: 0.62, blue: 1)],
                            center: .center, angle: .degrees(t * 30))
                .mask(shape)
            // Inner depth: the liquid is darker at its floor.
            LinearGradient(colors: [.clear, Color(red: 0.02, green: 0.12, blue: 0.4).opacity(0.35)], startPoint: .top, endPoint: .bottom)
                .mask(shape)
            // Specular: a smaller copy of the liquid, shifted toward the light.
            Color.white.mask(highlight).blur(radius: size * 0.018).opacity(0.55)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
