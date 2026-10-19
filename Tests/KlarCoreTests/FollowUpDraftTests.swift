import XCTest
@testable import KlarCore

final class FollowUpDraftTests: XCTestCase {
    func testChangingSourceClearsAllDerivedContextButRetainsNewInput() throws {
        var draft = FollowUpDraft(sourcePrompt: "Ursprünglicher Prompt", answer: "Alte Antwort", desiredChange: "Kürzer", clarification: "Für wen?", clarificationAnswer: "Für Anfänger", generated: DemoContent.response, generatedOriginal: "Alte Anfrage mit alten Antworten", editedPrompt: "Alter Entwurf")
        draft.answer = "Neu eingefügte Antwort 👋"
        draft.desiredChange = "Konkrete Schritte"
        draft.resetGeneratedContext()
        XCTAssertEqual(draft.sourcePrompt, "Ursprünglicher Prompt")
        XCTAssertEqual(draft.answer, "Neu eingefügte Antwort 👋")
        XCTAssertEqual(draft.desiredChange, "Konkrete Schritte")
        XCTAssertEqual(draft.clarification, "")
        XCTAssertEqual(draft.clarificationAnswer, "")
        XCTAssertEqual(draft.generatedOriginal, "")
        XCTAssertNil(draft.generated)
        XCTAssertNil(draft.editedPrompt)
        let input = try draft.preparedInput()
        XCTAssertTrue(input.contains(draft.answer))
        XCTAssertFalse(input.contains("Für Anfänger"))
        XCTAssertFalse(input.contains("Alte Anfrage"))
    }

    func testTwoClarificationRoundsPreserveExactEarlierAnswers() throws {
        var draft = FollowUpDraft(sourcePrompt: "Erkläre Regen", answer: "Wasser fällt aus Wolken.", desiredChange: "Passender erklären", clarification: "Für wen?", clarificationAnswer: "  Für meine Kollegin Özdemir 👩🏽‍💻\nOhne Fachwörter.  ")
        let first = try draft.preparedInput()
        XCTAssertTrue(first.contains("Meine Ergänzung: " + draft.clarificationAnswer))
        draft.generatedOriginal = first
        draft.clarification = "Wie lang soll die Erklärung sein?"
        draft.clarificationAnswer = "Drei Sätze & ein Beispiel."
        let second = try draft.preparedInput()
        XCTAssertTrue(second.hasPrefix(first))
        XCTAssertTrue(second.contains("Für meine Kollegin Özdemir 👩🏽‍💻\nOhne Fachwörter.  "))
        XCTAssertTrue(second.contains("Meine Ergänzung: Drei Sätze & ein Beispiel."))
        XCTAssertEqual(second.components(separatedBy: "Rückfrage zum Folgeauftrag:").count - 1, 2)
    }

    func testPreparingAndRetryingConsumedRequestDoNotDuplicateClarification() throws {
        var draft = FollowUpDraft(answer: "Eine Antwort.", desiredChange: "Einfacher", clarification: "Für wen?", clarificationAnswer: "Für Einsteiger.")
        let snapshot = try draft.preparedInput()
        XCTAssertEqual(try draft.preparedInput(), snapshot)
        draft.generatedOriginal = snapshot
        XCTAssertEqual(try draft.preparedInput(), snapshot, "A saved snapshot with not-yet-cleared pending fields must also be retryable")
        draft.clarification = ""
        draft.clarificationAnswer = ""
        XCTAssertEqual(try draft.preparedInput(), snapshot)
        XCTAssertEqual(snapshot.components(separatedBy: "Meine Ergänzung:").count - 1, 1)
    }

    func testPendingQuestionRequiresAnswerOrExplicitVisibleUnknown() throws {
        var draft = FollowUpDraft(answer: "Eine Antwort.", desiredChange: "Besser passend", clarification: "Für welche Person?", clarificationAnswer: " \n ")
        XCTAssertThrowsError(try draft.preparedInput())
        let snapshot = try draft.preparedInput(leavingOpen: true)
        XCTAssertTrue(snapshot.contains("[Noch offen: Für welche Person?]"))
        XCTAssertTrue(snapshot.contains("lasse ich bewusst offen"))
        draft.generatedOriginal = snapshot
        draft.clarification = "Welche Form?"
        draft.clarificationAnswer = "Eine Tabelle"
        let next = try draft.preparedInput()
        XCTAssertTrue(next.hasPrefix(snapshot))
        XCTAssertTrue(next.contains("Meine Ergänzung: Eine Tabelle"))
    }

    func testEmptySourceAnswerAndOversizedContextCannotGenerate() {
        XCTAssertThrowsError(try FollowUpDraft(desiredChange: "Kürzer").preparedInput())
        let long = FollowUpDraft(answer: String(repeating: "😀", count: 12_001), desiredChange: "Kürzer")
        XCTAssertThrowsError(try long.preparedInput())
    }

    func testPracticePrincipleIDIsBackwardCompatible() throws {
        let legacy = """
        {"id":"DA6CDA75-F7D3-44F2-A91D-B7E59993E50D","createdAt":0,"answer":"Drei Sätze","feedback":"Eine Länge genannt","helpUsed":false}
        """
        let decoded = try JSONDecoder().decode(PracticeAttempt.self, from: Data(legacy.utf8))
        XCTAssertNil(decoded.principleID)
        let tagged = PracticeAttempt(answer: "Drei Sätze", feedback: "Eine Länge genannt", principleID: "format")
        let roundTrip = try JSONDecoder().decode(PracticeAttempt.self, from: JSONEncoder().encode(tagged))
        XCTAssertEqual(roundTrip.principleID, "format")
        XCTAssertEqual(roundTrip.answer, tagged.answer)
    }
}
