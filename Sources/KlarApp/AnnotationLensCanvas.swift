import AppKit
import QuartzCore

/// Per-frame description of the lens. Every material layer reads from this one
/// value, so outline, light and shadow always describe the same body.
struct AnnotationLensFrame {
    var shape: AnnotationLensShape
    var body: CGRect
    var tip: CGPoint?
    /// Light position relative to the body, -1...1 on each axis (y-up).
    var light: CGPoint
    /// Rim energy: 0 calm, ~1 freshly inflated or pressed.
    var rim: CGFloat
    /// Distance from the text: 0 resting on it, 1 fully lifted.
    var lift: CGFloat
    /// Motion tension 0...1 (cursor speed and deformation rate).
    var tension: CGFloat
    var motion: CGVector
    var incomingOrigin: CGPoint
    var incomingAlpha: CGFloat
    var outgoingAlpha: CGFloat
    /// The pointer position while the cursor itself is the bubble.
    var cursorDot = false
}

/// Opaline lens material. Text hosts sit above every material layer at their
/// fixed measured size; no transform or filter ever touches the glyphs.
@MainActor
final class AnnotationLensCanvas: NSView {
    private let shadowView = NSView()
    private let ambientShadow = CAShapeLayer()
    private let contactShadow = CAShapeLayer()
    private let shadowCutout = CAShapeLayer()
    private let material = NSVisualEffectView()
    private let materialMask = CAShapeLayer()
    private let surfaceView = NSView()
    private let interior = CALayer()
    private let interiorMask = CAShapeLayer()
    private let tint = CAShapeLayer()
    private let depth = CAGradientLayer()
    private let core = CAShapeLayer()
    private let caustic = CAGradientLayer()
    private let gloss = CAGradientLayer()
    private let band = CAGradientLayer()
    private let bandMask = CAShapeLayer()
    private let rim = CAGradientLayer()
    private let rimMask = CAShapeLayer()
    private let contrastEdge = CAShapeLayer()
    private let tipGlow = CAGradientLayer()
    private let cursorDot = CAShapeLayer()
    private var activeHost: NSView?
    private var outgoingHost: NSView?
    private var tracking: NSTrackingArea?
    private var displayOptionsObserver: Any?
    private var currentShape: AnnotationLensShape?
    private var solid = false
    private var contrast = false
    var onPointerInside: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(false)
        for view in [shadowView, surfaceView] {
            view.wantsLayer = true
            view.setAccessibilityElement(false)
            view.layer?.masksToBounds = false
        }
        addSubview(shadowView)
        shadowView.layer?.addSublayer(ambientShadow)
        shadowView.layer?.addSublayer(contactShadow)
        shadowView.layer?.mask = shadowCutout
        shadowCutout.fillRule = .evenOdd
        for shadow in [ambientShadow, contactShadow] { shadow.fillColor = nil }

        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.mask = materialMask
        addSubview(material)

        addSubview(surfaceView)
        let surface = surfaceView.layer!
        surface.addSublayer(interior)
        interior.mask = interiorMask
        [tint, core, depth, caustic, gloss, band].forEach { interior.addSublayer($0) }
        band.mask = bandMask
        bandMask.fillColor = nil; bandMask.strokeColor = NSColor.black.cgColor; bandMask.lineWidth = 10
        core.shadowOffset = .zero; core.shadowRadius = 12; core.shadowOpacity = 0.95
        caustic.type = .radial; gloss.type = .radial; tipGlow.type = .radial
        surface.addSublayer(rim)
        rim.mask = rimMask
        rimMask.fillColor = nil; rimMask.strokeColor = NSColor.black.cgColor; rimMask.lineWidth = 1.35
        surface.addSublayer(contrastEdge)
        contrastEdge.fillColor = nil; contrastEdge.lineWidth = 1.5
        surface.addSublayer(tipGlow)
        surface.addSublayer(cursorDot)
        cursorDot.lineWidth = 2
        updateMaterialColors()
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateMaterialColors() }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func install(_ host: NSView, size: CGSize, transitioning: Bool) {
        outgoingHost?.removeFromSuperview()
        // A prepared host can come back while it is still the active one; never fade it against itself.
        let transitioning = transitioning && host !== activeHost
        // The outgoing layout keeps its last position and width while it fades.
        outgoingHost = transitioning ? activeHost : nil
        if !transitioning { activeHost?.removeFromSuperview() }
        activeHost = host
        host.frame = NSRect(origin: .zero, size: size)
        host.alphaValue = 0
        addSubview(host)
    }

    func finishTransition() {
        outgoingHost?.removeFromSuperview()
        outgoingHost = nil
    }

    func contains(_ point: CGPoint) -> Bool { currentShape?.contains(point) ?? false }

    /// The panel moved by `delta` (screen points); keep outgoing text fixed on screen.
    func pinOutgoing(panelMovedBy delta: CGVector) {
        guard let outgoingHost, delta != .zero else { return }
        outgoingHost.setFrameOrigin(CGPoint(x: outgoingHost.frame.minX - delta.dx, y: outgoingHost.frame.minY - delta.dy))
    }

    func render(_ frame: AnnotationLensFrame) {
        currentShape = frame.shape
        let path = frame.shape.path
        let body = frame.body
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for view in [shadowView, material, surfaceView] { view.frame = bounds }
        for layer in [ambientShadow, contactShadow, shadowCutout, materialMask, interior, interiorMask,
                      tint, core, contrastEdge] as [CALayer] { layer.frame = bounds }
        materialMask.path = path
        interiorMask.path = path
        tint.path = path
        contrastEdge.path = path

        // The shadow follows the real contour and the lift; it never shows through the body.
        let cutout = CGMutablePath()
        cutout.addRect(bounds.insetBy(dx: -40, dy: -40))
        cutout.addPath(path)
        shadowCutout.path = cutout
        let lift = max(0, frame.lift)
        ambientShadow.shadowPath = path
        ambientShadow.shadowRadius = 7 + 10 * lift
        ambientShadow.shadowOffset = CGSize(width: -frame.light.x * 3 * lift, height: -(2 + 6 * lift))
        ambientShadow.shadowOpacity = Float(solid ? 0.10 : 0.06 + 0.12 * lift)
        contactShadow.shadowPath = path
        contactShadow.shadowRadius = 2.2
        contactShadow.shadowOffset = CGSize(width: 0, height: -1)
        contactShadow.shadowOpacity = Float(0.05 + 0.05 * (1 - min(1, lift)))

        // Milky reading core with a feathered edge.
        core.path = frame.shape.corePath
        core.shadowPath = frame.shape.corePath

        // Volume: brighter crown, slightly deeper floor; caustic opposite the light.
        let outset = body.insetBy(dx: -24, dy: -24)
        depth.frame = outset
        caustic.frame = CGRect(x: body.midX - frame.light.x * body.width * 0.30 - body.width * 0.36,
                               y: body.midY - frame.light.y * body.height * 0.32 - body.height * 0.30,
                               width: body.width * 0.72, height: body.height * 0.6)

        // Gloss sits closer to the cursor than the body and stretches with motion.
        let stretch = 1 + min(0.35, frame.tension * 0.4)
        let glossSize = CGSize(width: max(18, body.width * 0.62) * stretch, height: max(14, body.height * 0.46) / sqrt(stretch))
        let glossCenter = CGPoint(x: body.midX + frame.light.x * body.width * 0.30,
                                  y: body.midY + frame.light.y * body.height * 0.34)
        gloss.setAffineTransform(.identity)
        gloss.frame = CGRect(x: glossCenter.x - glossSize.width / 2, y: glossCenter.y - glossSize.height / 2,
                             width: glossSize.width, height: glossSize.height)
        if frame.tension > 0.02 {
            let angle = atan2(frame.motion.dy, frame.motion.dx)
            gloss.setAffineTransform(CGAffineTransform(rotationAngle: max(-0.35, min(0.35, angle * 0.2))))
        }

        // Rim light and the inner refraction band share one light vector.
        let length = max(0.001, hypot(frame.light.x, frame.light.y))
        let lx = frame.light.x / length, ly = frame.light.y / length
        for gradient in [band, rim] {
            gradient.frame = outset
            gradient.startPoint = CGPoint(x: 0.5 + 0.5 * lx, y: 0.5 + 0.5 * ly)
            gradient.endPoint = CGPoint(x: 0.5 - 0.5 * lx, y: 0.5 - 0.5 * ly)
        }
        for mask in [bandMask, rimMask] {
            mask.frame = CGRect(origin: CGPoint(x: -outset.minX, y: -outset.minY), size: bounds.size)
            mask.path = path
        }
        let energy = min(1.4, frame.rim + frame.tension * 0.6)
        rim.opacity = Float(contrast ? 0 : min(1, 0.62 + 0.38 * energy))
        rimMask.lineWidth = 1.2 + 0.7 * min(1, energy)
        band.opacity = Float(solid ? 0.35 : 0.55 + 0.4 * min(1, energy))
        gloss.opacity = Float(solid ? 0.4 : 0.74 + 0.26 * min(1, energy))

        // A little blue light travels down the neck into the highlighted words.
        if let tip = frame.tip {
            let glowSize: CGFloat = 30 + 10 * lift
            tipGlow.frame = CGRect(x: tip.x - glowSize / 2, y: tip.y - glowSize / 2, width: glowSize, height: glowSize)
            tipGlow.opacity = Float(min(1, 0.25 + 0.55 * lift))
        } else { tipGlow.opacity = 0 }
        if frame.cursorDot, let tip = frame.tip {
            cursorDot.frame = bounds
            cursorDot.path = CGPath(ellipseIn: CGRect(x: tip.x - 4.5, y: tip.y - 4.5, width: 9, height: 9), transform: nil)
            cursorDot.opacity = 1
        } else { cursorDot.opacity = 0 }
        CATransaction.commit()

        // Hosts keep their measured size; only origin and opacity change.
        activeHost?.setFrameOrigin(frame.incomingOrigin)
        activeHost?.alphaValue = frame.incomingAlpha
        outgoingHost?.alphaValue = frame.outgoingAlpha
    }

    /// Ink-blue liquid: opaque enough to cover the words beneath, with a white rim light,
    /// a softer inner glow and cyan transmission at the far edge.
    private func updateMaterialColors() {
        solid = AnnotationAccessibility.reduceTransparency
        contrast = AnnotationAccessibility.increaseContrast
        let white = NSColor.white
        let cyan = NSColor(srgbRed: 0.45, green: 0.88, blue: 1.0, alpha: 1)
        let sky = NSColor(srgbRed: 0.38, green: 0.62, blue: 1.0, alpha: 1)
        let blue = NSColor.sinnAnnotation
        let deep = NSColor(srgbRed: 0.02, green: 0.16, blue: 0.42, alpha: 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        material.isHidden = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            tint.fillColor = blue.withAlphaComponent(solid || contrast ? 1 : 0.97).cgColor
            core.fillColor = sky.withAlphaComponent(0.35).cgColor
            core.shadowColor = sky.cgColor
            core.shadowOpacity = 0.55
            core.isHidden = solid || contrast
            depth.colors = [deep.withAlphaComponent(0.35).cgColor, blue.withAlphaComponent(0).cgColor, white.withAlphaComponent(solid ? 0.08 : 0.22).cgColor]
            depth.locations = [0, 0.55, 1]
            depth.startPoint = CGPoint(x: 0.5, y: 0); depth.endPoint = CGPoint(x: 0.5, y: 1)
            caustic.colors = [cyan.withAlphaComponent(solid ? 0.1 : 0.35).cgColor, cyan.withAlphaComponent(0).cgColor]
            caustic.startPoint = CGPoint(x: 0.5, y: 0.5); caustic.endPoint = CGPoint(x: 1, y: 1)
            gloss.colors = [white.withAlphaComponent(0.42).cgColor, white.withAlphaComponent(0.12).cgColor, white.withAlphaComponent(0).cgColor]
            gloss.locations = [0, 0.45, 1]
            gloss.startPoint = CGPoint(x: 0.5, y: 0.5); gloss.endPoint = CGPoint(x: 1, y: 1)
            band.colors = [white.withAlphaComponent(0.55).cgColor, sky.withAlphaComponent(0.4).cgColor,
                           white.withAlphaComponent(0).cgColor, cyan.withAlphaComponent(0.45).cgColor]
            band.locations = [0, 0.3, 0.62, 1]
            rim.colors = [white.cgColor, white.withAlphaComponent(0.6).cgColor, sky.withAlphaComponent(0.6).cgColor, cyan.cgColor]
            rim.locations = [0, 0.32, 0.7, 1]
            contrastEdge.strokeColor = white.cgColor
            contrastEdge.isHidden = !contrast
            tipGlow.colors = [white.withAlphaComponent(0.7).cgColor, cyan.withAlphaComponent(0.3).cgColor, blue.withAlphaComponent(0).cgColor]
            tipGlow.locations = [0, 0.45, 1]
            tipGlow.startPoint = CGPoint(x: 0.5, y: 0.5); tipGlow.endPoint = CGPoint(x: 1, y: 1)
            cursorDot.fillColor = white.cgColor
            cursorDot.strokeColor = blue.cgColor
            ambientShadow.shadowColor = deep.cgColor
            contactShadow.shadowColor = deep.cgColor
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMaterialColors()
    }

    deinit {
        if let displayOptionsObserver { NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver) }
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) { onPointerInside?(contains(convert(event.locationInWindow, from: nil))) }
    override func mouseEntered(with event: NSEvent) { onPointerInside?(contains(convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { onPointerInside?(false) }
}
