import SwiftUI

/// Twelve profile companions, drawn as vectors: little drops of Sinnfaden's liquid with a
/// face of their own. They breathe, blink and wobble while the cursor is on them.
struct ProfileAvatar: View {
    static let count = 12
    let index: Int
    var size: CGFloat = 40
    /// Idle life (breathing, blinking). Off for small static uses, on for previews and hover.
    var live = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if live && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                    AvatarCanvas(style: AvatarStyle.all[Self.wrapped(index)], size: size, time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                AvatarCanvas(style: AvatarStyle.all[Self.wrapped(index)], size: size, time: nil)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.7), lineWidth: max(1, size * 0.025)))
        .accessibilityHidden(true)
    }

    static func wrapped(_ index: Int) -> Int { ((index % count) + count) % count }
    static func backdrop(_ index: Int) -> [Color] { AvatarStyle.all[wrapped(index)].backdrop }
    static func tone(_ index: Int) -> Color { AvatarStyle.all[wrapped(index)].body }
}

// MARK: - Styles

struct AvatarStyle {
    enum Eyes { case dots, shiny, happy, sleepy, wink, glasses }
    enum Mouth { case smile, open, small, cat, tongue }
    enum Extra { case none, sprout, antenna, halo, sparkle, thread }

    let body: Color
    let light: Color
    let deep: Color
    let backdrop: [Color]
    let eyes: Eyes
    let mouth: Mouth
    let extra: Extra
    var blush = false
    var darkBody = false
    /// Shape personality: how much and how the outline wobbles.
    var wobble: CGFloat = 1

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static let all: [AvatarStyle] = [
        AvatarStyle(body: rgb(0.30, 0.52, 1.0), light: rgb(0.66, 0.82, 1.0), deep: rgb(0.13, 0.27, 0.78),
                    backdrop: [rgb(0.88, 0.93, 1.0), rgb(0.76, 0.86, 1.0)], eyes: .shiny, mouth: .smile, extra: .sprout),
        AvatarStyle(body: rgb(1.0, 0.47, 0.40), light: rgb(1.0, 0.76, 0.66), deep: rgb(0.82, 0.24, 0.24),
                    backdrop: [rgb(1.0, 0.94, 0.88), rgb(1.0, 0.84, 0.76)], eyes: .happy, mouth: .open, extra: .none, blush: true, wobble: 1.3),
        AvatarStyle(body: rgb(0.16, 0.78, 0.62), light: rgb(0.58, 0.95, 0.82), deep: rgb(0.04, 0.52, 0.44),
                    backdrop: [rgb(0.88, 0.99, 0.94), rgb(0.74, 0.94, 0.86)], eyes: .dots, mouth: .cat, extra: .antenna),
        AvatarStyle(body: rgb(0.53, 0.40, 1.0), light: rgb(0.80, 0.72, 1.0), deep: rgb(0.32, 0.20, 0.80),
                    backdrop: [rgb(0.94, 0.91, 1.0), rgb(0.84, 0.80, 1.0)], eyes: .sleepy, mouth: .small, extra: .halo, wobble: 0.7),
        AvatarStyle(body: rgb(1.0, 0.75, 0.16), light: rgb(1.0, 0.92, 0.56), deep: rgb(0.88, 0.50, 0.04),
                    backdrop: [rgb(1.0, 0.98, 0.88), rgb(1.0, 0.91, 0.70)], eyes: .wink, mouth: .tongue, extra: .sparkle, blush: true),
        AvatarStyle(body: rgb(0.14, 0.15, 0.19), light: rgb(0.40, 0.43, 0.52), deep: rgb(0.04, 0.04, 0.06),
                    backdrop: [rgb(0.92, 0.93, 0.95), rgb(0.80, 0.82, 0.87)], eyes: .glasses, mouth: .smile, extra: .none, darkBody: true, wobble: 0.8),
        AvatarStyle(body: rgb(1.0, 0.44, 0.70), light: rgb(1.0, 0.76, 0.88), deep: rgb(0.82, 0.18, 0.48),
                    backdrop: [rgb(1.0, 0.92, 0.96), rgb(1.0, 0.82, 0.90)], eyes: .happy, mouth: .smile, extra: .sparkle, blush: true, wobble: 1.2),
        AvatarStyle(body: rgb(0.08, 0.72, 0.95), light: rgb(0.56, 0.92, 1.0), deep: rgb(0.02, 0.46, 0.74),
                    backdrop: [rgb(0.88, 0.97, 1.0), rgb(0.72, 0.91, 1.0)], eyes: .glasses, mouth: .open, extra: .antenna),
        AvatarStyle(body: rgb(0.55, 0.82, 0.20), light: rgb(0.82, 0.96, 0.52), deep: rgb(0.30, 0.58, 0.06),
                    backdrop: [rgb(0.95, 0.99, 0.88), rgb(0.86, 0.95, 0.70)], eyes: .dots, mouth: .cat, extra: .sprout, blush: true, wobble: 1.4),
        AvatarStyle(body: rgb(1.0, 0.56, 0.14), light: rgb(1.0, 0.80, 0.50), deep: rgb(0.84, 0.32, 0.02),
                    backdrop: [rgb(1.0, 0.94, 0.86), rgb(1.0, 0.85, 0.70)], eyes: .shiny, mouth: .open, extra: .antenna, wobble: 1.1),
        AvatarStyle(body: rgb(0.36, 0.45, 0.64), light: rgb(0.66, 0.74, 0.88), deep: rgb(0.18, 0.24, 0.40),
                    backdrop: [rgb(0.92, 0.94, 0.98), rgb(0.80, 0.85, 0.94)], eyes: .wink, mouth: .smile, extra: .thread, wobble: 0.9),
        AvatarStyle(body: rgb(0.03, 0.39, 0.85), light: rgb(0.45, 0.70, 1.0), deep: rgb(0.01, 0.18, 0.55),
                    backdrop: [rgb(0.84, 0.90, 1.0), rgb(0.68, 0.80, 1.0)], eyes: .shiny, mouth: .smile, extra: .halo)
    ]
}

// MARK: - Drawing

private struct AvatarCanvas: View {
    let style: AvatarStyle
    let size: CGFloat
    /// nil draws the resting pose.
    let time: Double?

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width
            let t = time ?? 0
            let breathe = time == nil ? 0 : CGFloat(sin(t * 2.2)) * 0.012
            let phase = time == nil ? 0.6 : t * 1.7
            // Blink: a short squeeze every few seconds.
            let blinkCycle = time.map { $0.truncatingRemainder(dividingBy: 3.4) } ?? 1
            let blink: CGFloat = blinkCycle < 0.13 ? max(0.08, CGFloat(abs(blinkCycle - 0.065) / 0.065)) : 1

            drawBackdrop(&context, s: s)
            let center = CGPoint(x: s * 0.5, y: s * 0.6 - breathe * s * 0.5)
            let radius = s * (0.34 + breathe)
            let body = blobPath(center: center, radius: radius, phase: phase)

            // Contact shadow and body.
            var shadow = context
            shadow.addFilter(.blur(radius: s * 0.035))
            shadow.fill(Path(ellipseIn: CGRect(x: center.x - radius * 0.8, y: center.y + radius * 0.78, width: radius * 1.6, height: s * 0.09)), with: .color(.black.opacity(0.16)))
            context.fill(body, with: .radialGradient(Gradient(colors: [style.light, style.body, style.deep]),
                                                     center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.45),
                                                     startRadius: 0, endRadius: radius * 1.55))
            // Rim light along the lower edge.
            context.stroke(body, with: .linearGradient(Gradient(colors: [.white.opacity(0.0), .white.opacity(0.45)]),
                                                       startPoint: CGPoint(x: center.x, y: center.y - radius), endPoint: CGPoint(x: center.x, y: center.y + radius)),
                           lineWidth: max(0.8, s * 0.016))
            drawExtra(&context, s: s, center: center, radius: radius, t: t, live: time != nil)
            drawFace(&context, s: s, center: center, radius: radius, blink: blink)
            // Specular highlight: what makes it read as a drop, not a sticker.
            var gloss = context
            gloss.addFilter(.blur(radius: s * 0.012))
            gloss.translateBy(x: center.x - radius * 0.42, y: center.y - radius * 0.5)
            gloss.rotate(by: .degrees(-28))
            gloss.fill(Path(ellipseIn: CGRect(x: -radius * 0.24, y: -radius * 0.11, width: radius * 0.48, height: radius * 0.22)), with: .color(.white.opacity(0.7)))
        }
        .frame(width: size, height: size)
    }

    private func drawBackdrop(_ context: inout GraphicsContext, s: CGFloat) {
        let rect = CGRect(x: 0, y: 0, width: s, height: s)
        context.fill(Path(rect), with: .linearGradient(Gradient(colors: style.backdrop), startPoint: .zero, endPoint: CGPoint(x: s, y: s)))
        context.fill(Path(ellipseIn: CGRect(x: -s * 0.2, y: -s * 0.35, width: s * 0.9, height: s * 0.8)), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.65), .white.opacity(0)]), center: CGPoint(x: s * 0.25, y: s * 0.05), startRadius: 0, endRadius: s * 0.55))
    }

    private func blobPath(center: CGPoint, radius: CGFloat, phase: Double) -> Path {
        var path = Path()
        let steps = 72
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let wobble = 0.045 * sin(2 * angle + phase) + 0.03 * sin(3 * angle + 1.7 + phase * 1.3)
            let r = radius * (1 + CGFloat(wobble) * style.wobble)
            // Slightly wider than tall, resting on its floor like a drop of something thick.
            let squash: CGFloat = sin(angle) > 0 ? 0.92 : 1.0
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * r * 1.07, y: center.y + CGFloat(sin(angle)) * r * squash)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    // MARK: Face

    private func drawFace(_ context: inout GraphicsContext, s: CGFloat, center: CGPoint, radius: CGFloat, blink: CGFloat) {
        let ink: Color = style.darkBody ? .white : Color(red: 0.07, green: 0.07, blue: 0.1)
        let eyeY = center.y - radius * 0.12
        let spread = radius * 0.34
        let left = CGPoint(x: center.x - spread, y: eyeY), right = CGPoint(x: center.x + spread, y: eyeY)
        let line = max(1, s * 0.028)
        switch style.eyes {
        case .dots:
            for eye in [left, right] { dot(&context, eye, r: radius * 0.09, scaleY: blink, color: ink) }
        case .shiny:
            for eye in [left, right] { shinyEye(&context, eye, r: radius * 0.15, blink: blink, ink: ink) }
        case .happy:
            for eye in [left, right] { arc(&context, eye, width: radius * 0.3, height: -radius * 0.14, line: line, color: ink) }
        case .sleepy:
            for eye in [left, right] { arc(&context, CGPoint(x: eye.x, y: eye.y + radius * 0.02), width: radius * 0.28, height: radius * 0.1, line: line, color: ink) }
        case .wink:
            shinyEye(&context, left, r: radius * 0.15, blink: blink, ink: ink)
            arc(&context, right, width: radius * 0.3, height: -radius * 0.14, line: line, color: ink)
        case .glasses:
            for eye in [left, right] { shinyEye(&context, eye, r: radius * 0.11, blink: blink, ink: ink) }
            let frameColor: Color = style.darkBody ? .white.opacity(0.92) : Color(red: 0.07, green: 0.07, blue: 0.1)
            for eye in [left, right] {
                let lens = CGRect(x: eye.x - radius * 0.24, y: eye.y - radius * 0.2, width: radius * 0.48, height: radius * 0.4)
                context.fill(Path(roundedRect: lens, cornerRadius: radius * 0.14), with: .color(.white.opacity(0.14)))
                context.stroke(Path(roundedRect: lens, cornerRadius: radius * 0.14), with: .color(frameColor), lineWidth: line * 0.8)
            }
            var bridge = Path()
            bridge.move(to: CGPoint(x: left.x + radius * 0.24, y: eyeY - radius * 0.02))
            bridge.addQuadCurve(to: CGPoint(x: right.x - radius * 0.24, y: eyeY - radius * 0.02), control: CGPoint(x: center.x, y: eyeY - radius * 0.1))
            context.stroke(bridge, with: .color(frameColor), lineWidth: line * 0.8)
        }
        if style.blush {
            for side: CGFloat in [-1, 1] {
                context.fill(Path(ellipseIn: CGRect(x: center.x + side * radius * 0.56 - radius * 0.13, y: eyeY + radius * 0.16, width: radius * 0.26, height: radius * 0.14)),
                             with: .color(Color(red: 1, green: 0.35, blue: 0.5).opacity(0.35)))
            }
        }
        drawMouth(&context, center: CGPoint(x: center.x, y: center.y + radius * 0.2), radius: radius, line: line, ink: ink)
    }

    private func drawMouth(_ context: inout GraphicsContext, center m: CGPoint, radius: CGFloat, line: CGFloat, ink: Color) {
        let tongue = Color(red: 1, green: 0.42, blue: 0.5)
        switch style.mouth {
        case .smile:
            arc(&context, m, width: radius * 0.34, height: radius * 0.16, line: line, color: ink)
        case .open:
            var mouth = Path()
            mouth.move(to: CGPoint(x: m.x - radius * 0.2, y: m.y - radius * 0.03))
            mouth.addQuadCurve(to: CGPoint(x: m.x + radius * 0.2, y: m.y - radius * 0.03), control: CGPoint(x: m.x, y: m.y + radius * 0.34))
            mouth.closeSubpath()
            context.fill(mouth, with: .color(ink))
            context.fill(Path(ellipseIn: CGRect(x: m.x - radius * 0.09, y: m.y + radius * 0.07, width: radius * 0.18, height: radius * 0.09)), with: .color(tongue))
        case .small:
            context.fill(Path(ellipseIn: CGRect(x: m.x - radius * 0.06, y: m.y - radius * 0.04, width: radius * 0.12, height: radius * 0.14)), with: .color(ink))
        case .cat:
            arc(&context, CGPoint(x: m.x - radius * 0.08, y: m.y), width: radius * 0.16, height: radius * 0.09, line: line * 0.85, color: ink)
            arc(&context, CGPoint(x: m.x + radius * 0.08, y: m.y), width: radius * 0.16, height: radius * 0.09, line: line * 0.85, color: ink)
        case .tongue:
            context.fill(Path(ellipseIn: CGRect(x: m.x - radius * 0.07, y: m.y + radius * 0.02, width: radius * 0.14, height: radius * 0.16)), with: .color(tongue))
            arc(&context, m, width: radius * 0.34, height: radius * 0.14, line: line, color: ink)
        }
    }

    private func dot(_ context: inout GraphicsContext, _ p: CGPoint, r: CGFloat, scaleY: CGFloat, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * scaleY, width: r * 2, height: r * 2 * scaleY)), with: .color(color))
    }

    private func shinyEye(_ context: inout GraphicsContext, _ p: CGPoint, r: CGFloat, blink: CGFloat, ink: Color) {
        if style.darkBody {
            dot(&context, p, r: r, scaleY: blink, color: .white)
            dot(&context, CGPoint(x: p.x + r * 0.15, y: p.y + r * 0.1), r: r * 0.55, scaleY: blink, color: Color(red: 0.07, green: 0.07, blue: 0.1))
        } else {
            dot(&context, p, r: r, scaleY: blink, color: ink)
        }
        guard blink > 0.6 else { return }
        dot(&context, CGPoint(x: p.x - r * 0.32, y: p.y - r * 0.34), r: r * 0.32, scaleY: 1, color: .white.opacity(0.95))
        dot(&context, CGPoint(x: p.x + r * 0.35, y: p.y + r * 0.3), r: r * 0.14, scaleY: 1, color: .white.opacity(0.7))
    }

    /// Positive height curves down (smile), negative curves up (happy closed eye).
    private func arc(_ context: inout GraphicsContext, _ p: CGPoint, width: CGFloat, height: CGFloat, line: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: p.x - width / 2, y: p.y))
        path.addQuadCurve(to: CGPoint(x: p.x + width / 2, y: p.y), control: CGPoint(x: p.x, y: p.y + height * 2))
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: line, lineCap: .round))
    }

    // MARK: Extras

    private func drawExtra(_ context: inout GraphicsContext, s: CGFloat, center: CGPoint, radius: CGFloat, t: Double, live: Bool) {
        let top = CGPoint(x: center.x, y: center.y - radius * 0.97)
        let sway = live ? CGFloat(sin(t * 2.6)) * radius * 0.06 : 0
        let line = max(1, s * 0.024)
        switch style.extra {
        case .none:
            break
        case .sprout:
            var stem = Path()
            stem.move(to: top)
            stem.addQuadCurve(to: CGPoint(x: top.x + sway, y: top.y - radius * 0.3), control: CGPoint(x: top.x - radius * 0.05, y: top.y - radius * 0.15))
            context.stroke(stem, with: .color(Color(red: 0.2, green: 0.62, blue: 0.3)), style: StrokeStyle(lineWidth: line, lineCap: .round))
            let tip = CGPoint(x: top.x + sway, y: top.y - radius * 0.3)
            for side: Double in [-1, 1] {
                var leaf = context
                leaf.translateBy(x: tip.x, y: tip.y)
                leaf.rotate(by: .degrees(side * 40 - 10))
                leaf.fill(Path(ellipseIn: CGRect(x: side > 0 ? 0 : -radius * 0.3, y: -radius * 0.08, width: radius * 0.3, height: radius * 0.16)),
                          with: .color(Color(red: 0.36, green: 0.8, blue: 0.4)))
            }
        case .antenna:
            var wire = Path()
            let end = CGPoint(x: top.x + radius * 0.12 + sway, y: top.y - radius * 0.36)
            wire.move(to: top)
            wire.addQuadCurve(to: end, control: CGPoint(x: top.x - radius * 0.05, y: top.y - radius * 0.2))
            context.stroke(wire, with: .color(style.deep), style: StrokeStyle(lineWidth: line, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: end.x - radius * 0.1, y: end.y - radius * 0.1, width: radius * 0.2, height: radius * 0.2)),
                         with: .radialGradient(Gradient(colors: [.white, style.light, style.body]), center: CGPoint(x: end.x - radius * 0.03, y: end.y - radius * 0.03), startRadius: 0, endRadius: radius * 0.12))
        case .halo:
            let ring = CGRect(x: center.x - radius * 0.46, y: top.y - radius * 0.28 + sway * 0.4, width: radius * 0.92, height: radius * 0.22)
            context.stroke(Path(ellipseIn: ring), with: .color(Color(red: 1, green: 0.82, blue: 0.3)), lineWidth: line * 1.1)
            context.stroke(Path(ellipseIn: ring.insetBy(dx: -1, dy: -1)), with: .color(.white.opacity(0.5)), lineWidth: line * 0.4)
        case .sparkle:
            let pulse = live ? 0.85 + 0.15 * CGFloat(sin(t * 4)) : 1
            star(&context, CGPoint(x: center.x + radius * 0.82, y: center.y - radius * 0.86), r: radius * 0.2 * pulse)
            star(&context, CGPoint(x: center.x - radius * 0.9, y: center.y - radius * 0.55), r: radius * 0.11 * (2 - pulse))
        case .thread:
            // A loose curl of the Sinnfaden thread rising from the head.
            var curl = Path()
            curl.move(to: top)
            curl.addCurve(to: CGPoint(x: top.x + radius * 0.06 + sway, y: top.y - radius * 0.42),
                          control1: CGPoint(x: top.x + radius * 0.3, y: top.y - radius * 0.1),
                          control2: CGPoint(x: top.x - radius * 0.3, y: top.y - radius * 0.3))
            context.stroke(curl, with: .color(Color.sinnAnnotation), style: StrokeStyle(lineWidth: line * 1.1, lineCap: .round))
        }
    }

    private func star(_ context: inout GraphicsContext, _ p: CGPoint, r: CGFloat) {
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let radius = i % 2 == 0 ? r : r * 0.32
            let point = CGPoint(x: p.x + CGFloat(cos(angle)) * radius, y: p.y + CGFloat(sin(angle)) * radius)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        context.fill(path, with: .color(Color(red: 1, green: 0.84, blue: 0.3)))
        context.fill(path, with: .color(.white.opacity(0.35)))
    }
}

// MARK: - Picker

/// Avatar grid: the hovered companion wakes up and lifts; a liquid ring follows the choice.
struct AvatarPicker: View {
    @Binding var selection: Int
    var size: CGFloat = 54
    var columns = 6
    @Namespace private var ring
    @State private var hovered: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(size + 12), spacing: 8), count: columns), spacing: 10) {
            ForEach(0..<ProfileAvatar.count, id: \.self) { index in
                let isSelected = selection == index
                let isHovered = hovered == index
                Button { withAnimation(SinnMotion.selection) { selection = index } } label: {
                    ProfileAvatar(index: index, size: size, live: isHovered)
                        .shadow(color: ProfileAvatar.tone(index).opacity(isHovered || isSelected ? 0.35 : 0), radius: 8, y: 4)
                        .padding(4)
                        .background {
                            if isSelected {
                                Circle().strokeBorder(Color.sinnAnnotation, lineWidth: 2.5)
                                    .matchedGeometryEffect(id: "ring", in: ring)
                            }
                        }
                        .scaleEffect(isHovered && !reduceMotion ? 1.12 : 1)
                        .offset(y: isHovered && !reduceMotion ? -2 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                .accessibilityLabel("Profilbild \(index + 1)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
