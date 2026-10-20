import XCTest
@testable import KlarCore

/// Regression for the meal-plan case: an orange placeholder in the improved prompt must
/// always have its own field, independent of practice, and its value must reach the prompt.
final class PlaceholderInputTests: XCTestCase {
    private let original = "Erstelle einen vegetarischen Essensplan für zwei Personen für drei Abende. Insgesamt höchstens 25 Euro, keine Pilze, kein Backofen, höchstens 20 Minuten pro Mahlzeit. Nur Zutaten, die ich schon habe."

    private func modelAnswer(inputs: [[String: Any]]) throws -> String {
        let object: [String: Any] = [
            "schema_version": 1, "status": "improved",
            "coach_message": "Nenne deine vorhandenen Zutaten, dann passt der Plan genau.",
            "segments": [
                ["id": "s1", "text": "Erstelle einen vegetarischen Essensplan für zwei Personen für drei Abende. Insgesamt höchstens 25 Euro, keine Pilze, kein Backofen, höchstens 20 Minuten pro Mahlzeit. "],
                ["id": "s2", "text": "Verwende ausschließlich diese vorhandenen Zutaten: [Ingredients and quantities]."]
            ],
            "changes": [["id": "c1", "kind": "addition", "original_text": NSNull(), "target_segment_ids": ["s2"], "category": "Kontext",
                         "title": "Vorhandene Zutaten nennen", "explanation": "So plant die KI nur mit dem, was du wirklich hast.", "rule_id": "unknowns-v1"]],
            "unknowns": [], "suggestions": [], "clarification": NSNull(),
            "exercise": ["id": "ex1", "question": "Welche Zutaten hast du noch?", "category": "Kontext"],
            "inputs": inputs
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    /// The model named the field in German while the prompt kept the English token.
    private var mismatchedInput: [String: Any] {
        ["id": "zutaten", "label": "Vorhandene Zutaten", "kind": "long_text", "placeholder": "[Zutaten und Mengen]",
         "options": [], "suggestion": NSNull(), "required": true, "why": "Damit nur vorhandene Zutaten verwendet werden."]
    }

    func testOrphanPlaceholderGetsItsOwnField() throws {
        for inputs in [[], [mismatchedInput]] {
            let data = CoachSanitizer.clean(try modelAnswer(inputs: inputs), original: original)
            let response = try CoachValidator.decode(data, original: original)
            let field = response.inputs.first { $0.placeholder == "[Ingredients and quantities]" }
            XCTAssertNotNil(field, "Every orange placeholder needs a field (inputs: \(inputs.count))")
            XCTAssertEqual(field?.kind, .long_text, "A list of ingredients needs several lines")
            XCTAssertEqual(response.unfilledPlaceholders(with: [:]), ["[Ingredients and quantities]"])
        }
    }

    func testMismatchedFieldKeepsItsWordingForTheOrphan() throws {
        let data = CoachSanitizer.clean(try modelAnswer(inputs: [mismatchedInput]), original: original)
        let response = try CoachValidator.decode(data, original: original)
        let field = try XCTUnwrap(response.inputs.first { $0.placeholder == "[Ingredients and quantities]" })
        XCTAssertEqual(field.id, "zutaten")
        XCTAssertEqual(field.label, "Vorhandene Zutaten")
    }

    func testRepairNeverInventsAValueFromAnUnmatchedFieldSuggestion() throws {
        var input = mismatchedInput
        input["suggestion"] = "Kartoffeln 2 kg"
        let data = CoachSanitizer.clean(try modelAnswer(inputs: [input]), original: original)
        let response = try CoachValidator.decode(data, original: original)
        XCTAssertNil(response.inputs.first?.suggestion,
                     "A differently named field is not evidence for the missing ingredient list")
        XCTAssertTrue(response.suggestedInputValues.isEmpty)
        XCTAssertEqual(response.unfilledPlaceholders(with: response.suggestedInputValues), ["[Ingredients and quantities]"])
    }

    func testFilledValueReachesThePromptAndKeepsEveryLimit() throws {
        let data = CoachSanitizer.clean(try modelAnswer(inputs: []), original: original)
        let response = try CoachValidator.decode(data, original: original)
        let field = try XCTUnwrap(response.inputs.first)
        let value = "Linsen 500 g\nReis 1 kg\nPaprika 3 Stück\nZwiebeln, Knoblauch, Olivenöl"
        let filled = try response.filled(with: [field.id: value])
        XCTAssertTrue(filled.prompt.contains(value), "Multi-line value arrives verbatim")
        XCTAssertFalse(filled.prompt.contains("[Ingredients and quantities]"))
        for limit in ["vegetarischen", "zwei Personen", "drei Abende", "höchstens 25 Euro", "keine Pilze", "kein Backofen", "höchstens 20 Minuten", "ausschließlich"] {
            XCTAssertTrue(filled.prompt.contains(limit), "Lost limit: \(limit)")
        }
        XCTAssertEqual(response.unfilledPlaceholders(with: [field.id: value]), [])
        // A value that itself looks like a placeholder is never filled again.
        let tricky = try response.filled(with: [field.id: "[Ingredients and quantities] Nudeln"])
        XCTAssertTrue(tricky.prompt.contains("[Ingredients and quantities] Nudeln."))
    }

    func testAmbiguousFieldsAreNotAssignedByArrayPosition() {
        let response = CoachResponse(status: .improved, coachMessage: "Ergänze deine Angaben.",
                                     segments: [PromptSegment(id: "s1", text: "Plane für [Budget] und [Zutaten].")])
        let unmatched = [
            PromptInput(id: "food", label: "Vorrat", kind: .long_text, placeholder: "[Vorrat]", suggestion: "Reis", why: "Vorrat nennen"),
            PromptInput(id: "money", label: "Kosten", kind: .number, placeholder: "[Kosten]", suggestion: "25", why: "Budget nennen")
        ]
        let repaired = response.coveringPlaceholders(unmatched: unmatched)
        XCTAssertEqual(repaired.inputs.map(\.label), ["Budget", "Zutaten"])
        XCTAssertEqual(repaired.inputs.map(\.kind), [.long_text, .long_text])
        XCTAssertTrue(repaired.suggestedInputValues.isEmpty)
        XCTAssertEqual(repaired.coveringPlaceholders(unmatched: unmatched), repaired)
    }

    func testOlderStoredResponsesAlsoGetFieldsForBareTokens() throws {
        let stored = CoachResponse(status: .improved, coachMessage: "Ergänze die Angabe.",
                                   segments: [PromptSegment(id: "s1", text: "Fasse [Text] in drei Sätzen zusammen.")],
                                   changes: [PromptChange(id: "c1", kind: .addition, targetSegmentIDs: ["s1"], category: "Form", title: "Länge", explanation: "Kurz.")])
        let covered = stored.coveringPlaceholders()
        XCTAssertEqual(covered.inputs.map(\.placeholder), ["[Text]"])
        XCTAssertEqual(covered.coveringPlaceholders(), covered, "Stable: ids and fields do not change on repeat")
        XCTAssertNoThrow(try CoachValidator.validate(covered, original: "Fasse den Text zusammen."))
    }

    func testResolvedFieldHintsDisappearButOtherUnknownsRemain() throws {
        var response = DemoContent.response
        response.unknowns += ["[Dein Name] und [Zeitraum] fehlen.", "Der Absagegrund ist unbekannt."]
        let partial = try response.filled(with: ["name": "Alex Test"])
        XCTAssertEqual(partial.unknowns, ["[Dein Name] und [Zeitraum] fehlen.", "Der Absagegrund ist unbekannt."])
        let complete = try response.filled(with: ["name": "Alex Test", "zeitraum": "morgen"])
        XCTAssertEqual(complete.unknowns, ["Der Absagegrund ist unbekannt."])
        XCTAssertEqual(try response.filled(with: [:]).unknowns, response.unknowns,
                       "Clearing the fields must restore the original hints")
    }
}
