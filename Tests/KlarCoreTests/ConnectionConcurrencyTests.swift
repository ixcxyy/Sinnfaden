import XCTest
@testable import KlarCore

final class ConnectionConcurrencyTests: XCTestCase {
    func testCancellingACredentialWaiterDoesNotCancelRotationOrReturnItsResult() async throws {
        let started = expectation(description: "Waiting for shared credentials")
        let gate = CredentialGate()
        let shared = Task<String, Error> { await gate.value() }
        let caller = Task {
            started.fulfill()
            return try await ConnectionManager.completedCredentialValue(from: shared)
        }
        await fulfillment(of: [started], timeout: 1)
        caller.cancel()
        await gate.complete("synthetic-rotated-credential")
        do { _ = try await caller.value; XCTFail("A cancelled caller must not proceed to inference.") }
        catch { XCTAssertTrue(error is CancellationError) }
        let persistedResult = try await shared.value
        XCTAssertEqual(persistedResult, "synthetic-rotated-credential")
        XCTAssertFalse(shared.isCancelled, "A shared rotating credential operation must finish independently.")
    }
}

private actor CredentialGate {
    private var result: String?
    private var waiter: CheckedContinuation<String, Never>?
    func value() async -> String {
        if let result { return result }
        return await withCheckedContinuation { waiter = $0 }
    }
    func complete(_ value: String) {
        result = value
        waiter?.resume(returning: value)
        waiter = nil
    }
}
