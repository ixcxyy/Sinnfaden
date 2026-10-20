import XCTest
import KlarCore
@testable import KlarApp

/// Cancelling a request keeps the draft, ends the loading state at once, and no timer of the
/// cancelled run may bring the loading state or a result back afterwards.
@MainActor
final class CancelFlowTests: XCTestCase {
    func testCancelKeepsDraftAndStaleTimersStayQuiet() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let app = AppModel(isDemo: true, storageBaseURL: root, connection: ConnectionManager(restore: false))
        app.draft = DemoContent.mealOriginal
        app.improve()
        XCTAssertTrue(app.busy, "The request starts immediately")
        try await Task.sleep(nanoseconds: 300_000_000)
        app.cancel()
        XCTAssertFalse(app.busy)
        XCTAssertEqual(app.phase, .interrupted)
        XCTAssertEqual(app.draft, DemoContent.mealOriginal, "The draft stays")
        // The demo run would have finished after ~3.2 s: nothing of it may come back.
        try await Task.sleep(nanoseconds: 3_600_000_000)
        XCTAssertFalse(app.busy)
        XCTAssertEqual(app.phase, .interrupted)
        XCTAssertNil(app.response)
    }
}
