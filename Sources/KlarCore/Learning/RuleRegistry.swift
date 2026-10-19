import Foundation

public struct LearningRule: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let sourceURL: URL
    public let evidenceType: String
    public let scope: String
    public let checkedAt: String
}

/// Versioned, locally reviewed sources. Model output may reference IDs, never supply source URLs.
public enum RuleRegistry {
    public static let version = 1
    public static let rules: [LearningRule] = [
        LearningRule(id: "goal-v1", title: "Das Ziel benennen", summary: "Ein konkretes Ziel und ausdrücklich genannte Grenzen helfen beim Formulieren der gewünschten Antwort. Das ist eine Anbieterempfehlung; ihr Nutzen hängt von der Aufgabe ab.", sourceURL: URL(string: "https://developers.openai.com/api/docs/guides/reasoning-best-practices")!, evidenceType: "Anbieterempfehlung", scope: "Prompts für OpenAI-Reasoning-Modelle; keine Wirksamkeitsgarantie", checkedAt: "2026-10-18"),
        LearningRule(id: "direct-v1", title: "Einfach und direkt schreiben", summary: "Klare, direkte Anweisungen genügen oft. Zusätzliche Rollen und lange Gedankenprotokolle sind kein Selbstzweck.", sourceURL: URL(string: "https://developers.openai.com/api/docs/guides/reasoning-best-practices")!, evidenceType: "Anbieterempfehlung", scope: "OpenAI-Reasoning-Modelle; auf andere Modelle nur mit Prüfung übertragen", checkedAt: "2026-10-18"),
        LearningRule(id: "examples-v1", title: "Beispiele mit Erklärung", summary: "Eine Studie mit 245 Studierenden zeigte bei einer von zwei Aufgaben Vorteile für die bewertete Promptkonstruktion. Bei der KI-Ausgabe gab es keinen signifikanten Vorteil gegenüber Anweisungen allein. Das ist kein Wirksamkeitsnachweis für Sinnfaden.", sourceURL: URL(string: "https://pubs.wi-kassel.de/wp-content/uploads/2024/10/JML_990.pdf")!, evidenceType: "Empirischer Befund", scope: "Tolzin, Knoth & Janson (ICIS 2024), Studierende und zwei konkrete Aufgaben", checkedAt: "2026-10-18"),
        LearningRule(id: "retrieval-v1", title: "Selbst versuchen", summary: "Eigenes Abrufen kann spätere Erinnerung unterstützen. Die zugrunde liegende Untersuchung nutzte Sachtexte; sie prüfte weder Promptkompetenz noch Sinnfaden.", sourceURL: URL(string: "https://learninglab.psych.purdue.edu/downloads/2006/2006_Roediger_Karpicke_PsychSci.pdf")!, evidenceType: "Empirischer Befund", scope: "Roediger & Karpicke (2006), Erinnern von Textinhalten", checkedAt: "2026-10-18"),
        LearningRule(id: "check-v1", title: "Die Antwort prüfen", summary: "Formulierungen und Formate können Modellantworten beeinflussen. Deshalb zählt das tatsächliche Ergebnis. Befunde mit älteren Modellen liefern keine Effektgröße für heutiges ChatGPT.", sourceURL: URL(string: "https://proceedings.iclr.cc/paper_files/paper/2024/hash/6c0e99d736da621403018ca7b32b1a4d-Abstract-Conference.html")!, evidenceType: "Empirischer Befund", scope: "Sclar et al. (ICLR 2024), Formatvariation in Few-shot-Aufgaben älterer offener Modelle", checkedAt: "2026-10-18"),
        LearningRule(id: "unknowns-v1", title: "Unbekanntes sichtbar lassen", summary: "Sinnfaden fragt nach entscheidenden Lücken und kennzeichnet andere fehlende Angaben. Namen, Zahlen, Termine, Stimme und Grenzen bleiben erhalten. Das ist eine Gestaltungsregel dieser App.", sourceURL: URL(string: "https://developers.openai.com/api/docs/guides/reasoning-best-practices")!, evidenceType: "Produktentscheidung", scope: "Sinnfaden Tutorvertrag Version 1; verlinkte Anbieterempfehlung ist Hintergrund, kein empirischer Beleg für diese Regel", checkedAt: "2026-10-18")
    ]
    public static func lookup(_ id: String) -> LearningRule? { rules.first { $0.id == id } }
}

public struct PracticeAttempt: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var answer: String
    public var feedback: String
    public var helpUsed: Bool
    public var principleID: String?
    public init(id: UUID = UUID(), createdAt: Date = Date(), answer: String, feedback: String, helpUsed: Bool = false, principleID: String? = nil) {
        self.id = id; self.createdAt = createdAt; self.answer = answer; self.feedback = feedback; self.helpUsed = helpUsed; self.principleID = principleID
    }
}

public enum LearningFeedback {
    /// Formatting and capitalization alone do not turn a shown example into a new answer.
    public static func matchesExample(_ answer: String, example: String) -> Bool {
        let normalized = normalizedAnswer(answer)
        return !normalized.isEmpty && normalized == normalizedAnswer(example)
    }

    static func normalizedAnswer(_ answer: String) -> String {
        answer.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// Conservative local feedback describes observable text. It never certifies task success or understanding.
    public static func evaluate(answer: String, exercise: CoachExercise, usedHelp: Bool) -> String {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Schreib zuerst deine eigene Idee auf. Du kannst dir jederzeit das Beispiel ansehen." }
        let excerpt = String(text.prefix(140)) + (text.count > 140 ? "…" : "")
        let lower = text.lowercased()
        let observation: String
        let formatTerms = "(tabelle|liste|stichpunkte|absatz|absätze|e-mail|mail)"
        let negatedFormat = "\\b(kein|keine|keinen|keiner|keines|nicht|ohne)\\s+(?:[\\p{L}]+\\s+){0,2}" + formatTerms + "\\b|\\b" + formatTerms + "\\s+(?:lieber\\s+)?nicht\\b"
        if lower.range(of: negatedFormat, options: .regularExpression) != nil {
            observation = "Du schließt eine Ausgabeform aus. Prüfe, ob daneben klar ist, welche Form du stattdessen möchtest."
        } else if lower.range(of: "\\b" + formatTerms + "\\b", options: .regularExpression) != nil {
            observation = "Du erwähnst eine Ausgabeform. Prüfe, ob deutlich wird, ob du diese Form möchtest oder nur als Beispiel nennst."
        } else if lower.range(of: "\\b(ohne|höchstens|maximal|mindestens|nicht mehr als)\\b", options: .regularExpression) != nil {
            observation = "Du formulierst eine Grenze. Prüfe, ob sie für diese Aufgabe nötig und eindeutig ist."
        } else if lower.range(of: "\\b[0-9]{1,2}(:[0-9]{2})?\\s*uhr\\b", options: .regularExpression) != nil {
            observation = "Deine Antwort enthält einen konkreten Zeitpunkt. Prüfe, ob klar ist, ob das der bisherige oder der gewünschte neue Termin ist."
        } else if lower.range(of: "\\b(für|damit|um zu|möchte|ziel)\\b", options: .regularExpression) != nil {
            observation = "Du sprichst einen Zweck oder Bezug an. Ist für eine andere Person klar, was das Ergebnis leisten soll?"
        } else {
            observation = "Vergleiche deine Idee mit der Übungsfrage: „\(exercise.question)“ Welche konkrete Angabe würde die Antwort verändern?"
        }
        let support = usedHelp ? "Du hast dabei Hilfe genutzt; der Versuch ist als unterstützt markiert." : "Dein Versuch ist als eigenständig markiert. Das allein ist noch kein Nachweis, dass das Ergebnis besser wird."
        return "Deine Idee: „\(excerpt)“\n\n\(observation)\n\n\(support)"
    }
}

public enum LearningStage: String, Codable, Sendable { case example, addDetail, newPrompt, transfer }

public enum LearningProgress {
    /// Only submitted attempts without help affect the next offered exercise. Copy actions are not accepted here.
    public static func stage(for attempts: [PracticeAttempt]) -> LearningStage {
        let own = attempts.filter { !$0.helpUsed && !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let distinct = Set(own.map { LearningFeedback.normalizedAnswer($0.answer) }).count
        switch distinct { case 0: return .example; case 1: return .addDetail; case 2: return .newPrompt; default: return .transfer }
    }
}
