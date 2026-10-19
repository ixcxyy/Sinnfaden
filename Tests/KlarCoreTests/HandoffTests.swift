import XCTest
@testable import KlarCore

final class HandoffTests: XCTestCase {
    func testPreparedURLPreservesExactPromptAndOnlySupportedParameter() throws {
        let text = "  Äpfel 👩🏽‍💻 é & # + % \"Zitat\"\nZweite Zeile\r\nDritte Zeile  "
        let url = try XCTUnwrap(ChatGPTHandoffPlan.preparedURL(prompt: text))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "codex"); XCTAssertEqual(parts.host, "threads"); XCTAssertEqual(parts.path, "/new")
        XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "prompt", value: text)])
        XCTAssertTrue(url.absoluteString.contains("%2B")); XCTAssertNil(parts.fragment)
    }
    func testUnverifiedDesktopAlwaysUsesPlainBrowserURL() {
        XCTAssertEqual(ChatGPTHandoffPlan.make(prompt: "privater Text", verifiedDesktopAvailable: false), .clipboardBrowser(URL(string: "https://chatgpt.com/")!, .desktopNotVerified))
    }
    func testLongUnicodePromptFallsBackWithoutPuttingTextInBrowserURL() {
        let text = String(repeating: "Ä & 👩🏽‍💻\n", count: 1_000)
        let plan = ChatGPTHandoffPlan.make(prompt: text, verifiedDesktopAvailable: true)
        XCTAssertEqual(plan, .clipboardBrowser(ChatGPTHandoffPlan.browserDestination, .promptTooLong))
    }
    func testVerifiedShortPromptCanUsePreparedDesktopURL() throws {
        let prompt = "Hilf mir, eine kurze E-Mail zu schreiben."
        XCTAssertEqual(ChatGPTHandoffPlan.make(prompt: prompt, verifiedDesktopAvailable: true), .preparedDesktop(try XCTUnwrap(ChatGPTHandoffPlan.preparedURL(prompt: prompt))))
    }
}
