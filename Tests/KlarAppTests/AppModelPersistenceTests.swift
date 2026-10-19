import XCTest
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
