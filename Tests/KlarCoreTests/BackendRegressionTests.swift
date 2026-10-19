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

    func testFinalizedMessageSurvivesAnOmittedOrNullTerminalOutput() throws {
        for output in ["", ",\"output\":null"] {
            var parser = ResponsesStreamParser()
            try event(#"{"type":"response.output_text.delta","delta":"partial"}"#, into: &parser)
            try event(#"{"type":"response.output_item.done","output_index":0,"item":{"id":"msg_final","type":"message","status":"completed","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"complete final answer"}]}}"#, into: &parser)
            try event("{\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"\(output)}}", into: &parser)
            XCTAssertEqual(try parser.finish(), "complete final answer")
        }
    }

    func testCommentaryIsNotPartOfTheFinalTutorJSON() throws {
        var parser = ResponsesStreamParser()
        try event(#"{"type":"response.completed","response":{"status":"completed","output":[{"type":"message","phase":"commentary","content":[{"type":"output_text","text":"I am preparing a response."}]},{"type":"message","phase":"final_answer","content":[{"type":"output_text","text":"{\"answer\":\"final\"}"}]}]}}"#, into: &parser)
        XCTAssertEqual(try parser.finish(), #"{"answer":"final"}"#)
    }

    func testFinalizedRefusalIsNotLostWhenTerminalOutputIsNull() throws {
        var parser = ResponsesStreamParser()
        try event(#"{"type":"response.output_text.delta","delta":"partial"}"#, into: &parser)
        XCTAssertThrowsError(try {
            try event(#"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","status":"completed","content":[{"type":"refusal","refusal":"Cannot comply"}]}}"#, into: &parser)
            try event(#"{"type":"response.completed","response":{"status":"completed","output":null}}"#, into: &parser)
            _ = try parser.finish()
        }())
    }

    func testExplicitEmptyTerminalOutputDoesNotResurrectPartialText() throws {
        var parser = ResponsesStreamParser()
        try event(#"{"type":"response.output_text.delta","delta":"partial"}"#, into: &parser)
        try event(#"{"type":"response.completed","response":{"status":"completed","output":[]}}"#, into: &parser)
        XCTAssertThrowsError(try parser.finish())
    }

    func testMalformedTerminalOutputDoesNotFallBackToPartialText() throws {
        for output in ["false", "{}", "[42]"] {
            var parser = ResponsesStreamParser()
            try event(#"{"type":"response.output_text.delta","delta":"partial"}"#, into: &parser)
            XCTAssertThrowsError(try event("{\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":\(output)}}", into: &parser))
        }
    }

    private func event(_ json: String, into parser: inout ResponsesStreamParser) throws {
        try parser.consume(line: "data: " + json)
        try parser.consume(line: "")
    }
}
