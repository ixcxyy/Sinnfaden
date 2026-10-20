import XCTest
import SQLite3
import Combine
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

    func testCommittedHistoryDeletionDoesNotRestoreEntriesWhenCompactionFails() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "demonstration", baseURL: root)
        let first = entry()
        try store.save(first)
        let app = model(at: root)
        app.select(first)
        try execute("CREATE TRIGGER fail_save BEFORE INSERT ON history BEGIN SELECT RAISE(FAIL, 'synthetic save failure'); END", at: store.databaseURL)
        app.inputValues["place"] = "Eintrag zum Löschen, noch ungespeichert"
        try execute("DROP TRIGGER fail_save", at: store.databaseURL)

        // Fault only this temporary connection, without a production fault-injection API.
        // VACUUM internally attaches a temporary database after the DELETE has committed.
        let appStore = try XCTUnwrap(Mirror(reflecting: app).children.first { $0.label == "store" }?.value as? HistoryStore)
        let database = try XCTUnwrap(Mirror(reflecting: appStore).children.first { $0.label == "database" }?.value as? OpaquePointer)
        let denied = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        denied.initialize(to: 0)
        defer {
            withExtendedLifetime(appStore) { _ = sqlite3_set_authorizer(database, nil, nil) }
            denied.deinitialize(count: 1); denied.deallocate()
        }
        XCTAssertEqual(sqlite3_set_authorizer(database, { context, action, _, _, _, _ in
            guard action == SQLITE_ATTACH else { return SQLITE_OK }
            context?.assumingMemoryBound(to: Int.self).pointee += 1
            return SQLITE_DENY
        }, denied), SQLITE_OK)

        app.deleteHistory()
        XCTAssertGreaterThan(denied.pointee, 0, "The test must actually fail compaction")
        XCTAssertTrue(try store.entries().isEmpty, "The deletion itself committed successfully")
        XCTAssertTrue(app.history.isEmpty)
        XCTAssertTrue(app.draft.isEmpty)
        XCTAssertNil(app.storageError, "A committed deletion must not be reported as failed")
        app.flushPendingSaves()
        app.saveCurrent()
        XCTAssertTrue(try store.entries().isEmpty, "Deleted pending entries must never be restored")
        XCTAssertTrue(try store.loadDraft().isEmpty)
        let reopened = model(at: root)
        XCTAssertTrue(reopened.history.isEmpty)
        // Demo startup intentionally seeds an example draft; stored deletion is checked above.
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

    func testFieldAnswersStillUpdateAnUntouchedOpenTextEditor() async throws {
        let root = try temporaryDirectory()
        let app = model(at: root)
        let first = entry()
        app.select(first)
        app.beginEditing()
        app.inputValues["place"] = "beim Café 👋"
        XCTAssertEqual(app.visiblePrompt, "Wir treffen uns beim Café 👋.")
        app.updateEditedPrompt()
        app.editing = false
        XCTAssertFalse(app.manuallyEdited)
        XCTAssertNil(app.history.first { $0.id == first.id }?.editedPrompt)
        XCTAssertEqual(app.visiblePrompt, "Wir treffen uns beim Café 👋.")
        let reopened = model(at: root)
        reopened.select(try XCTUnwrap(reopened.history.first { $0.id == first.id }))
        XCTAssertEqual(reopened.visiblePrompt, "Wir treffen uns beim Café 👋.")
        XCTAssertFalse(reopened.manuallyEdited)
    }

    func testFieldChangeDoesNotOverwriteTypedTextBeforeEditNotificationArrives() async throws {
        let root = try temporaryDirectory()
        let app = model(at: root)
        app.select(entry())
        app.beginEditing()
        app.editedPrompt = "Meine gerade eingegebene Einladung"
        // SwiftUI's edit notification has not run yet; the current text is still authoritative.
        XCTAssertFalse(app.manuallyEdited)
        app.inputValues["place"] = "am See"
        XCTAssertEqual(app.visiblePrompt, "Meine gerade eingegebene Einladung")
        app.updateEditedPrompt()
        app.editing = false
        XCTAssertTrue(app.manuallyEdited)
        XCTAssertEqual(app.visiblePrompt, "Meine gerade eingegebene Einladung")
    }

    func testPracticeAfterOpeningWorkedExampleFromHistoryIsMarkedSupported() async throws {
        let root = try temporaryDirectory()
        let app = model(at: root)
        var first = entry()
        first.response?.exercise = CoachExercise(id: "practice", question: "Ergänze eine konkrete Angabe.", category: "Kontext")
        app.select(first)
        XCTAssertTrue(app.solutionRevealed, "Opening history displays the worked example")
        app.exerciseAnswer = "Bitte schlage einen Treffpunkt mit Sitzgelegenheiten vor."
        app.submitPractice()
        let attempts = try XCTUnwrap(app.history.first { $0.id == first.id }?.practiceAttempts)
        XCTAssertEqual(attempts.last?.helpUsed, true)
        XCTAssertTrue(app.exerciseFeedback.contains("unterstützt"))
        XCTAssertEqual(LearningProgress.stage(for: attempts), .example)
    }

    func testCancellingANewDemoDoesNotMarkAnOlderHistoryEntryInterrupted() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "demonstration", baseURL: root)
        try store.save(HistoryEntry(original: "Älterer gespeicherter Entwurf", outcome: "draft"))
        let previous = try XCTUnwrap(store.entries().first)
        let app = model(at: root)
        app.draft = previous.original
        app.select(previous)
        app.draft = "Neuer synthetischer Demo-Entwurf"
        app.improve()
        app.cancel()

        let saved = try store.entries()
        XCTAssertEqual(saved.first { $0.id == previous.id }, previous)
        let interrupted = try XCTUnwrap(saved.first { $0.original == "Neuer synthetischer Demo-Entwurf" })
        XCTAssertNotEqual(interrupted.id, previous.id)
        XCTAssertEqual(interrupted.outcome, "interrupted")
        XCTAssertNil(interrupted.response)
        XCTAssertTrue(interrupted.practiceAttempts.isEmpty)
    }

    func testDemoResultAndPracticeAreSavedToTheirOwnHistoryEntry() async throws {
        let root = try temporaryDirectory()
        let store = try HistoryStore(accountID: "demonstration", baseURL: root)
        try store.save(HistoryEntry(original: "Älterer gespeicherter Entwurf", outcome: "draft"))
        let previous = try XCTUnwrap(store.entries().first)
        let app = model(at: root)
        app.draft = previous.original
        app.select(previous)
        app.draft = DemoContent.original
        let completed = expectation(description: "Bundled demo completed")
        let subscription = app.$phase.dropFirst().filter { $0 == .showingResult }.prefix(1).sink { _ in completed.fulfill() }
        defer { subscription.cancel(); app.cancel() }
        app.improve()
        await fulfillment(of: [completed], timeout: 5)

        let result = try XCTUnwrap(store.entries().first { $0.original == DemoContent.original })
        XCTAssertNotEqual(result.id, previous.id)
        XCTAssertEqual(result.response, DemoContent.response)
        XCTAssertEqual(result.outcome, DemoContent.response.status.rawValue)
        app.exerciseAnswer = "Bitte formuliere die Einladung für Freitagvormittag."
        app.submitPractice()
        let saved = try store.entries()
        XCTAssertEqual(saved.first { $0.id == previous.id }, previous)
        XCTAssertEqual(saved.first { $0.id == result.id }?.practiceAttempts.count, 1)
        XCTAssertEqual(saved.first { $0.id == result.id }?.practiceAttempts.first?.helpUsed, true)
    }

    func testReopeningAnAlreadyGoodOriginalDoesNotClaimExampleHelp() async throws {
        let root = try temporaryDirectory()
        let app = model(at: root)
        let original = "Erkläre Regen in drei Sätzen."
        let response = CoachResponse(status: .already_good, coachMessage: "Schon klar.",
                                     segments: [PromptSegment(id: "s1", text: original)],
                                     exercise: CoachExercise(id: "practice", question: "Formuliere eine andere Anfrage.", category: "Transfer"))
        let first = HistoryEntry(original: original, response: response)
        app.select(first)
        app.exerciseAnswer = "Erkläre Schnee für Einsteiger mit einem Beispiel."
        app.submitPractice()
        XCTAssertEqual(app.history.first { $0.id == first.id }?.practiceAttempts.last?.helpUsed, false)
    }

    func testCopiedPracticeWithFormattingChangesDoesNotCountAsIndependent() async throws {
        let root = try temporaryDirectory()
        let app = model(at: root)
        let original = "Erkläre Regen\nin drei Sätzen."
        let response = CoachResponse(status: .already_good, coachMessage: "Schon klar.",
                                     segments: [PromptSegment(id: "s1", text: original)],
                                     exercise: CoachExercise(id: "practice", question: "Formuliere eine neue Anfrage.", category: "Transfer"))
        let first = HistoryEntry(original: original, response: response)
        app.select(first)
        app.exerciseAnswer = "  ERKLÄRE  Regen in drei Sätzen. "
        app.submitPractice()
        XCTAssertEqual(app.history.first { $0.id == first.id }?.practiceAttempts.last?.helpUsed, true)
        XCTAssertTrue(app.exerciseFeedback.contains("entspricht dem Vorschlag"))
    }
}
