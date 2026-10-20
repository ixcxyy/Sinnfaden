import AppKit
import SwiftUI
import KlarCore
import QuartzCore

/// Pointer source. The bubble lab's autopilot may substitute a scripted cursor.
@MainActor
enum AnnotationPointer {
    static var scripted: CGPoint?
    static var location: CGPoint { scripted ?? NSEvent.mouseLocation }
}

/// One controller for the explanation lens: hover, formation around the cursor, following,
/// content morphs and the flow back into the cursor. The lens is never clicked or pinned:
/// its panel lets every mouse event through, and the words under the pointer decide.
@MainActor
final class AnnotationPresentation: NSObject, ObservableObject {
    var onHelpUsed: (() -> Void)?
    weak var textView: AnnotationTextView?
    @Published var inlineChangeID: String?
    @Published var inlineWasExplicit = false
    private(set) var state: AnnotationInteractionState = .idle
    private(set) var activeChange: PromptChange?
    /// Rendered lens frames; the bubble lab derives the observed frame cadence from it.
    private(set) var renderedFrames = 0

    private var panel: AnnotationPanel?
    private var canvas: AnnotationLensCanvas?
    private let bubbleState = AnnotationBubbleState()
    private var hoverWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var eventMonitor: Any?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var displayLink: CADisplayLink?
    private var armingID: String?
    private var generation = 0

    // The origin is where the lens grows from and rests around: the pointer, or the focused
    // words when the keyboard opened it.
    private var origin: CGPoint = .zero
    private var pointer: CGPoint = .zero
    private var previousPointer: CGPoint = .zero
    private var pointerTime: TimeInterval = 0
    private var pointerVelocity: CGSize = .zero

    // Target geometry versus visible body.
    private var baseFrame: CGRect = .zero
    private var boundary: CGRect = .zero
    private var targetSize: CGSize = .zero
    private var lens = AnnotationLensMotion(frame: .zero, tip: .zero)
    private(set) var bodyScreenFrame: CGRect = .zero
    private var ripplePhase: CGFloat = 0

    // Content version and text-layer visibility.
    private var textAlpha: CGFloat = 0
    private var textAlphaAtClose: CGFloat = 0
    private var outgoingAlpha: CGFloat = 0
    private var outgoingAlphaStart: CGFloat = 0
    private var lastPanelOrigin: CGPoint?

    // Light under the words.
    private var glow = AnnotationAnchorMotion()
    private var glowChangeID: String?
    /// One-time light sweep across new annotations: orientation for where explanations live.
    private var intro: (ids: [String], start: TimeInterval)?
    private static var introducedPrompts = Set<String>()
    private var glowFragments: [CGRect] = []

    private var lastFrameTime: TimeInterval = 0
    private var transitionStart: TimeInterval = 0
    private var armStart: TimeInterval = 0

    private var reduced: Bool { AnnotationAccessibility.reduceMotion }
    var shouldUseInline: Bool {
        guard let textView else { return true }
        return textView.bounds.width < 370 || textView.displayFontSize > 22
    }

    /// While an overlay (the navigation dial) covers the text, no bubble may open.
    static let suspendNotification = Notification.Name("SinnfadenSuspendAnnotationHover")
    private(set) static var hoverSuspended = false
    static func setHoverSuspended(_ suspended: Bool) {
        hoverSuspended = suspended
        NotificationCenter.default.post(name: suspendNotification, object: nil)
    }
    private var suspendObserver: NSObjectProtocol?

    override init() {
        super.init()
        suspendObserver = NotificationCenter.default.addObserver(forName: Self.suspendNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, Self.hoverSuspended else { return }
                self.hoverWork?.cancel(); self.armingID = nil
                self.close()
            }
        }
    }

    // MARK: - Pointer input

    /// The annotation under the pointer (nil: none). Called for every mouse move over the text.
    func hover(_ change: PromptChange?, pointer screenPoint: CGPoint? = nil) {
        guard !Self.hoverSuspended || change == nil else { return }
        if change != nil { intro = nil }
        let pointer = screenPoint ?? AnnotationPointer.location
        self.pointer = pointer
        guard let change else {
            hoverWork?.cancel(); armingID = nil
            if state == .arming { state = .idle; startTicking() }
            scheduleClose()
            return
        }
        closeWork?.cancel()
        if activeChange?.id == change.id && state.isPresented && state != .retracting {
            follow(pointer)
            return
        }
        if state == .retracting {
            // Reverse from the current shape and velocity; never restart the formation.
            hoverWork?.cancel(); armingID = nil
            present(change, origin: pointer)
            return
        }
        if armingID == change.id { return }
        hoverWork?.cancel()
        generation += 1
        let expected = generation
        armingID = change.id
        if state == .idle { state = .arming; armStart = CACurrentMediaTime() }
        activateGlow(change)
        // Already shown: morph at once. First touch: a short beat of intent (the words light
        // up) avoids flashes while the pointer only crosses the text.
        let delay = state.isPresented ? 0.0 : AnnotationTuning.hoverDelay
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected, self.armingID == change.id else { return }
            self.present(change, origin: self.pointer)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        startTicking()
    }

    private func follow(_ pointer: CGPoint) {
        closeWork?.cancel()
        guard state.isPresented, state != .retracting else { return }
        let now = CACurrentMediaTime()
        let elapsed = now - pointerTime
        if pointerTime > 0 && elapsed > 0.002 && elapsed < 0.2 {
            let raw = CGSize(width: (pointer.x - previousPointer.x) / elapsed, height: (pointer.y - previousPointer.y) / elapsed)
            pointerVelocity = CGSize(width: max(-1800, min(1800, pointerVelocity.width * 0.35 + raw.width * 0.65)),
                                     height: max(-1100, min(1100, pointerVelocity.height * 0.35 + raw.height * 0.65)))
        }
        pointerTime = now; previousPointer = pointer; self.pointer = pointer
        if reduced { pointerVelocity = .zero }
        origin = pointer
        retargetAroundOrigin()
        startTicking()
    }

    /// The body rests around the origin; it follows with a short, damped spring.
    private func retargetAroundOrigin() {
        let target = centredFrame(origin)
        switch state {
        case .forming: lens.retarget(target, lead: AnnotationTuning.cursorPopLead, trail: AnnotationTuning.cursorPopTrail)
        case .morphing: lens.retarget(target, lead: AnnotationTuning.morphGrow, trail: AnnotationTuning.morphShrink)
        default: lens.retarget(target, lead: AnnotationTuning.cursorLead, trail: AnnotationTuning.cursorTrail)
        }
        lens.textX.retarget(target.midX, AnnotationTuning.cursorText)
        lens.textY.retarget(target.midY, AnnotationTuning.cursorText)
        lens.tipX.retarget(origin.x, AnnotationTuning.cursorTip)
        lens.tipY.retarget(origin.y, AnnotationTuning.cursorTip)
    }

    /// Mouse movement anywhere in the app while the lens is shown.
    func trackPointer(_ point: CGPoint) {
        guard state.isPresented, state != .retracting else { return }
        pointer = point
        if pointerOnWords(point) { closeWork?.cancel() } else { scheduleClose() }
    }

    private func pointerOnWords(_ point: CGPoint) -> Bool {
        guard let change = activeChange, let textView else { return false }
        return textView.screenFragments(for: change).contains { $0.insetBy(dx: -6, dy: -5).contains(point) }
    }

    func scheduleClose() {
        guard state.isPresented, state != .retracting else { return }
        // A pending close keeps its deadline; continued movement outside must not postpone it.
        if let closeWork, !closeWork.isCancelled { return }
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWork = nil
            guard self.generation == expected else { return }
            // Only the real pointer position decides: back on the words keeps it open.
            guard !self.pointerOnWords(AnnotationPointer.location) else { return }
            self.close()
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + AnnotationTuning.leaveTolerance, execute: work)
    }

    // MARK: - Opening and morphing

    /// Keyboard focus: the focused words are the origin (the pointer, if it rests on them).
    func open(_ change: PromptChange) {
        guard let textView else { return }
        let fragments = textView.screenFragments(for: change)
        guard let first = fragments.first else { return }
        if fragments.contains(where: { $0.insetBy(dx: -6, dy: -5).contains(pointer) }) {
            present(change, origin: pointer)
        } else {
            present(change, origin: CGPoint(x: first.minX + min(first.width / 2, 80), y: first.midY), explicit: true)
        }
    }

    private func present(_ change: PromptChange, origin: CGPoint, explicit: Bool = false) {
        guard let textView, let parent = textView.window else { return }
        let fragments = textView.screenFragments(for: change)
        guard !fragments.isEmpty else { return }
        hoverWork?.cancel(); closeWork?.cancel(); armingID = nil
        if shouldUseInline {
            close()
            if explicit { inlineWasExplicit = true; inlineChangeID = change.id; onHelpUsed?() }
            return
        }
        self.origin = origin
        if activeChange?.id == change.id && state.isPresented && state != .retracting {
            retargetAroundOrigin()
            startTicking()
            return
        }
        let wasVisible = panel?.isVisible == true && state.isPresented
        let reversing = wasVisible && state == .retracting && activeChange?.id == change.id
        generation += 1
        previousPointer = pointer; pointerTime = 0; pointerVelocity = .zero
        inlineChangeID = nil
        activeChange = change
        activateGlow(change)
        onHelpUsed?()
        bubbleState.fontSize = min(20, max(16, textView.displayFontSize - 1))
        boundary = parent.frame.insetBy(dx: 12, dy: 12).intersection(parent.screen?.visibleFrame ?? parent.frame)
        // Measured once per content version at its final width; never during cursor motion.
        var host: NSView?
        if !reversing {
            let measured = measure(change, limit: min(360, max(240, parent.frame.width - 52)))
            guard measured.size.width <= boundary.width, measured.size.height <= boundary.height else {
                showInline(change, explicit: explicit)
                return
            }
            host = measured.host
            targetSize = measured.size
        }
        baseFrame = centredFrame(origin)
        let (targetPanel, targetCanvas) = ensurePanel(parent)
        targetPanel.appearance = parent.appearance
        // Every mouse event falls through to the words underneath; the system pointer stays visible.
        targetPanel.ignoresMouseEvents = true
        if let host {
            let crossfade = wasVisible && textAlpha > 0.05
            targetCanvas.install(host, size: targetSize, transitioning: crossfade)
            outgoingAlphaStart = crossfade ? textAlpha : 0
            outgoingAlpha = outgoingAlphaStart
            textAlpha = 0
        }
        if !wasVisible {
            beginFormation()
        } else if reversing {
            state = .forming
            lens.retarget(baseFrame, lead: AnnotationTuning.cursorPopLead, trail: AnnotationTuning.cursorPopTrail)
            lens.rim.velocity += 10
        } else {
            beginMorph()
        }
        lens.textX.retarget(baseFrame.midX, AnnotationTuning.cursorText)
        lens.textY.retarget(baseFrame.midY, AnnotationTuning.cursorText)
        lens.tipX.retarget(origin.x, AnnotationTuning.cursorTip)
        lens.tipY.retarget(origin.y, AnnotationTuning.cursorTip)
        lens.roundness.retarget(AnnotationTuning.restRoundness, AnnotationTiming(0.26, 0.8))
        lens.lift.retarget(1, AnnotationTiming(0.36, 0.86))
        lens.presence.retarget(1, AnnotationTiming(reduced ? 0.2 : 0.1, 0.99))
        transitionStart = CACurrentMediaTime()
        render(now: transitionStart)
        targetPanel.orderFront(nil)
        installEventMonitor()
        startTicking()
    }

    /// Kern → Körper: a small nucleus at the origin swells outward on every side at once.
    private func beginFormation() {
        let size = AnnotationTuning.nucleus
        let nucleus = CGRect(x: origin.x - size / 2, y: origin.y - size / 2, width: size, height: size)
        lens = AnnotationLensMotion(frame: reduced ? baseFrame : nucleus, tip: origin)
        lens.roundness.value = reduced ? AnnotationTuning.restRoundness : 2
        lens.textX = AnnotationSpring(baseFrame.midX); lens.textY = AnnotationSpring(baseFrame.midY)
        if !reduced { lens.rim.velocity = 14 }
        lastPanelOrigin = nil
        textAlpha = 0
        state = .forming
        lens.retarget(baseFrame, lead: AnnotationTuning.cursorPopLead, trail: AnnotationTuning.cursorPopTrail)
    }

    /// Same body, new volume: the edges retarget from their current motion.
    private func beginMorph() {
        state = .morphing
        lens.retarget(baseFrame, lead: AnnotationTuning.morphGrow, trail: AnnotationTuning.morphShrink)
        // Incoming text is prepared at its final place; its own travel stays small.
        let from = lens.textCenter
        let dx = baseFrame.midX - from.x, dy = baseFrame.midY - from.y
        let distance = max(1, hypot(dx, dy)), travel = min(8, distance)
        lens.textX = AnnotationSpring(baseFrame.midX - dx / distance * travel)
        lens.textY = AnnotationSpring(baseFrame.midY - dy / distance * travel)
        lens.rim.velocity += 12
        lens.conserve.retarget(0, AnnotationTiming(0.12, 0.99))
    }

    /// Bubble contents are laid out once per change, font size and width, ideally right when
    /// the suggestion appears (see `prepare`), so opening never waits for layout.
    private var measured: [String: (host: NSView, size: CGSize)] = [:]

    func prepare(_ changes: [PromptChange]) {
        guard let textView, let parent = textView.window, !shouldUseInline else { return }
        bubbleState.fontSize = min(20, max(16, textView.displayFontSize - 1))
        let limit = min(360, max(240, parent.frame.width - 52))
        for change in changes where change.kind != .deletion { _ = measure(change, limit: limit) }
    }

    private func measure(_ change: PromptChange, limit: CGFloat) -> (host: NSView, size: CGSize) {
        let key = "\(change.id)|\(change.title.hashValue)|\(change.explanation.hashValue)|\(Int(limit))|\(Int(bubbleState.fontSize))"
        if let cached = measured[key] { return cached }
        let length = change.title.count + change.explanation.count + (change.originalText?.count ?? 0)
        let width = AnnotationGeometry.readingWidth(textLength: length, limit: limit)
        let natural = NSHostingView(rootView: AnnotationBubbleContent(state: bubbleState, change: change, width: width))
        let header = AnnotationBubbleContent.headerHeight(change: change, width: width)
        let details = max(0, natural.fittingSize.height - 2 * AnnotationTuning.bubblePadding - AnnotationTuning.cursorRest - header)
        // Keep the quiet band at the body's geometric centre, even for a long explanation.
        let host = NSHostingView(rootView: AnnotationBubbleContent(state: bubbleState, change: change, width: width,
                                                                 topBalance: max(0, details - header),
                                                                 bottomBalance: max(0, header - details)))
        let fresh = (host: host as NSView, size: host.fittingSize)
        if measured.count > 60 { measured.removeAll() }
        measured[key] = fresh
        return fresh
    }

    private func ensurePanel(_ parent: NSWindow) -> (AnnotationPanel, AnnotationLensCanvas) {
        if let panel, let canvas { return (panel, canvas) }
        let created = AnnotationPanel(contentRect: baseFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = false
        created.hidesOnDeactivate = true
        created.level = .floating
        created.isMovableByWindowBackground = false
        created.ignoresMouseEvents = true
        let surface = AnnotationLensCanvas(frame: NSRect(origin: .zero, size: baseFrame.size))
        created.contentView = surface
        panel = created; canvas = surface
        parent.addChildWindow(created, ordered: .above)
        return (created, surface)
    }

    private func showInline(_ change: PromptChange, explicit: Bool) {
        close()
        finishClosing()
        inlineWasExplicit = explicit
        inlineChangeID = change.id
    }

    // MARK: - Closing

    func close() {
        hoverWork?.cancel(); closeWork?.cancel(); armingID = nil
        guard state != .retracting else { return }
        generation += 1
        guard let panel, panel.isVisible, state.isPresented else {
            state = .idle
            startTicking()
            return
        }
        state = .retracting
        transitionStart = CACurrentMediaTime()
        textAlphaAtClose = textAlpha
        // The body flows back into its origin from every side.
        let size = AnnotationTuning.nucleus - 2
        let nucleus = CGRect(x: origin.x - size / 2, y: origin.y - size / 2, width: size, height: size)
        let speed = AnnotationTuning.cursorRetract
        lens.left.retarget(nucleus.minX, speed)
        lens.right.retarget(nucleus.maxX, speed)
        lens.bottom.retarget(nucleus.minY, speed)
        lens.top.retarget(nucleus.maxY, speed)
        lens.roundness.retarget(2.2, AnnotationTiming(0.2, 0.9))
        lens.lift.retarget(0.1, AnnotationTiming(0.22, 0.95))
        lens.tipX.retarget(origin.x, AnnotationTuning.tip)
        lens.tipY.retarget(origin.y, AnnotationTuning.tip)
        lens.leanX.target = 0; lens.leanY.target = 0
        lens.conserve.retarget(0, AnnotationTiming(0.12, 0.99))
        if reduced { lens.presence.retarget(0, AnnotationTiming(0.16, 0.99)) }
        startTicking()
    }

    private func finishClosing() {
        panel?.orderOut(nil)
        canvas?.finishTransition()
        activeChange = nil; state = .idle
        textAlpha = 0; outgoingAlpha = 0
        lastPanelOrigin = nil
        removeMonitors()
        // The last light core is absorbed by the words.
        if !reduced { glow.coreRadius.velocity += 40 }
        startTicking()
    }

    func tearDown() {
        hoverWork?.cancel(); closeWork?.cancel(); generation += 1
        close(); finishClosing()
        stopTicking()
        glowChangeID = nil
        textView?.anchorGlow = nil
        if let panel { panel.parent?.removeChildWindow(panel) }
        panel = nil; canvas = nil
    }

    static func position(size: CGSize, anchor: CGRect, boundary: CGRect) -> CGRect {
        AnnotationGeometry.position(size: size, anchor: anchor, boundary: boundary)
    }

    // MARK: - Events

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.close(); self?.finishClosing() }
        })
        if let window = textView?.window {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                lifecycleObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.close(); self?.finishClosing() }
                })
            }
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .scrollWheel, .mouseMoved]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .mouseMoved: self.trackPointer(AnnotationPointer.location)
            case .keyDown where event.keyCode == 53: self.close(); return nil
            // A click acts on the text underneath (selection, an orange slot): the lens steps aside.
            case .leftMouseDown, .scrollWheel: self.close()
            default: break
            }
            return event
        }
    }

    private func removeMonitors() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers.removeAll()
    }

    // MARK: - Frame loop

    private func startTicking() {
        guard displayLink == nil, let textView else { return }
        lastFrameTime = CACurrentMediaTime()
        let link = textView.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopTicking() { displayLink?.invalidate(); displayLink = nil }

    @objc private func tick(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(0.05, max(0.001, now - lastFrameTime))
        lastFrameTime = now
        let reduced = self.reduced
        if state.isPresented {
            stepLens(now: now, dt: dt, reduced: reduced)
            render(now: now)
            if state == .retracting {
                let elapsed = now - transitionStart
                let body = lens.frame
                if (body.width < 40 && body.height < 32) || elapsed > 0.22 {
                    lens.presence.retarget(0, AnnotationTiming(0.09, 0.99))
                }
                if lens.presence.value < 0.03 || elapsed > 0.42 { finishClosing() }
            }
        }
        advanceIntro(now)
        stepGlow(now: now, dt: dt, reduced: reduced)
        pushGlow()
        if isAtRest { stopTicking() }
    }

    private func stepLens(now: TimeInterval, dt: Double, reduced: Bool) {
        let elapsed = now - transitionStart
        let decay = CGFloat(exp(-dt * 11))
        pointerVelocity.width *= decay; pointerVelocity.height *= decay
        ripplePhase += CGFloat(dt) * 8.5
        let active = state == .following || state == .forming || state == .morphing
        // Contour pull reacts more directly than position; light more directly still.
        let leanGain: CGFloat = 0.0035, leanLimit: CGFloat = 5
        lens.leanX.retarget(active ? max(-leanLimit, min(leanLimit, pointerVelocity.width * leanGain)) : 0, AnnotationTuning.lean)
        lens.leanY.retarget(active ? max(-leanLimit * 0.7, min(leanLimit * 0.7, pointerVelocity.height * leanGain * 0.75)) : 0, AnnotationTuning.lean)
        aimLight()
        if state != .retracting && state != .morphing {
            lens.conserve.retarget(state == .following ? 1 : 0, AnnotationTiming(0.3, 0.99))
        }
        lens.advance(dt, reduced: reduced)

        switch state {
        case .retracting:
            textAlpha = max(0, textAlphaAtClose * (1 - CGFloat(elapsed / AnnotationTuning.textFadeOut)))
        default:
            if reduced { textAlpha = max(textAlpha, min(1, lens.presence.value * 1.2)) }
            else if textAlpha < 1 && textHasRoom(elapsed: elapsed) { textAlpha = min(1, textAlpha + CGFloat(dt / 0.11)) }
        }
        outgoingAlpha = state == .morphing ? max(0, outgoingAlphaStart * (1 - CGFloat(elapsed / AnnotationTuning.textFadeOut))) : 0
        if outgoingAlpha == 0 { canvas?.finishTransition() }
        if state == .forming && elapsed > AnnotationTuning.formHandOff { state = .following }
        if state == .morphing && elapsed > AnnotationTuning.morphHandOff { state = .following }
    }

    /// The reading layer appears once the moving surface covers it with calm corners.
    private func textHasRoom(elapsed: TimeInterval) -> Bool {
        guard elapsed > 0.1, lens.roundness.value > 4.2 else { return false }
        let inner = CGRect(x: lens.textX.value - targetSize.width / 2, y: lens.textY.value - targetSize.height / 2,
                           width: targetSize.width, height: targetSize.height).insetBy(dx: 18, dy: 16)
        let overlap = inner.intersection(lens.frame)
        guard !overlap.isNull, inner.width > 0, inner.height > 0 else { return false }
        return overlap.width * overlap.height / (inner.width * inner.height) > 0.985
    }

    private func aimLight() {
        let body = lens.frame
        let rx = max(-1.3, min(1.3, (pointer.x - body.midX) / max(40, body.width / 2)))
        let ry = max(-1.3, min(1.3, (pointer.y - body.midY) / max(30, body.height / 2)))
        let vx = max(-0.3, min(0.3, pointerVelocity.width * 0.00025))
        let vy = max(-0.3, min(0.3, pointerVelocity.height * 0.00025))
        lens.glossX.retarget(-0.36 + rx * 0.26 + vx, AnnotationTuning.light)
        lens.glossY.retarget(0.46 + ry * 0.18 + vy, AnnotationTuning.light)
    }

    private var isAtRest: Bool {
        if intro != nil { return false }
        if state == .arming || state == .retracting || state == .forming || state == .morphing { return false }
        let lensRest = !state.isPresented || (lens.isSettled && textAlpha >= 1 && outgoingAlpha == 0
            && abs(pointerVelocity.width) < 1 && abs(pointerVelocity.height) < 1)
        return lensRest && (glowChangeID == nil || glow.isSettled)
    }

    private func render(now: TimeInterval) {
        guard let panel, let canvas else { return }
        renderedFrames += 1
        var body = lens.frame
        // Pure cursor deformation keeps roughly constant volume.
        let conserve = lens.conserve.value
        if conserve > 0.01 && body.width > 40 && body.height > 40 {
            let stretchX = body.width - targetSize.width, stretchY = body.height - targetSize.height
            let insetX = max(-8, min(8, stretchY * body.width / body.height * 0.5)) * conserve
            let insetY = max(-6, min(6, stretchX * body.height / body.width * 0.5)) * conserve
            body = body.insetBy(dx: insetX / 2, dy: insetY / 2)
        }
        // Soft limits against the window: the body gives way inward, no hard stops, no flips.
        let left = AnnotationGeometry.rubber(body.minX, min: boundary.minX, max: .infinity)
        let right = AnnotationGeometry.rubber(body.maxX, min: -.infinity, max: boundary.maxX)
        let bottom = AnnotationGeometry.rubber(body.minY, min: boundary.minY, max: .infinity)
        let top = AnnotationGeometry.rubber(body.maxY, min: -.infinity, max: boundary.maxY)
        body = CGRect(x: left, y: bottom, width: max(6, right - left), height: max(6, top - bottom))
        bodyScreenFrame = body

        let drawing = body.insetBy(dx: -28, dy: -28).integral
        if let last = lastPanelOrigin {
            canvas.pinOutgoing(panelMovedBy: CGVector(dx: drawing.minX - last.x, dy: drawing.minY - last.y))
        }
        lastPanelOrigin = drawing.origin
        panel.setFrame(drawing, display: false)
        canvas.frame = NSRect(origin: .zero, size: drawing.size)
        let panelOrigin = drawing.origin
        let localBody = body.offsetBy(dx: -panelOrigin.x, dy: -panelOrigin.y)
        let localRest = CGPoint(x: lens.tip.x - panelOrigin.x, y: lens.tip.y - panelOrigin.y)
        let reduced = self.reduced
        // No neck and no tail: the outline is one closed body around the origin.
        let shape = AnnotationLensShape.make(AnnotationLensForm(
            body: localBody, roundness: lens.roundness.value, tip: nil, neckWidth: 0,
            lean: CGVector(dx: lens.leanX.value, dy: lens.leanY.value),
            ripple: reduced ? 0 : 1.2 * lens.energy, ripplePhase: ripplePhase,
            weight: min(localBody.width, localBody.height) > 60 ? 3 : 0))
        let scale = panel.backingScaleFactor
        let rise = reduced ? 0 : (1 - textAlpha) * 2.5
        let textOrigin = CGPoint(x: ((lens.textX.value - targetSize.width / 2 - panelOrigin.x) * scale).rounded() / scale,
                                 y: ((lens.textY.value - targetSize.height / 2 - panelOrigin.y - rise) * scale).rounded() / scale)
        let tension = min(1, hypot(pointerVelocity.width, pointerVelocity.height) / 1600 + lens.energy * 0.6)
        // The soft light at the resting point sits under the cursor, inside the body.
        canvas.render(AnnotationLensFrame(
            shape: shape, body: localBody, tip: localBody.contains(localRest) ? localRest : nil,
            light: CGPoint(x: lens.glossX.value, y: lens.glossY.value),
            rim: max(0, lens.rim.value), lift: lens.lift.value, tension: reduced ? 0 : tension,
            motion: CGVector(dx: pointerVelocity.width, dy: pointerVelocity.height),
            incomingOrigin: textOrigin, incomingAlpha: textAlpha, outgoingAlpha: outgoingAlpha,
            cursorDot: false))
        panel.alphaValue = min(1, max(0, lens.presence.value))
    }

    /// The resting point (the cursor's hotspot) lies in the calm gap between heading and
    /// explanation, horizontally centred under the arrow. Near a window edge the body is
    /// pushed inward; the cursor stays where it is and remains inside the body.
    private func centredFrame(_ point: CGPoint) -> CGRect {
        AnnotationGeometry.centred(size: targetSize, around: point, boundary: boundary)
    }

    // MARK: - Light under the words

    /// Runs once per suggestion text: light travels along each blue change in turn.
    func introduce(_ ids: [String], prompt: String) {
        guard !reduced, !ids.isEmpty, state == .idle, textView != nil,
              !AnnotationPresentation.introducedPrompts.contains(prompt) else { return }
        AnnotationPresentation.introducedPrompts.insert(prompt)
        intro = (ids, CACurrentMediaTime() + 0.45)
        startTicking()
    }

    private func advanceIntro(_ now: TimeInterval) {
        guard let current = intro, let textView else { return }
        guard state == .idle else { intro = nil; return }
        let elapsed = now - current.start
        guard elapsed >= 0 else { return }
        let step = 0.42
        let index = Int(elapsed / step)
        guard index < current.ids.count else {
            intro = nil
            return
        }
        let id = current.ids[index]
        if glowChangeID != id {
            glowChangeID = id
            glowFragments = textView.fragmentRects(for: id)
            if let first = glowFragments.first { glow.lightX.value = first.minX - 30 }
        }
        let span = glowFragments.reduce(CGRect.null) { $0.union($1) }
        guard !span.isNull else { return }
        let progress = CGFloat((elapsed - Double(index) * step) / step)
        glow.lightX.target = span.minX - 30 + (span.width + 60) * min(1, progress * 1.15)
    }

    /// The touched words light up under the pointer while the lens arms and grows.
    private func activateGlow(_ change: PromptChange) {
        guard glowChangeID != change.id, let textView else { return }
        let local = textView.localPoint(fromScreen: pointer)
        if glowChangeID == nil { glow.coreRadius = AnnotationSpring(0, response: 0.22, damping: 0.55) }
        glowChangeID = change.id
        glowFragments = textView.fragmentRects(for: change.id)
        let home = AnnotationGeometry.nearestRect(glowFragments, to: local) ?? .zero
        glow.coreX.value = local.x; glow.coreX.target = local.x
        glow.coreY.value = home.midY; glow.coreY.target = home.midY
        glow.lightX.value = local.x; glow.lightX.target = local.x
        startTicking()
    }

    private func stepGlow(now: TimeInterval, dt: Double, reduced: Bool) {
        guard glowChangeID != nil else { return }
        let (intensity, radius, drift): (CGFloat, CGFloat, CGFloat)
        switch state {
        case .arming:
            // Touch: light gathers, the core contracts, then expansion begins.
            (intensity, radius, drift) = now - armStart < 0.075 ? (0.62, 7.5, 0) : (0.95, 4.4, 0)
        case .forming, .morphing: (intensity, radius, drift) = (0.95, 5.8, 1)
        case .following: (intensity, radius, drift) = (0.85, 4.2, 0.85)
        case .retracting: (intensity, radius, drift) = (1, 6.4, 1)
        case .idle: (intensity, radius, drift) = intro == nil ? (0, 0, 0) : (0.6, 0, 0)
        }
        glow.intensity.target = intensity
        glow.intensity.response = state == .idle ? 0.24 : 0.11
        glow.coreRadius.target = reduced ? 0 : radius
        glow.coreDrift.target = drift
        if let textView, !glowFragments.isEmpty, intro == nil, state != .idle {
            // The light core stays under the origin: where the lens grows from.
            let local = textView.localPoint(fromScreen: state.isPresented ? origin : pointer)
            glow.lightX.target = local.x
            glow.coreX.target = local.x
            glow.coreY.target = (AnnotationGeometry.nearestRect(glowFragments, to: local) ?? .zero).midY
        }
        glow.advance(dt, reduced: reduced)
    }

    private func pushGlow() {
        guard let textView, let id = glowChangeID else { return }
        if state == .idle && intro == nil && glow.intensity.value < 0.01 && abs(glow.coreRadius.value) < 0.3 {
            glowChangeID = nil
            textView.anchorGlow = nil
            return
        }
        textView.anchorGlow = AnnotationAnchorGlow(
            changeID: id, intensity: glow.intensity.value,
            coreX: glow.coreX.value, coreY: glow.coreY.value, coreRadius: glow.coreRadius.value,
            coreDrift: glow.coreDrift.value, lightX: glow.lightX.value, towardMaxY: true)
    }

    deinit {
        if let suspendObserver { NotificationCenter.default.removeObserver(suspendObserver) }
        displayLink?.invalidate()
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}

/// The lens panel never takes focus or clicks; it only shows.
final class AnnotationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
