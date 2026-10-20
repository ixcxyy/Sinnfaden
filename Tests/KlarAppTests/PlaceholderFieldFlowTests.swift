import XCTest
import KlarCore
@testable import KlarApp

/// The reported case end to end in the model: an orange placeholder without a field from the
/// model gets one, is guarded before copying, and its value survives history.
@MainActor
final class PlaceholderFieldFlowTests: XCTestCase {
    private func app() throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppModel(isDemo: false, storageBaseURL: root, connection: ConnectionManager(restore: false))
    }

    private let token = "[Ingredients and quantities]"
    private let value = "Linsen 500 g\nReis 1 kg\nPaprika 3 Stück"

    func testAlreadyGoodBracketedTextDoesNotCreateAnUnfillableCopyGuard() throws {
        let app = try app()
        let prompt = "Erkläre die Liste [1, 2, 3] in einem Satz."
        app.presentCoachResult(CoachResponse(status: .already_good, coachMessage: "Schon klar.",
                                            segments: [PromptSegment(id: "s1", text: prompt)]))
        XCTAssertTrue(app.openPlaceholders.isEmpty)
        XCTAssertTrue(app.mayHandOff())
        XCTAssertEqual(app.visiblePrompt, prompt)
    }

    func testOrphanPlaceholderIsFillableWithoutPracticeAndGuardsCopy() throws {
        let app = try app()
        app.presentCoachResult(DemoContent.mealResponse)
        let field = try XCTUnwrap(app.response?.inputs.first { $0.placeholder == token })
        XCTAssertEqual(app.openPlaceholders, [token])
        XCTAssertFalse(app.showExercise, "Filling never waits for the exercise")

        app.copyPrompt()
        XCTAssertTrue(app.copyNeedsInputs, "Copying with an open placeholder stops and says so")
        XCTAssertFalse(app.copied)
        XCTAssertFalse(app.mayHandOff())

        app.inputValues[field.id] = value
        XCTAssertFalse(app.copyNeedsInputs, "The notice disappears once everything is filled")
        XCTAssertEqual(app.openPlaceholders, [])
        XCTAssertTrue(app.mayHandOff())
        XCTAssertTrue(app.visiblePrompt.contains(value))
        for limit in ["vegetarischen", "zwei Personen", "drei Abende", "höchstens 25 Euro", "keine Pilze", "kein Backofen", "höchstens 20 Minuten", "ausschließlich"] {
            XCTAssertTrue(app.visiblePrompt.contains(limit), "Lost limit: \(limit)")
        }
    }

    func testValueOfAStoredAnswerWithoutFieldsSurvivesHistory() throws {
        let app = try app()
        let stored = HistoryEntry(original: DemoContent.mealOriginal, response: DemoContent.mealResponse, outcome: "improved")
        app.select(stored)
        let field = try XCTUnwrap(app.response?.inputs.first { $0.placeholder == token })
        app.inputValues[field.id] = value
        XCTAssertEqual(app.history.first { $0.id == stored.id }?.inputValues?[field.id], value, "The typed value is saved")

        app.newPrompt()
        let saved = try XCTUnwrap(app.history.first { $0.id == stored.id })
        app.select(saved)
        XCTAssertEqual(app.inputValues[field.id], value)
        XCTAssertTrue(app.visiblePrompt.contains(value))
    }

    func testLeavingAResultClearsItsPendingFocusAndCopyWarning() async throws {
        let app = try app()
        app.presentCoachResult(DemoContent.mealResponse)
        app.copyPrompt()
        XCTAssertTrue(app.copyNeedsInputs)
        app.newPrompt()
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertNil(app.focusedInputID)
        XCTAssertFalse(app.copyNeedsInputs)
    }
}
