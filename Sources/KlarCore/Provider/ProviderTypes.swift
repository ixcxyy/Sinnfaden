import Foundation
import CryptoKit

public enum ProviderKind: String, Codable, CaseIterable, Sendable { case chatGPT, apiKey }
public enum ConnectionStatus: String, Sendable { case disconnected, connecting, connected, identityOnly, error }

public struct SavedAccount: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let clientID: String
    public let subject: String
    public let label: String
    public let provider: ProviderKind
}

public struct ProviderFailure: LocalizedError, Sendable {
    public enum Kind: String, Sendable { case authentication, permission, limit, unavailable, interrupted, incomplete, invalidResponse, cancelled, storage }
    public let kind: Kind
    public let message: String
    public let status: Int?
    public let code: String?
    public let requestID: String?
    public let parameter: String?
    public let bodyShape: String?
    public var errorDescription: String? { message }
    public init(_ kind: Kind, _ message: String, status: Int? = nil, code: String? = nil, requestID: String? = nil, parameter: String? = nil, bodyShape: String? = nil) {
        self.kind = kind; self.message = message; self.status = status; self.code = code; self.requestID = requestID; self.parameter = parameter; self.bodyShape = bodyShape
    }
    static func http(_ status: Int, body: Data, requestID: String?) -> ProviderFailure {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let err = object?["error"] as? [String: Any]
        let code = (err?["code"] as? String) ?? (object?["error"] as? String)
        let param = err?["param"] as? String
        let shape = err != nil ? "error-object" : (object?["detail"] != nil ? "detail" : "other")
        if status == 429 || code == "subscription_sharing_usage_limit_exceeded" {
            return .init(.limit, "Für diesen Zugang ist derzeit ein Nutzungslimit erreicht. Prüfe die Nutzung in den ChatGPT-Einstellungen oder versuche es später erneut.", status: status, code: code, requestID: requestID, parameter: param, bodyShape: shape)
        }
        if status == 401 || ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"].contains(code ?? "") {
            return .init(.authentication, "Die Anmeldung muss erneuert werden. Dein Entwurf bleibt erhalten.", status: status, code: code, requestID: requestID, parameter: param, bodyShape: shape)
        }
        if status == 403 || ["subscription_sharing_user_not_eligible", "subscription_sharing_route_not_supported", "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context", "subscription_sharing_unsupported_capability"].contains(code ?? "") {
            return .init(.permission, "OpenAI erlaubt diese Anfrage für den gewählten Zugang derzeit nicht. Prüfe Konto und Freigabe in den Einstellungen.", status: status, code: code, requestID: requestID, parameter: param, bodyShape: shape)
        }
        return .init(.unavailable, "Die Verbindung zu OpenAI konnte die Anfrage nicht abschließen. Dein Entwurf bleibt erhalten.", status: status, code: code, requestID: requestID, parameter: param, bodyShape: shape)
    }
}

struct OAuthTokens: Codable, Sendable {
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var scope: String
    var expiresAt: Date
    var canUsePlan: Bool { Set(scope.split(separator: " ").map(String.init)).contains("chatgpt.tokens.use.direct") }
}

public enum OAuthProof {
    public static func challenge(verifier: String) -> String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }
    static func random(_ size: Int = 32) throws -> String {
        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, size, $0.baseAddress!) }
        guard result == errSecSuccess else { throw ProviderFailure(.authentication, "Die Anmeldung konnte nicht sicher vorbereitet werden.") }
        return data.base64URL
    }
    static func identityID(subject: String, clientID: String) -> String {
        Data(SHA256.hash(data: Data("https://auth.openai.com\n\(clientID)\n\(subject)".utf8))).map { String(format: "%02x", $0) }.joined()
    }
}

import Security
extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) {
        let value = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: value + String(repeating: "=", count: (4 - value.count % 4) % 4))
    }
}
