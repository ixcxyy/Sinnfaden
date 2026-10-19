import XCTest
import Security
@testable import KlarCore

final class ProviderTests: XCTestCase {
    func testPKCEUsesRFC7636Vector() {
        XCTAssertEqual(OAuthProof.challenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    @MainActor func testCallbackRejectsStateConsentAndWrongClient() throws {
        XCTAssertThrowsError(try ConnectionManager.validateCallback(["state": "wrong", "code": "test", "client_id": "issued"], state: "expected", savedClientID: nil))
        XCTAssertThrowsError(try ConnectionManager.validateCallback(["state": "expected", "error": "access_denied"], state: "expected", savedClientID: nil))
        XCTAssertThrowsError(try ConnectionManager.validateCallback(["state": "expected", "code": "test", "client_id": "wrong"], state: "expected", savedClientID: "issued"))
        XCTAssertThrowsError(try ConnectionManager.validateCallback(["state": "expected", "code": "test", "client_id": "dynamic_agent_client"], state: "expected", savedClientID: nil))
        XCTAssertEqual(try ConnectionManager.validateCallback(["state": "expected", "code": "test"], state: "expected", savedClientID: "issued").clientID, "issued")
    }
    @MainActor func testIdentityOnlyAndRefreshScopeAreDistinct() throws {
        let initial = try ConnectionManager.decodeTokens(Data(#"{"id_token":"id","access_token":"access","expires_in":3600,"scope":"openid profile email"}"#.utf8), previous: nil)
        XCTAssertFalse(initial.canUsePlan)
        let plan = try ConnectionManager.decodeTokens(Data(#"{"id_token":"id","access_token":"access","expires_in":3600,"refresh_token":"old","scope":"openid chatgpt.tokens.use.direct"}"#.utf8), previous: nil)
        XCTAssertTrue(plan.canUsePlan)
        let refreshed = try ConnectionManager.decodeTokens(Data(#"{"access_token":"new","expires_in":3600,"refresh_token":"replacement"}"#.utf8), previous: plan)
        XCTAssertTrue(refreshed.canUsePlan); XCTAssertEqual(refreshed.refreshToken, "replacement")
        XCTAssertThrowsError(try ConnectionManager.decodeTokens(Data(#"{"access_token":"access"}"#.utf8), previous: nil))
    }
    func testResponseRequestContainsOnlySupportedContract() throws {
        let body = try OpenAITransport.responseBody(model: "catalog-entry", instructions: "Tutor", input: "Ändere 👩🏽‍💻 nicht.")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["model", "instructions", "input", "store", "stream"]))
        XCTAssertEqual(object["store"] as? Bool, false); XCTAssertEqual(object["stream"] as? Bool, true)
        XCTAssertNotNil(object["input"] as? [[String: String]])
    }
    func testStreamRequiresObservedCompleted() throws {
        var parser = ResponsesStreamParser()
        try event(#"{"type":"response.output_text.delta","delta":"Ä 👩🏽‍💻 é"}"#, into: &parser)
        XCTAssertThrowsError(try parser.finish())
        try event(#"{"type":"response.completed","response":{"status":"completed"}}"#, into: &parser)
        XCTAssertEqual(try parser.finish(), "Ä 👩🏽‍💻 é")
    }
    func testStreamFailureAfterPartialTextNeverSucceeds() throws {
        var parser = ResponsesStreamParser()
        try event(#"{"type":"response.output_text.delta","delta":"partial"}"#, into: &parser)
        XCTAssertThrowsError(try event(#"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"#, into: &parser)) { error in
            XCTAssertEqual((error as? ProviderFailure)?.kind, .limit)
            XCTAssertNil((error as? ProviderFailure)?.status)
        }
        XCTAssertFalse(parser.completed)
        XCTAssertThrowsError(try parser.finish())
    }
    func testIncompleteAndDoneAreNotCompletion() throws {
        var parser = ResponsesStreamParser()
        try parser.consume(line: "data: [DONE]"); try parser.consume(line: "")
        XCTAssertThrowsError(try parser.finish())
        XCTAssertThrowsError(try event(#"{"type":"response.incomplete","response":{"status":"incomplete"}}"#, into: &parser)) { error in XCTAssertEqual((error as? ProviderFailure)?.kind, .incomplete) }
    }
    func testIdentityValidationChecksIssuerAudienceNonceAndTime() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let claims: [String: Any] = ["iss": "https://auth.openai.com", "aud": "issued", "sub": "subject", "nonce": "nonce", "iat": 9_900.0, "exp": 10_100.0]
        XCTAssertEqual(try IDTokenVerifier.validateClaims(claims, issuer: "https://auth.openai.com", audience: "issued", nonce: "nonce", now: now).subject, "subject")
        for (key, value) in [("iss", "https://attacker.invalid"), ("aud", "other"), ("nonce", "other")] {
            var invalid = claims; invalid[key] = value
            XCTAssertThrowsError(try IDTokenVerifier.validateClaims(invalid, issuer: "https://auth.openai.com", audience: "issued", nonce: "nonce", now: now))
        }
        var expired = claims; expired["exp"] = 9_000.0
        XCTAssertThrowsError(try IDTokenVerifier.validateClaims(expired, issuer: "https://auth.openai.com", audience: "issued", nonce: "nonce", now: now))
        var future = claims; future["iat"] = 11_000.0
        XCTAssertThrowsError(try IDTokenVerifier.validateClaims(future, issuer: "https://auth.openai.com", audience: "issued", nonce: "nonce", now: now))
    }
    func testRSASignatureVerificationRejectsTampering() throws {
        let key = try XCTUnwrap(SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil))
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(key))
        let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, nil)) as Data
        var offset = 0
        func read() throws -> Data {
            guard offset + 2 <= der.count else { throw NSError(domain: "test", code: 1) }
            offset += 1
            var length = Int(der[offset]); offset += 1
            if length & 0x80 != 0 {
                let count = length & 0x7f; length = 0
                for _ in 0..<count { length = length << 8 | Int(der[offset]); offset += 1 }
            }
            let data = der.subdata(in: offset..<(offset + length)); offset += length; return data
        }
        // Skip the SEQUENCE header, then parse the RSA public modulus and exponent.
        offset = 2 + (der[1] & 0x80 != 0 ? Int(der[1] & 0x7f) : 0)
        let n = try read(), e = try read()
        let jwk = JWK(kty: "RSA", kid: "test", n: n.base64URL, e: e.base64URL, alg: "RS256", use: "sig")
        let now = Date()
        let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": "test"]).base64URL
        let payload = try JSONSerialization.data(withJSONObject: ["iss": "https://auth.openai.com", "aud": "issued", "sub": "subject", "nonce": "nonce", "iat": now.timeIntervalSince1970, "exp": now.addingTimeInterval(300).timeIntervalSince1970]).base64URL
        let input = header + "." + payload
        let signature = try XCTUnwrap(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(input.utf8) as CFData, nil)) as Data
        let token = input + "." + signature.base64URL
        XCTAssertEqual(try IDTokenVerifier.verify(token, keys: JWKSet(keys: [jwk]), issuer: "https://auth.openai.com", audience: "issued", nonce: "nonce").subject, "subject")
        var corrupted = signature; corrupted[0] ^= 1
        XCTAssertThrowsError(try IDTokenVerifier.verify(input + "." + corrupted.base64URL, keys: JWKSet(keys: [jwk]), issuer: "https://auth.openai.com", audience: "issued", nonce: "nonce"))
    }
    func testAccountsRemainSeparateAcrossRegistrations() {
        XCTAssertNotEqual(OAuthProof.identityID(subject: "same-user", clientID: "workspace-a"), OAuthProof.identityID(subject: "same-user", clientID: "workspace-b"))
    }
    func testStructuredErrorsPreserveCodeButNotPromptPayload() {
        let failure = ProviderFailure.http(403, body: Data(#"{"error":{"code":"subscription_sharing_user_not_eligible","message":"sensitive text","param":"model"}}"#.utf8), requestID: "request-id")
        XCTAssertEqual(failure.kind, .permission); XCTAssertEqual(failure.code, "subscription_sharing_user_not_eligible")
        XCTAssertEqual(failure.parameter, "model"); XCTAssertEqual(failure.requestID, "request-id")
        XCTAssertFalse(failure.message.contains("sensitive"))
    }
    func testLoopbackCallbackUsesExactLocalPathAndCompletes() async throws {
        let server = LoopbackCallback()
        try await server.start()
        XCTAssertTrue(server.redirectURI.hasPrefix("http://127.0.0.1:"))
        XCTAssertTrue(server.redirectURI.hasSuffix("/auth/callback"))
        let waiting = Task { try await server.result() }
        let url = try XCTUnwrap(URL(string: server.redirectURI + "?state=test-state&code=test-code&client_id=issued"))
        let (body, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertFalse(String(decoding: body, as: UTF8.self).contains("test-code"))
        let values = try await waiting.value
        XCTAssertEqual(values["state"], "test-state")
        XCTAssertEqual(values["client_id"], "issued")
    }
    func testLoopbackCancellationResolvesPendingAttempt() async throws {
        let server = LoopbackCallback()
        try await server.start()
        let waiting = Task { try await server.result() }
        server.cancel()
        do { _ = try await waiting.value; XCTFail("Cancelled callback should throw") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testMissingMIMEStillRequiresSSEAndExplicitConflictIsRejected() {
        XCTAssertTrue(OpenAITransport.acceptsStreamingMIME(nil))
        XCTAssertTrue(OpenAITransport.acceptsStreamingMIME("text/event-stream; charset=utf-8"))
        XCTAssertFalse(OpenAITransport.acceptsStreamingMIME("application/json"))
    }
    @MainActor func testCredentialFailuresRequireReconnectionButLimitsDoNotChangeAccountState() {
        XCTAssertEqual(ConnectionManager.stateAfterFailure(.init(.authentication, "expired"), current: .connected), .error)
        XCTAssertEqual(ConnectionManager.stateAfterFailure(.init(.permission, "scope", code: "missing_plan_scope"), current: .connected), .identityOnly)
        XCTAssertEqual(ConnectionManager.stateAfterFailure(.init(.permission, "unsupported", code: "subscription_sharing_unsupported_capability"), current: .connected), .connected)
        XCTAssertEqual(ConnectionManager.stateAfterFailure(.init(.limit, "limit"), current: .connected), .connected)
        XCTAssertEqual(ConnectionManager.stateAfterFailure(.init(.unavailable, "network"), current: .connected), .connected)
    }
    func testLogoutTombstonePreventsAutomaticRestoreButKeepsRegistrationForRetry() throws {
        let account = SavedAccount(id: "account", clientID: "issued", subject: "subject", label: "Test", provider: .chatGPT)
        var store = RegistrationStore(hostID: "urn:uuid:test", accounts: [account], selectedID: account.id)
        store.markSignedOut(account.id)
        let restored = try JSONDecoder().decode(RegistrationStore.self, from: JSONEncoder().encode(store))
        XCTAssertNil(restored.selectedID)
        XCTAssertEqual(restored.lastSignedOutID, account.id)
        XCTAssertEqual(restored.accounts.first?.clientID, "issued")
    }
    func testActualByteStreamFramingPreservesEmptyLinesAndMissingMIME() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SyntheticSSEProtocol.self]
        let transport = OpenAITransport(session: URLSession(configuration: configuration))
        let text = try await transport.generate(token: "synthetic-test-token", model: "synthetic-model", instructions: "test", input: "test", onProgress: { _ in })
        XCTAssertEqual(text, "Ä 👩🏽‍💻 é")
    }
    func testPartialTextRemainsAvailableWhenTransportFailsAfterDelta() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FailingSyntheticSSEProtocol.self]
        let transport = OpenAITransport(session: URLSession(configuration: configuration))
        let recorder = PartialTextRecorder()
        do {
            _ = try await transport.generate(token: "synthetic-test-token", model: "synthetic-failure", instructions: "test", input: "test", onPartialText: { recorder.record($0) }, onProgress: { _ in })
            XCTFail("A failed terminal event must not become success")
        } catch {
            XCTAssertEqual((error as? ProviderFailure)?.kind, .limit)
            XCTAssertEqual(recorder.last, "Ä 👩🏽‍💻 é")
        }
    }
    private func event(_ json: String, into parser: inout ResponsesStreamParser) throws { try parser.consume(line: "data: " + json); try parser.consume(line: "") }
}

private class SyntheticSSEProtocol: URLProtocol {
    var textDeltas: [String] { ["Ä 👩🏽‍💻 é"] }
    var terminalEvent: String { #"{"type":"response.completed","response":{"status":"completed"}}"# }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let deltaEvents = textDeltas.map { delta in
            let data = try! JSONSerialization.data(withJSONObject: ["type": "response.output_text.delta", "delta": delta])
            return "event: response.output_text.delta\r\ndata: \(String(decoding: data, as: UTF8.self))\r\n\r\n"
        }.joined()
        let payload = deltaEvents + "data: \(terminalEvent)\r\n\r\n"
        for byte in payload.utf8 { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class FailingSyntheticSSEProtocol: SyntheticSSEProtocol {
    override var textDeltas: [String] { ["Ä 👩🏽‍💻 e", "\u{0301}"] }
    override var terminalEvent: String { #"{"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}}"# }
}

private final class PartialTextRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    func record(_ value: String) { lock.lock(); text = value; lock.unlock() }
    var last: String { lock.lock(); defer { lock.unlock() }; return text }
}
