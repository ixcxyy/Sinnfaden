import Foundation

public enum TutorPrompt {
    public static let version = 1
    public static var instructions: String {
        guard let url = Bundle.module.url(forResource: "tutor-v1", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            preconditionFailure("Die mitgelieferte Tutor-Instruktion fehlt.")
        }
        return text
    }
}

public enum DemoContent {
    public static let original = "Schreib eine E-Mail an Frau Berger. Ich kann am 24. Oktober um 14 Uhr nicht und möchte einen neuen Termin. Bitte kurz und freundlich."
    public static let response = CoachResponse(
        status: .improved,
        coachMessage: "Dein Anliegen ist klar. Drei Angaben fehlen noch – füll sie hier aus, dann muss ChatGPT nicht nachfragen.",
        segments: [
            PromptSegment(id: "s1", text: "Schreib eine kurze, freundliche E-Mail an Frau Berger. Ich kann am 24. Oktober um 14 Uhr nicht. "),
            PromptSegment(id: "s2", text: "Bitte sie um einen neuen Terminvorschlag für [Zeitraum]."),
            PromptSegment(id: "s3", text: "\n\n"),
            PromptSegment(id: "s4", text: "Erfinde keinen Grund für die Absage. Verwende für meinen Namen [Dein Name]."),
            PromptSegment(id: "s5", text: " Der Ton soll [Ton] sein.")
        ],
        changes: [
            PromptChange(id: "c1", kind: .replacement, originalText: "möchte einen neuen Termin", targetSegmentIDs: ["s2"], category: "Ziel", title: "Sag, was als Nächstes passieren soll", explanation: "Damit ist klar, dass Frau Berger einen neuen Termin vorschlagen soll – und in welchem Zeitraum er dir passt.", ruleID: "goal-v1"),
            PromptChange(id: "c2", kind: .addition, targetSegmentIDs: ["s4"], category: "Kontext", title: "Fehlendes bleibt erkennbar", explanation: "So werden weder ein Absagegrund noch dein Name ergänzt, obwohl du sie nicht angegeben hast.", ruleID: "unknowns-v1"),
            PromptChange(id: "c3", kind: .addition, targetSegmentIDs: ["s5"], category: "Format", title: "Ton ausdrücklich festlegen", explanation: "„Freundlich“ kann vieles heißen. Ein klar gewählter Ton macht die Antwort vorhersehbarer.", ruleID: "direct-v1")
        ],
        unknowns: ["Dein Name fehlt. Er bleibt als [Dein Name] bearbeitbar."],
        exercise: CoachExercise(id: "ex-goal", question: "Welche Information würdest du ergänzen, damit ein neuer Termin für dich passt?", category: "Kontext"),
        inputs: [
            PromptInput(id: "zeitraum", label: "Wann passt es dir?", kind: .multi_choice, placeholder: "[Zeitraum]", options: ["nächste Woche vormittags", "nächste Woche nachmittags", "übernächste Woche"], required: true, why: "So schlägt Frau Berger gleich einen passenden Termin vor."),
            PromptInput(id: "name", label: "Dein Name", kind: .text, placeholder: "[Dein Name]", required: true, why: "Damit die E-Mail mit deinem Namen endet."),
            PromptInput(id: "ton", label: "Ton", kind: .scale, placeholder: "[Ton]", options: ["locker", "freundlich", "förmlich"], suggestion: "freundlich", why: "Du hast „freundlich“ geschrieben – hier kannst du es genauer festlegen.")
        ]
    )
}
