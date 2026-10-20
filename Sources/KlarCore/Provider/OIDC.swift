import Foundation
import Security

struct OIDCConfiguration: Decodable {
    let issuer: String
    let authorization_endpoint: URL
    let token_endpoint: URL
    let jwks_uri: URL
    let revocation_endpoint: URL?
    func validate() throws {
        guard issuer == "https://auth.openai.com",
              [authorization_endpoint, token_endpoint, jwks_uri].allSatisfy({ Self.trusted($0) }),
              revocation_endpoint.map(Self.trusted) ?? true else {
            throw ProviderFailure(.authentication, "Die Anmeldekonfiguration von OpenAI konnte nicht überprüft werden.")
        }
    }
    static func trusted(_ url: URL) -> Bool { url.scheme == "https" && url.host == "auth.openai.com" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) }
}

struct VerifiedIdentity {
    let subject: String
    let email: String?
    let name: String?
}

struct JWKSet: Decodable { let keys: [JWK] }
struct JWK: Decodable { let kty: String; let kid: String; let n: String?; let e: String?; let alg: String?; let use: String? }

struct IDTokenVerifier {
    static func verify(_ token: String, keys: JWKSet, issuer: String, audience: String, nonce: String?, now: Date = Date()) throws -> VerifiedIdentity {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, token.utf8.count <= 64_000,
              let headerData = Data(base64URL: parts[0]), let body = Data(base64URL: parts[1]), let signature = Data(base64URL: parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              header["alg"] as? String == "RS256", header["crit"] == nil,
              let kid = header["kid"] as? String,
              let jwk = keys.keys.first(where: { $0.kid == kid && $0.kty == "RSA" && ($0.alg == nil || $0.alg == "RS256") && ($0.use == nil || $0.use == "sig") }),
              let n = jwk.n.flatMap(Data.init(base64URL:)), let e = jwk.e.flatMap(Data.init(base64URL:)), n.count >= 256,
              let key = SecKeyCreateWithData(rsaDER(n: n, e: e) as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
              SecKeyVerifySignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, nil),
              let claims = try JSONSerialization.jsonObject(with: body) as? [String: Any] else { throw invalid }
        return try validateClaims(claims, issuer: issuer, audience: audience, nonce: nonce, now: now)
    }
    static func validateClaims(_ claims: [String: Any], issuer: String, audience: String, nonce: String?, now: Date) throws -> VerifiedIdentity {
        let audiences = (claims["aud"] as? [String]) ?? (claims["aud"] as? String).map { [$0] } ?? []
        let time = now.timeIntervalSince1970
        guard claims["iss"] as? String == issuer, audiences.contains(audience),
              let expiration = claims["exp"] as? Double, expiration > time - 5,
              let issued = claims["iat"] as? Double, issued <= time + 5, issued <= expiration,
              let subject = claims["sub"] as? String, !subject.isEmpty,
              (claims["nbf"] as? Double).map({ $0 <= time + 5 }) ?? true,
              nonce.map({ claims["nonce"] as? String == $0 }) ?? true else { throw invalid }
        if audiences.count > 1 || claims["azp"] != nil {
            guard claims["azp"] as? String == audience else { throw invalid }
        }
        return .init(subject: subject, email: claims["email"] as? String, name: claims["name"] as? String)
    }
    private static var invalid: ProviderFailure { .init(.authentication, "Die Identität konnte nicht sicher bestätigt werden. Bitte melde dich erneut an.") }
    private static func der(_ tag: UInt8, _ bytes: Data) -> Data {
        var length = bytes.count
        var size = Data()
        if length < 128 { size.append(UInt8(length)) }
        else {
            var values = [UInt8]()
            while length > 0 { values.insert(UInt8(length & 255), at: 0); length >>= 8 }
            size.append(0x80 | UInt8(values.count)); size.append(contentsOf: values)
        }
        return Data([tag]) + size + bytes
    }
    static func rsaDER(n: Data, e: Data) -> Data {
        func integer(_ data: Data) -> Data {
            var value = Array(data)
            while value.count > 1 && value.first == 0 { value.removeFirst() }
            if let first = value.first, first & 0x80 != 0 { value.insert(0, at: 0) }
            return der(0x02, Data(value))
        }
        return der(0x30, integer(n) + integer(e))
    }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct OpenAITransport {
    let session: URLSession
    init(session: URLSession) { self.session = session }
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    func json<T: Decodable>(_ type: T.Type, url: URL) async throws -> T {
        var request = URLRequest(url: url); request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await self.data(request)
        return try JSONDecoder().decode(type, from: data)
    }
    func data(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw ProviderFailure(.invalidResponse, "OpenAI hat eine unerwartete Antwort gesendet.") }
        // Enforce the bound while downloading, including responses with no Content-Length.
        // Waiting for EOF first lets a large or never-ending body bypass the memory limit.
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2_000_000 else { throw ProviderFailure(.invalidResponse, "OpenAI hat eine unerwartete Antwort gesendet.") }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard (200..<300).contains(http.statusCode) else { throw ProviderFailure.http(http.statusCode, body: data, requestID: http.value(forHTTPHeaderField: "x-request-id") ?? http.value(forHTTPHeaderField: "openai-request-id")) }
        return data
    }
    func configuration() async throws -> OIDCConfiguration {
        let value = try await json(OIDCConfiguration.self, url: URL(string: "https://auth.openai.com/.well-known/openid-configuration")!)
        try value.validate(); return value
    }
    func form(_ url: URL, fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let body = fields.sorted { $0.key < $1.key }.map { key, value in
            (key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&")
        request.httpBody = Data(body.utf8); return request
    }
}
