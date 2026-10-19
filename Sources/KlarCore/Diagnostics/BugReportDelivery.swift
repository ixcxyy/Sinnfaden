import Foundation

public struct BugReportDelivery {
    private let endpoint: URL
    private let session: URLSession
    public init(endpoint: URL) {
        self.endpoint = endpoint
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    init(endpoint: URL, session: URLSession) { self.endpoint = endpoint; self.session = session }

    public struct Failure: Error { public let retryAfter: TimeInterval }

    /// Only an explicit allowlist crosses the network. Never serialize the originating Error.
    static func payload(_ report: DiagnosticReport) throws -> Data {
        struct Payload: Encodable {
            let schemaVersion = 1
            let id: String
            let area: DiagnosticArea
            let category: DiagnosticCategory
            let httpStatus: Int?
            let version: String
            let build: String
        }
        return try JSONEncoder().encode(Payload(id: report.id.uuidString, area: report.area, category: report.category, httpStatus: report.httpStatus, version: report.version, build: report.build))
    }

    public func send(_ report: DiagnosticReport) async throws {
        guard MaintenanceConfiguration.validFeed(endpoint.absoluteString) != nil else { throw Failure(retryAfter: 86_400) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.payload(report)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure(retryAfter: 300) }
        guard (200..<300).contains(http.statusCode) else {
            let delay = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 300
            throw Failure(retryAfter: delay.isFinite ? delay : 300)
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            guard data.count <= 1_024 else { throw Failure(retryAfter: 300) }
        }
        try Task.checkCancellation()
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Bool], result["accepted"] == true else { throw Failure(retryAfter: 300) }
    }
}
