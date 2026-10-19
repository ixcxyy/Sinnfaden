import XCTest
@testable import KlarCore

final class DiagnosticsTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private var failure: ProviderFailure { .init(.invalidResponse, "PRIVATE PROMPT sk-secret", status: 502, code: "private@example.com", requestID: "secret", parameter: "private", bodyShape: "private") }

    func testPayloadContainsOnlyAllowedTechnicalFields() throws {
        let report = try XCTUnwrap(DiagnosticReport(error: failure, area: .coach, version: "0.4.1", build: "5"))
        let data = try BugReportDelivery.payload(report)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["schemaVersion", "id", "area", "category", "httpStatus", "version", "build"]))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret"))
        XCTAssertEqual(object["category"] as? String, "invalidResponse")
    }

    func testExpectedCancellationAndLimitsAreNotBugReports() {
        for error: Error in [CancellationError(), URLError(.cancelled), ProviderFailure(.cancelled, "cancel"), ProviderFailure(.limit, "limit")] {
            XCTAssertNil(DiagnosticReport(error: error, area: .coach, version: "1", build: "1"))
        }
    }

    @MainActor func testConsentDeduplicationAndPendingDeliverySurviveRestart() throws {
        let root = try directory()
        let journal = DiagnosticJournal(directory: root, version: "0.4.1", build: "5")
        journal.record(failure, area: .coach)
        XCTAssertEqual(journal.reports.first?.delivery, .local)
        journal.automaticReportingEnabled = true
        journal.record(failure, area: .history)
        journal.record(failure, area: .history)
        XCTAssertEqual(journal.reports.count, 2)
        XCTAssertEqual(journal.reports.first?.occurrences, 2)
        XCTAssertEqual(journal.reports.first?.delivery, .pending)
        let reopened = DiagnosticJournal(directory: root, version: "0.4.1", build: "5")
        XCTAssertEqual(reopened.reports, journal.reports)
        reopened.automaticReportingEnabled = false
        XCTAssertTrue(reopened.reports.allSatisfy { $0.delivery == .local })
    }

    @MainActor func testRetryBackoffAndAcknowledgement() throws {
        let journal = DiagnosticJournal(directory: try directory(), version: "0.4.1", build: "5")
        journal.automaticReportingEnabled = true
        journal.record(failure, area: .coach)
        let id = try XCTUnwrap(journal.reports.first?.id)
        let now = Date(timeIntervalSince1970: 10_000)
        journal.deferDelivery(id, now: now, minimumDelay: 3600)
        XCTAssertEqual(journal.reports.first?.retryAfter, now.addingTimeInterval(3600))
        XCTAssertEqual(journal.reports.first?.delivery, .pending)
        journal.markSent(id)
        XCTAssertEqual(journal.reports.first?.delivery, .sent)
        XCTAssertNil(journal.reports.first?.retryAfter)
    }

    @MainActor func testEnablingReportingOnlyQueuesFreshOccurrencesOfAnExistingLocalError() throws {
        let root = try directory()
        let journal = DiagnosticJournal(directory: root, version: "0.4.1", build: "5")
        var queuedIDs: [UUID] = []
        journal.onNewReport = { if $0.delivery == .pending { queuedIDs.append($0.id) } }
        journal.record(failure, area: .coach)
        let local = try XCTUnwrap(journal.reports.first)

        journal.automaticReportingEnabled = true
        XCTAssertEqual(journal.reports, [local], "Consent alone must not queue old reports")
        XCTAssertTrue(queuedIDs.isEmpty)
        journal.record(failure, area: .coach)

        let fresh = try XCTUnwrap(journal.reports.first)
        XCTAssertNotEqual(fresh.id, local.id)
        XCTAssertEqual(fresh.delivery, .pending)
        XCTAssertEqual(journal.reports.last, local)
        XCTAssertEqual(queuedIDs, [fresh.id], "Fresh occurrence must wake the delivery loop")
        let reopened = DiagnosticJournal(directory: root, version: "0.4.1", build: "5")
        XCTAssertEqual(reopened.reports, journal.reports)
    }

    @MainActor func testFreshErrorAfterConsentReturnsDoesNotInheritCancelledRetry() throws {
        let journal = DiagnosticJournal(directory: try directory(), version: "0.4.1", build: "5")
        journal.automaticReportingEnabled = true
        journal.record(failure, area: .coach)
        let oldID = try XCTUnwrap(journal.reports.first?.id)
        journal.deferDelivery(oldID, minimumDelay: 86_400)
        journal.automaticReportingEnabled = false
        journal.automaticReportingEnabled = true
        XCTAssertEqual(journal.reports.first?.delivery, .local)
        journal.record(failure, area: .coach)
        journal.record(failure, area: .coach)

        let fresh = try XCTUnwrap(journal.reports.first)
        XCTAssertNotEqual(fresh.id, oldID)
        XCTAssertEqual(fresh.delivery, .pending)
        XCTAssertEqual(fresh.attempts, 0)
        XCTAssertNil(fresh.retryAfter)
        XCTAssertEqual(fresh.occurrences, 2)
        XCTAssertEqual(journal.reports.count, 2)
        journal.markSent(fresh.id)
        journal.record(failure, area: .coach)
        XCTAssertEqual(journal.reports.first?.delivery, .sent)
        XCTAssertEqual(journal.reports.count, 2, "Acknowledged errors still deduplicate for the day")
    }

    @MainActor func testJournalIsBoundedAndCorruptionIsNotOverwritten() throws {
        let root = try directory()
        let journal = DiagnosticJournal(directory: root, version: "0.4.1", build: "5")
        for code in 400...599 { journal.record(ProviderFailure(.unavailable, "private", status: code), area: .coach) }
        XCTAssertEqual(journal.reports.count, DiagnosticJournal.maximumReports)
        let url = root.appendingPathComponent("reports-v1.json")
        let corrupt = Data("bad data".utf8); try corrupt.write(to: url)
        let reopened = DiagnosticJournal(directory: root, version: "0.4.1", build: "5")
        reopened.record(failure, area: .coach)
        XCTAssertNotNil(reopened.storageError)
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        reopened.clear()
        XCTAssertTrue(reopened.reports.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testConfigurationRequiresHTTPSAndARealEd25519Key() {
        for url in ["http://updates.example/appcast.xml", "https://user:password@updates.example/a", "file:///tmp/update", "https://updates.example/a#fragment"] {
            XCTAssertNil(MaintenanceConfiguration.validFeed(url))
        }
        XCTAssertNotNil(MaintenanceConfiguration.validFeed("https://updates.example/appcast.xml"))
        XCTAssertFalse(MaintenanceConfiguration.validPublicKey("placeholder"))
        XCTAssertTrue(MaintenanceConfiguration.validPublicKey(Data(repeating: 1, count: 32).base64EncodedString()))
    }

    func testDeliveryRequiresExplicitAcknowledgementAndDoesNotSendCredentials() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ReportProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let report = try XCTUnwrap(DiagnosticReport(error: failure, area: .coach, version: "0.4.1", build: "5"))
        try await BugReportDelivery(endpoint: URL(string: "https://relay.test/accepted")!, session: session).send(report)
        for path in ["unacknowledged", "redirect", "limited", "failure"] {
            do {
                try await BugReportDelivery(endpoint: URL(string: "https://relay.test/\(path)")!, session: session).send(report)
                XCTFail("Accepted \(path)")
            } catch { XCTAssertTrue(error is BugReportDelivery.Failure) }
        }
    }
}

private final class ReportProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let path = request.url!.lastPathComponent
        let code = ["redirect": 302, "limited": 429, "failure": 503][path] ?? 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "600"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((path == "accepted" ? #"{"accepted":true}"# : #"{"accepted":false}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
