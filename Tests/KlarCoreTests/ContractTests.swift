import XCTest
@testable import KlarCore

final class ContractTests: XCTestCase {
    func testGermanDemoDecodesAndCopiesSameSegments() throws {
        let data = try JSONEncoder().encode(DemoContent.response)
        let response = try CoachValidator.decode(data, original: DemoContent.original)
        XCTAssertEqual(response.prompt, response.segments.map(\.text).joined())
        for fact in ["Frau Berger", "24. Oktober", "14 Uhr", "kurze", "freundliche"] { XCTAssertTrue(response.prompt.contains(fact)) }
        XCTAssertEqual(response.changes.count, 3)
        XCTAssertEqual(response.inputs.count, 3)
    }

    func testGeneratedInputsFillTheirPlaceholdersAndKeepSegments() throws {
        let filled = DemoContent.response.filled(with: ["name": "Alex", "zeitraum": "nächste Woche vormittags", "ton": ""])
        XCTAssertTrue(filled.prompt.contains("Verwende für meinen Namen Alex."))
        XCTAssertTrue(filled.prompt.contains("für nächste Woche vormittags."))
        XCTAssertTrue(filled.prompt.contains("[Ton]"), "An empty answer keeps the visible placeholder")
        XCTAssertEqual(filled.segments.map(\.id), DemoContent.response.segments.map(\.id))
        XCTAssertEqual(filled.changes, DemoContent.response.changes)
    }

    func testFillingFieldsNeverReinterpretsTheUsersTextAsAnotherPlaceholder() {
        let response = CoachResponse(status: .improved, coachMessage: "Ergänze die Angaben.",
            segments: [PromptSegment(id: "s1", text: "[Name]: [Text]. Noch einmal: [Name]")], inputs: [
                PromptInput(id: "name", label: "Name", kind: .text, placeholder: "[Name]", why: "Wer ist gemeint?"),
                PromptInput(id: "text", label: "Text", kind: .long_text, placeholder: "[Text]", why: "Was ist wichtig?")
            ])
        let filled = response.filled(with: ["name": "[Text]", "text": "  Grüße 👩🏽‍💻\n[Name]  "])
        XCTAssertEqual(filled.prompt, "[Text]:   Grüße 👩🏽‍💻\n[Name]  . Noch einmal: [Text]")
        XCTAssertEqual(response.prompt, "[Name]: [Text]. Noch einmal: [Name]")
        var reversed = response
        reversed.inputs.reverse()
        XCTAssertEqual(reversed.filled(with: ["name": "[Text]", "text": "  Grüße 👩🏽‍💻\n[Name]  "]).prompt, filled.prompt)
    }

    func testFieldSplitAcrossSegmentsStillFillsAndPreservesSegmentIdentities() {
        let response = CoachResponse(status: .improved, coachMessage: "Ergänze den Namen.", segments: [
            PromptSegment(id: "before", text: "Grüße 👩🏽‍💻 [Na"),
            PromptSegment(id: "middle", text: "me"),
            PromptSegment(id: "after", text: "]! Und [Name].")
        ], inputs: [PromptInput(id: "name", label: "Name", kind: .text, placeholder: "[Name]", why: "Wer ist gemeint?")])
        let filled = response.filled(with: ["name": "Özdemir"])
        XCTAssertEqual(filled.prompt, "Grüße 👩🏽‍💻 Özdemir! Und Özdemir.")
        XCTAssertEqual(filled.segments.map(\.id), response.segments.map(\.id))
        XCTAssertEqual(response.filled(with: ["name": " \n "]).prompt, response.prompt)
    }

    func testInputCannotReplaceAnOrdinaryWordOrAnInvalidBracketToken() {
        for placeholder in ["Berger", "[]", "[ ]", "[[Name]]", "[Name\rZusatz]"] {
            let response = CoachResponse(status: .improved, coachMessage: "Ergänze den Namen.",
                segments: [PromptSegment(id: "s1", text: "Schreibe an \(placeholder).")],
                inputs: [PromptInput(id: "name", label: "Name", kind: .text, placeholder: placeholder, why: "Wer ist gemeint?")])
            XCTAssertThrowsError(try CoachValidator.validate(response, original: "Schreibe eine Mail."), placeholder)
        }
    }

    func testInputsMustMatchPlaceholdersAndOptions() throws {
        var response = DemoContent.response
        response.inputs[0].placeholder = "[Gibt es nicht]"
        XCTAssertThrowsError(try CoachValidator.validate(response, original: DemoContent.original))
        response = DemoContent.response
        response.inputs[2].options = ["nur eine"]
        XCTAssertThrowsError(try CoachValidator.validate(response, original: DemoContent.original))
        response = DemoContent.response
        response.inputs[1].id = response.inputs[0].id
        XCTAssertThrowsError(try CoachValidator.validate(response, original: DemoContent.original))
    }

    func testOlderAnswersWithoutInputsStillDecode() throws {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DemoContent.response)) as! [String: Any]
        object.removeValue(forKey: "inputs")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(CoachResponse.self, from: data)
        XCTAssertTrue(decoded.inputs.isEmpty)
    }

    func testAlreadyGoodRequiresExactUnchangedTextAndZeroChanges() throws {
        let original = "Erkläre mir in drei kurzen Absätzen, wie ein Regenbogen entsteht. Verwende keine Formeln."
        var response = CoachResponse(status: .already_good, coachMessage: "Dein Prompt ist schon klar.", segments: [PromptSegment(id: "s1", text: original)])
        XCTAssertNoThrow(try CoachValidator.validate(response, original: original))
        response.segments[0].text += " "
        XCTAssertThrowsError(try CoachValidator.validate(response, original: original))
    }

    func testUnicodeRangesStayAttachedToRepeatedTextAndNewlines() throws {
        let texts = ["Grüße 👩🏽‍💻 ", "Cafe\u{301}", "\nGrüße ", "👨‍👩‍👧‍👦", "\nEnde"]
        let response = CoachResponse(status: .already_good, coachMessage: "Passt.", segments: texts.enumerated().map { PromptSegment(id: "s\($0.offset)", text: $0.element) })
        try CoachValidator.validate(response, original: texts.joined())
        for segment in response.segments {
            let range = try XCTUnwrap(response.segmentRanges[segment.id])
            XCTAssertEqual((response.prompt as NSString).substring(with: range), segment.text)
        }
        XCTAssertNotEqual(response.segmentRanges["s0"]?.length, texts[0].count)
        XCTAssertEqual(response.segmentRanges["s2"]?.location, (texts[0] + texts[1]).utf16.count)
        let splitGrapheme = CoachResponse(status: .already_good, coachMessage: "Passt.", segments: [PromptSegment(id: "s1", text: "e"), PromptSegment(id: "s2", text: "\u{301}")])
        XCTAssertThrowsError(try CoachValidator.validate(splitGrapheme, original: "e\u{301}"))
    }

    func testDeletionHasNoTargetAndMustQuoteOriginal() throws {
        let original = "Sei ein Supergenie! Erkläre Regen."
        let change = PromptChange(id: "d1", kind: .deletion, originalText: "Sei ein Supergenie! ", category: "Kürzen", title: "Direkt fragen", explanation: "Die zusätzliche Rolle ist hier nicht nötig.", ruleID: "direct-v1")
        var response = CoachResponse(status: .improved, coachMessage: "Die Frage genügt.", segments: [PromptSegment(id: "s1", text: "Erkläre Regen.")], changes: [change])
        XCTAssertNoThrow(try CoachValidator.validate(response, original: original))
        XCTAssertEqual(response.removedChanges.count, 1)
        response.changes[0].targetSegmentIDs = ["s1"]
        XCTAssertThrowsError(try CoachValidator.validate(response, original: original))
    }

    func testInvalidReferencesDuplicateIDsAndInventedQuotesAreRejected() {
        var response = DemoContent.response
        response.changes[0].targetSegmentIDs = ["nonexistent"]
        XCTAssertThrowsError(try CoachValidator.validate(response, original: DemoContent.original))
        response = DemoContent.response
        response.segments[1].id = "s1"
        XCTAssertThrowsError(try CoachValidator.validate(response, original: DemoContent.original))
        response = DemoContent.response
        response.changes[0].originalText = "Das habe ich nie geschrieben."
        XCTAssertThrowsError(try CoachValidator.validate(response, original: DemoContent.original))
        response = DemoContent.response
        response.changes[0].ruleID = "https://untrusted.example"
        XCTAssertThrowsError(try CoachValidator.validate(response, original: DemoContent.original))
    }

    func testClarificationIsSeparateFromFinishedPrompt() throws {
        var response = CoachResponse(status: .needs_clarification, coachMessage: "Eine Angabe würde helfen.", segments: [], clarification: Clarification(question: "Für wie viele Personen planst du?"))
        try CoachValidator.validate(response, original: "Plane ein Essen.")
        response.segments = [PromptSegment(id: "s1", text: "Plane ein Essen für vier Personen.")]
        XCTAssertThrowsError(try CoachValidator.validate(response, original: "Plane ein Essen."))
    }

    func testSchemaMissingFieldsOversizeAndPartialJSONRejected() throws {
        for text in ["{\"status\":\"improved\"}", "{", "```json\n{}\n```", "null"] {
            XCTAssertThrowsError(try CoachValidator.decode(Data(text.utf8), original: "Hallo"))
        }
        var response = DemoContent.response
        response.schemaVersion = 999
        XCTAssertThrowsError(try CoachValidator.validate(response, original: DemoContent.original))
        XCTAssertThrowsError(try CoachValidator.decode(Data(repeating: 32, count: 256_001), original: "Hallo"))
    }

    func testFalseAnnotationsAndModelProvidedPositionsAreRejected() throws {
        var response = DemoContent.response
        response.changes[0].targetSegmentIDs = ["s4", "s2"]
        XCTAssertThrowsError(try CoachValidator.validate(response, original: DemoContent.original))
        response = CoachResponse(status: .improved, coachMessage: "Geändert.", segments: [PromptSegment(id: "s1", text: "Hallo Welt!")], changes: [PromptChange(id: "c1", kind: .addition, targetSegmentIDs: ["s1"], category: "Ziel", title: "Neu", explanation: "Ein Zusatz.")])
        XCTAssertThrowsError(try CoachValidator.validate(response, original: "Hallo Welt! Noch mehr Text."))
        response.changes = [PromptChange(id: "d1", kind: .deletion, originalText: "Hallo", category: "Kürzen", title: "Entfernt", explanation: "Nicht mehr da.")]
        XCTAssertThrowsError(try CoachValidator.validate(response, original: "Hallo Welt! Noch mehr Text."))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(DemoContent.response)) as? [String: Any])
        object["character_positions"] = [4, 12]
        XCTAssertThrowsError(try CoachValidator.decode(JSONSerialization.data(withJSONObject: object), original: DemoContent.original))
    }

    func testRepresentativeTasksCanHaveHonestUnchangedState() throws {
        let tasks = [
            "Schreibe eine freundliche E-Mail an Herrn Özdemir: Bitte verschiebe unseren Termin vom 12.11. um 9 Uhr. Erfinde keinen Grund.",
            "Erkläre mir Photosynthese in verständlichem Deutsch mit einem Beispiel, ohne Formeln.",
            "Plane einen Spaziergang von höchstens 30 Minuten. Start und Ende: [Ort]. Frage nach dem Ort, bevor du eine Route vorschlägst.",
            "Fasse [Text] in fünf Stichpunkten zusammen. Ergänze keine Fakten, die nicht im Text stehen.",
            "Schreibe eine kurze Geschichte über einen verlorenen Schlüssel, mit offenem Ende.",
            "Erstelle einen wiederverwendbaren Prompt für meine Wochenplanung: Frage nach Aufgaben, festen Terminen und freier Zeit. Liefere eine Tabelle und prüfe Überschneidungen."
        ]
        for task in tasks {
            let response = CoachResponse(status: .already_good, coachMessage: "Dein Prompt ist schon klar.", segments: [PromptSegment(id: "s1", text: task)])
            try CoachValidator.validate(response, original: task)
            XCTAssertEqual(response.prompt, task)
        }
        // Contract fixtures only: these are not claims of model performance.
    }
}
