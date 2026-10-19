import AppKit
import SwiftUI
import KlarCore
import QuartzCore

/// Text stays native and selectable; only verified segments receive annotations.
struct AnnotatedPromptView: View {
    let response: CoachResponse
    var fontSize: CGFloat = 17
    var onHelpUsed: () -> Void = {}
    var onCompare: ((PromptChange) -> Void)? = nil
    @StateObject private var presentation = AnnotationPresentation()
    @State private var textHeight: CGFloat = 0
    @State private var showAll = false
    @FocusState private var focusedChangeID: String?
    @State private var skipFocusRevealID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleChanges: [PromptChange] {
        showAll ? response.changes : Array(response.changes.prefix(3))
    }

    private func openExplanation(_ change: PromptChange) {
        onHelpUsed()
        if presentation.shouldUseInline || change.targetSegmentIDs.isEmpty {
            presentation.close()
            presentation.inlineWasExplicit = true
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                presentation.inlineChangeID = presentation.inlineChangeID == change.id ? nil : change.id
            }
        } else {
            presentation.inlineChangeID = nil
            presentation.open(change, pin: true)
        }
    }

    private func moveFocus(from id: String, by offset: Int) -> KeyPress.Result {
        guard let index = visibleChanges.firstIndex(where: { $0.id == id }),
              visibleChanges.indices.contains(index + offset) else { return .ignored }
        focusedChangeID = visibleChanges[index + offset].id
        return .handled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            NativeAnnotatedText(response: response, changes: visibleChanges,
                                fontSize: fontSize, presentation: presentation,
                                onHeight: { measured in if abs(measured - textHeight) > 0.5 { textHeight = measured } })
                // The text reports its laid-out height; SwiftUI's own sizing pass cached stale
                // values and stacked the controls below on top of the words.
                .frame(height: max(fontSize * 2, textHeight))
                .accessibilityLabel("Vorschlag")
            if !response.changes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Warum diese Änderung?")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sinnMuted)
                    ForEach(visibleChanges, id: \.id) { change in
                        Button {
                            openExplanation(change)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Image(systemName: change.targetSegmentIDs.isEmpty ? "minus.circle" : "sparkle")
                                    .font(.system(size: 11))
                                Text(change.title).underline(color: Color.sinnAnnotation.opacity(0.6))
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right").font(.system(size: 10))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(true)
                        .focused($focusedChangeID, equals: change.id)
                        .onKeyPress(.space, phases: .down) { _ in openExplanation(change); return .handled }
                        .onKeyPress(.return, phases: .down) { _ in openExplanation(change); return .handled }
                        .onKeyPress(.downArrow) { moveFocus(from: change.id, by: 1) }
                        .onKeyPress(.upArrow) { moveFocus(from: change.id, by: -1) }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.sinnAnnotation)
                        .accessibilityLabel("Änderung erklären: \(change.title)")
                        .help("Erklärung an der Textstelle öffnen. Leertaste öffnet, Pfeiltasten wechseln zwischen Änderungen.")
                        if presentation.inlineChangeID == change.id {
                            AnnotationExplanation(change: change, pinned: true, close: {
                                presentation.inlineChangeID = nil
                                focusedChangeID = change.id
                            }, pin: {}, compare: onCompare.map { callback in { callback(change) } }, focusOnOpen: presentation.inlineWasExplicit)
                            .padding(18)
                            .background {
                                RoundedRectangle(cornerRadius: 20)
                                    .fill(Color.sinnAnnotationWash)
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.sinnAnnotation.opacity(0.25), lineWidth: 1)
                            }
                        }
                    }
                    if response.changes.count > 3 {
                        Button(showAll ? "Weniger Änderungen" : "Alle Änderungen (\(response.changes.count))") {
                            presentation.close()
                            presentation.inlineChangeID = nil
                            showAll.toggle()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.sinnMuted)
                        .padding(.top, 2)
                    }
                }
            }
        }
        .onAppear {
            let ids = visibleChanges.filter { !$0.targetSegmentIDs.isEmpty }.map(\.id)
            let prompt = response.prompt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { presentation.introduce(ids, prompt: prompt) }
            // Lay out every explanation now, while the page settles, so hovering opens instantly.
            let prepared = visibleChanges
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { presentation.prepare(prepared) }
            presentation.onHelpUsed = onHelpUsed
            presentation.onCompare = onCompare
            presentation.didClosePinned = { id in
                skipFocusRevealID = id
                focusedChangeID = id
            }
        }
        .onDisappear { presentation.tearDown() }
        .onChange(of: focusedChangeID) { _, id in
            defer { skipFocusRevealID = nil }
            guard let id, id != skipFocusRevealID,
                  let change = visibleChanges.first(where: { $0.id == id }) else { return }
            if presentation.shouldUseInline || change.targetSegmentIDs.isEmpty {
                presentation.inlineWasExplicit = false
                presentation.inlineChangeID = id
                onHelpUsed()
            } else {
                presentation.open(change, pin: false)
            }
        }
        .onChange(of: response) { _, _ in
            presentation.onHelpUsed = onHelpUsed
            presentation.onCompare = onCompare
            presentation.close()
            presentation.inlineChangeID = nil
            showAll = false
        }
    }
}

private struct NativeAnnotatedText: NSViewRepresentable {
    let response: CoachResponse
    let changes: [PromptChange]
    let fontSize: CGFloat
    let presentation: AnnotationPresentation
    let onHeight: (CGFloat) -> Void

    func makeNSView(context: Context) -> AnnotationTextView {
        let textView = AnnotationTextView(frame: .zero)
        textView.presentation = presentation
        presentation.textView = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        // SwiftUI owns the frame. A self-resizing text view fights animated layout
        // passes (endless relayout); the height comes from sizeThatFits only.
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width, .height]
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.delegate = textView
        return textView
    }

    func updateNSView(_ nsView: AnnotationTextView, context: Context) {
        nsView.onHeightChange = onHeight
        nsView.configure(response: response, changes: changes, fontSize: fontSize)
        nsView.reportHeight()
    }

    /// Width comes from SwiftUI, height from the text's own report (see `reportHeight`).
    /// Measuring here mutated the live container and left SwiftUI with stale heights.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AnnotationTextView, context: Context) -> CGSize? {
        CGSize(width: max(120, proposal.width ?? 560), height: proposal.height ?? nsView.reportedHeight)
    }
}

@MainActor
final class AnnotationTextView: NSTextView, NSTextViewDelegate {
    weak var presentation: AnnotationPresentation?
    private var annotations: [(change: PromptChange, ranges: [NSRange])] = []
    private var tracking: NSTrackingArea?
    private var hoveredID: String?
    private var glowFragments: [CGRect] = []
    private var simulatedInside = false
    /// Light under the active words, driven by the presentation's frame loop.
    var anchorGlow: AnnotationAnchorGlow? {
        didSet {
            guard anchorGlow != oldValue else { return }
            if !glowFragments.isEmpty { setNeedsDisplay(AnnotationAnchorGlowRenderer.dirtyRect(glowFragments)) }
            if oldValue?.changeID != anchorGlow?.changeID {
                glowFragments = anchorGlow.map { fragmentRects(for: $0.changeID) } ?? []
            }
            if !glowFragments.isEmpty { setNeedsDisplay(AnnotationAnchorGlowRenderer.dirtyRect(glowFragments)) }
        }
    }
    private var configuredResponse: CoachResponse?
    private var configuredChanges: [PromptChange] = []
    private(set) var displayFontSize: CGFloat = 17
    private var lineSpacing: CGFloat = 6

    func configure(response: CoachResponse, changes: [PromptChange], fontSize: CGFloat) {
        guard response != configuredResponse || changes != configuredChanges || fontSize != displayFontSize else { return }
        pendingSingleClick?.cancel()
        presentation?.close()
        anchorGlow = nil
        configuredResponse = response
        configuredChanges = changes
        displayFontSize = fontSize
        var segmentRanges: [String: NSRange] = [:]
        var location = 0
        for segment in response.segments {
            let length = (segment.text as NSString).length
            segmentRanges[segment.id] = NSRange(location: location, length: length)
            location += length
        }
        annotations = changes.map { change in
            (change, change.targetSegmentIDs.compactMap { segmentRanges[$0] }.filter { $0.length > 0 })
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = max(6, fontSize * 0.36)
        lineSpacing = style.lineSpacing
        style.paragraphSpacing = 10
        let attributed = NSMutableAttributedString(string: response.prompt, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.sinnInk,
            .paragraphStyle: style
        ])
        for annotation in annotations {
            for range in annotation.ranges where NSMaxRange(range) <= attributed.length {
                // A light dotted line instead of a solid underline: whole sentences stay readable.
                attributed.addAttributes([
                    .foregroundColor: NSColor.sinnAnnotation,
                    .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                    .underlineColor: NSColor.sinnAnnotation.withAlphaComponent(0.45),
                    .init("SinnfadenChangeID"): annotation.change.id
                ], range: range)
            }
        }
        // Open placeholders read as small fill-in slots, so the gaps are visible at a glance.
        if let slots = try? NSRegularExpression(pattern: "\\[[^\\[\\]\\n]{1,60}\\]") {
            for match in slots.matches(in: response.prompt, range: NSRange(location: 0, length: attributed.length)) {
                attributed.addAttributes([
                    .foregroundColor: NSColor(red: 0.72, green: 0.38, blue: 0.0, alpha: 1),
                    .backgroundColor: NSColor(red: 1.0, green: 0.93, blue: 0.80, alpha: 1),
                    .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold)
                ], range: match.range)
            }
        }
        linkTextAttributes = [.foregroundColor: NSColor.sinnAnnotation,
                              .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                              .underlineColor: NSColor.sinnAnnotation.withAlphaComponent(0.45)]
        textStorage?.setAttributedString(attributed)
        setAccessibilityLabel("Vorschlag. Unterstrichene blaue Stellen haben eine Erklärung. Die Erklärungen sind auch unter dem Text erreichbar.")
        invalidateIntrinsicContentSize()
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let found = annotation(at: convert(event.locationInWindow, from: nil))
        hoveredID = found?.id
        presentation?.hover(found, pointer: AnnotationPointer.location)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredID = nil
        presentation?.hover(nil)
        super.mouseExited(with: event)
    }

    private var pendingSingleClick: DispatchWorkItem?
    func cancelPendingClick() { pendingSingleClick?.cancel(); pendingSingleClick = nil }
    override func mouseDown(with event: NSEvent) {
        pendingSingleClick?.cancel()
        let start = NSEvent.mouseLocation
        let change = annotation(at: convert(event.locationInWindow, from: nil))
        // NSTextView owns its entire native selection/drag loop. There is no link interception.
        if event.clickCount > 1 { presentation?.close() }
        super.mouseDown(with: event)
        let end = NSEvent.mouseLocation
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard let change, event.clickCount == 1, distance < 4,
              selectedRange().length == 0, !event.modifierFlags.contains(.shift) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.window != nil, self.selectedRange().length == 0 else { return }
            self.presentation?.open(change, pin: true)
        }
        pendingSingleClick = work
        // Waiting for the system interval protects a subsequent double-click word selection.
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    func change(atScreen point: CGPoint) -> PromptChange? {
        guard let window else { return nil }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        guard visibleRect.contains(local) else { return nil }
        return annotation(at: local)
    }

    override func cancelOperation(_ sender: Any?) { presentation?.close() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { pendingSingleClick?.cancel(); presentation?.close() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 1
        if widthChanged { presentation?.close() }
        super.setFrameSize(newSize)
        if widthChanged, let anchorGlow { glowFragments = fragmentRects(for: anchorGlow.changeID); needsDisplay = true }
        if widthChanged { reportHeight() }
    }

    var onHeightChange: ((CGFloat) -> Void)?
    private(set) var reportedHeight: CGFloat = 40

    /// Lays the text out at the current width and tells SwiftUI the height it really needs.
    func reportHeight() {
        guard let layoutManager, let textContainer, frame.width > 1 else { return }
        if abs(textContainer.containerSize.width - frame.width) > 0.5 {
            textContainer.containerSize = NSSize(width: frame.width, height: .greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let height = ceil(layoutManager.usedRect(for: textContainer).height) + 12
        guard abs(height - reportedHeight) > 0.5 else { return }
        reportedHeight = height
        let report = onHeightChange
        DispatchQueue.main.async { report?(height) }
    }

    /// SwiftUI sizes the host; the text always fills it exactly. With width-only autoresizing
    /// in a non-flipped host, a taller host kept the old bottom margin and the words drifted
    /// upward over the controls above them.
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        guard let superview else { return super.resize(withOldSuperviewSize: oldSize) }
        if frame != superview.bounds { frame = superview.bounds }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let superview { frame = superview.bounds }
        watchHost()
    }

    /// SwiftUI can place the representable's host inside a graphics container of exactly the
    /// host's size but with a stale origin (seen when the card holds more views below the text):
    /// the words then sit above their slot and cover the controls there. The host belongs at
    /// the container's origin, so it is put back there whenever its frame changes.
    private var hostObserver: NSObjectProtocol?
    private func watchHost() {
        if let hostObserver { NotificationCenter.default.removeObserver(hostObserver) }
        hostObserver = nil
        guard let host = superview else { return }
        host.postsFrameChangedNotifications = true
        hostObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: host, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.realignHost() }
        }
        realignHost()
    }

    private func realignHost() {
        guard let host = superview, let container = host.superview,
              abs(container.bounds.width - host.frame.width) < 0.5, abs(container.bounds.height - host.frame.height) < 0.5,
              host.frame.origin != .zero else { return }
        host.setFrameOrigin(.zero)
    }

    override func layout() {
        super.layout()
        realignHost()
    }

    /// The light is painted behind the glyphs; letters keep their shape and contrast.
    override func draw(_ dirtyRect: NSRect) {
        if let anchorGlow, !glowFragments.isEmpty, let context = NSGraphicsContext.current?.cgContext {
            AnnotationAnchorGlowRenderer.draw(anchorGlow, fragments: glowFragments, in: context)
        }
        super.draw(dirtyRect)
    }

    /// Glyph-tight line fragments of one annotation in view coordinates
    /// (trailing spaces and the paragraph's line spacing excluded).
    func fragmentRects(for id: String) -> [CGRect] {
        guard let layoutManager, let textContainer,
              let annotation = annotations.first(where: { $0.change.id == id }) else { return [] }
        layoutManager.ensureLayout(for: textContainer)
        let text = string as NSString
        var rects: [CGRect] = []
        for range in annotation.ranges {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, container, lineGlyphs, _ in
                var part = NSIntersectionRange(lineGlyphs, glyphRange)
                while part.length > 0 {
                    let character = text.character(at: layoutManager.characterIndexForGlyph(at: NSMaxRange(part) - 1))
                    guard let scalar = UnicodeScalar(character), CharacterSet.whitespacesAndNewlines.contains(scalar) else { break }
                    part.length -= 1
                }
                guard part.length > 0 else { return }
                var rect = layoutManager.boundingRect(forGlyphRange: part, in: container)
                rect.origin.y = usedRect.minY
                rect.size.height = max(self.displayFontSize, usedRect.height - self.lineSpacing)
                rects.append(rect)
            }
        }
        let origin = textContainerOrigin
        return rects.map { $0.offsetBy(dx: origin.x, dy: origin.y) }
    }

    /// Visible fragments of one annotation in screen coordinates (y-up).
    func screenFragments(for change: PromptChange) -> [CGRect] {
        guard let window else { return [] }
        return fragmentRects(for: change.id).filter { $0.intersects(visibleRect) }
            .map { window.convertToScreen(convert($0, to: nil)) }
    }

    func localPoint(fromScreen point: CGPoint) -> CGPoint {
        guard let window else { return .zero }
        return convert(window.convertPoint(fromScreen: point), from: nil)
    }

    /// Bubble lab autopilot: behaves like a real mouse move to a screen point.
    func simulatePointer(atScreen point: CGPoint) {
        AnnotationPointer.scripted = point
        presentation?.trackPointer(point)
        let local = localPoint(fromScreen: point)
        let inside = visibleRect.contains(local)
        if inside { presentation?.hover(annotation(at: local), pointer: point) }
        else if simulatedInside { presentation?.hover(nil, pointer: point) }
        simulatedInside = inside
    }

    private func annotation(at point: NSPoint) -> PromptChange? {
        guard let layoutManager, let textContainer else { return nil }
        let textPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        guard layoutManager.usedRect(for: textContainer).contains(textPoint) else { return nil }
        for annotation in annotations {
            for range in annotation.ranges {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                var contains = false
                layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                    if rect.insetBy(dx: -2, dy: -3).contains(textPoint) { contains = true }
                }
                if contains { return annotation.change }
            }
        }
        return nil
    }
}

@MainActor
final class AnnotationBubbleState: ObservableObject {
    @Published var pinned = false
    @Published var fontSize: CGFloat = 16
}

struct AnnotationBubbleContent: View {
    @ObservedObject var state: AnnotationBubbleState
    let change: PromptChange
    let width: CGFloat
    let close: () -> Void
    let pin: () -> Void
    let compare: (() -> Void)?

    var body: some View {
        AnnotationExplanation(change: change, pinned: state.pinned, close: close, pin: pin, compare: compare, onBlue: true)
            .font(.system(size: state.fontSize))
            .padding(22)
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .onExitCommand(perform: close)
    }
}

private struct AnnotationExplanation: View {
    let change: PromptChange
    let pinned: Bool
    let close: () -> Void
    let pin: () -> Void
    var compare: (() -> Void)? = nil
    var focusOnOpen = true
    /// White type on the blue bubble; actions only once the bubble is pinned.
    var onBlue = false
    private var ink: Color { onBlue ? .white : .sinnAnnotation }
    /// The following bubble is read-only; buttons appear once it is pinned.
    private var showsActions: Bool { !onBlue || pinned }
    @FocusState private var closeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(onBlue ? "WARUM DIESE ÄNDERUNG?" : "Warum diese Änderung?")
                    .font(.system(size: onBlue ? 10 : 11, weight: onBlue ? .bold : .semibold))
                    .tracking(onBlue ? 1.2 : 0)
                    .foregroundStyle(ink.opacity(onBlue ? 0.75 : 1))
                Spacer(minLength: 4)
                if showsActions { Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(true)
                .focused($closeFocused)
                .onKeyPress(.space, phases: .down) { _ in close(); return .handled }
                .onKeyPress(.return, phases: .down) { _ in close(); return .handled }
                .accessibilityLabel("Erklärung schließen")
                .help("Schließen · Escape") }
            }
            Text(change.title)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(change.explanation)
                .foregroundStyle(ink)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let original = change.originalText, !original.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.targetSegmentIDs.isEmpty ? "Entfernte Passage" : "Vorher")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(ink)
                    Text(original)
                        .font(.system(size: 13))
                        .foregroundStyle(ink)
                        .lineLimit(4)
                        .textSelection(.enabled)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(onBlue ? Color.white.opacity(0.14) : Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
            }
            if showsActions, let ruleID = change.ruleID, let rule = RuleRegistry.lookup(ruleID) {
                Link("Mehr erfahren", destination: rule.sourceURL)
                    .font(.system(size: 12, weight: .medium))
                    .focusable(true)
                    .onKeyPress(.space, phases: .down) { _ in NSWorkspace.shared.open(rule.sourceURL); return .handled }
                    .onKeyPress(.return, phases: .down) { _ in NSWorkspace.shared.open(rule.sourceURL); return .handled }
                    .help("\(rule.summary)\n\(rule.evidenceType) · geprüft am \(rule.checkedAt)")
            }
            if showsActions, let compare {
                Button(action: compare) {
                    Label("Im Ergebnis ansehen", systemImage: "rectangle.split.2x1")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ink)
                .focusable(true)
                .onKeyPress(.space, phases: .down) { _ in compare(); return .handled }
            }
            if !pinned && onBlue {
                Label("Klicken zum Festhalten", systemImage: "cursorarrow.click")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.7))
            } else if !pinned {
                Button(action: pin) {
                    Label("Erklärung festhalten", systemImage: "pin")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(ink)
            }
        }
        .foregroundStyle(ink)
        .tint(ink)
        .onExitCommand(perform: close)
        .onAppear {
            if pinned && focusOnOpen { DispatchQueue.main.async { closeFocused = true } }
        }
        .onChange(of: pinned) { _, value in
            if value && focusOnOpen { closeFocused = true }
        }
    }
}
