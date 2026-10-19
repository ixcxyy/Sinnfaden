import AppKit
import SwiftUI

/// Where one typed word sits on screen, in SwiftUI's global (window, top-left) space.
struct CapturedWord: Identifiable, Equatable {
    let id: Int
    let text: String
    let frame: CGRect
}

/// Lets the coach page ask the editor where its words are, right before they fly off.
@MainActor
final class PromptEditorHandle {
    fileprivate weak var textView: PromptNSTextView?

    func capturedWords(limit: Int = 80) -> [CapturedWord] {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer,
              let root = textView.window?.contentView else { return [] }
        let string = textView.string as NSString
        var words: [CapturedWord] = []
        let visible = textView.visibleRect
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byWords) { substring, range, _, stop in
            guard let substring else { return }
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y
            guard rect.intersects(visible) else { return }
            var converted = root.convert(rect, from: textView)
            if !root.isFlipped { converted.origin.y = root.bounds.height - converted.maxY }
            words.append(CapturedWord(id: words.count, text: substring, frame: converted))
            if words.count >= limit { stop.pointee = true }
        }
        return words
    }
}

/// Plain native editor for the start page: no scroller gutter, a placeholder drawn exactly
/// where the first typed character will appear, and a height that follows the text.
struct PromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    @Binding var contentHeight: CGFloat
    var placeholder: String
    var fontSize: CGFloat
    var textHidden = false
    var handle: PromptEditorHandle?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .none

        let textView = PromptNSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.insertionPointColor = NSColor.sinnAnnotation
        textView.setAccessibilityLabel("Dein Prompt")
        textView.onFocusChange = { [weak coordinator = context.coordinator] isFocused in coordinator?.focusChanged(isFocused) }
        scroll.documentView = textView
        handle?.textView = textView
        apply(to: textView)
        textView.string = text
        context.coordinator.reportHeight(of: textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? PromptNSTextView else { return }
        handle?.textView = textView
        apply(to: textView)
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
            context.coordinator.reportHeight(of: textView)
        }
        if focused, textView.window != nil, textView.window?.firstResponder !== textView {
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
    }

    private func apply(to textView: PromptNSTextView) {
        let font = NSFont.systemFont(ofSize: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.sinnInk]
        if textView.font != font { textView.font = font }
        textView.typingAttributes = attributes
        textView.defaultParagraphStyle = paragraph
        if textView.placeholder != placeholder || textView.placeholderAttributes[.font] as? NSFont != font {
            textView.placeholder = placeholder
            textView.placeholderAttributes = [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.sinnMuted.withAlphaComponent(0.75)]
            textView.needsDisplay = true
        }
        // Words are hidden (not removed) while their flying copies leave the editor.
        textView.alphaValue = textHidden ? 0 : 1
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptEditor
        init(_ parent: PromptEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PromptNSTextView else { return }
            if parent.text != textView.string { parent.text = textView.string }
            textView.needsDisplay = true
            reportHeight(of: textView)
        }

        func focusChanged(_ isFocused: Bool) {
            if parent.focused != isFocused { parent.focused = isFocused }
        }

        func reportHeight(of textView: NSTextView) {
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
            layout.ensureLayout(for: container)
            let height = ceil(layout.usedRect(for: container).height)
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(self.parent.contentHeight - height) > 0.5 else { return }
                self.parent.contentHeight = height
            }
        }
    }
}

final class PromptNSTextView: NSTextView {
    var placeholder = ""
    var placeholderAttributes: [NSAttributedString.Key: Any] = [:]
    var onFocusChange: ((Bool) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        // Same origin as the first glyph: the caret blinks exactly at the placeholder's first letter.
        let origin = textContainerOrigin
        let width = bounds.width - origin.x * 2
        (placeholder as NSString).draw(with: CGRect(x: origin.x, y: origin.y, width: width, height: bounds.height),
                                       options: [.usesLineFragmentOrigin], attributes: placeholderAttributes)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }
}
