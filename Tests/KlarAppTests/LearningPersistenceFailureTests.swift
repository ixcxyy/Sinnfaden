import XCTest
@testable import KlarApp
@testable import KlarCore

@MainActor
final class LearningPersistenceFailureTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sinnfaden-learning-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func workspace(at root: URL) -> LearningWorkspace {
        LearningWorkspace(connection: ConnectionManager(registrations: RegistrationStore(hostID: "synthetic-tests")),
                          isDemo: true, storageBaseURL: root)
    }

    func testCorrectedRecipeClearsObsoleteErrorAfterSuccessfulSave() async throws {
        let root = try temporaryDirectory()
        let app = workspace(at: root)
        app.switchAccount("recipe-retry")
        var recipe = PromptRecipe(title: "Korrigierte Vorlage", template: "{{fehlend}}")
        app.saveRecipe(recipe)
        XCTAssertNotNil(app.errorMessage)
        recipe.template = "Erkläre Regen in drei Sätzen."
        app.saveRecipe(recipe)
        XCTAssertNil(app.errorMessage)
        XCTAssertNil(app.storageError)
        XCTAssertEqual(try LearningStore(accountID: "recipe-retry", baseURL: root).load().recipes.first { $0.id == recipe.id }?.template, recipe.template)
    }

    func testFailedSaveSurvivesAccountSwitchWithoutCrossAccountDisclosure() async throws {
        let root = try temporaryDirectory()
        let storeA = try LearningStore(accountID: "account-a", baseURL: root)
        try storeA.save(LearningState())
        let original = try Data(contentsOf: storeA.fileURL)
        let app = workspace(at: root)
        app.switchAccount("account-a")
        // Simulate an incompatible writer appearing after this app opened its store.
        let newerFile = Data(#"{"schemaVersion":99}"#.utf8)
        try newerFile.write(to: storeA.fileURL, options: .atomic)
        app.state.lessonDrafts["goal"] = "Noch ungespeichert in Konto A"
        app.flushPendingSave()
        XCTAssertNotNil(app.storageError)

        app.switchAccount("account-b")
        XCTAssertNil(app.state.lessonDrafts["goal"], "Account A's unsaved text must not appear under account B")
        XCTAssertNotNil(app.storageError, "Keep a reminder that another account still has unsaved work")
        app.state.lessonDrafts["goal"] = "Nur Konto B"
        app.flushPendingSave()
        XCTAssertNotNil(app.storageError, "Saving B does not resolve A's pending recovery")
        app.switchAccount("account-a")
        XCTAssertEqual(app.state.lessonDrafts["goal"], "Noch ungespeichert in Konto A")
        XCTAssertNotNil(app.storageError)
        XCTAssertEqual(try Data(contentsOf: storeA.fileURL), newerFile)

        // Once compatible storage is available, returning to A retries the recovered work.
        try original.write(to: storeA.fileURL, options: .atomic)
        app.switchAccount("account-b")
        XCTAssertEqual(app.state.lessonDrafts["goal"], "Nur Konto B")
        app.switchAccount("account-a")
        XCTAssertEqual(app.state.lessonDrafts["goal"], "Noch ungespeichert in Konto A")
        XCTAssertEqual(try storeA.load().lessonDrafts["goal"], "Noch ungespeichert in Konto A")
        XCTAssertNil(app.storageError)
    }

    func testEditsMadeWithoutAnOpenStoreStayRecoverable() async throws {
        let root = try temporaryDirectory()
        let store = try LearningStore(accountID: "unavailable", baseURL: root)
        let newerFile = Data(#"{"schemaVersion":99}"#.utf8)
        try newerFile.write(to: store.fileURL, options: .atomic)
        let app = workspace(at: root)
        app.switchAccount("unavailable")
        XCTAssertNotNil(app.storageError)
        app.state.followUp.clarification = "Meine Ergänzung bleibt erhalten"
        app.switchAccount("other")
        XCTAssertTrue(app.state.followUp.clarification.isEmpty)
        app.switchAccount("unavailable")
        XCTAssertEqual(app.state.followUp.clarification, "Meine Ergänzung bleibt erhalten")
        XCTAssertEqual(try Data(contentsOf: store.fileURL), newerFile)
    }

    func testExplicitDeletionDoesNotResurrectCachedFailedEdits() async throws {
        let root = try temporaryDirectory()
        let store = try LearningStore(accountID: "a", baseURL: root)
        let app = workspace(at: root)
        app.switchAccount("a")
        try Data(#"{"schemaVersion":99}"#.utf8).write(to: store.fileURL, options: .atomic)
        app.state.lessonDrafts["goal"] = "Danach bewusst gelöscht"
        app.flushPendingSave()
        XCTAssertNotNil(app.storageError)
        app.deleteLearningData()
        XCTAssertTrue(app.state.recipes.isEmpty)
        app.switchAccount("b")
        app.switchAccount("a")
        XCTAssertTrue(app.state.lessonDrafts.isEmpty)
        XCTAssertTrue(app.state.recipes.isEmpty)
        XCTAssertNil(app.storageError)
    }

    func testUnreadableAccountWithoutEditsDoesNotReplaceRepairedData() async throws {
        let root = try temporaryDirectory()
        let store = try LearningStore(accountID: "a", baseURL: root)
        try store.save(LearningState(lessonDrafts: ["goal": "Bestehender Entwurf"]))
        let original = try Data(contentsOf: store.fileURL)
        try Data(#"{"schemaVersion":99}"#.utf8).write(to: store.fileURL, options: .atomic)
        let app = workspace(at: root)
        app.switchAccount("a")
        app.switchAccount("b")
        try original.write(to: store.fileURL, options: .atomic)
        app.switchAccount("a")
        XCTAssertEqual(app.state.lessonDrafts["goal"], "Bestehender Entwurf")
        XCTAssertNil(app.storageError)
    }
}
