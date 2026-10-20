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
        try event(#"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","status":"completed","content":[{"type":"output_text","text":"earlier finalized text"}]}}"#, into: &parser)
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

    func testFinalizedMessageSurvivesAnOmittedNullOrEmptyTerminalOutput() throws {
        for output in ["", ",\"output\":null", ",\"output\":[]"] {
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

    func testEmptyTerminalOutputUsesFinalizedItemsInOrderWithoutCommentaryOrDeltas() throws {
        var parser = ResponsesStreamParser()
        try event(#"{"type":"response.output_text.delta","delta":"partial commentary must not leak"}"#, into: &parser)
        try event(#"{"type":"response.output_item.done","output_index":2,"item":{"type":"message","status":"completed","phase":"final_answer","content":[{"type":"output_text","text":"world"}]}}"#, into: &parser)
        try event(#"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","status":"completed","phase":"commentary","content":[{"type":"output_text","text":"Working on it"}]}}"#, into: &parser)
        try event(#"{"type":"response.output_item.done","output_index":1,"item":{"type":"message","status":"completed","phase":"final_answer","content":[{"type":"output_text","text":"Hello "}]}}"#, into: &parser)
        try event(#"{"type":"response.completed","response":{"status":"completed","output":[]}}"#, into: &parser)
        XCTAssertEqual(try parser.finish(), "Hello world")
    }

    func testFinalizedItemsStillRequireSuccessfulCompletionAndAnActualAnswer() throws {
        for phase in ["commentary", "final_answer"] {
            var parser = ResponsesStreamParser()
            try event("{\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"type\":\"message\",\"status\":\"completed\",\"phase\":\"\(phase)\",\"content\":[{\"type\":\"output_text\",\"text\":\"finished item\"}]}}", into: &parser)
            XCTAssertThrowsError(try parser.finish()) { error in
                XCTAssertEqual((error as? ProviderFailure)?.kind, .interrupted)
            }
            if phase == "commentary" {
                try event(#"{"type":"response.completed","response":{"status":"completed","output":[]}}"#, into: &parser)
                XCTAssertThrowsError(try parser.finish()) { error in
                    XCTAssertEqual((error as? ProviderFailure)?.code, "empty_text_response")
                }
            } else {
                XCTAssertThrowsError(try event(#"{"type":"response.incomplete","response":{"status":"incomplete","output":[]}}"#, into: &parser)) { error in
                    XCTAssertEqual((error as? ProviderFailure)?.kind, .incomplete)
                }
            }
        }
    }

    func testMalformedTerminalOutputDoesNotFallBackToPartialText() throws {
        for output in ["false", "{}", "[42]"] {
            var parser = ResponsesStreamParser()
            try event(#"{"type":"response.output_text.delta","delta":"partial"}"#, into: &parser)
            try event(#"{"type":"response.output_item.done","output_index":0,"item":{"type":"message","status":"completed","content":[{"type":"output_text","text":"finalized text"}]}}"#, into: &parser)
            XCTAssertThrowsError(try event("{\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"output\":\(output)}}", into: &parser))
        }
    }

    func testMalformedFinalMessageCannotDisappearBesideAValidAnswer() throws {
        let valid: [String: Any] = ["type": "message", "content": [["type": "output_text", "text": "Only the first part"]]]
        let malformed: [[String: Any]] = [
            ["type": "message"],
            ["type": "message", "content": NSNull()],
            ["type": "message", "content": "Missing required text structure"],
            ["type": "message", "content": [true]],
            ["type": "message", "content": [["text": "Missing content type"]]],
            ["type": "message", "content": [["type": "output_text", "text": 42]]]
        ]
        for item in malformed {
            for finalizedSeparately in [false, true] {
                var parser = ResponsesStreamParser()
                let payload: [String: Any] = finalizedSeparately
                    ? ["type": "response.output_item.done", "output_index": 1, "item": item]
                    : ["type": "response.completed", "response": ["status": "completed", "output": [valid, item]]]
                let json = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
                try event(#"{"type":"response.output_text.delta","delta":"Only the first part"}"#, into: &parser)
                XCTAssertThrowsError(try event(json, into: &parser)) { error in
                    XCTAssertEqual((error as? ProviderFailure)?.kind, .invalidResponse)
                }
            }
        }
    }

    func testWhitespaceOnlyCompletedResponseIsNotAUsableAnswer() throws {
        for explicitOutput in [false, true] {
            var parser = ResponsesStreamParser()
            try event(#"{"type":"response.output_text.delta","delta":" \n\t "}"#, into: &parser)
            let response: [String: Any] = explicitOutput
                ? ["status": "completed", "output": [["type": "message", "content": [["type": "output_text", "text": " \n\t "]]]]]
                : ["status": "completed"]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: ["type": "response.completed", "response": response]), as: UTF8.self)
            try event(json, into: &parser)
            XCTAssertThrowsError(try parser.finish()) { error in
                XCTAssertEqual((error as? ProviderFailure)?.kind, .invalidResponse)
                XCTAssertEqual((error as? ProviderFailure)?.code, "empty_text_response")
            }
        }
    }

    func testNonAnswerItemsRemainSeparateAndFinalWhitespaceIsPreserved() throws {
        var parser = ResponsesStreamParser()
        try event(#"{"type":"response.completed","response":{"status":"completed","output":[{"type":"reasoning","summary":[]},{"type":"function_call","arguments":"{}"},{"type":"message","phase":"commentary","content":[]},{"type":"message","phase":"final_answer","content":[{"type":"output_text","text":" \nDie vollständige Antwort.\n "}]}]}}"#, into: &parser)
        XCTAssertEqual(try parser.finish(), " \nDie vollständige Antwort.\n ")
    }

    private func event(_ json: String, into parser: inout ResponsesStreamParser) throws {
        try parser.consume(line: "data: " + json)
        try parser.consume(line: "")
    }
}
