import XCTest
import SQLite3
@testable import KlarCore

final class StorageLearningTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("klar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testRestartDraftHistoryEditsAndAttemptsPersist() throws {
        let root = try temporaryDirectory()
        let entry = HistoryEntry(createdAt: Date(timeIntervalSince1970: 1_700_000_000), original: DemoContent.original, response: DemoContent.response, editedPrompt: "Mein eigener bearbeiteter Text 👋", practiceAttempts: [PracticeAttempt(createdAt: Date(timeIntervalSince1970: 1_700_000_001), answer: "Nur am Vormittag", feedback: "Eine eigene Angabe.", helpUsed: false)])
        do {
            let first = try HistoryStore(accountID: "chatgpt:user-a:workspace-1", baseURL: root)
            try first.saveDraft("Noch unfertig: Grüße e\u{301} 👨‍👩‍👧‍👦")
            try first.save(entry)
        }
        let reopened = try HistoryStore(accountID: "chatgpt:user-a:workspace-1", baseURL: root)
        XCTAssertEqual(try reopened.loadDraft(), "Noch unfertig: Grüße e\u{301} 👨‍👩‍👧‍👦")
        XCTAssertEqual(try reopened.entries(), [entry])
        XCTAssertFalse(try XCTUnwrap(reopened.entries().first).annotationsAreCurrent)
        XCTAssertEqual(try XCTUnwrap(reopened.entries().first).visiblePrompt, entry.editedPrompt)
    }

    func testAccountsAreSeparatedAndDeletionIsScoped() throws {
        let root = try temporaryDirectory()
        let first = try HistoryStore(accountID: "chatgpt:a", baseURL: root)
        let second = try HistoryStore(accountID: "api:b", baseURL: root)
        XCTAssertNotEqual(first.databaseURL, second.databaseURL)
        try first.saveDraft("A geheim")
        try second.saveDraft("B bleibt")
        try first.save(HistoryEntry(original: "A", outcome: "interrupted"))
        try first.deleteAll()
        XCTAssertEqual(try first.loadDraft(), "")
        XCTAssertEqual(try first.entries().count, 0)
        XCTAssertEqual(try second.loadDraft(), "B bleibt")
        try second.saveDraft("")
        XCTAssertEqual(try second.loadDraft(), "")
    }

    func testGeneratedFieldsPersistAndExportWithoutRewritingPromptOrAnnotations() throws {
        let root = try temporaryDirectory()
        let response = CoachResponse(status: .improved, coachMessage: "Ergänze den Ort.",
                                     segments: [PromptSegment(id: "s1", text: "Treffen: [Ort]")],
                                     inputs: [PromptInput(id: "place", label: "Ort", kind: .text, placeholder: "[Ort]", suggestion: "Bahnhof", why: "")])
        let entry = HistoryEntry(createdAt: Date(timeIntervalSince1970: 1_700_000_000), original: "Ein Treffen", response: response, inputValues: ["place": "Café e\u{301} 👋 [Ort]"])
        do { try HistoryStore(accountID: "a", baseURL: root).save(entry) }
        let reopened = try HistoryStore(accountID: "a", baseURL: root)
        let restored = try XCTUnwrap(reopened.entries().first)
        XCTAssertEqual(restored, entry)
        XCTAssertEqual(restored.visiblePrompt, "Treffen: Café e\u{301} 👋 [Ort]")
        XCTAssertEqual(restored.response, response)
        XCTAssertTrue(restored.annotationsAreCurrent)
        let export = try XCTUnwrap(JSONSerialization.jsonObject(with: reopened.exportData()) as? [String: Any])
        let entries = try XCTUnwrap(export["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.first?["inputValues"] as? [String: String], entry.inputValues)

        var cleared = entry
        cleared.inputValues = [:]
        try reopened.save(cleared)
        XCTAssertEqual(try reopened.entries().first?.visiblePrompt, "Treffen: [Ort]")
        let otherAccount = try HistoryStore(accountID: "b", baseURL: root)
        XCTAssertTrue(try otherAccount.entries().isEmpty)
    }

    func testHistoryWithoutSavedFieldValuesStillDecodes() throws {
        let response = CoachResponse(status: .improved, coachMessage: "", segments: [PromptSegment(id: "s1", text: "[Ort]")],
                                     inputs: [PromptInput(id: "place", label: "Ort", kind: .text, placeholder: "[Ort]", suggestion: "Wien", why: "")])
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(HistoryEntry(original: "Alt", response: response))) as? [String: Any])
        legacy.removeValue(forKey: "inputValues")
        let decoded = try JSONDecoder().decode(HistoryEntry.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.inputValues)
        XCTAssertEqual(decoded.visiblePrompt, "Wien")
        XCTAssertEqual(decoded.response, response)
    }

    func testExportIsParseableAndFileIsPrivate() throws {
        let store = try HistoryStore(accountID: "a", baseURL: temporaryDirectory())
        try store.saveDraft("Export Ä😀")
        try store.save(HistoryEntry(original: "Original", outcome: "error"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: store.exportData()) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["draft"] as? String, "Export Ä😀")
        XCTAssertEqual((object["entries"] as? [[String: Any]])?.count, 1)
        let permissions = try FileManager.default.attributesOfItem(atPath: store.databaseURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testNewerDatabaseVersionIsNotOverwritten() throws {
        let root = try temporaryDirectory()
        var databaseURL: URL!
        do { databaseURL = try HistoryStore(accountID: "a", baseURL: root).databaseURL }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database, "PRAGMA user_version=99", nil, nil, nil), SQLITE_OK)
        sqlite3_close(database)
        XCTAssertThrowsError(try HistoryStore(accountID: "a", baseURL: root))
    }

    func testFeedbackDescribesActualAnswerWithoutAssigningSuccess() {
        let exercise = CoachExercise(id: "ex1", question: "Wie soll die Antwort aussehen?", category: "Ausgabe")
        let table = LearningFeedback.evaluate(answer: "Als Tabelle", exercise: exercise, usedHelp: false)
        let constraint = LearningFeedback.evaluate(answer: "Höchstens fünf Zeilen", exercise: exercise, usedHelp: true)
        let vague = LearningFeedback.evaluate(answer: "Weiß ich noch nicht", exercise: exercise, usedHelp: false)
        XCTAssertTrue(table.contains("Ausgabeform"))
        XCTAssertTrue(table.contains("Als Tabelle"))
        XCTAssertTrue(constraint.contains("Grenze"))
        XCTAssertTrue(constraint.contains("Hilfe genutzt"))
        XCTAssertTrue(vague.contains(exercise.question))
        XCTAssertFalse(vague.contains("Ausgabeform"))
        XCTAssertTrue(LearningFeedback.evaluate(answer: "Ich möchte den 28. Oktober um 14 Uhr vorschlagen.", exercise: exercise, usedHelp: false).contains("konkreten Zeitpunkt"))
        XCTAssertTrue(LearningFeedback.evaluate(answer: "  ", exercise: exercise, usedHelp: false).contains("zuerst"))
        for answer in ["Keine Tabelle", "Nicht als Liste", "Tabelle lieber nicht", "Ohne lange Absätze"] {
            let feedback = LearningFeedback.evaluate(answer: answer, exercise: exercise, usedHelp: false)
            XCTAssertTrue(feedback.contains("schließt eine Ausgabeform aus"), answer)
            XCTAssertFalse(feedback.contains("erwähnst eine Ausgabeform"), answer)
        }
    }

    func testLearningStageRequiresOwnDistinctAttemptsNotCopiesOrLogins() {
        XCTAssertEqual(LearningProgress.stage(for: []), .example)
        let assisted = PracticeAttempt(answer: "Als Liste", feedback: "", helpUsed: true)
        XCTAssertEqual(LearningProgress.stage(for: [assisted]), .example)
        let own = PracticeAttempt(answer: "Eine Tabelle", feedback: "")
        XCTAssertEqual(LearningProgress.stage(for: [own, own, assisted]), .addDetail)
        let second = PracticeAttempt(answer: "Nur offene Fragen", feedback: "")
        XCTAssertEqual(LearningProgress.stage(for: [own, second]), .newPrompt)
    }

    func testTutorResourceHasVersionedBoundaryAndKnownRules() {
        XCTAssertTrue(TutorPrompt.instructions.contains("schema_version"))
        XCTAssertTrue(TutorPrompt.instructions.contains("keine Werkzeuge"))
        for rule in RuleRegistry.rules { XCTAssertTrue(TutorPrompt.instructions.contains(rule.id)) }
    }
}
