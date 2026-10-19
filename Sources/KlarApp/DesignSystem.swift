import SwiftUI
import AppKit

extension NSColor {
    private static func adaptive(_ name: String, _ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: NSColor.Name(name)) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        }
    }
    // The app deliberately uses a white appearance, including native child panels.
    static let sinnWindow = adaptive("SinnWindow", 0xFFFFFF, 0xFFFFFF)
    static let sinnSurface = adaptive("SinnSurface", 0xFFFFFF, 0xFFFFFF)
    static let sinnInk = adaptive("SinnInk", 0x19191B, 0x19191B)
    static let sinnMuted = adaptive("SinnMuted", 0x69696E, 0x69696E)
    static let sinnAction = adaptive("SinnAction", 0x19191B, 0x19191B)
    static let sinnActionText = adaptive("SinnActionText", 0xFFFFFF, 0xFFFFFF)
    static let sinnStructure = adaptive("SinnStructure", 0xF0F0F2, 0xF0F0F2)
    static let sinnChrome = adaptive("SinnChrome", 0xDADADD, 0xDADADD)
    static let sinnAnnotation = adaptive("SinnAnnotation", 0x0864D9, 0x0864D9)
    static let sinnAnnotationWash = adaptive("SinnAnnotationWash", 0xEDF5FF, 0xEDF5FF)
}
extension Color {
    static let sinnWindow = Color(nsColor: .sinnWindow)
    static let sinnSurface = Color(nsColor: .sinnSurface)
    static let sinnInk = Color(nsColor: .sinnInk)
    static let sinnMuted = Color(nsColor: .sinnMuted)
    static let sinnAction = Color(nsColor: .sinnAction)
    static let sinnActionText = Color(nsColor: .sinnActionText)
    static let sinnStructure = Color(nsColor: .sinnStructure)
    static let sinnChrome = Color(nsColor: .sinnChrome)
    static let sinnAnnotation = Color(nsColor: .sinnAnnotation)
    static let sinnAnnotationWash = Color(nsColor: .sinnAnnotationWash)
    static let klarBlue = sinnAction
    static let klarInk = sinnInk
    static let klarMuted = sinnMuted
}

/// The Sinnfaden thread: one continuous line that also reads as the capital S.
struct SinnfadenMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 128
        let o = CGPoint(x: rect.midX - 64 * s, y: rect.midY - 64 * s)
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var p = Path()
        p.move(to: pt(89, 29))
        p.addCurve(to: pt(32, 36), control1: pt(74, 14), control2: pt(43, 18))
        p.addCurve(to: pt(79, 70), control1: pt(13, 63), control2: pt(62, 58))
        p.addCurve(to: pt(37, 102), control1: pt(107, 90), control2: pt(76, 122))
        p.move(to: pt(25, 94)); p.addLine(to: pt(21, 88))
        return p
    }
}

struct SinnfadenMark: View {
    var progress: CGFloat = 1
    var color: Color = .sinnAction
    var weight: CGFloat = 1
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 128
            SinnfadenMarkShape()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 11 * s * weight, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}

/// The wordmark: the thread is the S, followed by "innfaden".
struct SinnfadenWordmark: View {
    /// Square frame for the 128-unit mark: ink height 0.729 em incl. a 0.105 em stroke.
    static func markFrame(_ size: CGFloat) -> CGFloat { size * 0.9022 }
    static let markWeight: CGFloat = 1.354
    /// Baseline 0.804 em below the frame top (ink bottom overshoots by 0.012 em, like the glyph).
    static let baselineFraction: CGFloat = 0.891
    /// Gap from thread ink to the "i" ink equals the font's own S→i gap after tracking.
    static func spacing(_ size: CGFloat) -> CGFloat { -size * 0.212 }
    static func leading(_ size: CGFloat) -> CGFloat { -size * 0.054 }

    static func mark(size: CGFloat, progress: CGFloat = 1, color: Color = .sinnInk) -> some View {
        SinnfadenMark(progress: progress, color: color, weight: markWeight)
            .frame(width: markFrame(size), height: markFrame(size))
            .alignmentGuide(.firstTextBaseline) { d in d.height * baselineFraction }
            .padding(.leading, leading(size))
    }

    var size: CGFloat = 22
    var color: Color = .sinnInk
    var markProgress: CGFloat = 1
    var lettersVisible = true
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.spacing(size)) {
            Self.mark(size: size, progress: markProgress, color: color)
            Text("innfaden")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .tracking(-size * 0.035)
                .foregroundStyle(color)
                .opacity(lettersVisible ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sinnfaden")
    }
}

/// Type scale (ratio 1.333): one clear system family, bold display, quiet body text.
enum SinnType {
    static func display(_ size: CGFloat = 44) -> Font { .system(size: size, weight: .bold) }
    static func title(_ size: CGFloat = 24) -> Font { .system(size: size, weight: .semibold) }
    static let heading = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15)
    static let meta = Font.system(size: 12, weight: .medium)
    static let eyebrow = Font.system(size: 11, weight: .semibold)
}

/// Motion tokens. Every animation has one purpose: orientation, feedback, continuity or status.
enum SinnMotion {
    static let hover = Animation.easeOut(duration: 0.12)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.7)
    static let page = Animation.spring(response: 0.42, dampingFraction: 0.88)
    static let reveal = Animation.spring(response: 0.5, dampingFraction: 0.86)
    static let selection = Animation.spring(response: 0.34, dampingFraction: 0.82)
    static let stagger = 0.045
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(configuration: configuration, primary: true)
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ActionButtonBody(configuration: configuration, primary: false)
    }
}
private struct ActionButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .frame(minHeight: 42)
            .foregroundStyle(enabled ? (primary ? Color.white : Color.sinnInk) : Color.sinnMuted)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(primary && enabled ? Color.sinnAction.opacity(configuration.isPressed ? 0.8 : 1) : Color.sinnStructure.opacity(configuration.isPressed ? 1 : hovered ? 0.95 : 0.65))
                    .overlay {
                        // A soft top light on the black action reads as a physical key.
                        if primary && enabled {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(LinearGradient(colors: [Color.white.opacity(hovered ? 0.2 : 0.12), .clear], startPoint: .top, endPoint: .center))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.sinnInk.opacity(contrast == .increased ? 0.6 : primary ? 0 : 0.06), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(primary && enabled ? (hovered ? 0.22 : 0.12) : 0), radius: hovered ? 10 : 5, y: hovered ? 5 : 2)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .offset(y: hovered && !configuration.isPressed && !reduceMotion && enabled ? -1 : 0)
            .animation(reduceMotion ? nil : SinnMotion.press, value: configuration.isPressed)
            .animation(reduceMotion ? nil : SinnMotion.hover, value: hovered)
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onHover { hovered = $0 }
    }
}

/// Frosted material belongs behind content; letters never receive a blur.
struct CardSurface: ViewModifier {
    var radius: CGFloat = 26
    var elevated = false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        // Shadows and stroke live on the background shape only. A shadow on the content would
        // render the whole card, native AppKit text included, into its own graphics layer, and
        // SwiftUI then places that text at a stale position over the controls around it.
        content.background {
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                if reduceTransparency || contrast == .increased {
                    shape.fill(Color.white)
                } else {
                    // Milky glass: the flowing background shows through, softened.
                    shape.fill(.ultraThinMaterial)
                        .overlay(shape.fill(Color.white.opacity(0.55)))
                        .overlay(shape.fill(LinearGradient(colors: [Color.white.opacity(0.9), Color.white.opacity(0)], startPoint: .top, endPoint: .center)).opacity(0.5))
                }
                shape.strokeBorder(contrast == .increased ? Color.sinnMuted : Color.black.opacity(elevated ? 0.09 : 0.06), lineWidth: 1)
                    .padding(0.5)
            }
            .shadow(color: Color.black.opacity(elevated ? 0.075 : 0.035), radius: elevated ? 30 : 22, x: 0, y: elevated ? 16 : 9)
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        }
    }
}
extension View {
    func cardSurface(radius: CGFloat = 26, elevated: Bool = false) -> some View { modifier(CardSurface(radius: radius, elevated: elevated)) }
    /// Staggered entrance: content rises a few points and fades in once it appears.
    func sinnReveal(_ index: Int = 0) -> some View { modifier(SinnReveal(index: index)) }
}

/// Whole-card buttons (lessons, templates, history): they lift toward the cursor and press in.
struct LiftCardStyle: ButtonStyle {
    var radius: CGFloat = 24
    func makeBody(configuration: Configuration) -> some View { LiftCardBody(configuration: configuration, radius: radius) }
}
private struct LiftCardBody: View {
    let configuration: ButtonStyleConfiguration
    let radius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(radius: radius, elevated: hovered)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hovered ? Color.sinnInk : Color.sinnMuted.opacity(0.7))
                    .offset(x: hovered && !reduceMotion ? 2 : 0, y: hovered && !reduceMotion ? -2 : 0)
                    .padding(20)
                    .accessibilityHidden(true)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .offset(y: hovered && !reduceMotion ? -3 : 0)
            .animation(reduceMotion ? nil : SinnMotion.press, value: configuration.isPressed)
            .animation(reduceMotion ? nil : SinnMotion.selection, value: hovered)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovered = $0 }
    }
}

private struct SinnReveal: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        // The animation is scoped to these two properties. A global transaction would also
        // animate the first frame of hosted AppKit text and leave it at a stale position.
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .animation(reduceMotion ? .easeOut(duration: 0.15) : SinnMotion.reveal.delay(Double(min(index, 8)) * SinnMotion.stagger), value: shown)
            .onAppear { if !shown { shown = true } }
    }
}

/// Editorial page head: small blue eyebrow, serif display title, calm lead.
struct SinnPageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(eyebrow.uppercased()).font(SinnType.eyebrow).tracking(2).foregroundStyle(Color.sinnAnnotation)
            Text(title).font(SinnType.display()).tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(size: 16)).foregroundStyle(Color.sinnMuted).lineSpacing(5)
                .frame(maxWidth: 620, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 6)
        .sinnReveal(0)
    }
}

/// Sinnfaden's status signature: a thread of light runs along a gently moving line.
/// Reduced motion shows a static thread with the system spinner.
struct ThreadLoader: View {
    var width: CGFloat = 120
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if reduceMotion {
            ProgressView().controlSize(.small)
        } else {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                Canvas { context, size in
                    var path = Path()
                    let mid = size.height / 2
                    for step in 0...60 {
                        let x = size.width * CGFloat(step) / 60
                        let y = mid + sin(CGFloat(step) / 60 * .pi * 2.4 + CGFloat(t) * 3.2) * size.height * 0.28
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path, with: .color(Color.sinnAnnotation.opacity(0.18)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    let head = CGFloat((t * 0.7).truncatingRemainder(dividingBy: 1))
                    let gradient = Gradient(stops: [
                        .init(color: Color.sinnAnnotation.opacity(0), location: max(0, head - 0.35)),
                        .init(color: Color.sinnAnnotation, location: head),
                        .init(color: Color.sinnAnnotation.opacity(0), location: min(1, head + 0.02))
                    ])
                    context.stroke(path, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                                   style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                }
            }
            .frame(width: width, height: 18)
            .accessibilityLabel("Wird erstellt")
        }
    }
}

/// Calm filled field: no hard bezel; focus is shown by the annotation light on its edge.
struct SinnFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View { SinnField(field: configuration) }
}
private struct SinnField<Field: View>: View {
    let field: Field
    @FocusState private var focused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        field
            .textFieldStyle(.plain)
            .focused($focused)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Color.sinnStructure.opacity(focused ? 0.35 : 0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? Color.sinnAnnotation.opacity(0.55) : Color.black.opacity(contrast == .increased ? 0.4 : 0.06), lineWidth: focused ? 1.5 : 1)
            }
            .shadow(color: Color.sinnAnnotation.opacity(focused ? 0.14 : 0), radius: 10)
            .animation(reduceMotion ? nil : SinnMotion.hover, value: focused)
    }
}

extension View {
    /// Multi-line editors share the field surface, so every place you type looks alike.
    func sinnEditorSurface() -> some View {
        self.scrollContentBackground(.hidden)
            .padding(.horizontal, 8).padding(.vertical, 8)
            .background(Color.sinnStructure.opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.06)))
    }
}
