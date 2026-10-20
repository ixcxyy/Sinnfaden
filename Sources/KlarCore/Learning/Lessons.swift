import Foundation

public struct PromptLesson: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let principle: String
    public let baseline: String
    public let solution: String
    public let hint: String
    public let action: String
    public let version: Int
    public init(id: String, title: String, principle: String, baseline: String, solution: String, hint: String, action: String, version: Int = 1) {
        self.id = id; self.title = title; self.principle = principle; self.baseline = baseline; self.solution = solution
        self.hint = hint; self.action = action; self.version = version
    }
}

public struct LessonFeedback: Codable, Equatable, Sendable {
    public let observation: String
    public let independentApplication: Bool
    public let meetsExercise: Bool
    public init(observation: String, independentApplication: Bool, meetsExercise: Bool = false) {
        self.observation = observation; self.independentApplication = independentApplication; self.meetsExercise = meetsExercise
    }
}

public struct LessonAttempt: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let lessonID: String
    public let answer: String
    public let feedback: LessonFeedback
    public let usedHint: Bool
    public let revealedSolution: Bool
    public init(id: UUID = UUID(), createdAt: Date = Date(), lessonID: String, answer: String, feedback: LessonFeedback, usedHint: Bool = false, revealedSolution: Bool = false) {
        self.id = id; self.createdAt = createdAt; self.lessonID = lessonID; self.answer = answer; self.feedback = feedback
        self.usedHint = usedHint; self.revealedSolution = revealedSolution
    }
}

public enum LessonPracticeStage: String, Codable, Sendable { case guided, independent, transfer }

public enum LessonCatalog {
    public static let lessons: [PromptLesson] = [
        PromptLesson(id: "goal", title: "Das Ziel ausdrücken", principle: "Schreib, was das Ergebnis ermöglichen soll.", baseline: "Hilf mir mit einer E-Mail.", solution: "Schreibe eine E-Mail, in der ich um einen neuen Terminvorschlag bitte.", hint: "Soll die E-Mail zum Beispiel absagen, einladen oder um eine Rückmeldung bitten? Wähle selbst ein Ziel.", action: "Ergänze selbst, was diese E-Mail erreichen soll."),
        PromptLesson(id: "context", title: "Hilfreichen Kontext geben", principle: "Ergänze Umstände, die den Vorschlag tatsächlich verändern.", baseline: "Plane einen Spaziergang.", solution: "Plane einen Spaziergang von höchstens 30 Minuten. Start und Ende sind [Ort].", hint: "Zeit, Startort oder eine Grenze können wichtig sein. Gib nur an, was du wirklich weißt.", action: "Ergänze eine konkrete Dauer oder einen Startort für den Spaziergang."),
        PromptLesson(id: "audience", title: "Person und Ton beschreiben", principle: "Für wen eine Antwort gedacht ist, beeinflusst Sprache und Vorwissen.", baseline: "Erkläre, wie ein Passwortmanager funktioniert.", solution: "Erkläre, wie ein Passwortmanager funktioniert, für eine Person ohne Vorkenntnisse. Schreibe sachlich und verständlich.", hint: "Nenne die Personengruppe oder ihr Vorwissen und einen gewünschten Ton.", action: "Ergänze selbst, für wen die Erklärung gedacht ist und wie sie klingen soll."),
        PromptLesson(id: "format", title: "Form und Länge wählen", principle: "Wähle eine Form, die du anschließend gut verwenden kannst.", baseline: "Fasse den folgenden Text zusammen: [Text].", solution: "Fasse den folgenden Text in fünf kurzen Stichpunkten zusammen: [Text].", hint: "Möglich sind etwa Absätze, eine Tabelle oder Stichpunkte. Eine Länge kann beim Eingrenzen helfen.", action: "Beschreibe eine gewünschte Ausgabeform und ihre Länge."),
        PromptLesson(id: "followup", title: "Gezielt nachfragen", principle: "Benenne die Lücke in der Antwort und den nächsten gewünschten Schritt.", baseline: "Die Antwort lautet: „Du könntest dich besser organisieren.“ Das ist mir zu allgemein.", solution: "Mach daraus bitte drei konkrete Schritte, die ich heute ausprobieren kann. Frage nach, wenn dir dafür eine wichtige Angabe fehlt.", hint: "Bitte zum Beispiel um ein Beispiel oder einen konkreten nächsten Schritt. Füge keine erfundenen Umstände hinzu.", action: "Formuliere eine Rückfrage, die aus der allgemeinen Antwort etwas Konkretes macht."),
        PromptLesson(id: "check", title: "Eine Antwort prüfen", principle: "Vergleiche wichtige Aussagen mit deiner Anfrage, bevor du sie übernimmst.", baseline: "Deine Anfrage: „Das Treffen ist Dienstag um 16 Uhr.“\nDie Antwort: „Wir treffen uns Mittwoch um 16 Uhr.“", solution: "Der Wochentag stimmt nicht: In meiner Anfrage steht Dienstag, in der Antwort Mittwoch. Bitte korrigiere den Tag und behalte 16 Uhr bei.", hint: "Prüfe Tag und Uhrzeit einzeln. Welche Angabe weicht tatsächlich ab?", action: "Benenne die tatsächliche Abweichung und bitte um eine gezielte Korrektur.")
    ]

    public static func lookup(_ id: String) -> PromptLesson? { lessons.first { $0.id == id } }

    /// Deterministic checks for these six fixed exercises, not an unrestricted semantic grading model.
    /// The feedback always makes its limited observation explicit and never scores general ability.
    public static func evaluate(answer: String, lesson: PromptLesson, usedHint: Bool = false, revealedSolution: Bool = false) -> LessonFeedback {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return LessonFeedback(observation: "Schreib zuerst deine eigene Idee auf. Hilfe bleibt jederzeit verfügbar.", independentApplication: false) }
        let lower = text.lowercased()
        func matches(_ pattern: String) -> Bool { lower.range(of: pattern, options: .regularExpression) != nil }
        func affirmed(_ pattern: String) -> Bool { containsAffirmed(pattern, in: lower) }
        let uncertain = matches("\\b(keine ahnung|weiß (ich )?nicht|weiss (ich )?nicht|keine idee|weiß nicht wie)\\b")
        var matchesTask = false
        var detail = ""
        var missingDetail: String?
        switch lesson.id {
        case "goal":
            matchesTask = matches("\\b(bitte|bitten|möchte|soll|um|lade|sage|absagen|einladen|informieren|frage)\\b") && affirmed("\\b(termin|terminvorschlag|absagen|absage|einladen|einladung|rückmeldung|bestätigung|antwort|informieren)\\b")
            detail = "Du nennst eine konkrete Absicht für die E-Mail. Prüfe, ob eine lesende Person daraus die gewünschte Reaktion erkennt."
        case "context":
            let duration = affirmed("\\b([1-9][0-9]{0,2}|zehn|zwanzig|dreißig|dreissig|vierzig|sechzig|eine|einer)\\s*(minuten?|stunden?)\\b")
            let place = "(?!(?:dem|der|den|die|das|ist|morgen|übermorgen|heute|jetzt|sofort|bald|dann|nun|nächste[nrms]?|kommende[nrms]?|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)\\b)[\\p{L}]{3,}"
            let start = affirmed("\\b(?:start(?:ort)?|starte[n]?|beginne[n]?)\\s+(?:(?:ist|liegt)\\s+)?(?:am|beim|in|im|bei|vom|an der|an dem)\\s+" + place
                + "|\\b(?:ab|vom)\\s+(?:(?:dem|der)\\s+)?" + place
                + "|\\b(?:start|startort)\\s*:\\s*" + place)
            matchesTask = duration || start
            if !matchesTask { missingDetail = "Eine gewünschte Dauer oder ein Startort ist noch nicht eindeutig. „Ab morgen“ nennt einen Zeitpunkt; ergänze etwa eine Gehzeit oder den Ort, an dem du losgehen möchtest." }
            detail = "Du gibst eine Dauer oder einen Startbezug an. Prüfe noch, ob der Startort eindeutig und tatsächlich bekannt ist."
        case "audience":
            let audience = affirmed("\\b(ohne vorkenntnisse|anfänger|anfängerin|kinder|fachleute|einsteiger|erwachsene|kolleginnen|kollegen|schüler|schülerinnen)\\b")
            let tone = affirmed("\\b(verständlich|einfach|sachlich|freundlich|ruhig|förmlich|locker|klar|respektvoll)\\b")
            matchesTask = audience && tone
            if !audience { missingDetail = "Nenne, für wen die Erklärung gedacht ist. Eine ausdrücklich ausgeschlossene Zielgruppe reicht dafür noch nicht." }
            else if !tone { missingDetail = "Die Zielgruppe ist erkennbar. Ergänze, wie die Erklärung klingen soll, etwa sachlich oder freundlich." }
            detail = "Du erwähnst eine Zielgruppe oder ihr Vorwissen und einen Ton. Prüfe, ob beides für diese Erklärung passt."
        case "format":
            let evidence = formatEvidence(in: lower)
            matchesTask = evidence.form && evidence.length
            if !evidence.form { missingDetail = "Eine gewünschte Ausgabeform ist noch nicht eindeutig. Nenne zum Beispiel Absätze, Stichpunkte oder eine Tabelle; eine ausgeschlossene Form zählt nicht als Wunsch." }
            else if !evidence.length { missingDetail = "Die Ausgabeform ist erkennbar. Ergänze noch die gewünschte Länge, etwa drei Stichpunkte oder eine Tabelle mit fünf Zeilen. Eine Zahl zum Inhalt legt die Ausgabelänge nicht fest." }
            detail = "Du nennst eine Ausgabeform und eine Anzahl. Prüfe, ob diese Länge zu dem Ausgangstext passt."
        case "followup":
            let request = matches("\\b(bitte|gib|zeige|nenn|nenne|mach|mache|beschreibe|erkläre|welche[rns]?|wie|kannst)\\b")
            matchesTask = request && affirmed("\\b(beispiel|konkret[eernms]*|schritt[eens]*|heute|anfangen|beginnen)\\b")
            detail = "Du fragst nach einem Beispiel oder einer konkreten Handlung. Prüfe, ob die Rückfrage genau die zu allgemeine Antwort weiterführt."
        case "check":
            let identifies = matches("\\bdienstag\\b") && matches("\\bmittwoch\\b")
            let correction = "(?:korrigiere[n]?|berichtige[n]?|ändere|ändern|ersetze[n]?)"
            // Mentioning both days and saying “please” is not yet a request to fix the error.
            // Accept an explicit day target, a reference to the described error, or a bare
            // correction request after the discrepancy; unrelated targets do not qualify.
            let target = "(?:(?:den|das|diesen|diese|die)\\s+)?(?:tag|wochentag|dienstag|mittwoch|fehler)"
            let asksForCorrection = affirmed("\\b" + correction + "\\s+(?:bitte\\s+)?" + target + "\\b"
                + "|\\b(?:" + target + "|das|dies)\\s+(?:bitte\\s+)?" + correction + "\\b"
                + "|\\b" + correction + "\\s+(?:das|dies)\\s*(?:bitte\\s*)?(?=[.!?;\\n]|$)"
                + "|^\\s*(?:bitte\\s+)?" + correction + "\\s*(?:bitte\\s*)?(?=[.!?;\\n]|$)"
                + "|\\bdienstag\\s+statt\\s+mittwoch\\b")
            let wrongDirection = matches("\\b" + correction + "\\b[^.!?\\n]{0,100}\\b(?:auf|zu|in|durch|mit|gegen)\\s+(?:den\\s+)?mittwoch\\b|\\bdienstag\\s+(?:auf|zu|in|durch|mit|gegen)\\s+(?:den\\s+)?mittwoch\\b|\\bmittwoch\\s+statt\\s+dienstag\\b")
                || matches("\\bmittwoch\\s+(?:ist|war)\\s+(?:der\\s+)?(?:richtig|korrekt)\\b|\\bdienstag\\s+(?:ist|war)\\s+(?:der\\s+)?(?:falsch|fehlerhaft)\\b")
            let refusesCorrection = matches("\\b" + correction + "\\s+(?:bitte\\s+)?nicht\\s+(?:(?:den|das)\\s+)?(?:tag|wochentag|dienstag|mittwoch)\\b|\\bnicht\\s+" + correction + "\\b")
            let changesTime = explicitTimes(in: lower).contains { $0.hour != 16 || $0.minute != 0 }
            matchesTask = identifies && asksForCorrection && !wrongDirection && !refusesCorrection && !changesTime
            if wrongDirection { missingDetail = "Die Korrekturrichtung stimmt noch nicht: In der Anfrage steht Dienstag. Mittwoch ist die Abweichung in der Antwort." }
            else if changesTime { missingDetail = "Die Uhrzeit ist bereits richtig: 16 Uhr. Korrigiere nur den abweichenden Tag, ohne eine neue Uhrzeit einzuführen." }
            else if refusesCorrection { missingDetail = "Die Formulierung schließt die Korrektur des Tags aus. Bitte gezielt darum, Mittwoch durch Dienstag zu ersetzen." }
            else if !asksForCorrection { missingDetail = "Die gezielte Korrektur des falschen Wochentags ist noch nicht eindeutig. Nur beide Tage zu erwähnen oder etwas anderes zu ändern reicht dafür noch nicht. Benenne die Abweichung und bitte darum, genau diese zu korrigieren." }
            detail = "Du benennst die Abweichung beim Tag und bittest um Korrektur. Die Uhrzeit 16 Uhr kann dabei unverändert bleiben."
        default:
            return LessonFeedback(observation: "Diese Übung wird von der lokalen Prüfung noch nicht unterstützt. Deine Eingabe bleibt erhalten.", independentApplication: false)
        }
        matchesTask = matchesTask && !uncertain && normalize(text) != normalize(lesson.baseline)
        if uncertain { missingDetail = nil }
        let copied = normalize(text) == normalize(lesson.solution)
        let independent = matchesTask && !usedHint && !revealedSolution && !copied
        let excerpt = String(text.prefix(220)) + (text.count > 220 ? "…" : "")
        let next = matchesTask ? detail : (missingDetail ?? "Die lokale Prüfung findet die gesuchte Ergänzung noch nicht eindeutig. \(lesson.action)") + " Du kannst deinen Versuch überarbeiten oder einen Hinweis ansehen."
        let support: String
        if copied { support = "Dein Text entspricht der Beispiel-Lösung. Das wird als Übernahme gespeichert, nicht als selbstständige Anwendung." }
        else if usedHint || revealedSolution { support = "Der Versuch wird mit der verwendeten Hilfe gespeichert." }
        else if independent { support = "Die konkrete Ergänzung ist als eigener Versuch erfasst. Das ist kein allgemeiner Kompetenznachweis." }
        else { support = "Dein Versuch bleibt gespeichert; Länge allein zählt nicht als gelungene Anwendung." }
        return LessonFeedback(observation: "Dein Versuch: „\(excerpt)“\n\n\(next)\n\n\(support)", independentApplication: independent, meetsExercise: matchesTask)
    }

    public static func stage(for attempts: [LessonAttempt], lessonID: String) -> LessonPracticeStage {
        let eligible = attempts.filter { $0.lessonID == lessonID && $0.feedback.independentApplication && !$0.usedHint && !$0.revealedSolution }
        let count = Set(eligible.map { normalize($0.answer) }).count
        if count >= 4 { return .transfer }
        if count >= 2 { return .independent }
        return .guided
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
    }

    /// Recognizes nearby explicit negation in these fixed exercises. It is not a general language parser.
    private static func containsAffirmed(_ pattern: String, in text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let separated = text.replacingOccurrences(of: "\\bnicht (?:mehr|länger) als\\b", with: "höchstens", options: .regularExpression)
            .replacingOccurrences(of: "\\b(?:sondern|stattdessen|aber)\\b|[.;!?\\n]", with: "\n", options: .regularExpression)
        let negativePrefix = "\\b(?:nicht|kein(?:e[nmrs]?)?|ohne(?!\\s+vorkenntnisse\\b))\\s+(?:[\\p{L}]+\\s+){0,3}$"
        for clause in separated.components(separatedBy: "\n") {
            let source = clause as NSString
            for match in expression.matches(in: clause, range: NSRange(location: 0, length: source.length)) {
                let before = source.substring(to: match.range.location)
                let after = source.substring(from: NSMaxRange(match.range))
                if before.range(of: negativePrefix, options: .regularExpression) == nil,
                   after.range(of: "^\\s+(?:bitte\\s+)?nicht\\b", options: .regularExpression) == nil { return true }
            }
        }
        return false
    }

    private static func formatEvidence(in text: String) -> (form: Bool, length: Bool) {
        let form = "(?:stichpunkte[nr]?|punkte[n]?|absätze[n]?|absatz|tabelle|liste|sätze[n]?|satz|zeilen?)"
        let unit = "(?:stichpunkte[nr]?|punkte[n]?|absätze[n]?|absatz|sätze[n]?|satz|zeilen?|wörter[n]?|worte[n]?|zeichen|seiten?)"
        let count = "(?:[1-9][0-9]{0,2}|ein(?:e[nmrs]?)?|zwei|drei|vier|fünf|sechs|sieben|acht|neun|zehn)"
        let alternative = "\\b(?:statt|anstatt)\\s+(?:(?:einer?|einem|einen|der)\\s+)?" + form + "\\s+(?:bitte\\s+)?"
        let separated = text.replacingOccurrences(of: alternative, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "\\b(?:sondern|stattdessen|aber)\\b|[.;!?\\n]", with: "\n", options: .regularExpression)
        var hasForm = false, hasLength = false
        for raw in separated.components(separatedBy: "\n") {
            let clause = raw.replacingOccurrences(of: "\\bnicht (?:mehr|länger) als\\b", with: "höchstens", options: .regularExpression)
            let excluded = "\\b(?:kein(?:e[nmrs]?)?|nicht|ohne)\\s+(?:[\\p{L}0-9]+\\s+){0,4}" + form + "\\b|\\b" + form + "\\s+(?:bitte\\s+)?nicht\\b"
            guard clause.range(of: excluded, options: .regularExpression) == nil,
                  clause.range(of: "\\b(?:ausgangstext|quelltext|text)\\s+(?:hat|enthält|umfasst)\\b", options: .regularExpression) == nil else { continue }
            hasForm = hasForm || clause.range(of: "\\b" + form + "\\b", options: .regularExpression) != nil
            hasLength = hasLength || clause.range(of: "\\b" + count + "\\s+(?:(?:kurz|knapp|prägnant)[\\p{L}]*\\s+)?" + unit + "\\b", options: .regularExpression) != nil
        }
        return (hasForm, hasLength)
    }

    private static func explicitTimes(in text: String) -> [(hour: Int, minute: Int)] {
        // Colon times need no “Uhr”; dotted times do, so a date such as 16.10.
        // is not mistaken for a clock time. Preserve minutes in “16 Uhr 30” too.
        let expression = try! NSRegularExpression(pattern: "\\b([0-9]{1,2})(?::([0-9]{2})\\b(?:\\s*uhr\\b)?|\\.([0-9]{2})\\s*uhr\\b|\\s*uhr\\b(?:\\s+([0-9]{2})\\b)?)")
        let source = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard let hour = Int(source.substring(with: match.range(at: 1))) else { return nil }
            let minute = (2..<match.numberOfRanges).compactMap { index -> Int? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : Int(source.substring(with: range))
            }.first ?? 0
            return (hour, minute)
        }
    }
}
