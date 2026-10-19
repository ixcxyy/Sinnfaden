import AppKit
import SwiftUI
import KlarCore

/// Isolated development preview for tuning the explanation lens.
/// Start with `KLAR --demo --bubble-lab`; add `--autoplay` for the scripted test sequence.
/// Not a product screen: nothing here talks to a provider.
struct AnnotationBubbleLab: View {
    static var isRequested: Bool { CommandLine.arguments.contains("--bubble-lab") }
    static var autoplay: Bool { CommandLine.arguments.contains("--autoplay") }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Erklärungslinse · Labor")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.sinnMuted)
            AnnotatedPromptView(response: AnnotationBubbleLab.sample, fontSize: 18)
                .frame(width: 620, alignment: .leading)
            Spacer(minLength: 0)
            AnnotatedPromptView(response: AnnotationBubbleLab.edgeSample, fontSize: 18)
                .frame(width: 620, alignment: .leading)
        }
        .padding(.horizontal, 64).padding(.vertical, 40)
        .frame(width: 900, height: 760, alignment: .topLeading)
        .background(Color.sinnWindow)
        .onAppear {
            DispatchQueue.main.async { AnnotationLabAutopilot.shared.prepareWindow() }
            if AnnotationBubbleLab.autoplay { AnnotationLabAutopilot.shared.start(after: 4) }
        }
    }

    static let sample = CoachResponse(
        status: .improved, coachMessage: "Labor",
        segments: [
            PromptSegment(id: "a0", text: "Schreib eine kurze, freundliche E-Mail an Frau Berger. "),
            PromptSegment(id: "a1", text: "Bitte sie um einen neuen Terminvorschlag"),
            PromptSegment(id: "a2", text: ", weil ich am 24. Oktober um 14 Uhr nicht kann. "),
            PromptSegment(id: "a3", text: "Erfinde keinen Grund für die Absage"),
            PromptSegment(id: "a4", text: " und verwende für meinen Namen den Platzhalter "),
            PromptSegment(id: "a5", text: "[Dein Name]"),
            PromptSegment(id: "a6", text: ". Halte den Ton warm, aber sachlich, und schlage zwei mögliche Zeitfenster in der kommenden Woche vor.")
        ],
        changes: [
            PromptChange(id: "goal", kind: .replacement, originalText: "möchte einen neuen Termin", targetSegmentIDs: ["a1"], category: "Ziel",
                         title: "Sag, was als Nächstes passieren soll",
                         explanation: "Damit ist klar, dass Frau Berger einen neuen Termin vorschlagen soll."),
            PromptChange(id: "unknowns", kind: .addition, targetSegmentIDs: ["a3"], category: "Kontext",
                         title: "Fehlendes bleibt erkennbar",
                         explanation: "Ohne diesen Satz ergänzt ein Modell oft einen plausiblen, aber erfundenen Absagegrund. Dein Text würde dann etwas behaupten, das du nie gesagt hast. Ein klarer Hinweis verhindert das, ohne die E-Mail länger oder förmlicher zu machen. Wenn du einen echten Grund nennen möchtest, schreib ihn einfach dazu."),
            PromptChange(id: "name", kind: .addition, targetSegmentIDs: ["a5"], category: "Kontext",
                         title: "Platzhalter statt Erfindung",
                         explanation: "Dein Name bleibt offen.")
        ])

    static let edgeSample = CoachResponse(
        status: .improved, coachMessage: "Rand",
        segments: [
            PromptSegment(id: "e0", text: "Nahe am Fensterrand: "),
            PromptSegment(id: "e1", text: "Antworte in höchstens fünf Sätzen"),
            PromptSegment(id: "e2", text: " und schließe mit einer offenen Frage.")
        ],
        changes: [
            PromptChange(id: "length", kind: .addition, targetSegmentIDs: ["e1"], category: "Format",
                         title: "Länge begrenzen",
                         explanation: "Eine klare Obergrenze hält die Antwort kurz. Die Linse öffnet sich hier nach oben, weil unten kein Platz ist.")
        ])
}

/// Scripted cursor for the lab. Drives the same entry points as real mouse
/// events and logs states and frame cadence so the run can be checked.
@MainActor
final class AnnotationLabAutopilot {
    static let shared = AnnotationLabAutopilot()
    private var cursor: NSPanel?
    private var timer: Timer?
    private var steps: [(duration: Double, target: () -> CGPoint?, action: (() -> Void)?)] = []
    private var stepIndex = 0
    private var stepStart: TimeInterval = 0
    private var from: CGPoint = .zero
    private var position: CGPoint = .zero
    private var lastState: AnnotationInteractionState = .idle
    private var runStart: TimeInterval = 0
    private var frameMark = 0
    private var frameMarkTime: TimeInterval = 0

    func prepareWindow() {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) }),
              let screen = window.screen ?? NSScreen.main else { return }
        let size = CGSize(width: 900, height: 760)
        let origin = CGPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - size.height - 40)
        window.setFrame(window.frameRect(forContentRect: CGRect(origin: origin, size: size)), display: true)
        let frame = window.convertToScreen(window.contentLayoutRect)
        let topLeftY = screen.frame.maxY - frame.maxY
        print("LAB window content (top-left origin): \(Int(frame.minX)),\(Int(topLeftY)),\(Int(frame.width)),\(Int(frame.height))")
    }

    private var presentation: AnnotationPresentation? {
        let all = textViews().compactMap(\.presentation)
        return all.first { $0.state.isPresented } ?? all.first
    }

    private func textViews() -> [AnnotationTextView] {
        guard let root = NSApp.windows.first(where: { !($0 is NSPanel) })?.contentView else { return [] }
        var found: [AnnotationTextView] = []
        func walk(_ view: NSView) {
            if let textView = view as? AnnotationTextView { found.append(textView) }
            view.subviews.forEach(walk)
        }
        walk(root)
        func top(_ view: NSView) -> CGFloat { view.window?.convertToScreen(view.convert(view.bounds, to: nil)).maxY ?? 0 }
        return found.sorted { top($0) > top($1) }
    }

    /// Screen point on a fragment of an annotation: `line` picks the wrapped fragment, `x` 0...1 along it.
    private func point(_ id: String, x: CGFloat, line: Int = 0, view index: Int = 0) -> () -> CGPoint? {
        { [weak self] in
            guard let views = self?.textViews(), views.indices.contains(index) else { return nil }
            let view = views[index]
            let fragments = view.fragmentRects(for: id).sorted { $0.minY < $1.minY }
            guard let window = view.window, !fragments.isEmpty else { return nil }
            let rect = fragments[min(line, fragments.count - 1)]
            let local = CGPoint(x: rect.minX + rect.width * x, y: rect.midY)
            return window.convertPoint(toScreen: view.convert(local, to: nil))
        }
    }

    private func offset(_ base: @escaping () -> CGPoint?, dx: CGFloat, dy: CGFloat) -> () -> CGPoint? {
        { base().map { CGPoint(x: $0.x + dx, y: $0.y + dy) } }
    }

    private func bubbleCenter() -> () -> CGPoint? {
        { [weak self] in
            guard let frame = self?.presentation?.bodyScreenFrame, frame.width > 40 else { return nil }
            return CGPoint(x: frame.midX + 20, y: frame.midY)
        }
    }

    func start(after delay: Double) {
        let outside = offset(point("goal", x: 0.2), dx: -30, dy: 70)
        steps = [
            (0.4, outside, nil),
            (1.1, point("goal", x: 0.25), nil),                       // 1 slow approach
            (1.1, point("goal", x: 0.25), nil),                       // 2 watch the formation
            (0.9, point("goal", x: 0.9), nil),                        // 3 follow right
            (1.0, point("goal", x: 0.1), nil),                        //   left
            (0.7, point("goal", x: 0.55), nil),                       //   back
            (0.18, point("goal", x: 0.95), nil),                      // 4 fast direction change
            (0.16, point("goal", x: 0.2), nil),
            (0.8, point("goal", x: 0.45), nil),
            (0.55, point("unknowns", x: 0.5), nil),                   // 5 longer explanation
            (1.3, point("unknowns", x: 0.6), nil),
            (0.45, point("name", x: 0.5), nil),                       // 6 very short explanation
            (1.2, point("name", x: 0.55), nil),
            (0.7, bubbleCenter(), nil),                               // 7 into the lens, pin, Escape
            (0.8, bubbleCenter(), { [weak self] in self?.presentation?.pinCurrent() }),
            (1.0, bubbleCenter(), { [weak self] in self?.presentation?.close() }),
            (0.6, point("goal", x: 0.6), nil),                        // 8 reopen, leave, re-enter mid-retract
            (1.0, point("goal", x: 0.6), nil),
            (0.12, offset(point("goal", x: 0.6), dx: 0, dy: 90), nil),
            (0.2, offset(point("goal", x: 0.6), dx: 0, dy: 90), nil),
            (0.08, point("goal", x: 0.6), nil),
            (1.0, point("goal", x: 0.62), nil),
            (0.7, point("goal", x: 0.8, line: 0), nil),               // 9 wrapped annotation: line 1 → line 2
            (0.6, point("goal", x: 0.3, line: 0), nil),
            (0.7, point("goal", x: 0.3, line: 1), nil),
            (1.0, point("goal", x: 0.8, line: 1), nil),
            (0.9, point("length", x: 0.5, view: 1), nil),             //   near the window edge
            (1.2, point("length", x: 0.9, view: 1), nil),
            (0.6, offset(point("length", x: 0.9, view: 1), dx: 220, dy: -60), nil),
            (1.2, offset(point("length", x: 0.9, view: 1), dx: 220, dy: -60), nil)
        ]
        // `--autoplay-from=N` replays the sequence from step N (e.g. 22 = wrapped phrase and window edge).
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--autoplay-from=") }),
           let first = Int(argument.dropFirst("--autoplay-from=".count)), steps.indices.contains(first) {
            steps.removeFirst(first)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.run() }
    }

    private func run() {
        guard let first = steps.first?.target() else { print("LAB no target"); return }
        position = first; from = first
        showCursor()
        runStart = CACurrentMediaTime()
        stepStart = runStart; stepIndex = 0
        print("LAB autoplay start")
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advance() {
        let now = CACurrentMediaTime()
        guard stepIndex < steps.count else {
            timer?.invalidate(); cursor?.orderOut(nil)
            print(String(format: "LAB done %.2fs", now - runStart))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NSApp.terminate(nil) }
            return
        }
        let step = steps[stepIndex]
        let t = min(1, (now - stepStart) / step.duration)
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        if let target = step.target() {
            position = CGPoint(x: from.x + (target.x - from.x) * eased, y: from.y + (target.y - from.y) * eased)
        }
        cursor?.setFrameOrigin(CGPoint(x: position.x - 4, y: position.y - 20))
        textViews().forEach { $0.simulatePointer(atScreen: position) }
        logState(now)
        if t >= 1 {
            step.action?()
            from = position
            stepIndex += 1
            stepStart = now
        }
    }

    private func logState(_ now: TimeInterval) {
        guard let presentation, presentation.state != lastState else { return }
        let frames = presentation.renderedFrames
        let rate = frameMarkTime > 0 && now > frameMarkTime ? Double(frames - frameMark) / (now - frameMarkTime) : 0
        print(String(format: "LAB %6.2fs %@ → %@ · body %@ · %.0f lens frames/s in previous state",
                     now - runStart, lastState.rawValue, presentation.state.rawValue,
                     NSStringFromRect(presentation.bodyScreenFrame.integral), rate))
        lastState = presentation.state
        frameMark = frames; frameMarkTime = now
    }

    private func showCursor() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 24, height: 24), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        let image = NSImageView(image: NSCursor.arrow.image)
        image.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        panel.contentView = image
        panel.orderFront(nil)
        cursor = panel
    }
}
