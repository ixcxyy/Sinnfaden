import AppKit

/// State of the light under the highlighted words, in the text view's flipped
/// coordinates. Drawn behind the glyphs, so letters keep their shape and contrast.
struct AnnotationAnchorGlow: Equatable {
    var changeID: String
    var intensity: CGFloat
    /// Core home in view coordinates: under the cursor while arming, at the neck once shown.
    var coreX: CGFloat
    var coreY: CGFloat
    var coreRadius: CGFloat
    /// 0 = core rests in the fragment's centre, 1 = core sits on the edge facing the lens.
    var coreDrift: CGFloat
    var lightX: CGFloat
    /// Lens side in flipped view coordinates (true = larger y, below the words).
    var towardMaxY: Bool
}

enum AnnotationAnchorGlowRenderer {
    static let reach: CGFloat = 10

    static func dirtyRect(_ fragments: [CGRect]) -> CGRect {
        fragments.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -reach - 6, dy: -reach)
    }

    static func draw(_ glow: AnnotationAnchorGlow, fragments: [CGRect], in context: CGContext) {
        let strength = min(1, max(0, glow.intensity))
        guard strength > 0.004, !fragments.isEmpty else { return }
        let wash = NSColor.sinnAnnotationWash, blue = NSColor.sinnAnnotation
        let cyan = NSColor(srgbRed: 0.42, green: 0.86, blue: 1.0, alpha: 1)
        let ice = NSColor(srgbRed: 0.80, green: 0.91, blue: 1.0, alpha: 1)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let anchor = AnnotationGeometry.nearestRect(fragments, to: CGPoint(x: glow.coreX, y: glow.coreY)) ?? fragments[0]

        for fragment in fragments {
            let pill = fragment.insetBy(dx: -3, dy: 0)
            let radius = min(pill.height / 2, 8)
            let path = CGPath(roundedRect: pill, cornerWidth: radius, cornerHeight: radius, transform: nil)
            context.saveGState()
            context.addPath(path)
            context.setFillColor(wash.withAlphaComponent(min(1, strength * 1.6)).cgColor)
            context.fillPath()
            context.addPath(path)
            context.clip()
            // Depth: a faint inner shade at the top and a bright lower lip read as a shallow basin.
            if let depth = CGGradient(colorsSpace: space, colors: [blue.withAlphaComponent(0.11 * strength).cgColor,
                                                                    blue.withAlphaComponent(0).cgColor,
                                                                    NSColor.white.withAlphaComponent(0.55 * strength).cgColor] as CFArray,
                                      locations: [0, 0.45, 1]) {
                context.drawLinearGradient(depth, start: CGPoint(x: pill.midX, y: pill.minY), end: CGPoint(x: pill.midX, y: pill.maxY), options: [])
            }
            // Light condenses locally around the cursor.
            let lightCenter = CGPoint(x: glow.lightX, y: fragment.midY)
            if let light = CGGradient(colorsSpace: space, colors: [cyan.withAlphaComponent(0.34 * strength).cgColor,
                                                                    blue.withAlphaComponent(0.10 * strength).cgColor,
                                                                    blue.withAlphaComponent(0).cgColor] as CFArray,
                                      locations: [0, 0.4, 1]) {
                context.drawRadialGradient(light, startCenter: lightCenter, startRadius: 0, endCenter: lightCenter, endRadius: 52, options: [])
            }
            context.restoreGState()
            context.saveGState()
            context.addPath(path)
            context.setStrokeColor(blue.withAlphaComponent(0.18 * strength).cgColor)
            context.setLineWidth(0.75)
            context.strokePath()
            context.restoreGState()
        }

        // The glossy core: the nucleus the lens grows from and flows back into.
        let radius = max(0, glow.coreRadius)
        guard radius > 0.3 else { return }
        let alpha = min(1, strength * 1.25)
        let direction: CGFloat = glow.towardMaxY ? 1 : -1
        let drift = min(1.2, max(0, glow.coreDrift))
        let x = min(anchor.maxX - 2, max(anchor.minX + 2, glow.coreX))
        let center = CGPoint(x: x, y: glow.coreY + direction * drift * (anchor.height / 2 - 1.5))
        let rx = radius * (1 + 0.15 * drift), ry = radius * (1 + 0.45 * drift)
        context.saveGState()
        context.clip(to: fragments.map { $0.insetBy(dx: -4, dy: -3) })
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: rx / radius, y: ry / radius)
        if let halo = CGGradient(colorsSpace: space, colors: [cyan.withAlphaComponent(0.30 * alpha).cgColor, cyan.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
            context.drawRadialGradient(halo, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius * 2.6, options: [])
        }
        if let body = CGGradient(colorsSpace: space, colors: [NSColor.white.withAlphaComponent(0.97 * alpha).cgColor,
                                                              ice.withAlphaComponent(0.75 * alpha).cgColor,
                                                              cyan.withAlphaComponent(0).cgColor] as CFArray,
                                 locations: [0, 0.55, 1]) {
            context.drawRadialGradient(body, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: radius, options: [])
        }
        let specular = CGPoint(x: -radius * 0.32, y: -radius * 0.36)
        if let spot = CGGradient(colorsSpace: space, colors: [NSColor.white.withAlphaComponent(alpha).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1]) {
            context.drawRadialGradient(spot, startCenter: specular, startRadius: 0, endCenter: specular, endRadius: radius * 0.42, options: [])
        }
        context.restoreGState()
    }
}
