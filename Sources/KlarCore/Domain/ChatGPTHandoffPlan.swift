import Foundation

/// Pure handoff planning. No clipboard, process launch, or network side effects.
public enum ChatGPTHandoffPlan: Equatable, Sendable {
    case preparedDesktop(URL)
    case clipboardBrowser(URL, FallbackReason)

    public enum FallbackReason: String, Equatable, Sendable {
        case desktopNotVerified, promptTooLong, encodingFailed
    }
    public static let browserDestination = URL(string: "https://chatgpt.com/")!
    /// A conservative application limit, not a claim about macOS or ChatGPT limits.
    public static let maximumPreparedURLBytes = 8_000

    public static func make(prompt: String, verifiedDesktopAvailable: Bool) -> Self {
        guard verifiedDesktopAvailable else { return .clipboardBrowser(browserDestination, .desktopNotVerified) }
        guard let url = preparedURL(prompt: prompt) else { return .clipboardBrowser(browserDestination, .encodingFailed) }
        guard url.absoluteString.utf8.count <= maximumPreparedURLBytes else { return .clipboardBrowser(browserDestination, .promptTooLong) }
        return .preparedDesktop(url)
    }

    public static func preparedURL(prompt: String) -> URL? {
        var components = URLComponents()
        components.scheme = "codex"; components.host = "threads"; components.path = "/new"
        components.queryItems = [URLQueryItem(name: "prompt", value: prompt)]
        // URLComponents permits literal '+' in queries. Percent-encode it so clients
        // using form-style query decoding preserve '+' instead of turning it into space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == prompt else { return nil }
        return url
    }
}
