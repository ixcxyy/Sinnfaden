import XCTest
import SQLite3
@testable import KlarApp
@testable import KlarCore

@MainActor
final class AppModelPersistenceTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sinnfaden-app-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func model(at root: URL) -> AppModel {
        AppModel(isDemo: true, storageBaseURL: root,
                 connection: ConnectionManager(registrations: RegistrationStore(hostID: "synthetic-tests")))
    }

    private func entry() -> HistoryEntry {
        HistoryEntry(original: "Schreibe eine Einladung.", response: CoachResponse(
            status: .improved, coachMessage: "Ergänze den Treffpunkt.",
            segments: [PromptSegment(id: "s1", text: "Wir treffen uns [Ort].")],
            inputs: [PromptInput(id: "place", label: "Treffpunkt", kind: .text,
                                 placeholder: "[Ort]", suggestion: "am Bahnhof", why: "Der Treffpunkt fehlt.")]))
    }

    private func execute(_ sql: String, at databaseURL: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else { throw HistoryStoreError.unavailable }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw HistoryStoreError.unavailable }
    }

    func testFailedHistoryWritesSurviveNavigationAndExportThenRetry() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "demonstration", baseURL: root)
        let first = entry()
        let second = HistoryEntry(original: "Anderer Entwurf")
        try store.save(first); try store.save(second)
        let app = model(at: root)
        app.select(first)
        try execute("CREATE TRIGGER fail_save BEFORE INSERT ON history BEGIN SELECT RAISE(FAIL, 'synthetic save failure'); END", at: store.databaseURL)
        app.inputValues["place"] = "am See, noch ungespeichert"
        XCTAssertNotNil(app.storageError)
        XCTAssertEqual(app.history.first { $0.id == first.id }?.visiblePrompt, "Wir treffen uns am See, noch ungespeichert.")
        app.select(second)
        app.select(first) // Even a row captured before the failed save must restore the latest edits.
        XCTAssertEqual(app.inputValues["place"], "am See, noch ungespeichert")
        let export = try XCTUnwrap(JSONSerialization.jsonObject(with: app.historyExportData()) as? [String: Any])
        let entries = try XCTUnwrap(export["entries"] as? [[String: Any]])
        let exported = try XCTUnwrap(entries.first { ($0["id"] as? String) == first.id.uuidString })
        XCTAssertEqual((exported["inputValues"] as? [String: String])?["place"], "am See, noch ungespeichert")
        try execute("DROP TRIGGER fail_save", at: store.databaseURL)
        app.saveCurrent()
        XCTAssertEqual(try store.entries().first { $0.id == first.id }?.inputValues?["place"], "am See, noch ungespeichert")
        XCTAssertNil(app.storageError)
    }

    func testFailedHistoryWritesSurviveNewPromptButNotExplicitDeletion() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "demonstration", baseURL: root)
        let first = entry()
        try store.save(first)
        let app = model(at: root)
        app.select(first)
        try execute("CREATE TRIGGER fail_save BEFORE INSERT ON history BEGIN SELECT RAISE(FAIL, 'synthetic save failure'); END", at: store.databaseURL)
        app.inputValues["place"] = "im Garten"
        app.newPrompt()
        app.select(try XCTUnwrap(app.history.first { $0.id == first.id }))
        XCTAssertEqual(app.inputValues["place"], "im Garten")
        app.deleteHistory()
        XCTAssertTrue(app.history.isEmpty)
        XCTAssertTrue(app.draft.isEmpty)
        app.switchStorageAccount(to: "other")
        app.switchStorageAccount(to: "demonstration")
        XCTAssertTrue(app.history.isEmpty)
        XCTAssertTrue(try store.entries().isEmpty)
    }

    func testFailedDraftAndHistoryWritesStayInTheirOriginalAccount() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "a", baseURL: root)
        let first = entry()
        try store.save(first)
        let app = model(at: root)
        app.switchStorageAccount(to: "a")
        app.select(first)
        try execute("CREATE TRIGGER fail_save BEFORE INSERT ON history BEGIN SELECT RAISE(FAIL, 'synthetic save failure'); END", at: store.databaseURL)
        try execute("CREATE TRIGGER fail_draft BEFORE INSERT ON metadata BEGIN SELECT RAISE(FAIL, 'synthetic draft failure'); END", at: store.databaseURL)
        app.inputValues["place"] = "Eintrag nur für Konto A"
        app.draft = "Neuer ungespeicherter Entwurf A"
        app.switchStorageAccount(to: "b")
        XCTAssertTrue(app.draft.isEmpty)
        XCTAssertTrue(app.history.isEmpty)
        XCTAssertNotNil(app.storageError)
        app.draft = "Entwurf B"
        app.switchStorageAccount(to: "a")
        XCTAssertEqual(app.draft, "Neuer ungespeicherter Entwurf A")
        XCTAssertEqual(app.history.first { $0.id == first.id }?.inputValues?["place"], "Eintrag nur für Konto A")
        try execute("DROP TRIGGER fail_save; DROP TRIGGER fail_draft", at: store.databaseURL)
        app.switchStorageAccount(to: "b")
        XCTAssertEqual(app.draft, "Entwurf B")
        app.switchStorageAccount(to: "a")
        XCTAssertEqual(try store.loadDraft(), "Neuer ungespeicherter Entwurf A")
        XCTAssertEqual(try store.entries().first { $0.id == first.id }?.inputValues?["place"], "Eintrag nur für Konto A")
        XCTAssertNil(app.storageError)
    }

    func testUnavailableHistoryCanExportNewDraftWithoutReplacingNewerDatabase() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "newer", baseURL: root)
        try store.saveDraft("Unveränderter gespeicherter Text")
        try store.save(entry())
        try execute("PRAGMA user_version=999", at: store.databaseURL)
        let before = try Data(contentsOf: store.databaseURL)
        let app = model(at: root)
        app.switchStorageAccount(to: "newer")
        XCTAssertTrue(app.history.isEmpty)
        app.draft = "Neuer Text bei nicht lesbarem Verlauf"
        app.switchStorageAccount(to: "other")
        XCTAssertTrue(app.draft.isEmpty)
        app.switchStorageAccount(to: "newer")
        XCTAssertEqual(app.draft, "Neuer Text bei nicht lesbarem Verlauf")
        let export = try XCTUnwrap(JSONSerialization.jsonObject(with: app.historyExportData()) as? [String: Any])
        XCTAssertEqual(export["draft"] as? String, app.draft)
        XCTAssertEqual(export["includesCompleteStoredHistory"] as? Bool, false)
        XCTAssertEqual(try Data(contentsOf: store.databaseURL), before)
        XCTAssertNotNil(app.storageError)
    }

    func testSuccessfulEntrySaveDoesNotHideFailedDraftAndFailedDeletionKeepsRecovery() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "demonstration", baseURL: root)
        let first = entry()
        try store.save(first)
        let app = model(at: root)
        app.select(first)
        try execute("CREATE TRIGGER fail_draft BEFORE INSERT ON metadata BEGIN SELECT RAISE(FAIL, 'synthetic draft failure'); END", at: store.databaseURL)
        app.draft = "Nicht gespeicherter Entwurf"
        app.inputValues["place"] = "im Park"
        XCTAssertNotNil(app.storageError, "Saving a history entry does not save the draft")
        try execute("CREATE TRIGGER fail_save BEFORE INSERT ON history BEGIN SELECT RAISE(FAIL, 'synthetic save failure'); END", at: store.databaseURL)
        try execute("CREATE TRIGGER fail_delete BEFORE DELETE ON history BEGIN SELECT RAISE(FAIL, 'synthetic deletion failure'); END", at: store.databaseURL)
        app.inputValues["place"] = "am See"
        app.deleteHistory()
        XCTAssertEqual(app.history.first { $0.id == first.id }?.inputValues?["place"], "am See")
        XCTAssertEqual(app.draft, "Nicht gespeicherter Entwurf")
        try execute("DROP TRIGGER fail_draft; DROP TRIGGER fail_save; DROP TRIGGER fail_delete", at: store.databaseURL)
        app.flushPendingSaves()
        XCTAssertEqual(try store.loadDraft(), app.draft)
        XCTAssertEqual(try store.entries().first { $0.id == first.id }?.inputValues?["place"], "am See")
        XCTAssertNil(app.storageError)
    }

    func testFieldAnswersSurviveNavigationRestartAndHistoryPreview() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "demonstration", baseURL: root)
        let first = entry()
        let second = HistoryEntry(original: "Ein anderer Entwurf")
        try store.save(first); try store.save(second)
        let app = model(at: root)
        app.select(first)
        XCTAssertEqual(app.inputValues["place"], "am Bahnhof")
        app.inputValues["place"] = "beim Café 👋 [Treffpunkt]"
        XCTAssertEqual(app.visiblePrompt, "Wir treffen uns beim Café 👋 [Treffpunkt].")
        app.select(second)
        app.select(try XCTUnwrap(app.history.first { $0.id == first.id }))
        XCTAssertEqual(app.inputValues["place"], "beim Café 👋 [Treffpunkt]")
        app.newPrompt()

        let reopened = model(at: root)
        let restored = try XCTUnwrap(reopened.history.first { $0.id == first.id })
        XCTAssertEqual(restored.visiblePrompt, "Wir treffen uns beim Café 👋 [Treffpunkt].")
        reopened.select(restored)
        XCTAssertEqual(reopened.visiblePrompt, restored.visiblePrompt)
        XCTAssertEqual(reopened.inputValues["place"], "beim Café 👋 [Treffpunkt]")
        XCTAssertNil(app.storageError); XCTAssertNil(reopened.storageError)
    }

    func testClearedSuggestionsStayClearedWhenSameResponseIsReopened() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "demonstration", baseURL: root)
        let first = entry()
        var second = first
        second.id = UUID()
        try store.save(first); try store.save(second)
        let app = model(at: root)
        app.select(first)
        app.inputValues = [:]
        app.select(second)
        XCTAssertEqual(app.inputValues["place"], "am Bahnhof", "An identical response in another entry needs its own field values")
        app.inputValues["place"] = "in Wien"
        app.select(try XCTUnwrap(app.history.first { $0.id == first.id }))
        XCTAssertTrue(app.inputValues.isEmpty)
        XCTAssertEqual(app.visiblePrompt, "Wir treffen uns [Ort].")
        app.newPrompt()
        let reopened = model(at: root)
        reopened.select(try XCTUnwrap(reopened.history.first { $0.id == first.id }))
        XCTAssertTrue(reopened.inputValues.isEmpty)
    }

    func testManualEditsRetainPriorityOverPersistedFieldAnswers() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "demonstration", baseURL: root)
        let first = entry()
        try store.save(first)
        let app = model(at: root)
        app.select(first)
        app.inputValues["place"] = "im Park"
        app.beginEditing()
        app.editedPrompt = "Meine eigene Einladung"
        app.updateEditedPrompt()
        app.newPrompt()
        let reopened = model(at: root)
        reopened.select(try XCTUnwrap(reopened.history.first { $0.id == first.id }))
        XCTAssertEqual(reopened.visiblePrompt, "Meine eigene Einladung")
        XCTAssertEqual(reopened.inputValues["place"], "im Park")
    }
}
