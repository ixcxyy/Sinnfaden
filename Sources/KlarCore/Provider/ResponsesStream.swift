import Foundation

public struct ResponsesStreamParser {
    public private(set) var text = ""
    public private(set) var completed = false
    private var dataLines = [String]()
    private var eventSize = 0
    private var totalSize = 0
    public init() {}
    public mutating func consume(line: String) throws {
        totalSize += line.utf8.count
        guard totalSize <= 2_000_000 else { throw ProviderFailure(.invalidResponse, "Die Antwort ist zu groß. Bitte grenze die Anfrage ein.") }
        if line.isEmpty {
            try flush(); return
        }
        if line.hasPrefix("data:") {
            var data = String(line.dropFirst(5)); if data.first == " " { data.removeFirst() }
            eventSize += data.utf8.count
            guard eventSize <= 512_000 else { throw ProviderFailure(.invalidResponse, "Die Antwort ist zu groß.") }
            dataLines.append(data)
        }
    }
    public mutating func finish() throws -> String {
        try flush()
        guard completed else { throw ProviderFailure(.interrupted, "Die Antwort wurde unterbrochen. Dein Entwurf bleibt erhalten; du kannst es erneut versuchen.") }
        guard !text.isEmpty else { throw ProviderFailure(.invalidResponse, "OpenAI hat keine Textantwort geliefert.") }
        return text
    }
    private mutating func flush() throws {
        guard !dataLines.isEmpty else { return }
        let payload = dataLines.joined(separator: "\n"); dataLines.removeAll(keepingCapacity: true); eventSize = 0
        if payload == "[DONE]" { return }
        guard let data = payload.data(using: .utf8), let event = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = event["type"] as? String else {
            throw ProviderFailure(.invalidResponse, "Das Antwortformat von OpenAI konnte nicht gelesen werden.")
        }
        if completed { return }
        switch type {
        case "response.output_text.delta":
            guard let delta = event["delta"] as? String else { throw ProviderFailure(.invalidResponse, "Ein Textteil der Antwort ist ungültig.") }
            text += delta
            guard text.utf8.count <= 256_000 else { throw ProviderFailure(.invalidResponse, "Die Antwort ist zu lang. Bitte grenze deine Anfrage ein.") }
        case "response.completed":
            guard let response = event["response"] as? [String: Any], response["status"] as? String == "completed" else { throw ProviderFailure(.invalidResponse, "Die Antwort wurde nicht eindeutig abgeschlossen.") }
            if let output = response["output"] as? [[String: Any]] {
                let content = output.flatMap { $0["content"] as? [[String: Any]] ?? [] }
                guard !content.contains(where: { $0["type"] as? String == "refusal" }) else {
                    throw ProviderFailure(.permission, "OpenAI konnte zu dieser Anfrage keinen Vorschlag liefern.")
                }
                // The terminal response is authoritative, even if a delta was missing.
                text = content.filter { $0["type"] as? String == "output_text" }.compactMap { $0["text"] as? String }.joined()
            }
            guard text.utf8.count <= 256_000 else { throw ProviderFailure(.invalidResponse, "Die Antwort ist zu lang.") }
            completed = true
        case "response.failed", "error":
            let response = event["response"] as? [String: Any]
            let error = (response?["error"] as? [String: Any]) ?? (event["error"] as? [String: Any]) ?? event
            let data = (try? JSONSerialization.data(withJSONObject: ["error": error])) ?? Data()
            let code = error["code"] as? String
            let mapped = ProviderFailure.http(code == "subscription_sharing_usage_limit_exceeded" ? 429 : 502, body: data, requestID: nil)
            throw ProviderFailure(mapped.kind, mapped.message, code: mapped.code, parameter: mapped.parameter, bodyShape: "stream-error")
        case "response.incomplete":
            throw ProviderFailure(.incomplete, "OpenAI konnte die Antwort nicht vollständig erzeugen. Der unvollständige Vorschlag wird nicht übernommen.")
        case "response.refusal.delta", "response.refusal.done":
            throw ProviderFailure(.permission, "OpenAI konnte zu dieser Anfrage keinen Vorschlag liefern. Du kannst sie bearbeiten und erneut versuchen.")
        default: break
        }
    }
}

extension OpenAITransport {
    static func acceptsStreamingMIME(_ value: String?) -> Bool {
        // The observed direct SIWC route may omit Content-Type. Success still requires
        // valid SSE events and response.completed; an explicit conflicting MIME is rejected.
        value == nil || value?.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "text/event-stream"
    }
    static func responseBody(model: String, instructions: String, input: String, textFormat: [String: Any]? = nil) throws -> Data {
        var body: [String: Any] = ["model": model, "instructions": instructions, "input": [["role": "user", "content": input]], "store": false, "stream": true]
        if let textFormat { body["text"] = ["format": textFormat] }
        return try JSONSerialization.data(withJSONObject: body)
    }
    func generate(token: String, model: String, instructions: String, input: String, textFormat: [String: Any]? = nil, onPartialText: (@Sendable (String) -> Void)? = nil, onProgress: @escaping @Sendable (Int) -> Void) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try Self.responseBody(model: model, instructions: instructions, input: input, textFormat: textFormat)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderFailure(.invalidResponse, "OpenAI hat keine gültige Antwort gesendet.") }
        guard (200..<300).contains(http.statusCode) else {
            var data = Data()
            for try await byte in bytes { data.append(byte); if data.count >= 32_768 { break } }
            throw ProviderFailure.http(http.statusCode, body: data, requestID: http.value(forHTTPHeaderField: "x-request-id") ?? http.value(forHTTPHeaderField: "openai-request-id"))
        }
        guard Self.acceptsStreamingMIME(http.value(forHTTPHeaderField: "Content-Type")) else {
            var sample = Data()
            for try await byte in bytes { sample.append(byte); if sample.count >= 64_000 { break } }
            let trimmed = String(decoding: sample.prefix(128), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let shape: String
            if trimmed.hasPrefix("event:") || trimmed.hasPrefix("data:") { shape = "sse-prefix" }
            else if let object = try? JSONSerialization.jsonObject(with: sample) as? [String: Any] {
                let known = Set(["error", "detail", "id", "object", "status", "output", "type", "response"])
                shape = "json:" + object.keys.filter { known.contains($0) }.sorted().joined(separator: ",")
            } else { shape = "other" }
            let mime = http.value(forHTTPHeaderField: "Content-Type")?.components(separatedBy: ";").first ?? "missing"
            throw ProviderFailure(.invalidResponse, "OpenAI hat keinen erwarteten Antwortstream geliefert.", status: http.statusCode, code: "unexpected_content_type", requestID: http.value(forHTTPHeaderField: "x-request-id"), bodyShape: mime + " · " + shape)
        }
        var parser = ResponsesStreamParser()
        var previousByteCount = 0
        var line = Data()
        // AsyncBytes.lines does not preserve every empty separator on all Foundation
        // versions. SSE framing requires those separators, so split raw UTF-8 bytes.
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte == 10 {
                if line.last == 13 { line.removeLast() }
                guard let decoded = String(data: line, encoding: .utf8) else { throw ProviderFailure(.invalidResponse, "Der Antwortstream enthält ungültigen Text.") }
                try parser.consume(line: decoded); line.removeAll(keepingCapacity: true)
                // A combining scalar can extend the last Character without changing
                // Character.count. Every new UTF-8 delta must still reach the preview.
                if parser.text.utf8.count != previousByteCount {
                    previousByteCount = parser.text.utf8.count
                    onProgress(parser.text.count); onPartialText?(parser.text)
                }
                if parser.completed { return try parser.finish() }
            } else {
                line.append(byte)
                guard line.count <= 512_000 else { throw ProviderFailure(.invalidResponse, "Ein Teil der Antwort ist zu groß.") }
            }
        }
        if !line.isEmpty {
            guard let decoded = String(data: line, encoding: .utf8) else { throw ProviderFailure(.invalidResponse, "Der Antwortstream enthält ungültigen Text.") }
            try parser.consume(line: decoded)
        }
        try Task.checkCancellation()
        return try parser.finish()
    }
}
