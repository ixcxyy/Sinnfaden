import Foundation
import Network

final class LoopbackCallback: @unchecked Sendable {
    private let queue = DispatchQueue(label: "de.klar.oauth.callback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<[String: String], Error>?
    private var pendingResult: Result<[String: String], Error>?
    private var timeout: DispatchWorkItem?
    private(set) var redirectURI = ""
    private var finished = false
    private var readyContinuation: CheckedContinuation<Void, Error>?

    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters)
        listener = server
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, Error>) in
            readyContinuation = ready
            server.stateUpdateHandler = { [weak self] state in
                guard let self, let ready = self.readyContinuation else { return }
                switch state {
                case .ready:
                    guard let port = server.port else { return }
                    self.readyContinuation = nil; self.redirectURI = "http://127.0.0.1:\(port.rawValue)/auth/callback"; ready.resume()
                case .failed(let error): self.readyContinuation = nil; ready.resume(throwing: error)
                case .cancelled: self.readyContinuation = nil; ready.resume(throwing: CancellationError())
                default: break
                }
            }
            server.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
            server.start(queue: queue)
        }
    }
    func result() async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    if let result = self.pendingResult { continuation.resume(with: result); return }
                    self.continuation = continuation
                    let work = DispatchWorkItem { [weak self] in self?.finish(.failure(ProviderFailure(.authentication, "Die Anmeldung ist abgelaufen. Bitte starte sie erneut."))) }
                    self.timeout = work; self.queue.asyncAfter(deadline: .now() + 300, execute: work)
                }
            }
        } onCancel: { self.cancel() }
    }
    func cancel() { queue.async { self.finish(.failure(CancellationError())) } }
    private func receive(_ connection: NWConnection) {
        connection.start(queue: queue)
        read(connection, collected: Data())
        queue.asyncAfter(deadline: .now() + 5) { connection.cancel() }
    }
    private func read(_ connection: NWConnection, collected: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            let buffer = collected + (data ?? Data())
            guard buffer.count <= 16_384, error == nil else { connection.cancel(); return }
            guard let raw = String(data: buffer, encoding: .utf8), raw.contains("\r\n\r\n") else {
                if !complete { self.read(connection, collected: buffer) } else { connection.cancel() }
                return
            }
            let pieces = raw.components(separatedBy: "\r\n").first?.split(separator: " ").map(String.init) ?? []
            let expectedHost = URL(string: self.redirectURI)?.host.map { "\($0):\(self.listener?.port?.rawValue ?? 0)" } ?? ""
            let headers = raw.components(separatedBy: "\r\n")
            let host = headers.first { $0.lowercased().hasPrefix("host:") }?.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard pieces.count == 3, pieces[0] == "GET", host == expectedHost,
                  let url = URLComponents(string: "http://127.0.0.1" + pieces[1]), url.path == "/auth/callback" else {
                self.respond(connection, status: "404 Not Found", text: "Nicht gefunden."); return
            }
            let items = url.queryItems ?? []
            var values = [String: String]()
            for item in items {
                guard values[item.name] == nil, let value = item.value else {
                    self.respond(connection, status: "400 Bad Request", text: "Die Anmeldung konnte nicht verarbeitet werden.")
                    self.finish(.failure(ProviderFailure(.authentication, "Die Rückkehr aus dem Browser war ungültig."))); return
                }
                values[item.name] = value
            }
            self.respond(connection, status: "200 OK", text: "Du kannst dieses Fenster schließen und zu Sinnfaden zurückkehren. Die Anmeldung wird dort geprüft.")
            self.finish(.success(values))
        }
    }
    private func respond(_ connection: NWConnection, status: String, text: String) {
        let body = "<!doctype html><html lang=\"de\"><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><title>Sinnfaden</title><body style=\"font:20px system-ui;padding:8vw;line-height:1.5\"><h1>Sinnfaden</h1><p>\(text)</p></body></html>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nContent-Security-Policy: default-src 'none'; style-src 'unsafe-inline'\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
    private func finish(_ result: Result<[String: String], Error>) {
        guard !finished else { return }; finished = true
        timeout?.cancel(); listener?.cancel()
        if let continuation { self.continuation = nil; continuation.resume(with: result) } else { pendingResult = result }
    }
    deinit { listener?.cancel(); timeout?.cancel() }
}
