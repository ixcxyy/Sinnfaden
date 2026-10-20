import XCTest
import KlarCore
@testable import KlarApp

@MainActor
final class PromptGenerationPresentationTests: XCTestCase {
    private func app() throws -> AppModel {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return AppModel(isDemo: false, storageBaseURL: root, connection: ConnectionManager(restore: false))
    }

    func testGeneratedPromptIsUsableWithoutCompletingTheOptionalExercise() async throws {
        let app = try app()
        app.draft = DemoContent.original
        app.presentCoachResult(DemoContent.response)
        XCTAssertEqual(app.phase, .showingResult)
        XCTAssertEqual(app.visiblePrompt, try DemoContent.response.filled(with: DemoContent.response.suggestedInputValues).prompt)
        XCTAssertTrue(app.canUsePrompt)
        XCTAssertTrue(app.solutionRevealed, "Generation must show the result without another reveal action")
        XCTAssertFalse(app.showExercise, "The optional exercise must not open in place of the requested prompt")
        XCTAssertTrue(app.exerciseHelp, "A visible worked example must not count as independent practice")
        XCTAssertFalse(app.openRequiredInputs.isEmpty, "Missing-detail fields remain available with the result")
        app.exerciseAnswer = "Bitte schlage zwei alternative Termine vor."
        app.submitPractice()
        XCTAssertEqual(app.history.first?.practiceAttempts.last?.helpUsed, true)
    }

    func testAlreadyClearPromptStaysVisibleAndPracticeRemainsOptional() async throws {
        let app = try app()
        let original = "Erkläre Regen in drei einfachen Sätzen."
        let result = CoachResponse(status: .already_good, coachMessage: "Schon klar.",
                                   segments: [PromptSegment(id: "s1", text: original)],
                                   exercise: CoachExercise(id: "e1", question: "Formuliere eine neue Anfrage.", category: "Transfer"))
        app.presentCoachResult(result)
        XCTAssertEqual(app.visiblePrompt, original)
        XCTAssertTrue(app.solutionRevealed)
        XCTAssertTrue(app.canUsePrompt)
        XCTAssertFalse(app.showExercise)
        XCTAssertFalse(app.exerciseHelp, "An unchanged original is not a worked improvement")
    }

    func testClarificationDoesNotPretendToHaveBuiltAPrompt() async throws {
        let app = try app()
        let result = CoachResponse(status: .needs_clarification, coachMessage: "Eine Angabe fehlt.",
                                   segments: [], clarification: Clarification(question: "Was möchtest du planen?", optional: false))
        app.presentCoachResult(result)
        XCTAssertEqual(app.phase, .clarifying)
        XCTAssertFalse(app.canUsePrompt)
        XCTAssertFalse(app.solutionRevealed)
        XCTAssertFalse(app.showExercise)
    }
}
