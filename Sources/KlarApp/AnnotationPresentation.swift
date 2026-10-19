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

/// One controller for the explanation lens: hover, formation, cursor following,
/// content morphs, reading, pinning and the flow back into the words.
@MainActor
final class AnnotationPresentation: NSObject, ObservableObject {
    var onHelpUsed: (() -> Void)?
    var onCompare: ((PromptChange) -> Void)?
    var didClosePinned: ((String) -> Void)?
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
    private weak var savedResponder: NSResponder?
    private weak var savedWindow: NSWindow?
    private var armingID: String?
    private var generation = 0

    // Pointer and anchor. `anchor` spans every visible fragment of the phrase and
    // stays clear; `attach` is the fragment on the lens side where the neck lands.
    private var anchor: CGRect = .zero
    private var attach: CGRect = .zero
    private var pointer: CGPoint = .zero
    private var pointerOrigin: CGPoint = .zero
    private var previousPointer: CGPoint = .zero
    private var pointerTime: TimeInterval = 0
    private var pointerVelocity: CGSize = .zero

    // Target geometry versus visible body.
    private var baseFrame: CGRect = .zero
    private var boundary: CGRect = .zero
    private var targetSize: CGSize = .zero
    private var prefersBelow: Bool?
    private var lens = AnnotationLensMotion(frame: .zero, tip: .zero)
    private(set) var bodyScreenFrame: CGRect = .zero
    private var lastPanelOrigin: CGPoint?
    private var ripplePhase: CGFloat = 0

    // Content version and text-layer visibility.
    private var textAlpha: CGFloat = 0
    private var textAlphaAtClose: CGFloat = 0
    private var outgoingAlpha: CGFloat = 0
    private var outgoingAlphaStart: CGFloat = 0

    // Light under the words.
    private var glow = AnnotationAnchorMotion()
    private var glowChangeID: String?
    /// One-time light sweep across new annotations: orientation for where explanations live.
    private var intro: (ids: [String], start: TimeInterval)?
    private static var introducedPrompts = Set<String>()
    private var glowFragments: [CGRect] = []
    private var glowTowardMaxY = true

    /// Cursor mode: the pointer itself becomes the bubble and the bubble rides along with it.
    /// Anchored mode (pinned or opened from the keyboard) rests next to the words.
    private var cursorMode = false
    private var cursorHidden = false
    private var flipX = false
    private var flipY = false

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
                if self.state != .pinned { self.close() }
            }
        }
    }

    // MARK: - Pointer input

    func hover(_ change: PromptChange?, pointer screenPoint: CGPoint? = nil) {
        guard state != .pinned else { return }
        guard !Self.hoverSuspended || change == nil else { return }
        if change != nil { intro = nil }
        if change != nil && reduced == false && state == .idle { armStart = CACurrentMediaTime() }
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
            open(change, pin: false)
            return
        }
        if armingID == change.id { return }
        hoverWork?.cancel()
        generation += 1
        let expected = generation
        armingID = change.id
        if state == .idle { state = .arming; armStart = CACurrentMediaTime() }
        // Already shown: morph at once. First touch: a short beat avoids flashes while crossing text.
        let delay = state.isPresented ? 0.0 : 0.05
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == expected, self.armingID == change.id else { return }
            self.open(change, pin: false)
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        startTicking()
    }

    private func follow(_ pointer: CGPoint) {
        closeWork?.cancel()
        guard state != .pinned, state != .retracting, let change = activeChange, let textView else { return }
        let fragments = textView.screenFragments(for: change)
        guard !fragments.isEmpty else { return }
        let now = CACurrentMediaTime()
        let elapsed = now - pointerTime
        if pointerTime > 0 && elapsed > 0.002 && elapsed < 0.2 {
            let raw = CGSize(width: (pointer.x - previousPointer.x) / elapsed, height: (pointer.y - previousPointer.y) / elapsed)
            pointerVelocity = CGSize(width: max(-1800, min(1800, pointerVelocity.width * 0.35 + raw.width * 0.65)),
                                     height: max(-1100, min(1100, pointerVelocity.height * 0.35 + raw.height * 0.65)))
        }
        pointerTime = now; previousPointer = pointer; self.pointer = pointer
        if reduced { pointerVelocity = .zero }
        anchor = AnnotationGeometry.union(fragments)
        attach = AnnotationGeometry.facing(fragments, below: prefersBelow ?? true)
        if state == .reading { state = .following }
        retargetToCursor()
        startTicking()
    }

    private func retargetToCursor() {
        if cursorMode {
            lens.tipX.retarget(pointer.x, AnnotationTuning.cursorTip)
            lens.tipY.retarget(pointer.y, AnnotationTuning.cursorTip)
            let target = cursorFrame(pointer)
            let lead = state == .morphing ? AnnotationTuning.morphGrow : AnnotationTuning.cursorLead
            let trail = state == .morphing ? AnnotationTuning.morphShrink : AnnotationTuning.cursorTrail
            lens.retarget(target, lead: lead, trail: trail)
            lens.textX.retarget(target.midX, AnnotationTuning.cursorText)
            lens.textY.retarget(target.midY, AnnotationTuning.cursorText)
            return
        }
        // A resting card: it does not drift with the pointer once it has formed.
        let target = AnnotationGeometry.clamp(baseFrame, inside: boundary)
        switch state {
        case .forming: lens.retarget(target, lead: AnnotationTuning.formLead, trail: AnnotationTuning.formTrail)
        case .morphing: lens.retarget(target, lead: AnnotationTuning.morphGrow, trail: AnnotationTuning.morphShrink)
        default: lens.retarget(target, lead: AnnotationTuning.followLead, trail: AnnotationTuning.followTrail)
        }
        lens.textX.retarget(target.midX, AnnotationTuning.text)
        lens.textY.retarget(target.midY, AnnotationTuning.text)
    }

    func pointerEnteredBubble() {
        closeWork?.cancel()
        guard state == .forming || state == .following || state == .morphing else { return }
        state = .reading
        holdPosition()
    }

    /// The lens stops where it is and relaxes into a calm, reachable reading plane.
    private func holdPosition() {
        let center = CGPoint(x: lens.textX.value + lens.textX.velocity * 0.03, y: lens.textY.value + lens.textY.velocity * 0.03)
        let rest = AnnotationGeometry.clamp(CGRect(x: center.x - targetSize.width / 2, y: center.y - targetSize.height / 2,
                                                   width: targetSize.width, height: targetSize.height), inside: boundary)
        lens.retarget(rest, lead: AnnotationTuning.settle, trail: AnnotationTuning.settle)
        lens.textX.retarget(rest.midX, AnnotationTuning.text)
        lens.textY.retarget(rest.midY, AnnotationTuning.text)
        pointerVelocity = .zero
        startTicking()
    }

    /// Mouse movement anywhere in the app while the lens is shown.
    func trackPointer(_ point: CGPoint) {
        guard state.isPresented, state != .pinned, state != .retracting, !cursorMode else { return }
        if containsInBody(point) { pointerEnteredBubble() }
        else if AnnotationGeometry.transitionContains(point, anchor: anchor, body: bodyScreenFrame) { closeWork?.cancel() }
        else { scheduleClose() }
    }

    private func containsInBody(_ point: CGPoint) -> Bool {
        if let panel, let canvas, canvas.contains(CGPoint(x: point.x - panel.frame.minX, y: point.y - panel.frame.minY)) { return true }
        return bodyScreenFrame.insetBy(dx: 6, dy: 6).contains(point)
    }

    func scheduleClose() {
        guard state.isPresented, state != .pinned, state != .retracting else { return }
        // A pending close keeps its deadline; continued movement outside must not postpone it.
        if let closeWork, !closeWork.isCancelled { return }
        let expected = generation
        let following = cursorMode
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWork = nil
            guard self.generation == expected else { return }
            if !following {
                let point = AnnotationPointer.location
                guard !self.containsInBody(point),
                      !AnnotationGeometry.transitionContains(point, anchor: self.anchor, body: self.bodyScreenFrame) else { return }
            }
            self.close()
        }
        closeWork = work
        // A cursor bubble leaves almost at once; a resting one keeps a forgiving corridor.
        DispatchQueue.main.asyncAfter(deadline: .now() + (following ? 0.12 : AnnotationTuning.leaveTolerance), execute: work)
    }

    // MARK: - Opening, morphing, pinning

    func open(_ change: PromptChange, pin: Bool) {
        guard let textView, let parent = textView.window else { return }
        let fragments = textView.screenFragments(for: change)
        guard !fragments.isEmpty else { return }
        let fragment = AnnotationGeometry.union(fragments)
        hoverWork?.cancel(); closeWork?.cancel(); armingID = nil
        if shouldUseInline {
            close()
            if pin { inlineWasExplicit = true; inlineChangeID = change.id; onHelpUsed?() }
            return
        }
        if activeChange?.id == change.id && state.isPresented && state != .retracting {
            if pin { pinCurrent() }
            return
        }
        let wasVisible = panel?.isVisible == true && state.isPresented
        let reversing = wasVisible && state == .retracting && activeChange?.id == change.id
        generation += 1
        anchor = fragment
        pointerOrigin = pointer; previousPointer = pointer
        pointerTime = 0; pointerVelocity = .zero
        inlineChangeID = nil
        activeChange = change
        onHelpUsed?()
        // The bubble blooms out of the spot where the pointer touched the words, then rests
        // beside them as a calm card. It no longer rides on the cursor: a panel under the
        // pointer made the words report "mouse left" and closed the bubble whenever you held still.
        let pointerOnWords = fragments.contains { $0.insetBy(dx: -6, dy: -6).contains(pointer) }
        let bloomFromPointer = !pin && pointerOnWords && !wasVisible
        cursorMode = false
        if !wasVisible { flipX = false; flipY = false }
        bubbleState.pinned = pin
        bubbleState.fontSize = min(20, max(16, textView.displayFontSize - 1))
        boundary = parent.frame.insetBy(dx: 16, dy: 20).intersection(parent.screen?.visibleFrame ?? parent.frame)
        // Measured once per content version at its final width; never during cursor motion.
        var host: NSView?
        if !reversing {
            let measured = measure(change, limit: min(cursorMode ? 340 : 392, max(260, parent.frame.width - 52)))
            host = measured.host
            targetSize = measured.size
        }
        if cursorMode {
            baseFrame = cursorFrame(pointer)
        } else {
            guard let fitted = AnnotationGeometry.fittedPosition(size: targetSize, anchor: fragment, boundary: boundary,
                                                                preferBelow: wasVisible ? prefersBelow : nil) else {
                showInline(change, explicit: pin)
                return
            }
            baseFrame = fitted
        }
        prefersBelow = baseFrame.midY < fragment.midY
        attach = AnnotationGeometry.facing(fragments, below: prefersBelow ?? true)
        glowTowardMaxY = prefersBelow ?? true
        let (targetPanel, targetCanvas) = ensurePanel(parent)
        targetPanel.appearance = parent.appearance
        // The cursor bubble lets every mouse event fall through to the words underneath.
        targetPanel.ignoresMouseEvents = cursorMode
        setCursorHidden(cursorMode && !reduced)
        if let host {
            let crossfade = wasVisible && textAlpha > 0.05
            targetCanvas.install(host, size: targetSize, transitioning: crossfade)
            outgoingAlphaStart = crossfade ? textAlpha : 0
            outgoingAlpha = outgoingAlphaStart
            textAlpha = 0
        }
        let tip = bloomFromPointer ? pointer : AnnotationGeometry.connectionPoint(anchor: attach, pointer: pointer, body: baseFrame)
        if !wasVisible {
            beginFormation(tip: tip, fromPointer: bloomFromPointer)
            // The pointer turns into the bubble: it hides until the mouse moves again.
            if bloomFromPointer && !reduced { NSCursor.setHiddenUntilMouseMoves(true) }
        } else if reversing {
            state = .forming
            lens.retarget(baseFrame, lead: AnnotationTuning.formLead, trail: AnnotationTuning.formTrail)
            lens.rim.velocity += 10
        } else {
            beginMorph()
        }
        lens.textX.retarget(baseFrame.midX, cursorMode ? AnnotationTuning.cursorText : AnnotationTuning.text)
        lens.textY.retarget(baseFrame.midY, cursorMode ? AnnotationTuning.cursorText : AnnotationTuning.text)
        lens.tipX.retarget(tip.x, AnnotationTuning.tip)
        lens.tipY.retarget(tip.y, AnnotationTuning.tip)
        lens.roundness.retarget(AnnotationTuning.restRoundness, cursorMode ? AnnotationTiming(0.26, 0.8) : AnnotationTiming(0.42, 0.72))
        lens.neck.retarget(cursorMode ? AnnotationTuning.cursorNeck : AnnotationTuning.restNeck, AnnotationTiming(cursorMode ? 0.26 : 0.46, 0.84))
        lens.lift.retarget(1, AnnotationTiming(0.36, 0.86))
        lens.presence.retarget(1, AnnotationTiming(reduced ? 0.2 : 0.1, 0.99))
        transitionStart = CACurrentMediaTime()
        render(now: transitionStart)
        targetPanel.orderFront(nil)
        installEventMonitor()
        startTicking()
        if pin { pinCurrent() }
    }

    /// Kern → Hals → Körper: the body starts as a droplet just outside the words.
    private func beginFormation(tip: CGPoint, fromPointer: Bool = false) {
        let size = AnnotationTuning.nucleus
        let below = prefersBelow ?? true
        let nucleus = cursorMode || fromPointer
            ? CGRect(x: tip.x - size / 2, y: tip.y - size / 2, width: size, height: size)
            : CGRect(x: tip.x - size / 2, y: below ? tip.y - 2 - size : tip.y + 2, width: size, height: size)
        lens = AnnotationLensMotion(frame: reduced ? baseFrame : nucleus, tip: tip)
        lens.roundness.value = reduced ? AnnotationTuning.restRoundness : 2
        lens.neck.value = reduced ? AnnotationTuning.restNeck : 24
        lens.textX = AnnotationSpring(baseFrame.midX); lens.textY = AnnotationSpring(baseFrame.midY)
        if !reduced { lens.rim.velocity = cursorMode ? 14 : 26 }
        lastPanelOrigin = nil
        textAlpha = 0
        state = .forming
        if cursorMode {
            lens.retarget(baseFrame, lead: AnnotationTuning.cursorPop, trail: AnnotationTuning.cursorPop)
        } else {
            lens.retarget(baseFrame, lead: AnnotationTuning.formLead, trail: AnnotationTuning.formTrail)
        }
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
        let limit = min(392, max(260, parent.frame.width - 52))
        for change in changes where change.kind != .deletion { _ = measure(change, limit: limit) }
    }

    private func measure(_ change: PromptChange, limit: CGFloat) -> (host: NSView, size: CGSize) {
        let key = "\(change.id)|\(change.title.hashValue)|\(change.explanation.hashValue)|\(Int(limit))|\(Int(bubbleState.fontSize))"
        if let cached = measured[key] { return cached }
        let fresh = layout(change, limit: limit)
        if measured.count > 60 { measured.removeAll() }
        measured[key] = fresh
        return fresh
    }

    private func layout(_ change: PromptChange, limit: CGFloat) -> (host: NSView, size: CGSize) {
        func content(_ width: CGFloat) -> AnnotationBubbleContent {
            AnnotationBubbleContent(state: bubbleState, change: change, width: width,
                                    close: { [weak self] in self?.close() },
                                    pin: { [weak self] in self?.pinCurrent() },
                                    compare: onCompare == nil ? nil : { [weak self] in
                                        self?.close(); self?.onCompare?(change)
                                    })
        }
        let length = change.title.count + change.explanation.count + (change.originalText?.count ?? 0)
        let host = NSHostingView(rootView: content(AnnotationGeometry.readingWidth(textLength: length, limit: limit)))
        return (host, CGSize(width: host.fittingSize.width, height: max(110, host.fittingSize.height)))
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
        created.closeExplanation = { [weak self] in self?.close() }
        let surface = AnnotationLensCanvas(frame: NSRect(origin: .zero, size: baseFrame.size))
        surface.onPointerInside = { [weak self] inside in
            if inside { self?.pointerEnteredBubble() } else { self?.scheduleClose() }
        }
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

    func pinCurrent() {
        guard let panel else { return }
        if savedWindow == nil {
            savedWindow = textView?.window
            savedResponder = savedWindow?.firstResponder
        }
        let wasPinned = state == .pinned
        let settled = CACurrentMediaTime() - transitionStart > 0.28 || cursorMode
        let leavingCursor = cursorMode
        state = .pinned
        bubbleState.pinned = true
        if leavingCursor {
            // The bubble stops following and becomes a card you can click into.
            cursorMode = false
            setCursorHidden(false)
            panel.ignoresMouseEvents = false
            if let change = activeChange, let canvas, let parent = textView?.window {
                let measured = measure(change, limit: min(392, max(260, parent.frame.width - 52)))
                canvas.install(measured.host, size: measured.size, transitioning: true)
                outgoingAlphaStart = textAlpha; outgoingAlpha = textAlpha; textAlpha = 0
                targetSize = measured.size
                transitionStart = CACurrentMediaTime() - 0.12
            }
        }
        closeWork?.cancel(); hoverWork?.cancel(); armingID = nil
        if !wasPinned && settled {
            holdPosition()
            // Pinning is felt: a short local compression, then the surface sets.
            if !reduced { lens.compress(by: 120) }
        }
        pointerVelocity = .zero
        panel.makeKey()
        panel.selectNextKeyView(nil)
        startTicking()
    }

    // MARK: - Closing

    func close() {
        hoverWork?.cancel(); closeWork?.cancel(); armingID = nil
        textView?.cancelPendingClick()
        guard state != .retracting else { return }
        let closingID = state == .pinned ? activeChange?.id : nil
        generation += 1
        guard let panel, panel.isVisible, state.isPresented else {
            state = .idle
            startTicking()
            return
        }
        state = .retracting
        transitionStart = CACurrentMediaTime()
        textAlphaAtClose = textAlpha
        panel.ignoresMouseEvents = true
        let below = prefersBelow ?? (bodyScreenFrame.midY < anchor.midY)
        let tip = cursorMode ? lens.tip : AnnotationGeometry.connectionPoint(anchor: attach, pointer: pointer, body: bodyScreenFrame)
        let size = AnnotationTuning.nucleus - 2
        let nucleus = cursorMode
            ? CGRect(x: tip.x - size / 2, y: tip.y - size / 2, width: size, height: size)
            : CGRect(x: tip.x - size / 2, y: below ? tip.y - 2 - size : tip.y + 2, width: size, height: size)
        // The cursor returns the instant the bubble starts flowing back into it.
        setCursorHidden(false)
        // The far side pulls in first; the mass gathers toward the words.
        let far = cursorMode ? AnnotationTuning.cursorRetract : AnnotationTuning.retractFar
        lens.left.retarget(nucleus.minX, far)
        lens.right.retarget(nucleus.maxX, far)
        lens.bottom.retarget(nucleus.minY, below || cursorMode ? far : AnnotationTuning.retractNear)
        lens.top.retarget(nucleus.maxY, below && !cursorMode ? AnnotationTuning.retractNear : far)
        lens.roundness.retarget(2.2, AnnotationTiming(0.2, 0.9))
        lens.neck.retarget(22, AnnotationTiming(0.2, 0.9))
        lens.lift.retarget(0.1, AnnotationTiming(0.22, 0.95))
        lens.tipX.retarget(tip.x, AnnotationTuning.tip)
        lens.tipY.retarget(tip.y, AnnotationTuning.tip)
        lens.leanX.target = 0; lens.leanY.target = 0
        lens.conserve.retarget(0, AnnotationTiming(0.12, 0.99))
        if reduced { lens.presence.retarget(0, AnnotationTiming(0.16, 0.99)) }
        if let savedWindow {
            savedWindow.makeKey(); savedWindow.makeFirstResponder(savedResponder)
        }
        if let closingID { didClosePinned?(closingID) }
        savedWindow = nil; savedResponder = nil
        bubbleState.pinned = false
        startTicking()
    }

    private func finishClosing() {
        setCursorHidden(false)
        cursorMode = false
        panel?.orderOut(nil)
        canvas?.finishTransition()
        activeChange = nil; state = .idle; prefersBelow = nil
        textAlpha = 0; outgoingAlpha = 0
        lastPanelOrigin = nil
        removeMonitors()
        // The last light core is absorbed by the words.
        if !reduced { glow.coreRadius.velocity += 40 }
        startTicking()
    }

    func tearDown() {
        setCursorHidden(false)
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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .scrollWheel, .mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self else { return event }
            let point = AnnotationPointer.location
            if event.type == .mouseMoved { self.trackPointer(point) }
            if event.type == .keyDown && event.keyCode == 53 {
                self.close(); return nil
            }
            if event.type == .scrollWheel && event.window !== self.panel { self.close() }
            if event.type == .leftMouseDown && event.window !== self.panel {
                // Same-window clicks outside an actual annotation also dismiss a pinned bubble.
                if self.textView?.change(atScreen: point) == nil { self.close() }
            }
            if event.type == .leftMouseDragged && event.window !== self.panel { self.close() }
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
        let leanGain: CGFloat = cursorMode ? 0.0035 : 0.0055, leanLimit: CGFloat = cursorMode ? 5 : 7
        lens.leanX.retarget(active ? max(-leanLimit, min(leanLimit, pointerVelocity.width * leanGain)) : 0, AnnotationTuning.lean)
        lens.leanY.retarget(active ? max(-leanLimit * 0.7, min(leanLimit * 0.7, pointerVelocity.height * leanGain * 0.75)) : 0, AnnotationTuning.lean)
        aimLight()
        if state != .retracting {
            // The cursor bubble's tip is set only while the pointer is on the words (in follow),
            // so leaving never stretches a long tail after the cursor.
            if !cursorMode {
                let tip = AnnotationGeometry.connectionPoint(anchor: attach, pointer: pointer, body: lens.frame)
                lens.tipX.target = tip.x; lens.tipY.target = tip.y
            }
        }
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
        let calm: CGFloat = state == .pinned || state == .reading ? 0.5 : 1
        lens.glossX.retarget(-0.36 + rx * 0.26 * calm + vx, AnnotationTuning.light)
        lens.glossY.retarget(0.46 + ry * 0.18 * calm + vy, AnnotationTuning.light)
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
        // Soft limits against the window and the source words: no hard stops, no flips.
        let below = prefersBelow ?? (body.midY < anchor.midY)
        let left = AnnotationGeometry.rubber(body.minX, min: boundary.minX, max: .infinity)
        let right = AnnotationGeometry.rubber(body.maxX, min: -.infinity, max: boundary.maxX)
        var bottom = AnnotationGeometry.rubber(body.minY, min: boundary.minY, max: .infinity)
        var top = AnnotationGeometry.rubber(body.maxY, min: -.infinity, max: boundary.maxY)
        if !cursorMode {
            if below { top = AnnotationGeometry.rubber(top, min: -.infinity, max: anchor.minY - 8) }
            else { bottom = AnnotationGeometry.rubber(bottom, min: anchor.maxY + 8, max: .infinity) }
        }
        body = CGRect(x: left, y: bottom, width: max(6, right - left), height: max(6, top - bottom))
        bodyScreenFrame = body
        var tip = lens.tip
        if !cursorMode { tip.y = below ? min(tip.y, anchor.minY - 1.5) : max(tip.y, anchor.maxY + 1.5) }

        var drawing = body.union(CGRect(x: tip.x - 4, y: tip.y - 4, width: 8, height: 8)).insetBy(dx: -28, dy: -28)
        // A resting bubble never covers the source glyphs; the cursor bubble deliberately does
        // (its panel ignores mouse events, so selection still reaches the text).
        if cursorMode {
        } else if below { drawing.size.height = max(1, min(drawing.maxY, anchor.minY - 1) - drawing.minY) }
        else {
            let y = max(drawing.minY, anchor.maxY + 1)
            drawing.size.height = max(1, drawing.maxY - y); drawing.origin.y = y
        }
        drawing = drawing.integral
        if let last = lastPanelOrigin {
            canvas.pinOutgoing(panelMovedBy: CGVector(dx: drawing.minX - last.x, dy: drawing.minY - last.y))
        }
        lastPanelOrigin = drawing.origin
        panel.setFrame(drawing, display: false)
        canvas.frame = NSRect(origin: .zero, size: drawing.size)
        let origin = drawing.origin
        let localBody = body.offsetBy(dx: -origin.x, dy: -origin.y)
        let localTip = CGPoint(x: tip.x - origin.x, y: tip.y - origin.y)
        let reduced = self.reduced
        let shape = AnnotationLensShape.make(AnnotationLensForm(
            body: localBody, roundness: lens.roundness.value, tip: localTip, neckWidth: lens.neck.value,
            lean: CGVector(dx: lens.leanX.value, dy: lens.leanY.value),
            ripple: reduced || cursorMode ? 0 : 1.8 * lens.energy, ripplePhase: ripplePhase))
        let scale = panel.backingScaleFactor
        let rise = reduced ? 0 : (1 - textAlpha) * 5
        let textOrigin = CGPoint(x: ((lens.textX.value - targetSize.width / 2 - origin.x) * scale).rounded() / scale,
                                 y: ((lens.textY.value - targetSize.height / 2 - origin.y - rise) * scale).rounded() / scale)
        let tension = min(1, hypot(pointerVelocity.width, pointerVelocity.height) / 1600 + lens.energy * 0.6)
        canvas.render(AnnotationLensFrame(
            shape: shape, body: localBody, tip: localTip,
            light: CGPoint(x: lens.glossX.value, y: lens.glossY.value),
            rim: max(0, lens.rim.value), lift: lens.lift.value, tension: reduced ? 0 : tension,
            motion: CGVector(dx: pointerVelocity.width, dy: pointerVelocity.height),
            incomingOrigin: textOrigin, incomingAlpha: textAlpha, outgoingAlpha: outgoingAlpha,
            cursorDot: cursorMode && state != .retracting))
        panel.alphaValue = min(1, max(0, lens.presence.value))
    }

    // MARK: - Cursor bubble geometry

    /// Below and right of the pointer, so the pointer is the bubble's tip. Near an edge it
    /// flips once and keeps that side until there is clearly room again (no flicker).
    private func cursorFrame(_ point: CGPoint) -> CGRect {
        let width = targetSize.width, height = targetSize.height, gap: CGFloat = 18
        if flipX { if point.x + gap + width < boundary.maxX - 60 { flipX = false } }
        else if point.x + gap + width > boundary.maxX { flipX = true }
        if flipY { if point.y - gap - height > boundary.minY + 60 { flipY = false } }
        else if point.y - gap - height < boundary.minY { flipY = true }
        let frame = CGRect(x: flipX ? point.x - gap - width : point.x + gap,
                           y: flipY ? point.y + gap : point.y - gap - height,
                           width: width, height: height)
        return AnnotationGeometry.clamp(frame, inside: boundary)
    }

    private func setCursorHidden(_ hidden: Bool) {
        guard hidden != cursorHidden else { return }
        cursorHidden = hidden
        if hidden { NSCursor.hide() } else { NSCursor.unhide() }
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
        case .following, .reading, .pinned: (intensity, radius, drift) = (0.85, 4.2, 0.85)
        case .retracting: (intensity, radius, drift) = (1, 6.4, 1)
        case .idle: (intensity, radius, drift) = intro == nil ? (0, 0, 0) : (0.6, 0, 0)
        }
        glow.intensity.target = intensity
        glow.intensity.response = state == .idle ? 0.24 : 0.11
        glow.coreRadius.target = reduced ? 0 : radius
        glow.coreDrift.target = drift
        if let textView, !glowFragments.isEmpty {
            let local = textView.localPoint(fromScreen: pointer)
            if intro == nil { glow.lightX.target = local.x }
            // The core sits under the cursor while arming and travels to the neck once shown.
            if state.isPresented {
                let tip = textView.localPoint(fromScreen: lens.tip)
                let home = glowTowardMaxY ? glowFragments.max { $0.maxY < $1.maxY }! : glowFragments.min { $0.minY < $1.minY }!
                glow.coreX.target = min(home.maxX - 2, max(home.minX + 2, tip.x))
                glow.coreY.target = home.midY
            } else if state != .idle {
                glow.coreX.target = local.x
                glow.coreY.target = (AnnotationGeometry.nearestRect(glowFragments, to: local) ?? .zero).midY
            }
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
            coreDrift: glow.coreDrift.value, lightX: glow.lightX.value, towardMaxY: glowTowardMaxY)
    }

    deinit {
        if let suspendObserver { NotificationCenter.default.removeObserver(suspendObserver) }
        displayLink?.invalidate()
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }
}

final class AnnotationPanel: NSPanel {
    var closeExplanation: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { closeExplanation?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { closeExplanation?() } else { super.keyDown(with: event) }
    }
}
