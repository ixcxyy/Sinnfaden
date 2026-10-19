import XCTest
@testable import KlarCore

final class BackendRegressionTests: XCTestCase {
    @MainActor func testRefreshCannotReuseStaleIdentityWhenAccessTokenIsMissing() {
        let previous = OAuthTokens(accessToken: "old", refreshToken: "refresh", idToken: "identity", scope: "chatgpt.tokens.use.direct", expiresAt: Date())
        for json in [#"{}"#, #"{"access_token":"","expires_in":3600}"#, #"{"access_token":"new","expires_in":true}"#] {
            XCTAssertThrowsError(try ConnectionManager.decodeTokens(Data(json.utf8), previous: previous), json)
        }
    }

    func testStreamingMIMERequiresAnExactMediaType() {
        XCTAssertTrue(OpenAITransport.acceptsStreamingMIME("Text/Event-Stream; charset=utf-8"))
        XCTAssertTrue(OpenAITransport.acceptsStreamingMIME(nil))
        XCTAssertFalse(OpenAITransport.acceptsStreamingMIME("application/x-text/event-stream-invalid"))
    }

    func testFinalResponseTextIsAuthoritative() throws {
        var parser = ResponsesStreamParser()
        try parser.consume(line: #"data: {"type":"response.output_text.delta","delta":"incomplete"}"#)
        try parser.consume(line: "")
        try parser.consume(line: #"data: {"type":"response.completed","response":{"status":"completed","output":[{"content":[{"type":"output_text","text":"complete answer"}]}]}}"#)
        try parser.consume(line: "")
        XCTAssertEqual(try parser.finish(), "complete answer")
    }

    func testCompletedRefusalNeverBecomesPartialSuccess() throws {
        var parser = ResponsesStreamParser()
        try parser.consume(line: #"data: {"type":"response.output_text.delta","delta":"partial"}"#)
        try parser.consume(line: "")
        try parser.consume(line: #"data: {"type":"response.completed","response":{"status":"completed","output":[{"content":[{"type":"refusal","refusal":"no"}]}]}}"#)
        XCTAssertThrowsError(try parser.consume(line: ""))
    }
}
