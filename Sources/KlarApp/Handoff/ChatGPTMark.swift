import SwiftUI
import AppKit

/// The genuine bundled service artwork is rendered in its supplied black or white
/// form. A text label is retained as an honest fallback if an asset is missing.
struct ChatGPTMark: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 20
    var body: some View {
        Group {
            if let image = artwork {
                // The supplied artwork carries a quarter of clear space on every side; `size` is the
                // visible blossom, the clear space comes from the surrounding button padding.
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: size * 2.01, height: size * 2.01)
                    .frame(width: size, height: size)
                    .clipped()
                    .accessibilityLabel("ChatGPT")
            } else {
                Text("ChatGPT").font(.system(size: min(size * 0.65, 13), weight: .medium))
            }
        }
    }
    private var artwork: NSImage? {
        let name = colorScheme == .dark ? "OAI_OpenAI-Blossom_White" : "OAI_OpenAI-Blossom_Black"
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
