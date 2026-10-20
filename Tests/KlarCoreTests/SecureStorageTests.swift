import XCTest
@testable import KlarCore

final class SecureStorageTests: XCTestCase {
    @MainActor func testCredentialReadsDoNotRunOnTheUIThread() async throws {
        let store = SecureStorage(readData: { account in
            XCTAssertFalse(Thread.isMainThread, "A macOS permission dialog must not freeze the app's main thread.")
            XCTAssertEqual(account, "synthetic-account")
            return Data(#""synthetic-value""#.utf8)
        })
        let value = try await store.load(String.self, account: "synthetic-account")
        XCTAssertEqual(value, "synthetic-value")
    }

    func testCancelledReadDoesNotDeliverLateCredentials() async throws {
        let started = expectation(description: "Keychain read started")
        let release = DispatchSemaphore(value: 0)
        let store = SecureStorage(readData: { _ in
            started.fulfill()
            _ = release.wait(timeout: .now() + 2)
            return Data(#""synthetic-value""#.utf8)
        })
        let task = Task { try await store.load(String.self, account: "synthetic-account") }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        release.signal()
        do { _ = try await task.value; XCTFail("Cancelled reads must not deliver credentials.") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCancellationCompletesWithoutWaitingForTheSecureStorageRead() async throws {
        let started = expectation(description: "Secure storage read started")
        let cancelled = expectation(description: "Caller returned before the read was released")
        let readFinished = expectation(description: "Background read finished independently")
        let release = DispatchSemaphore(value: 0)
        let store = SecureStorage(readData: { _ in
            started.fulfill()
            _ = release.wait(timeout: .now() + 5)
            defer { readFinished.fulfill() }
            return Data(#""synthetic-late-value""#.utf8)
        })
        let caller = Task {
            do {
                _ = try await store.load(String.self, account: "synthetic-account")
                XCTFail("Cancellation must not return credentials")
            } catch { XCTAssertTrue(error is CancellationError) }
            cancelled.fulfill()
        }
        await fulfillment(of: [started], timeout: 1)
        caller.cancel()
        await fulfillment(of: [cancelled], timeout: 0.5)
        release.signal()
        await fulfillment(of: [readFinished], timeout: 1)
        await caller.value
    }

    func testAlreadyCancelledCallDoesNotStartSecureStorageAccess() async throws {
        let store = SecureStorage(readData: { _ in
            XCTFail("An already cancelled request must not start a permission operation")
            return nil
        })
        let caller = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await store.load(String.self, account: "synthetic-account")
        }
        do { _ = try await caller.value; XCTFail("An already cancelled call must throw") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testMissingAndInvalidStoredValuesRemainDistinct() async throws {
        let missing = SecureStorage(readData: { _ in nil })
        let value = try await missing.load(String.self, account: "synthetic-account")
        XCTAssertNil(value)
        let corrupt = SecureStorage(readData: { _ in Data("not JSON".utf8) })
        do { _ = try await corrupt.load(String.self, account: "synthetic-account"); XCTFail("Corrupt data must fail.") }
        catch { XCTAssertTrue(error is DecodingError) }
    }
}
