import XCTest
@testable import KlarCore

final class LearningFeaturesTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sinnfaden-learning-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func replacementFixture(original: String = "Erkläre Regen in drei Sätzen.", source: String = "in drei Sätzen", target: String = "in fünf Sätzen") -> CoachResponse {
        let range = original.range(of: source)!
        return CoachResponse(status: .improved, coachMessage: "Eine Änderung.", segments: [
            PromptSegment(id: "s1", text: String(original[..<range.lowerBound])),
            PromptSegment(id: "s2", text: target),
            PromptSegment(id: "s3", text: String(original[range.upperBound...]))
        ].filter { !$0.text.isEmpty }, changes: [PromptChange(id: "c1", kind: .replacement, originalText: source, targetSegmentIDs: ["s2"], category: "Länge", title: "Länge ändern", explanation: "Die Antwort soll mehr Raum haben.")])
    }

    func testComparisonIsolatesExactlyOneLiteralReplacement() throws {
        let original = "Erkläre Regen in drei Sätzen."
        let plan = try ComparisonPlan.make(original: original, response: replacementFixture(), changeID: "c1")
        XCTAssertEqual(plan.kind, .isolated)
        XCTAssertEqual(plan.baseline, original)
        XCTAssertEqual(plan.variant, "Erkläre Regen in fünf Sätzen.")
        XCTAssertTrue(plan.criterion.contains("Länge"))
    }

    func testComparisonUsesFilledAnswersForIsolatedAndWholePromptPlans() throws {
        let original = "Erkläre Regen in drei Sätzen."
        var response = replacementFixture(target: "in [Anzahl] Sätzen")
        response.inputs = [PromptInput(id: "length", label: "Länge", kind: .text, placeholder: "[Anzahl]", why: "Wähle die Länge.")]
        let values = ["length": "fünf"]
        let isolated = try ComparisonPlan.make(original: original, response: response, changeID: "c1", inputValues: values)
        XCTAssertEqual(isolated.kind, .isolated)
        XCTAssertEqual(isolated.variant, "Erkläre Regen in fünf Sätzen.")
        XCTAssertEqual(isolated.baseline, original)
        let whole = try ComparisonPlan.make(original: original, response: response, inputValues: values)
        XCTAssertEqual(whole.kind, .wholePrompt)
        XCTAssertEqual(whole.variant, try response.filled(with: values).prompt)
        XCTAssertTrue(response.prompt.contains("[Anzahl]"), "Preparing a comparison must not rewrite the saved response")
    }

    func testComparisonRejectsFilledIdentityAndOversizedOrInvalidFieldText() throws {
        let original = "Erkläre Regen in drei Sätzen."
        var response = replacementFixture(target: "in [Anzahl] Sätzen")
        response.inputs = [PromptInput(id: "length", label: "Länge", kind: .text, placeholder: "[Anzahl]", why: "Wähle die Länge.")]
        for value in ["drei", String(repeating: "a", count: 48_001), "fünf\u{0000}"] {
            XCTAssertThrowsError(try ComparisonPlan.make(original: original, response: response, changeID: "c1", inputValues: ["length": value]))
        }
    }

    func testRepeatedOriginalAndChangedClauseBoundariesUseExplicitWholeComparison() throws {
        let repeated = "Erkläre Regen in drei Sätzen. Erkläre Schnee in drei Sätzen."
        let repeatedPlan = try ComparisonPlan.make(original: repeated, response: replacementFixture(original: repeated), changeID: "c1")
        XCTAssertEqual(repeatedPlan.kind, .wholePrompt)
        XCTAssertTrue(repeatedPlan.note.contains("mehrere Ursachen"))
        let demoPlan = try ComparisonPlan.make(original: DemoContent.original, response: DemoContent.response, changeID: "c1")
        XCTAssertEqual(demoPlan.kind, .wholePrompt)
        XCTAssertEqual(demoPlan.variant, DemoContent.response.prompt)
    }

    func testComparisonAdditionUsesExactOriginalAnchorAndUnicode() throws {
        let original = "Erkläre Grüße 👩🏽‍💻 und Cafe\u{301}."
        let response = CoachResponse(status: .improved, coachMessage: "Form ergänzt.", segments: [PromptSegment(id: "s1", text: original), PromptSegment(id: "s2", text: "\nNutze drei Sätze.")], changes: [PromptChange(id: "a1", kind: .addition, targetSegmentIDs: ["s2"], category: "Ausgabe", title: "Form", explanation: "Die gewünschte Länge ist sichtbar.")])
        let plan = try ComparisonPlan.make(original: original, response: response, changeID: "a1")
        XCTAssertEqual(plan.kind, .isolated)
        XCTAssertEqual(plan.variant, original + "\nNutze drei Sätze.")
    }

    func testComparisonValidatesRecordsAndCannotInventAnEdit() {
        var response = replacementFixture()
        response.changes[0].originalText = "Diesen Text gab es nie"
        XCTAssertThrowsError(try ComparisonPlan.make(original: "Erkläre Regen in drei Sätzen.", response: response, changeID: "c1"))
        let unchanged = CoachResponse(status: .already_good, coachMessage: "Passt.", segments: [PromptSegment(id: "s1", text: "Hallo")])
        XCTAssertThrowsError(try ComparisonPlan.make(original: "Hallo", response: unchanged))
    }

    func testPartialWordEditUsesWholePromptComparison() throws {
        let original = "Beschreibe Sommerurlaub."
        let response = replacementFixture(original: original, source: "Sommer", target: "Winter")
        let plan = try ComparisonPlan.make(original: original, response: response, changeID: "c1")
        XCTAssertEqual(plan.kind, .wholePrompt)
        XCTAssertEqual(plan.variant, "Beschreibe Winterurlaub.")
    }

    func testComparisonRestartRetainsCompletedAnswerAndInterruptsOnlyRunningSide() throws {
        let root = try temporaryDirectory()
        let store = try LearningStore(accountID: "chatgpt:a", baseURL: root)
        let plan = try ComparisonPlan.make(original: "Erkläre Regen in drei Sätzen.", response: replacementFixture(), changeID: "c1")
        var state = LearningState()
        let run = ComparisonRun(plan: plan, model: "fixture-model-from-catalog", baselineAnswer: ComparisonAnswer(status: .completed, text: "Diese tatsächliche Testantwort bleibt erhalten."), variantAnswer: ComparisonAnswer(status: .running, text: "Teilantwort"))
        state.comparisons = [run]
        try store.save(state)
        let reopened = try LearningStore(accountID: "chatgpt:a", baseURL: root).load()
        XCTAssertEqual(reopened.comparisons[0].model, run.model)
        XCTAssertEqual(reopened.comparisons[0].baselineAnswer, run.baselineAnswer)
        XCTAssertEqual(reopened.comparisons[0].variantAnswer.status, .interrupted)
        XCTAssertEqual(reopened.comparisons[0].variantAnswer.text, "Teilantwort")
        XCTAssertFalse(reopened.comparisons[0].isComplete)
        // Reading state invokes no provider and cannot regenerate either answer.
    }

    func testEmptyComparisonCannotBeStoredAsCompleted() throws {
        let store = try LearningStore(accountID: "a", baseURL: temporaryDirectory())
        let plan = try ComparisonPlan.make(original: "Erkläre Regen in drei Sätzen.", response: replacementFixture(), changeID: "c1")
        var state = LearningState()
        state.comparisons = [ComparisonRun(plan: plan, model: "fixture", baselineAnswer: ComparisonAnswer(status: .completed))]
        XCTAssertThrowsError(try store.save(state))
    }

    func testAllSixLessonsHaveConcreteActionsAndFeedbackChangesWithActualAnswer() throws {
        XCTAssertEqual(LessonCatalog.lessons.count, 6)
        let independent: [String: String] = [
            "goal": "Bitte in der E-Mail um eine Rückmeldung zum Termin.",
            "context": "Der Spaziergang soll 20 Minuten dauern.",
            "audience": "Für Einsteiger, bitte einfach und freundlich.",
            "format": "Bitte als Tabelle mit drei Zeilen.",
            "followup": "Zeige mir ein konkretes Beispiel für den ersten Schritt.",
            "check": "Bitte korrigiere Mittwoch auf Dienstag; 16 Uhr bleibt."
        ]
        for lesson in LessonCatalog.lessons {
            XCTAssertFalse(lesson.action.isEmpty)
            XCTAssertFalse(lesson.hint.isEmpty)
            let answer = try XCTUnwrap(independent[lesson.id])
            let observed = LessonCatalog.evaluate(answer: answer, lesson: lesson)
            XCTAssertTrue(observed.independentApplication, lesson.id + ": " + observed.observation)
            XCTAssertTrue(observed.observation.contains(answer))
            let uncertain = LessonCatalog.evaluate(answer: "Keine Ahnung", lesson: lesson)
            XCTAssertFalse(uncertain.independentApplication)
            XCTAssertFalse(uncertain.meetsExercise)
            XCTAssertTrue(uncertain.observation.contains(lesson.action))
        }
    }

    func testLessonCopiesHintsAndNegatedFormatsAreNotIndependentSuccess() throws {
        let lesson = try XCTUnwrap(LessonCatalog.lookup("format"))
        XCTAssertFalse(LessonCatalog.evaluate(answer: lesson.solution, lesson: lesson).independentApplication)
        XCTAssertFalse(LessonCatalog.evaluate(answer: "Drei Stichpunkte", lesson: lesson, usedHint: true).independentApplication)
        XCTAssertFalse(LessonCatalog.evaluate(answer: "Drei Stichpunkte", lesson: lesson, revealedSolution: true).independentApplication)
        XCTAssertFalse(LessonCatalog.evaluate(answer: "Keine Tabelle mit fünf Zeilen", lesson: lesson).meetsExercise)
        XCTAssertFalse(LessonCatalog.evaluate(answer: "", lesson: lesson).independentApplication)
        let checking = try XCTUnwrap(LessonCatalog.lookup("check"))
        XCTAssertFalse(LessonCatalog.evaluate(answer: "Bitte korrigiere den falschen Wochentag.", lesson: checking).meetsExercise)
        XCTAssertFalse(LessonCatalog.evaluate(answer: "Bitte ändere Dienstag auf Mittwoch.", lesson: checking).meetsExercise)
        XCTAssertTrue(LessonCatalog.evaluate(answer: "Bitte Dienstag statt Mittwoch schreiben und die Uhrzeit behalten.", lesson: checking).meetsExercise)
    }

    func testFormatLessonConnectsLengthToOutputAndAllowsAnExplicitAlternative() throws {
        let lesson = try XCTUnwrap(LessonCatalog.lookup("format"))
        for answer in ["Bitte als Tabelle. Der Text handelt von drei Personen.", "Drei Tage später möchte ich eine Liste.", "Bitte keine Tabelle mit fünf Zeilen.", "Drei Stichpunkte bitte nicht."] {
            XCTAssertFalse(LessonCatalog.evaluate(answer: answer, lesson: lesson).meetsExercise, answer)
        }
        for answer in ["Bitte keine Tabelle, sondern drei kurze Stichpunkte.", "Statt einer Liste bitte zwei Absätze.", "Bitte als Tabelle mit maximal vier Zeilen.", "In einem kurzen Satz."] {
            XCTAssertTrue(LessonCatalog.evaluate(answer: answer, lesson: lesson).meetsExercise, answer)
        }
        let missingLength = LessonCatalog.evaluate(answer: "Bitte als Tabelle.", lesson: lesson)
        XCTAssertTrue(missingLength.observation.contains("Länge"))
        XCTAssertFalse(missingLength.independentApplication)
    }

    func testCheckingLessonDoesNotRewardWrongDayOrChangedTime() throws {
        let lesson = try XCTUnwrap(LessonCatalog.lookup("check"))
        for answer in ["Mittwoch ist richtig, Dienstag ist falsch. Bitte korrigiere.", "Bitte korrigiere Mittwoch auf Dienstag um 17 Uhr.", "Bitte korrigiere nicht den Tag von Mittwoch auf Dienstag."] {
            XCTAssertFalse(LessonCatalog.evaluate(answer: answer, lesson: lesson).meetsExercise, answer)
        }
        for answer in ["In meiner Anfrage steht Dienstag, in der Antwort Mittwoch. Bitte korrigiere den Tag.", "Dienstag in meiner Anfrage wurde zu Mittwoch. Bitte korrigiere das."] {
            XCTAssertTrue(LessonCatalog.evaluate(answer: answer, lesson: lesson).meetsExercise, answer)
        }
    }

    func testLessonsDoNotCountNegatedRequestsAsLearningEvidence() throws {
        let cases: [(String, String)] = [
            ("goal", "Bitte keine Einladung und keine Absage."),
            ("context", "Plane einen Spaziergang, aber keine 20 Minuten."),
            ("context", "Plane einen Spaziergang ab morgen."),
            ("context", "Plane einen Spaziergang ab dem nächsten Montag."),
            ("audience", "Nicht für Kinder und bitte nicht freundlich."),
            ("followup", "Bitte keine konkreten Schritte und kein Beispiel.")
        ]
        for (id, answer) in cases {
            let lesson = try XCTUnwrap(LessonCatalog.lookup(id))
            let feedback = LessonCatalog.evaluate(answer: answer, lesson: lesson)
            XCTAssertFalse(feedback.meetsExercise, answer)
            XCTAssertFalse(feedback.independentApplication, answer)
        }
    }

    func testLessonsAcceptAConcreteAlternativeAfterANegatedRequest() throws {
        let cases: [(String, String)] = [
            ("goal", "Bitte keine Einladung, sondern eine Absage zum Termin."),
            ("context", "Plane einen Spaziergang. Start am Bahnhof."),
            ("context", "Der Start ist am Bahnhof."),
            ("context", "Plane einen Spaziergang ab Wien Mitte."),
            ("context", "Bitte nicht mehr als 20 Minuten gehen."),
            ("audience", "Nicht für Kinder, sondern für Erwachsene. Schreibe sachlich und klar."),
            ("audience", "Für eine Person ohne Vorkenntnisse. Bitte freundlich erklären."),
            ("followup", "Bitte statt allgemeiner Tipps drei konkrete Schritte.")
        ]
        for (id, answer) in cases {
            let lesson = try XCTUnwrap(LessonCatalog.lookup(id))
            XCTAssertTrue(LessonCatalog.evaluate(answer: answer, lesson: lesson).meetsExercise, answer)
        }
    }

    func testScaffoldRequiresDistinctIndependentApplicationsForSamePrinciple() throws {
        let lesson = try XCTUnwrap(LessonCatalog.lookup("format"))
        func attempt(_ answer: String, hint: Bool = false) -> LessonAttempt {
            LessonAttempt(lessonID: lesson.id, answer: answer, feedback: LessonCatalog.evaluate(answer: answer, lesson: lesson, usedHint: hint), usedHint: hint)
        }
        let one = attempt("Drei Stichpunkte")
        XCTAssertEqual(LessonCatalog.stage(for: [one, one], lessonID: lesson.id), .guided)
        XCTAssertEqual(LessonCatalog.stage(for: [one, attempt("Eine Tabelle mit vier Zeilen")], lessonID: lesson.id), .independent)
        XCTAssertEqual(LessonCatalog.stage(for: [one, attempt("Zwei Absätze", hint: true)], lessonID: lesson.id), .guided)
        XCTAssertEqual(LessonCatalog.stage(for: [one, attempt("Zwei Absätze"), attempt("Vier Sätze"), attempt("Fünf Stichpunkte")], lessonID: lesson.id), .transfer)
    }

    func testRecipeLiveRenderRequiredAndExplicitUnknownPreserveExactValue() {
        var recipe = PromptRecipe(title: "Mail", template: "Für {{person}}:\n{{text}}", fields: [RecipeField(id: "person", label: "Empfänger"), RecipeField(id: "text", label: "Text")])
        XCTAssertFalse(recipe.render().isReady)
        XCTAssertEqual(recipe.render().missingRequired, ["Empfänger", "Text"])
        recipe.values = ["person": "[Empfänger noch offen]", "text": "Grüße 👩🏽‍💻\n& # + % \"Zitat\" {{person}}"]
        let rendered = recipe.render()
        XCTAssertTrue(rendered.isReady)
        XCTAssertEqual(rendered.unknownFields, ["Empfänger"])
        XCTAssertEqual(rendered.text, "Für [Empfänger noch offen]:\nGrüße 👩🏽‍💻\n& # + % \"Zitat\" {{person}}")
    }

    func testOversizedRecipeDraftDoesNotBlockSavingUnrelatedLearningWork() throws {
        let store = try LearningStore(accountID: "recipe-draft", baseURL: temporaryDirectory())
        let recipe = PromptRecipe(title: "Textvorlage", template: "Fasse {{text}} zusammen.",
                                  fields: [RecipeField(id: "text", label: "Ausgangstext")],
                                  values: ["text": String(repeating: "a", count: 24_001)])
        XCTAssertFalse(recipe.render().isReady)
        let state = LearningState(recipes: [recipe], lessonDrafts: ["goal": "Unabhängige Lernantwort"],
                                  followUp: FollowUpDraft(answer: "Unabhängiger Folgeentwurf"))
        XCTAssertNoThrow(try store.save(state))
        var restored = try store.load()
        XCTAssertTrue(restored.recipes.first?.values["text"] == recipe.values["text"], "Preserve the complete oversized draft")
        XCTAssertEqual(restored.lessonDrafts["goal"], "Unabhängige Lernantwort")
        XCTAssertEqual(restored.followUp.answer, "Unabhängiger Folgeentwurf")
        if !restored.recipes.isEmpty { restored.recipes[0].values["text"] = "Gekürzter Text" }
        try store.save(restored)
        XCTAssertEqual(try store.load().recipes.first?.render().text, "Fasse Gekürzter Text zusammen.")
        XCTAssertEqual(try store.load().recipes.first?.render().isReady, true)
    }

    func testRepeatedRecipeFieldsStopExpansionBeforeCreatingOversizedPreview() {
        let recipe = PromptRecipe(title: "Wiederholung", template: String(repeating: "{{text}} ", count: 100),
                                  fields: [RecipeField(id: "text", label: "Text")],
                                  values: ["text": String(repeating: "a", count: 2_000)])
        let rendered = recipe.render()
        XCTAssertFalse(rendered.isReady)
        XCTAssertFalse(rendered.validationErrors.isEmpty)
        XCTAssertLessThanOrEqual(rendered.text.utf16.count, 48_000)
        XCTAssertEqual(recipe.values["text"]?.count, 2_000, "The user's stored answer must remain intact")
    }

    func testRecipePreviewAcceptsExactUTF16LimitAndRejectsOnlyLargerOutput() {
        let value = String(repeating: "🧵", count: 12_000)
        var recipe = PromptRecipe(title: "Grenze", template: "{{text}}{{text}}",
                                  fields: [RecipeField(id: "text", label: "Text")], values: ["text": value])
        XCTAssertTrue(recipe.render().isReady)
        XCTAssertTrue(recipe.render().text == value + value)
        recipe.template += "!"
        XCTAssertFalse(recipe.render().isReady)
        XCTAssertLessThanOrEqual(recipe.render().text.utf16.count, 48_000)
    }

    func testRecipeDraftStorageStillRejectsInvalidDefinitionsWithoutReplacingFile() throws {
        let store = try LearningStore(accountID: "recipe-invalid", baseURL: temporaryDirectory())
        let valid = LearningState(lessonDrafts: ["goal": "Behalten"])
        try store.save(valid)
        let before = try Data(contentsOf: store.fileURL)
        for template in ["{{missing}}", "{{offen", String(repeating: "x", count: 48_001)] {
            let invalid = PromptRecipe(title: "Fehler", template: template)
            XCTAssertThrowsError(try store.save(LearningState(recipes: [invalid])))
            XCTAssertEqual(try Data(contentsOf: store.fileURL), before)
        }
    }

    func testRecipeRejectsMalformedAndUndefinedPlaceholders() {
        var recipe = PromptRecipe(title: "Fehler", template: "{{nicht_definiert}}")
        XCTAssertFalse(recipe.render().isReady)
        XCTAssertFalse(recipe.render().validationErrors.isEmpty)
        recipe.template = "{{offen"
        XCTAssertFalse(recipe.render().validationErrors.isEmpty)
        recipe = PromptRecipe(title: "Duplikat", template: "{{ziel}}", fields: [RecipeField(id: "ziel", label: "Ziel"), RecipeField(id: "ziel", label: "Noch einmal")])
        XCTAssertFalse(recipe.render().validationErrors.isEmpty)
    }

    func testRecipeVersionsAndUseSnapshotsSurviveEditingDuplicationDeletion() throws {
        var state = LearningState(recipes: [])
        var recipe = PromptRecipe(title: "Mein Rezept", template: "Erkläre {{thema}}.", fields: [RecipeField(id: "thema", label: "Thema")], values: ["thema": "Regen"])
        try state.upsertRecipe(recipe)
        state.recipeUses.append(RecipeUse(recipe: recipe, renderedText: recipe.render().text))
        recipe.values["thema"] = "Schnee"
        try state.upsertRecipe(recipe)
        XCTAssertEqual(state.recipes[0].version, 1)
        XCTAssertTrue(state.recipeVersions.isEmpty)
        recipe.title = "Meine Erklärung"
        try state.upsertRecipe(recipe)
        XCTAssertEqual(state.recipes[0].version, 2)
        XCTAssertEqual(state.recipeVersions.count, 1)
        XCTAssertEqual(state.recipeUses[0].renderedText, "Erkläre Regen.")
        let duplicateID = try state.duplicateRecipe(id: recipe.id)
        XCTAssertNotEqual(duplicateID, recipe.id)
        XCTAssertEqual(state.recipes.last?.version, 1)
        state.deleteRecipe(id: recipe.id)
        XCTAssertEqual(state.recipes.count, 1)
        XCTAssertEqual(state.recipeUses[0].recipe.title, "Mein Rezept")
    }

    func testDuplicatingMaximumLengthTitleKeepsEntireStateSaveable() throws {
        let store = try LearningStore(accountID: "long-title", baseURL: temporaryDirectory())
        let recipe = PromptRecipe(title: String(repeating: "🧵", count: 160), template: "Erkläre Regen.")
        var state = LearningState(recipes: [recipe])
        let duplicateID = try state.duplicateRecipe(id: recipe.id)
        let duplicate = try XCTUnwrap(state.recipes.first { $0.id == duplicateID })
        XCTAssertEqual(duplicate.title.count, 160)
        XCTAssertTrue(duplicate.title.hasSuffix(" – Kopie"))
        XCTAssertEqual(state.recipes.first?.title, recipe.title)
        XCTAssertTrue(duplicate.render().validationErrors.isEmpty)
        XCTAssertNoThrow(try store.save(state))
        XCTAssertEqual(try store.load().recipes.count, 2)
    }

    func testInvalidDuplicateDoesNotMutateState() throws {
        let invalid = PromptRecipe(title: "Noch ungültig", template: "{{fehlend}}")
        var state = LearningState(recipes: [invalid])
        XCTAssertThrowsError(try state.duplicateRecipe(id: invalid.id))
        XCTAssertEqual(state.recipes, [invalid])
    }

    func testAccountPersistenceFollowupDraftsExportAndDeletion() throws {
        let root = try temporaryDirectory()
        let first = try LearningStore(accountID: "chatgpt:a", baseURL: root)
        let second = try LearningStore(accountID: "api:a", baseURL: root)
        var state = LearningState()
        state.recipes[0].values["empfaenger"] = "Frau Özdemir"
        state.followUp = FollowUpDraft(sourcePrompt: "Original", answer: "Wirklich eingefügte Antwort", desiredChange: "Weniger allgemein", clarification: "Für welchen Bereich?", clarificationAnswer: "Alltag", generatedOriginal: "Vergleichsbasis", editedPrompt: "Eigene Nachfrage")
        state.lessonDrafts["goal"] = "Mein noch unfertiger Versuch"
        state.lessonHelp["goal"] = true
        try first.save(state)
        XCTAssertEqual(try LearningStore(accountID: "chatgpt:a", baseURL: root).load(), state)
        XCTAssertNotEqual(first.fileURL, second.fileURL)
        XCTAssertEqual(try second.load().followUp.answer, "")
        let exported = try XCTUnwrap(JSONSerialization.jsonObject(with: first.exportData()) as? [String: Any])
        XCTAssertEqual(exported["schemaVersion"] as? Int, 1)
        XCTAssertTrue(String(decoding: try first.exportData(), as: UTF8.self).contains("Frau Özdemir"))
        try first.deleteAll()
        XCTAssertTrue(try first.load().recipes.isEmpty)
        XCTAssertTrue(try first.load().lessonDrafts.isEmpty)
        XCTAssertEqual(try first.load().followUp, FollowUpDraft())
        XCTAssertEqual(try second.load().recipes.count, PromptRecipe.starterRecipes.count)
    }

    func testLearningStorePreservesExistingHistoryAndGuardsNewerOrCorruptFiles() throws {
        let root = try temporaryDirectory()
        let history = try HistoryStore(accountID: "same-account", baseURL: root)
        try history.saveDraft("Vor dem Namenwechsel geschrieben")
        let learning = try LearningStore(accountID: "same-account", baseURL: root)
        XCTAssertEqual(learning.fileURL.deletingLastPathComponent(), history.databaseURL.deletingLastPathComponent())
        try learning.save(LearningState())
        XCTAssertEqual(try history.loadDraft(), "Vor dem Namenwechsel geschrieben")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: learning.exportData()) as? [String: Any])
        object["schemaVersion"] = 99
        let newer = try JSONSerialization.data(withJSONObject: object)
        try newer.write(to: learning.fileURL)
        XCTAssertThrowsError(try learning.load())
        XCTAssertThrowsError(try learning.save(LearningState()))
        XCTAssertEqual(try Data(contentsOf: learning.fileURL), newer)
        try Data("{\"schemaVersion\":1}".utf8).write(to: learning.fileURL)
        XCTAssertThrowsError(try learning.save(LearningState()))
        XCTAssertEqual(try String(contentsOf: learning.fileURL), "{\"schemaVersion\":1}")
        try Data("broken".utf8).write(to: learning.fileURL)
        XCTAssertThrowsError(try learning.load())
        XCTAssertThrowsError(try learning.save(LearningState()))
        XCTAssertEqual(try String(contentsOf: learning.fileURL), "broken")
        try learning.deleteAll()
        XCTAssertTrue(try learning.load().recipes.isEmpty)
        XCTAssertEqual(try history.loadDraft(), "Vor dem Namenwechsel geschrieben")
    }

    func testEditableStarterRecipesHaveValidDefinitions() {
        XCTAssertGreaterThanOrEqual(PromptRecipe.starterRecipes.count, 3)
        for recipe in PromptRecipe.starterRecipes {
            XCTAssertTrue(recipe.render().validationErrors.isEmpty, recipe.title)
            XCTAssertFalse(recipe.render().isReady, "Starter recipe should still need the user's actual details")
        }
    }
}
