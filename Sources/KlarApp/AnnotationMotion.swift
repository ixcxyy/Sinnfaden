import AppKit

/// Accessibility display options for the lens. The bubble lab can force them
/// (`--lab-reduce-motion`, `--lab-reduce-transparency`) without changing system settings.
enum AnnotationAccessibility {
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || CommandLine.arguments.contains("--lab-reduce-motion")
    }
    static var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || CommandLine.arguments.contains("--lab-reduce-transparency")
    }
    static var increaseContrast: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast || CommandLine.arguments.contains("--lab-increase-contrast")
    }
}

/// Explicit presentation states of the explanation lens. Every timer and
/// animation completion checks a generation token, so a stale callback can
/// never overwrite a newer state.
enum AnnotationInteractionState: String {
    case idle, arming, forming, following, reading, pinned, morphing, retracting

    /// The lens body is on screen (possibly still forming or retracting).
    var isPresented: Bool { self != .idle && self != .arming }
}

struct AnnotationSpring {
    var value: CGFloat
    var velocity: CGFloat = 0
    var target: CGFloat
    var response: Double = 0.32
    var damping: Double = 0.84

    init(_ value: CGFloat, response: Double = 0.32, damping: Double = 0.84) {
        self.value = value; self.target = value
        self.response = response; self.damping = damping
    }

    /// Exact damped oscillator solution. Elapsed time, not frame count, controls motion.
    mutating func advance(_ dt: Double) {
        guard dt > 0 else { return }
        let omega = 2 * Double.pi / response
        let zeta = min(0.999, max(0.1, damping))
        let frequency = omega * sqrt(1 - zeta * zeta)
        let displacement = Double(value - target)
        let b = (Double(velocity) + zeta * omega * displacement) / frequency
        let decay = exp(-zeta * omega * dt)
        let cosine = cos(frequency * dt)
        let sine = sin(frequency * dt)
        let next = decay * (displacement * cosine + b * sine)
        let nextVelocity = decay * (-zeta * omega * (displacement * cosine + b * sine) + frequency * (-displacement * sine + b * cosine))
        value = target + CGFloat(next)
        velocity = CGFloat(nextVelocity)
        if abs(value - target) < 0.015 && abs(velocity) < 0.05 {
            value = target; velocity = 0
        }
    }

    /// Changes goal and character while keeping the current value and velocity.
    mutating func retarget(_ newTarget: CGFloat, _ timing: AnnotationTiming) {
        target = newTarget; response = timing.response; damping = timing.damping
    }

    var isSettled: Bool { abs(value - target) < 0.08 && abs(velocity) < 0.2 }
    mutating func snap() { value = target; velocity = 0 }
}

struct AnnotationTiming {
    let response: Double
    let damping: Double
    init(_ response: Double, _ damping: Double) { self.response = response; self.damping = damping }
}

/// Tuned starting points. Position, contour and light deliberately use
/// different speeds, close enough to read as one body.
enum AnnotationTuning {
    static let hoverDelay = 0.13
    static let leaveTolerance = 0.20
    static let textFadeOut = 0.075
    static let morphHandOff = 0.30
    static let formHandOff = 0.40

    // Contour: an edge that moves outward (or toward the cursor) leads, the opposite trails.
    static let formLead = AnnotationTiming(0.34, 0.66)
    static let formTrail = AnnotationTiming(0.46, 0.80)
    static let followLead = AnnotationTiming(0.22, 0.70)
    static let followTrail = AnnotationTiming(0.36, 0.78)
    static let morphGrow = AnnotationTiming(0.27, 0.70)
    static let morphShrink = AnnotationTiming(0.34, 0.90)
    static let retractFar = AnnotationTiming(0.21, 0.92)
    static let retractNear = AnnotationTiming(0.29, 0.96)
    static let settle = AnnotationTiming(0.30, 0.86)
    // Cursor bubble: one clean body. Both sides share a spring, so it glides without distorting.
    static let cursorLead = AnnotationTiming(0.17, 0.84)
    static let cursorTrail = AnnotationTiming(0.17, 0.84)
    static let cursorText = AnnotationTiming(0.17, 0.84)
    static let cursorTip = AnnotationTiming(0.05, 0.95)
    static let cursorPop = AnnotationTiming(0.24, 0.74)
    static let cursorRetract = AnnotationTiming(0.15, 0.95)
    static let cursorNeck: CGFloat = 10

    // Reading layer and light.
    static let text = AnnotationTiming(0.28, 0.90)
    static let light = AnnotationTiming(0.17, 0.92)
    static let lean = AnnotationTiming(0.15, 0.58)
    static let tip = AnnotationTiming(0.20, 0.82)

    /// Share of cursor travel that moves the lens, and the extra room it may use.
    static let cursorGain: CGFloat = 0.32
    static let cursorRange = CGSize(width: 28, height: 14)
    static let nucleus: CGFloat = 14
    static let restRoundness: CGFloat = 5.2
    static let restNeck: CGFloat = 15
}

/// The lens body: four independently sprung edges, a separately sprung
/// reading layer and a handful of coupled material values.
struct AnnotationLensMotion {
    var left, right, bottom, top: AnnotationSpring
    var textX, textY: AnnotationSpring
    var roundness = AnnotationSpring(2, response: 0.42, damping: 0.8)
    var neck = AnnotationSpring(26, response: 0.46, damping: 0.86)
    var tipX, tipY: AnnotationSpring
    var leanX = AnnotationSpring(0, response: 0.15, damping: 0.58)
    var leanY = AnnotationSpring(0, response: 0.15, damping: 0.58)
    var glossX = AnnotationSpring(-0.35, response: 0.17, damping: 0.92)
    var glossY = AnnotationSpring(0.45, response: 0.17, damping: 0.92)
    var lift = AnnotationSpring(0, response: 0.36, damping: 0.86)
    var rim = AnnotationSpring(0, response: 0.5, damping: 0.95)
    var conserve = AnnotationSpring(0, response: 0.3, damping: 0.99)
    var presence = AnnotationSpring(0, response: 0.12, damping: 0.99)

    init(frame: CGRect, tip: CGPoint) {
        left = AnnotationSpring(frame.minX); right = AnnotationSpring(frame.maxX)
        bottom = AnnotationSpring(frame.minY); top = AnnotationSpring(frame.maxY)
        textX = AnnotationSpring(frame.midX); textY = AnnotationSpring(frame.midY)
        tipX = AnnotationSpring(tip.x); tipY = AnnotationSpring(tip.y)
    }

    var frame: CGRect {
        let minimum: CGFloat = 8
        let width = max(minimum, right.value - left.value)
        let height = max(minimum, top.value - bottom.value)
        let midX = (left.value + right.value) / 2, midY = (bottom.value + top.value) / 2
        return CGRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
    }
    var targetFrame: CGRect {
        CGRect(x: left.target, y: bottom.target, width: right.target - left.target, height: top.target - bottom.target)
    }
    var tip: CGPoint { CGPoint(x: tipX.value, y: tipY.value) }
    var textCenter: CGPoint { CGPoint(x: textX.value, y: textY.value) }

    /// Retargets all four edges. An edge whose displacement points along its
    /// own outward normal (it grows or leads a move) receives `lead`.
    mutating func retarget(_ rect: CGRect, lead: AnnotationTiming, trail: AnnotationTiming) {
        func pick(_ spring: AnnotationSpring, _ newValue: CGFloat, outward: CGFloat) -> AnnotationTiming {
            (newValue - spring.value) * outward > 0 ? lead : trail
        }
        left.retarget(rect.minX, pick(left, rect.minX, outward: -1))
        right.retarget(rect.maxX, pick(right, rect.maxX, outward: 1))
        bottom.retarget(rect.minY, pick(bottom, rect.minY, outward: -1))
        top.retarget(rect.maxY, pick(top, rect.maxY, outward: 1))
    }

    /// Short local compression, then the surface settles (used for pinning).
    mutating func compress(by speed: CGFloat) {
        left.velocity += speed; right.velocity -= speed
        bottom.velocity += speed * 0.8; top.velocity -= speed * 0.8
        for edge in [\AnnotationLensMotion.left, \.right, \.bottom, \.top] {
            self[keyPath: edge].damping = 0.62; self[keyPath: edge].response = 0.26
        }
        rim.velocity += 7
    }

    /// Rate of shape change, used for surface tension ripples and rim energy.
    var energy: CGFloat {
        min(1, (abs(left.velocity) + abs(right.velocity) + abs(bottom.velocity) + abs(top.velocity)) / 1400)
    }

    mutating func advance(_ dt: Double, reduced: Bool) {
        let springs: [WritableKeyPath<AnnotationLensMotion, AnnotationSpring>] = [
            \.left, \.right, \.bottom, \.top, \.textX, \.textY, \.roundness, \.neck,
            \.tipX, \.tipY, \.leanX, \.leanY, \.glossX, \.glossY, \.lift, \.rim, \.conserve
        ]
        if reduced { springs.forEach { self[keyPath: $0].snap() } } else { springs.forEach { self[keyPath: $0].advance(dt) } }
        presence.advance(dt)
    }

    var isSettled: Bool {
        left.isSettled && right.isSettled && bottom.isSettled && top.isSettled && textX.isSettled && textY.isSettled
            && roundness.isSettled && neck.isSettled && tipX.isSettled && tipY.isSettled && leanX.isSettled && leanY.isSettled
            && glossX.isSettled && glossY.isSettled && lift.isSettled && rim.isSettled && conserve.isSettled && presence.isSettled
    }
}

/// Light gathering under the highlighted words before and while the lens is shown.
struct AnnotationAnchorMotion {
    var intensity = AnnotationSpring(0, response: 0.11, damping: 0.95)
    var coreRadius = AnnotationSpring(0, response: 0.22, damping: 0.55)
    var coreX = AnnotationSpring(0, response: 0.14, damping: 0.9)
    var coreY = AnnotationSpring(0, response: 0.2, damping: 0.85)
    var coreDrift = AnnotationSpring(0, response: 0.24, damping: 0.75)
    var lightX = AnnotationSpring(0, response: 0.09, damping: 0.95)

    mutating func advance(_ dt: Double, reduced: Bool) {
        intensity.advance(dt)
        if reduced { coreRadius.snap(); coreX.snap(); coreY.snap(); coreDrift.snap(); lightX.snap() }
        else { coreRadius.advance(dt); coreX.advance(dt); coreY.advance(dt); coreDrift.advance(dt); lightX.advance(dt) }
    }
    var isSettled: Bool {
        intensity.isSettled && coreRadius.isSettled && coreX.isSettled && coreY.isSettled && coreDrift.isSettled && lightX.isSettled
    }
}

enum AnnotationGeometry {
    static func cursorOffset(pointer: CGPoint, origin: CGPoint) -> CGSize {
        let range = AnnotationTuning.cursorRange, gain = AnnotationTuning.cursorGain
        return CGSize(width: min(range.width, max(-range.width, (pointer.x - origin.x) * gain)),
                      height: min(range.height, max(-range.height, (pointer.y - origin.y) * gain)))
    }

    static func clamp(_ frame: CGRect, inside boundary: CGRect) -> CGRect {
        CGRect(x: min(max(frame.minX, boundary.minX), max(boundary.minX, boundary.maxX - frame.width)),
               y: min(max(frame.minY, boundary.minY), max(boundary.minY, boundary.maxY - frame.height)),
               width: min(frame.width, boundary.width), height: min(frame.height, boundary.height))
    }

    /// Rubber band: inside the limit nothing changes; beyond it the overshoot
    /// is compressed, so the lens settles softly against a window edge.
    static func rubber(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        let give: CGFloat = 5
        if value < lower { let over = lower - value; return lower - give * (1 - exp(-over / give)) }
        if value > upper { let over = value - upper; return upper + give * (1 - exp(-over / give)) }
        return value
    }

    /// A measured surface must fit wholly on one side of its source. Clamping a
    /// too-tall surface across the source would crop its fixed-size text canvas.
    static func fittedPosition(size: CGSize, anchor: CGRect, boundary: CGRect, preferBelow: Bool? = nil) -> CGRect? {
        let below = max(0, anchor.minY - boundary.minY - 16)
        let above = max(0, boundary.maxY - anchor.maxY - 16)
        guard size.width > 0, size.height > 0,
              size.width <= boundary.width, size.height <= max(below, above) else { return nil }
        return position(size: size, anchor: anchor, boundary: boundary, preferBelow: preferBelow)
    }

    /// Keep the chosen side while it has room. Cursor movement never flips placement.
    static func position(size: CGSize, anchor: CGRect, boundary: CGRect, preferBelow: Bool? = nil) -> CGRect {
        let below = anchor.minY - size.height - 16
        let above = anchor.maxY + 16
        let fitsBelow = below >= boundary.minY
        let fitsAbove = above + size.height <= boundary.maxY
        let y: CGFloat
        if let preferBelow, preferBelow && fitsBelow { y = below }
        else if let preferBelow, !preferBelow && fitsAbove { y = above }
        else if fitsBelow { y = below }
        else if fitsAbove { y = above }
        else { y = below }
        return clamp(CGRect(x: anchor.minX - 14, y: y, width: size.width, height: size.height), inside: boundary)
    }

    /// Where the liquid neck touches the text: on the facing edge of the
    /// fragment, under the cursor, and inside the body's horizontal reach.
    static func connectionPoint(anchor: CGRect, pointer: CGPoint, body: CGRect) -> CGPoint {
        var low = anchor.minX + 2, high = anchor.maxX - 2
        let reachLow = body.minX + 22, reachHigh = body.maxX - 22
        if reachLow < high && reachHigh > low { low = max(low, reachLow); high = min(high, reachHigh) }
        let x = high >= low ? min(high, max(low, pointer.x)) : anchor.midX
        return CGPoint(x: x, y: body.midY < anchor.midY ? anchor.minY - 2 : anchor.maxY + 2)
    }

    static func transitionContains(_ point: CGPoint, anchor: CGRect, body: CGRect) -> Bool {
        if body.insetBy(dx: -10, dy: -10).contains(point) || anchor.insetBy(dx: -7, dy: -7).contains(point) { return true }
        // A short trapezoid bridges the nearest edge rather than a broad rectangular hot zone.
        let bodyAbove = body.midY > anchor.midY
        let aY = bodyAbove ? anchor.maxY : anchor.minY
        let bY = bodyAbove ? body.minY : body.maxY
        guard abs(aY - bY) > 0.1 else { return false }
        let fraction = (point.y - aY) / (bY - aY)
        guard fraction >= 0 && fraction <= 1 else { return false }
        let aLeft = anchor.minX - 10, aRight = anchor.maxX + 10
        let bLeft = max(body.minX, anchor.minX - 28) - 10
        let bRight = min(body.maxX, anchor.maxX + 28) + 10
        let left = aLeft + (bLeft - aLeft) * fraction
        let right = aRight + (bRight - aRight) * fraction
        return point.x >= left && point.x <= right
    }

    static func nearestRect(_ rects: [CGRect], to pointer: CGPoint) -> CGRect? {
        rects.min { distance(to: $0, point: pointer) < distance(to: $1, point: pointer) }
    }
    private static func distance(to rect: CGRect, point: CGPoint) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }

    /// Reading width from the amount of text: short explanations stay compact,
    /// long ones get a calmer, wider body. Measured height follows from this width.
    static func readingWidth(textLength: Int, limit: CGFloat) -> CGFloat {
        let t = smoothstep(70, 300, CGFloat(textLength))
        let width = (280 + 112 * t).rounded()
        return max(min(240, limit), min(limit, width))
    }

    static func union(_ rects: [CGRect]) -> CGRect {
        rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) }
    }

    /// The fragment on the lens side (screen y-up): the lowest line for a lens below.
    static func facing(_ rects: [CGRect], below: Bool) -> CGRect {
        let pick = below ? rects.min { $0.minY < $1.minY } : rects.max { $0.maxY < $1.maxY }
        return pick ?? .zero
    }

    static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(1, max(0, (x - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }
}
