import XCTest
@testable import KlarCore

/// Local fixtures only: near-miss model answers that used to fail the whole request.
final class CoachSanitizerTests: XCTestCase {
    private let original = "Schreib eine E-Mail an Frau Berger. Ich kann am 24. Oktober nicht."

    private func answer(_ object: [String: Any], fenced: Bool = false) throws -> String {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        return fenced ? "Hier ist das Ergebnis:\n```json\n\(json)\n```" : json
    }

    private var base: [String: Any] {
        [
            "schema_version": 1, "status": "improved", "coach_message": "Zwei Angaben machen die E-Mail klarer.",
            "segments": [
                ["id": "s1", "text": "Schreib eine kurze E-Mail an Frau Berger. Ich kann am 24. Oktober nicht. "],
                ["id": "s2", "text": "Schlag einen neuen Termin in [Zeitraum] vor."]
            ],
            "changes": [
                ["id": "c1", "kind": "addition", "original_text": NSNull(), "target_segment_ids": ["s2"], "category": "Ziel",
                 "title": "Nächsten Schritt nennen", "explanation": "So weiß Frau Berger, was du dir wünschst.", "rule_id": "goal-v1"]
            ],
            "unknowns": [], "suggestions": [], "clarification": NSNull(), "exercise": NSNull(),
            "inputs": [
                ["id": "zeitraum", "label": "Zeitraum", "kind": "choice", "placeholder": "[Zeitraum]", "options": ["nächste Woche", "übernächste Woche"],
                 "suggestion": NSNull(), "required": true, "why": "Damit der Termin passt."]
            ]
        ]
    }

    func testFencedAnswerWithLeadInIsAccepted() throws {
        let data = CoachSanitizer.clean(try answer(base, fenced: true), original: original)
        let response = try CoachValidator.decode(data, original: original)
        XCTAssertEqual(response.changes.count, 1)
        XCTAssertEqual(response.inputs.count, 1)
    }

    func testChoiceOptionsAreUniqueAfterTrimming() throws {
        var object = base
        var inputs = try XCTUnwrap(object["inputs"] as? [[String: Any]])
        inputs[0]["options"] = [" nächste Woche ", "nächste Woche", "übernächste Woche"]
        object["inputs"] = inputs
        let response = try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original)
        XCTAssertEqual(response.inputs.first?.options, ["nächste Woche", "übernächste Woche"])
        var invalid = response
        invalid.inputs[0].options = ["nächste Woche", "nächste Woche"]
        XCTAssertThrowsError(try CoachValidator.validate(invalid, original: original))
    }

    func testDuplicateOnlyOptionsBecomeAnEditableField() throws {
        var object = base
        var inputs = try XCTUnwrap(object["inputs"] as? [[String: Any]])
        inputs[0]["options"] = [" nächste Woche ", "nächste Woche"]
        object["inputs"] = inputs
        let response = try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original)
        XCTAssertEqual(response.inputs.first?.kind, .text)
        XCTAssertEqual(response.inputs.first?.options, [])
    }

    func testMalformedOptionalItemsDoNotDiscardAnOtherwiseUsablePrompt() throws {
        var object = base
        var changes = try XCTUnwrap(object["changes"] as? [[String: Any]])
        changes.append(["id": "bad", "kind": "unknown", "target_segment_ids": [], "title": "Ungültig", "category": "Form", "explanation": "Ungültig"])
        object["changes"] = changes
        var inputs = try XCTUnwrap(object["inputs"] as? [[String: Any]])
        inputs.append(["id": "bad", "label": "Ungültig", "kind": "unsupported_widget", "placeholder": "[Zeitraum]", "options": [], "required": false, "why": "Ungültig"])
        object["inputs"] = inputs
        object["exercise"] = ["id": "bad", "question": 42, "category": "Form"]
        let response = try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original)
        XCTAssertEqual(response.prompt, "Schreib eine kurze E-Mail an Frau Berger. Ich kann am 24. Oktober nicht. Schlag einen neuen Termin in [Zeitraum] vor.")
        XCTAssertEqual(response.changes.count, 1)
        XCTAssertEqual(response.inputs.count, 1)
        XCTAssertNil(response.exercise)
    }

    func testBrokenFieldsAreDroppedInsteadOfFailingTheRequest() throws {
        var object = base
        object["inputs"] = [
            ["id": "zeitraum", "label": "Zeitraum", "kind": "choice", "placeholder": "[Zeitraum]", "options": ["nur eine"], "required": true, "why": "Wozu."],
            ["id": "name", "label": "Name", "kind": "text", "placeholder": "[Name]", "options": [], "required": true, "why": "Unterschrift."],
            ["id": "zeitraum", "label": "Doppelt", "kind": "text", "placeholder": "[Zeitraum]", "options": [], "required": false, "why": "Doppelt."]
        ]
        object["exercise"] = ["id": "ex 1", "question": "", "category": "Ziel"]
        object["character_positions"] = [1, 2]
        let response = try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original)
        XCTAssertEqual(response.inputs.map(\.id), ["zeitraum"], "Missing placeholder and duplicate are dropped")
        XCTAssertEqual(response.inputs.first?.kind, .text, "A one-option choice becomes a text field")
        XCTAssertNil(response.exercise)
    }

    func testInvalidExplanationsAreDroppedButThePromptStays() throws {
        var object = base
        object["changes"] = [
            ["id": "c1", "kind": "replacement", "original_text": "Das stand nie da", "target_segment_ids": ["s2"], "category": "Ziel", "title": "X", "explanation": "Y"],
            ["id": "c2", "kind": "addition", "target_segment_ids": ["fehlt"], "category": "Ziel", "title": "X", "explanation": "Y", "rule_id": "https://example.com"]
        ]
        let response = try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original)
        XCTAssertTrue(response.changes.isEmpty)
        XCTAssertEqual(response.status, .improved)
        XCTAssertTrue(response.prompt.contains("Frau Berger"))
    }

    func testUnknownRuleIsRemovedAndDuplicateSegmentIDsAreRenamed() throws {
        var object = base
        object["segments"] = [
            ["id": "s1", "text": "Schreib eine kurze E-Mail an Frau Berger. Ich kann am 24. Oktober nicht. "],
            ["id": "s1", "text": "Schlag einen neuen Termin in [Zeitraum] vor."]
        ]
        object["changes"] = [["id": "c1", "kind": "addition", "target_segment_ids": ["s1"], "category": "Ziel", "title": "Kurz", "explanation": "Kürzer.", "rule_id": "erfunden-v9"]]
        let response = try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original)
        XCTAssertEqual(Set(response.segments.map(\.id)).count, 2)
        XCTAssertNil(response.changes.first?.ruleID)
    }

    func testAlreadyGoodWithStrayWhitespaceKeepsTheExactOriginal() throws {
        var object = base
        object["status"] = "already_good"
        object["segments"] = [["id": "s1", "text": original + " \n"]]
        object["changes"] = []
        let response = try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original)
        XCTAssertEqual(response.prompt, original)
        XCTAssertTrue(response.inputs.isEmpty)
    }

    func testRepairingChangeIDsNeverCollidesWithAKeptExplanation() throws {
        for secondID in ["c2x", "bad id", ""] {
            var object = base
            object["segments"] = [
                ["id": "s1", "text": original + " "],
                ["id": "s2", "text": "Fasse dich kurz. "],
                ["id": "s3", "text": "Schlage zwei Termine vor."]
            ]
            object["changes"] = [
                ["id": "c2x", "kind": "addition", "target_segment_ids": ["s2"], "category": "Länge", "title": "Kürzer", "explanation": "Die E-Mail bleibt übersichtlich."],
                ["id": secondID, "kind": "addition", "target_segment_ids": ["s3"], "category": "Ziel", "title": "Termine", "explanation": "Die Empfängerin kann einen Termin auswählen."]
            ]
            let cleaned = CoachSanitizer.clean(try answer(object), original: original)
            XCTAssertNoThrow(try CoachValidator.decode(cleaned, original: original))
            let response = try JSONDecoder().decode(CoachResponse.self, from: cleaned)
            XCTAssertEqual(response.changes.count, 2)
            XCTAssertEqual(Set(response.changes.map(\.id)).count, 2)
            XCTAssertEqual(response.changes.map(\.targetSegmentIDs), [["s2"], ["s3"]])
            XCTAssertEqual(response.prompt, original + " Fasse dich kurz. Schlage zwei Termine vor.")
        }
    }

    func testMetadataTrimmingKeepsWholeUnicodeCharactersAtTheUTF16Limit() {
        let text = " \u{0}Ä👩🏽‍💻e\u{301}終 \n"
        for (limit, expected) in [(0, ""), (1, "Ä"), (7, "Ä"), (8, "Ä👩🏽‍💻"), (9, "Ä👩🏽‍💻"),
                                  (10, "Ä👩🏽‍💻e\u{301}"), (11, "Ä👩🏽‍💻e\u{301}終"), (20, "Ä👩🏽‍💻e\u{301}終")] {
            XCTAssertEqual(CoachSanitizer.trimmed(text, limit: limit), expected)
        }
        XCTAssertEqual(CoachSanitizer.trimmed(" A\u{0}B\tC\nD\u{1B}E ", limit: 7), "AB\tC\nDE")
        XCTAssertEqual(CoachSanitizer.trimmed("a" + String(repeating: "\u{301}", count: 1_200), limit: 1_200), "",
                       "A single oversized composed character must not be split")
        XCTAssertEqual(CoachSanitizer.trimmed(String(repeating: "ä", count: 50_000), limit: 1_200), String(repeating: "ä", count: 1_200))
    }

    func testBrokenJSONStillFails() {
        XCTAssertThrowsError(try CoachValidator.decode(CoachSanitizer.clean("{invalid", original: original), original: original))
        XCTAssertThrowsError(try CoachValidator.decode(CoachSanitizer.clean("Kein JSON", original: original), original: original))
    }

    func testMalformedPromptSegmentsCannotBeSilentlyDropped() throws {
        for malformed: Any in [42, ["id": "lost", "text": false], ["id": "lost"]] {
            var object = base
            var segments = try XCTUnwrap(object["segments"] as? [Any])
            segments.insert(malformed, at: 1)
            object["segments"] = segments
            XCTAssertThrowsError(try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original))
        }
    }

    func testExplicitUnsupportedSchemaIsNotRewrittenAsCurrent() throws {
        for version: Any in [2, "future", true] {
            var object = base
            object["schema_version"] = version
            XCTAssertThrowsError(try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original))
        }
    }

    func testUnusedMalformedClarificationDoesNotDiscardAValidPrompt() throws {
        var object = base
        object["clarification"] = ["question": 42]
        let response = try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original)
        XCTAssertNil(response.clarification)
        XCTAssertTrue(response.prompt.contains("Frau Berger"))
        object["status"] = "needs_clarification"
        XCTAssertThrowsError(try CoachValidator.decode(CoachSanitizer.clean(try answer(object), original: original), original: original))
    }
}
