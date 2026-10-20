import CoreGraphics
import Foundation

/// Everything that defines the lens outline for one frame.
struct AnnotationLensForm {
    var body: CGRect
    /// Superellipse exponent: 2 is a drop/circle, ~5 a calm squircle.
    var roundness: CGFloat
    /// Point on the text fragment the liquid neck reaches for; nil = no neck.
    var tip: CGPoint?
    /// Gaussian width of the neck along the outline (points).
    var neckWidth: CGFloat
    /// Pull toward the cursor's motion. Volume-preserving: the opposite side gives way.
    var lean: CGVector = .zero
    /// Surface-tension ripple amplitude (points). Zero at rest.
    var ripple: CGFloat = 0
    var ripplePhase: CGFloat = 0
    /// Settled fullness of the lower edge (points): the surface hangs with a little weight,
    /// fuller toward the lower right. Zero keeps the plain contour.
    var weight: CGFloat = 0
}

/// One continuous outline for the lens body and its neck. Mask, fill, rim,
/// shadow and hit testing all use this same geometry.
struct AnnotationLensShape {
    let path: CGPath
    /// The opaline reading core: an inset of the body without the neck.
    let corePath: CGPath
    let points: [CGPoint]

    func contains(_ point: CGPoint) -> Bool { path.contains(point) }

    static func make(_ form: AnnotationLensForm) -> AnnotationLensShape {
        let base = superellipse(form.body, exponent: form.roundness, count: 160)
        let outline = deform(base, form: form)
        let inset = CGSize(width: min(16, form.body.width * 0.2), height: min(14, form.body.height * 0.22))
        let coreRect = form.body.insetBy(dx: inset.width, dy: inset.height)
            .offsetBy(dx: form.lean.dx * 0.4, dy: form.lean.dy * 0.4)
        let core = superellipse(coreRect, exponent: form.roundness, count: 72)
        return AnnotationLensShape(path: smoothClosedPath(outline), corePath: smoothClosedPath(core), points: outline)
    }

    // MARK: - Geometry

    /// Counter-clockwise samples (y-up), so the outward normal of a tangent (x, y) is (y, -x).
    static func superellipse(_ rect: CGRect, exponent: CGFloat, count: Int) -> [CGPoint] {
        let a = max(0.5, rect.width / 2), b = max(0.5, rect.height / 2)
        let power = 2 / max(2, exponent)
        return (0..<count).map { index in
            let theta = CGFloat(index) / CGFloat(count) * 2 * .pi
            let c = cos(theta), s = sin(theta)
            return CGPoint(x: rect.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), power),
                           y: rect.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), power))
        }
    }

    private struct Sample { var point: CGPoint; var normal: CGVector; var arc: CGFloat }

    /// Resamples the base outline (finely around the neck) and applies ripple,
    /// lean and the Gaussian neck pull along smoothed normals.
    private static func deform(_ base: [CGPoint], form: AnnotationLensForm) -> [CGPoint] {
        let count = base.count
        var cumulative = [CGFloat](repeating: 0, count: count + 1)
        for index in 0..<count {
            let a = base[index], b = base[(index + 1) % count]
            cumulative[index + 1] = cumulative[index] + hypot(b.x - a.x, b.y - a.y)
        }
        let length = cumulative[count]
        guard length > 1 else { return base }
        let vertexNormals = (0..<count).map { index -> CGVector in
            let previous = base[(index - 1 + count) % count], next = base[(index + 1) % count]
            return normalized(CGVector(dx: next.y - previous.y, dy: -(next.x - previous.x)))
        }

        // Attach point: closest outline point to the tip.
        var attachArc: CGFloat = 0, attachPoint = base[0], best = CGFloat.greatestFiniteMagnitude
        if let tip = form.tip {
            for index in 0..<count {
                let a = base[index], b = base[(index + 1) % count]
                let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
                let span = ab.dx * ab.dx + ab.dy * ab.dy
                let f = span > 0 ? min(1, max(0, ((tip.x - a.x) * ab.dx + (tip.y - a.y) * ab.dy) / span)) : 0
                let p = CGPoint(x: a.x + ab.dx * f, y: a.y + ab.dy * f)
                let d = hypot(tip.x - p.x, tip.y - p.y)
                if d < best { best = d; attachPoint = p; attachArc = cumulative[index] + sqrt(span) * f }
            }
        }
        let sigma = max(6, form.neckWidth)
        let window = sigma * 3.2
        let fine = max(1.2, sigma / 11), coarse: CGFloat = 5.5

        var samples: [Sample] = []
        samples.reserveCapacity(Int(length / coarse) + Int(window * 2 / fine) + 8)
        var arc: CGFloat = 0, segment = 0
        while arc < length - 0.01 {
            while segment < count - 1 && cumulative[segment + 1] < arc { segment += 1 }
            let a = base[segment], b = base[(segment + 1) % count]
            let span = cumulative[segment + 1] - cumulative[segment]
            let f = span > 0 ? (arc - cumulative[segment]) / span : 0
            let na = vertexNormals[segment], nb = vertexNormals[(segment + 1) % count]
            samples.append(Sample(point: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f),
                                  normal: normalized(CGVector(dx: na.dx + (nb.dx - na.dx) * f, dy: na.dy + (nb.dy - na.dy) * f)),
                                  arc: arc))
            let distance = form.tip == nil ? .greatestFiniteMagnitude : circular(arc, attachArc, length)
            arc += distance < window ? fine : coarse
        }

        // The neck only exists while the tip is outside the body.
        var neckStrength: CGFloat = 0
        var pull = CGVector.zero
        if let tip = form.tip {
            let index = samples.indices.min { circular(samples[$0].arc, attachArc, length) < circular(samples[$1].arc, attachArc, length) } ?? 0
            let n = samples[index].normal
            let outside = (tip.x - attachPoint.x) * n.dx + (tip.y - attachPoint.y) * n.dy
            neckStrength = AnnotationGeometry.smoothstep(0, 3, outside)
            pull = CGVector(dx: tip.x - attachPoint.x, dy: tip.y - attachPoint.y)
        }
        let leanLength = hypot(form.lean.dx, form.lean.dy)
        return samples.map { sample in
            let theta = 2 * .pi * sample.arc / length
            let g = neckStrength * exp(-pow(circular(sample.arc, attachArc, length) / sigma, 2))
            var offset = form.ripple * (0.7 * sin(3 * theta + form.ripplePhase) + 0.3 * sin(5 * theta - 1.3 * form.ripplePhase))
            if leanLength > 0.01 {
                let facing = (sample.normal.dx * form.lean.dx + sample.normal.dy * form.lean.dy) / leanLength
                offset += facing > 0 ? leanLength * facing * facing : -0.45 * leanLength * facing * facing
            }
            if form.weight > 0 {
                let down = max(0, -sample.normal.dy), right = max(0, sample.normal.dx)
                offset += form.weight * (down * down + 0.35 * right * down)
            }
            offset *= 1 - g
            return CGPoint(x: sample.point.x + sample.normal.dx * offset + pull.dx * g,
                           y: sample.point.y + sample.normal.dy * offset + pull.dy * g)
        }
    }

    /// Closed Catmull–Rom spline through every sample: C1-continuous Bézier outline.
    static func smoothClosedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let n = points.count
        guard n > 2 else { return path }
        path.move(to: points[0])
        for index in 0..<n {
            let p0 = points[(index - 1 + n) % n], p1 = points[index]
            let p2 = points[(index + 1) % n], p3 = points[(index + 2) % n]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }

    private static func normalized(_ v: CGVector) -> CGVector {
        let length = hypot(v.dx, v.dy)
        return length > 0 ? CGVector(dx: v.dx / length, dy: v.dy / length) : CGVector(dx: 0, dy: 1)
    }

    private static func circular(_ a: CGFloat, _ b: CGFloat, _ length: CGFloat) -> CGFloat {
        let d = abs(a - b).truncatingRemainder(dividingBy: length)
        return min(d, length - d)
    }
}
