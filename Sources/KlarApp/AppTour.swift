import AppKit
import SwiftUI
import KlarCore

/// Development-only walk through every screen at a fixed pace, so visuals and
/// transitions can be recorded and compared. Start with `KLAR --demo --ui-tour`.
/// It only changes navigation state; it never sends a request.
@MainActor
enum AppTour {
    static var isRequested: Bool { CommandLine.arguments.contains("--ui-tour") }

    /// `--click-probe x,y;x,y;…` sends real mouse-down/up events at window points
    /// (top-left origin, points) every 2.5 s and logs what changed. Demo mode only.
    static func startClickProbe(_ model: AppModel) {
        guard let index = CommandLine.arguments.firstIndex(of: "--click-probe"), CommandLine.arguments.indices.contains(index + 1) else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { placeWindow() }
        let points = CommandLine.arguments[index + 1].split(separator: ";").compactMap { pair -> CGPoint? in
            let parts = pair.split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
        }
        func state() -> String {
            "page=\(model.page) phase=\(model.phase.rawValue) settings=\(model.showSettings) dock=\(model.dockOpen) insight=\(model.insightMode) inputs=\(model.inputValues.sorted { $0.key < $1.key })"
        }
        for (step, point) in points.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4 + Double(step) * 2.5) {
                let before = state()
                clickAt(point)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    print("PROBE click \(Int(point.x)),\(Int(point.y))\n  before: \(before)\n  after:  \(state())")
                    if CommandLine.arguments.contains("--probe-layout"), let text = textViews().first {
                        var node: NSView? = text
                        var line = "  chain:"
                        while let current = node, current !== mainWindow?.contentView {
                            let f = current.convert(current.bounds, to: nil)
                            line += " \(String(describing: type(of: current)).prefix(24))[y=\(Int((mainWindow?.frame.height ?? 0) - f.maxY)) h=\(Int(f.height)) w=\(Int(f.width))]"
                            node = current.superview
                        }
                        print(line)
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5 + Double(points.count) * 2.5) { NSApp.terminate(nil) }
    }

    private static func clickAt(_ topLeft: CGPoint) {
        guard let window = mainWindow, let root = window.contentView else { return }
        let location = CGPoint(x: topLeft.x, y: window.frame.height - topLeft.y)
        let hit = root.hitTest(root.convert(location, from: nil))
        print("PROBE hitTest view: \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
        }
    }

    /// `--compose-probe`: clears the editor, types a sentence key by key into the real text
    /// view and sends it with ⌘↵, so the chip melt and the send flight can be recorded. Demo only.
    static func startComposeProbe() {
        guard CommandLine.arguments.contains("--compose-probe"), CommandLine.arguments.contains("--demo") else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { placeWindow() }
        func editor() -> NSTextView? { mainWindow?.firstResponder as? NSTextView }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            print("COMPOSE clear"); editor()?.selectAll(nil); editor()?.deleteBackward(nil)
        }
        let sentence = "Hilf mir bitte, eine kurze Rede für den 90. Geburtstag meiner Oma zu schreiben. Sie liebt Gartenarbeit und alte Schlager."
        for (index, character) in sentence.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0 + Double(index) * 0.035) { editor()?.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        }
        let sendAt = 6.0 + Double(sentence.count) * 0.035 + 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + sendAt) {
            print("COMPOSE send")
            guard let window = mainWindow, let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                                                                      windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) else { return }
            NSApp.sendEvent(event)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + sendAt + 8) { NSApp.terminate(nil) }
    }

    /// `--show-page recipes|recipe|followUp|laboratory|comparison|history` opens one page
    /// (or its first detail) for screenshots and quits after 25 s. Demo mode only.
    static func startShowPage(_ model: AppModel) {
        guard model.isDemo, let index = CommandLine.arguments.firstIndex(of: "--show-page"), CommandLine.arguments.indices.contains(index + 1) else { return }
        let target = CommandLine.arguments[index + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { placeWindow() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            switch target {
            case "recipes": model.page = .recipes
            case "recipe": model.learning.selectedRecipe = model.learning.state.recipes.first?.id; model.page = .recipes
            case "followUp": model.page = .followUp
            case "laboratory": model.page = .laboratory
            case "comparison": model.learning.selectedComparison = model.learning.state.comparisons.first?.id; model.page = .laboratory
            case "history": model.page = .history
            default: break
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { NSApp.terminate(nil) }
    }

    static func start(_ model: AppModel) {
        startClickProbe(model)
        startComposeProbe()
        startShowPage(model)
        guard isRequested else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { placeWindow() }
        let firstLesson = LessonCatalog.lessons.first?.id
        let steps: [(Double, String, () -> Void)] = [
            (2.8, "hero", { model.page = .coach }),
            (5.2, "send", { model.improve() }),
            (1.2, "fill-time", { model.inputValues["zeitraum"] = "nächste Woche vormittags" }),
            (0.9, "fill-time-2", { model.inputValues["zeitraum"] = "nächste Woche vormittags oder übernächste Woche" }),
            (1.6, "fill-name", { typeName("Alex", into: model) }),
            (1.0, "fill-tone", { model.inputValues["ton"] = "förmlich" }),
            (1.2, "lens-hover", { hoverFirstAnnotation(fraction: 0.2) }),
            (0.5, "lens-right", { hoverFirstAnnotation(fraction: 0.9, duration: 0.45) }),
            (0.4, "lens-left", { hoverFirstAnnotation(fraction: 0.1, duration: 0.35) }),
            (0.9, "lens-back", { hoverFirstAnnotation(fraction: 0.6, duration: 0.4) }),
            (1.2, "lens-leave", { leaveText() }),
            (2.4, "grid", { model.insightMode = "grid" }),
            (2.4, "steps", { model.insightMode = "steps" }),
            (2.2, "dial-open", { model.dockOpen = true }),
            (2.2, "lessons", { model.dockOpen = false; model.page = .lessons }),
            (2.0, "lesson-detail", { model.learning.selectedLesson = firstLesson }),
            (2.0, "recipes", { model.learning.selectedLesson = nil; model.page = .recipes }),
            (2.0, "follow-up", { model.page = .followUp }),
            (2.0, "comparison", { model.page = .laboratory }),
            (2.0, "history", { model.page = .history }),
            (2.4, "coach-return", { withAnimation(SinnMotion.selection) { model.page = .coach } }),  // stress: global transaction
            (1.0, "end", { NSApp.terminate(nil) })
        ]
        var delay = 4.0
        let origin = CACurrentMediaTime() + delay
        for (duration, name, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                print(String(format: "TOUR %6.2fs %@", CACurrentMediaTime() - origin, name))
                action()
            }
            delay += duration
        }
    }

    private static func typeName(_ name: String, into model: AppModel) {
        for (index, _) in name.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.18) {
                model.inputValues["name"] = String(name.prefix(index + 1))
            }
        }
    }

    private static var mainWindow: NSWindow? { NSApp.windows.first { $0.isVisible && !($0 is NSPanel) } }

    private static func placeWindow() {
        guard let window = mainWindow, let screen = window.screen ?? NSScreen.main else { return }
        let size = CGSize(width: 1280, height: 820)
        let origin = CGPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.maxY - size.height - 30)
        window.setFrame(CGRect(origin: origin, size: size), display: true)
        window.level = .floating  // tour only: keep the recorded window above other apps
        let frame = window.frame
        print("TOUR window (top-left origin): \(Int(frame.minX)),\(Int(screen.frame.maxY - frame.maxY)),\(Int(frame.width)),\(Int(frame.height))")
    }

    private static func textViews() -> [AnnotationTextView] {
        var found: [AnnotationTextView] = []
        func walk(_ view: NSView) {
            if let textView = view as? AnnotationTextView { found.append(textView) }
            view.subviews.forEach(walk)
        }
        if let root = mainWindow?.contentView { walk(root) }
        return found
    }

    private static func hoverFirstAnnotation(fraction: CGFloat, duration: Double = 0.6) {
        guard let view = textViews().first, let window = view.window,
              let change = DemoContent.response.changes.first,
              let rect = view.fragmentRects(for: change.id).first else { return }
        let start = AnnotationPointer.scripted ?? window.convertPoint(toScreen: view.convert(CGPoint(x: rect.minX, y: rect.maxY + 40), to: nil))
        let target = window.convertPoint(toScreen: view.convert(CGPoint(x: rect.minX + rect.width * fraction, y: rect.midY), to: nil))
        glide(view, from: start, to: target, duration: duration)
    }

    private static func leaveText() {
        guard let view = textViews().first, let current = AnnotationPointer.scripted else { return }
        glide(view, from: current, to: CGPoint(x: current.x, y: current.y + 140), duration: 0.4)
    }

    private static func glide(_ view: AnnotationTextView, from: CGPoint, to: CGPoint, duration: Double) {
        let frames = Int(duration * 120)
        for index in 0...frames {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) / 120) {
                let t = Double(index) / Double(frames)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                view.simulatePointer(atScreen: CGPoint(x: from.x + (to.x - from.x) * eased, y: from.y + (to.y - from.y) * eased))
            }
        }
    }
}
