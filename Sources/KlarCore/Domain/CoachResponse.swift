import Foundation

public enum CoachStatus: String, Codable, Sendable { case improved, already_good, needs_clarification }
public enum ChangeKind: String, Codable, Sendable { case addition, replacement, deletion }

public struct PromptSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var text: String
    public init(id: String, text: String) { self.id = id; self.text = text }
}

public struct PromptChange: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: ChangeKind
    public var originalText: String?
    public var targetSegmentIDs: [String]
    public var category: String
    public var title: String
    public var explanation: String
    public var ruleID: String?
    public init(id: String, kind: ChangeKind, originalText: String? = nil, targetSegmentIDs: [String] = [], category: String, title: String, explanation: String, ruleID: String? = nil) {
        self.id = id; self.kind = kind; self.originalText = originalText; self.targetSegmentIDs = targetSegmentIDs
        self.category = category; self.title = title; self.explanation = explanation; self.ruleID = ruleID
    }
    enum CodingKeys: String, CodingKey {
        case id, kind, category, title, explanation
        case originalText = "original_text", targetSegmentIDs = "target_segment_ids", ruleID = "rule_id"
    }
}

public struct Clarification: Codable, Equatable, Sendable {
    public var question: String
    public var optional: Bool
    public init(question: String, optional: Bool = false) { self.question = question; self.optional = optional }
}

public struct CoachExercise: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var question: String
    public var category: String
    public init(id: String, question: String, category: String) { self.id = id; self.question = question; self.category = category }
}

public enum PromptInputKind: String, Codable, Sendable, CaseIterable {
    case text, long_text, choice, multi_choice, number, date, scale
}

/// A form field the tutor proposes so missing details are collected up front.
/// `placeholder` is the exact bracketed token in the prompt that the answer replaces.
public struct PromptInput: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
    public var kind: PromptInputKind
    public var placeholder: String
    public var options: [String]
    public var suggestion: String?
    public var required: Bool
    public var why: String
    public init(id: String, label: String, kind: PromptInputKind, placeholder: String, options: [String] = [], suggestion: String? = nil, required: Bool = false, why: String) {
        self.id = id; self.label = label; self.kind = kind; self.placeholder = placeholder
        self.options = options; self.suggestion = suggestion; self.required = required; self.why = why
    }
}

public struct CoachResponse: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var status: CoachStatus
    public var coachMessage: String
    public var segments: [PromptSegment]
    public var changes: [PromptChange]
    public var unknowns: [String]
    public var suggestions: [String]
    public var clarification: Clarification?
    public var exercise: CoachExercise?
    /// Optional generated form. Absent in older answers and stored history.
    public var inputs: [PromptInput]
    public init(schemaVersion: Int = 1, status: CoachStatus, coachMessage: String, segments: [PromptSegment], changes: [PromptChange] = [], unknowns: [String] = [], suggestions: [String] = [], clarification: Clarification? = nil, exercise: CoachExercise? = nil, inputs: [PromptInput] = []) {
        self.schemaVersion = schemaVersion; self.status = status; self.coachMessage = coachMessage
        self.segments = segments; self.changes = changes; self.unknowns = unknowns; self.suggestions = suggestions
        self.clarification = clarification; self.exercise = exercise; self.inputs = inputs
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        status = try container.decode(CoachStatus.self, forKey: .status)
        coachMessage = try container.decode(String.self, forKey: .coachMessage)
        segments = try container.decode([PromptSegment].self, forKey: .segments)
        changes = try container.decode([PromptChange].self, forKey: .changes)
        unknowns = try container.decode([String].self, forKey: .unknowns)
        suggestions = try container.decode([String].self, forKey: .suggestions)
        clarification = try container.decodeIfPresent(Clarification.self, forKey: .clarification)
        exercise = try container.decodeIfPresent(CoachExercise.self, forKey: .exercise)
        inputs = try container.decodeIfPresent([PromptInput].self, forKey: .inputs) ?? []
    }

    public var suggestedInputValues: [String: String] {
        Dictionary(inputs.compactMap { input in input.suggestion.map { (input.id, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    /// Matches placeholders only in the original prompt, never in inserted user text.
    /// Unanswered fields stay visible, and segment IDs survive even when a token spans segments.
    public func filled(with values: [String: String]) -> CoachResponse {
        var copy = self
        var replacements: [String: String] = [:]
        for input in inputs {
            guard CoachValidator.validPlaceholder(input.placeholder),
                  let value = values[input.id], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            replacements[input.placeholder] = value
        }
        guard !replacements.isEmpty else { return copy }
        let source = prompt as NSString
        var offset = 0
        let ranges = segments.map { segment -> NSRange in
            let length = (segment.text as NSString).length
            defer { offset += length }
            return NSRange(location: offset, length: length)
        }
        // Work backwards so replacements do not invalidate earlier offsets in the same segment.
        for match in Self.placeholderPattern.matches(in: prompt, range: NSRange(location: 0, length: source.length)).reversed() {
            guard let value = replacements[source.substring(with: match.range)] else { continue }
            for (index, range) in ranges.enumerated() {
                let overlap = NSIntersectionRange(range, match.range)
                guard overlap.length > 0 else { continue }
                let replacement = overlap.location == match.range.location ? value : ""
                let local = NSRange(location: overlap.location - range.location, length: overlap.length)
                copy.segments[index].text = (copy.segments[index].text as NSString).replacingCharacters(in: local, with: replacement)
            }
        }
        return copy
    }
    private static let placeholderPattern = try! NSRegularExpression(pattern: "\\[[^\\[\\]\\r\\n]+\\]")
    public var prompt: String { segments.map(\.text).joined() }
    /// Native text layout and copying share this exact, ordered string. Never search by quote to locate an annotation.
    public var segmentRanges: [String: NSRange] {
        var offset = 0
        var result: [String: NSRange] = [:]
        for segment in segments {
            let length = (segment.text as NSString).length
            result[segment.id] = NSRange(location: offset, length: length)
            offset += length
        }
        return result
    }
    public var removedChanges: [PromptChange] { changes.filter { $0.kind == .deletion } }
    enum CodingKeys: String, CodingKey {
        case status, segments, changes, unknowns, suggestions, clarification, exercise, inputs
        case schemaVersion = "schema_version", coachMessage = "coach_message"
    }
}

public enum CoachValidationError: LocalizedError, Equatable {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let reason): return "Der Vorschlag konnte nicht sicher angezeigt werden: \(reason)" }
    }
}

public enum CoachValidator {
    public static let maximumInputLength = 24_000
    public static let maximumResponseBytes = 256_000
    public static func decode(_ data: Data, original: String) throws -> CoachResponse {
        guard data.count <= maximumResponseBytes else { throw CoachValidationError.invalid("Die Antwort ist zu groß.") }
        do {
            try validateShape(data)
            let response = try JSONDecoder().decode(CoachResponse.self, from: data)
            try validate(response, original: original)
            return response
        } catch let error as CoachValidationError { throw error }
        catch { throw CoachValidationError.invalid("Das Antwortformat ist unvollständig oder ungültig.") }
    }

    public static func validate(_ response: CoachResponse, original: String) throws {
        try require(response.schemaVersion == 1, "Diese Antwortversion wird noch nicht unterstützt.")
        try require(nonempty(response.coachMessage) && safeText(response.coachMessage, limit: 1_200), "Die Rückmeldung fehlt oder ist zu lang.")
        try require(original.utf16.count <= maximumInputLength, "Dein Prompt ist für diesen Versuch zu lang.")
        try require(response.segments.count <= 160 && response.changes.count <= 40, "Die Antwort enthält zu viele Textstellen.")
        try require(response.prompt.utf16.count <= 48_000, "Der Vorschlag ist zu lang.")
        try require(Set(response.segments.map(\.id)).count == response.segments.count, "Textstellen haben doppelte Kennungen.")
        try require(Set(response.changes.map(\.id)).count == response.changes.count, "Änderungen haben doppelte Kennungen.")
        for segment in response.segments {
            try require(validID(segment.id) && !segment.text.isEmpty && safeText(segment.text, limit: 48_000), "Eine Textstelle ist ungültig.")
        }
        try require(segmentsKeepCharacters(response), "Eine Textgrenze zerteilt ein Unicode-Zeichen.")
        try require(response.unknowns.count <= 20 && response.suggestions.count <= 20, "Es gibt zu viele Hinweise.")
        for note in response.unknowns + response.suggestions {
            try require(nonempty(note) && safeText(note, limit: 1_200), "Ein Hinweis ist ungültig.")
        }
        var annotated = Set<String>()
        for change in response.changes {
            try validateChange(change, in: response, original: original, annotated: &annotated)
        }
        if let question = response.clarification {
            try require(nonempty(question.question) && safeText(question.question, limit: 600), "Die Rückfrage fehlt oder ist zu lang.")
        }
        try require(response.inputs.count <= 12, "Es gibt zu viele Eingabefelder.")
        try require(Set(response.inputs.map(\.id)).count == response.inputs.count, "Eingabefelder haben doppelte Kennungen.")
        try require(Set(response.inputs.map(\.placeholder)).count == response.inputs.count, "Zwei Eingabefelder füllen denselben Platzhalter.")
        try require(response.inputs.isEmpty || response.status != .needs_clarification, "Eine Rückfrage enthält keine Eingabefelder.")
        for input in response.inputs { try validateInput(input, prompt: response.prompt) }
        if let exercise = response.exercise { try validateExercise(exercise) }
        switch response.status {
        case .already_good:
            try require(response.prompt == original && response.changes.isEmpty && response.clarification == nil, "Ein bereits klarer Prompt muss unverändert bleiben.")
        case .needs_clarification:
            try require(response.clarification != nil && response.changes.isEmpty && response.segments.isEmpty && response.exercise == nil, "Eine Rückfrage darf keinen fertigen Vorschlag vortäuschen.")
        case .improved:
            // Explanations are dropped one by one when they do not hold; a changed prompt
            // without a provable explanation is still shown, just without markings.
            try require(nonempty(response.prompt) && response.prompt != original && response.clarification == nil, "Der Vorschlag enthält keine nachvollziehbare Änderung.")
        }
    }

    // MARK: - Shared checks (also used to prune single items, see CoachSanitizer)

    static func require(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw CoachValidationError.invalid(reason) }
    }
    static func nonempty(_ text: String) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    static func safeText(_ text: String, limit: Int) -> Bool {
        text.utf16.count <= limit && !text.unicodeScalars.contains { $0.value < 32 && $0 != "\n" && $0 != "\t" && $0 != "\r" }
    }
    static func validID(_ id: String) -> Bool { id.range(of: "^[A-Za-z][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil }
    static func validPlaceholder(_ text: String) -> Bool {
        guard text.first == "[", text.last == "]", text.count >= 3 else { return false }
        let label = String(text.dropFirst().dropLast())
        return nonempty(label) && label.rangeOfCharacter(from: CharacterSet(charactersIn: "[]\r\n")) == nil
    }
    static func occurrences(_ needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }

    static func segmentsKeepCharacters(_ response: CoachResponse) -> Bool {
        var boundaries: Set<Int> = [0]
        var offset = 0
        for character in response.prompt {
            offset += String(character).utf16.count
            boundaries.insert(offset)
        }
        return response.segmentRanges.values.allSatisfy { boundaries.contains($0.location) && boundaries.contains(NSMaxRange($0)) }
    }

    static func validateChange(_ change: PromptChange, in response: CoachResponse, original: String, annotated: inout Set<String>) throws {
        let segmentsByID = Dictionary(response.segments.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        let order = Dictionary(response.segments.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        try require(validID(change.id), "Eine Änderungskennung ist ungültig.")
        try require(nonempty(change.title) && safeText(change.title, limit: 120), "Eine Überschrift ist ungültig.")
        try require(nonempty(change.category) && safeText(change.category, limit: 80), "Eine Kategorie fehlt.")
        try require(nonempty(change.explanation) && safeText(change.explanation, limit: 800), "Eine Erklärung fehlt oder ist zu lang.")
        try require(Set(change.targetSegmentIDs).count == change.targetSegmentIDs.count, "Eine Änderung verweist mehrfach auf dieselbe Textstelle.")
        try require(change.targetSegmentIDs.allSatisfy { segmentsByID[$0] != nil }, "Eine Erklärung verweist auf fehlenden Text.")
        let targetOrder = change.targetSegmentIDs.compactMap { order[$0] }
        try require(targetOrder == targetOrder.sorted(), "Die Textstellen einer Erklärung sind nicht in der richtigen Reihenfolge.")
        if let rule = change.ruleID { try require(RuleRegistry.lookup(rule) != nil, "Eine Quellenregel ist unbekannt.") }
        if let quote = change.originalText {
            try require(nonempty(quote) && original.contains(quote), "Ein Originalzitat kommt in deiner Eingabe nicht vor.")
        }
        switch change.kind {
        case .deletion:
            try require(change.targetSegmentIDs.isEmpty && change.originalText != nil, "Eine Entfernung muss getrennt vom Vorschlag erklärt werden.")
            if let quote = change.originalText {
                try require(occurrences(quote, in: original) > occurrences(quote, in: response.prompt), "Die als entfernt beschriebene Passage ist unverändert vorhanden.")
            }
        case .addition, .replacement:
            try require(!change.targetSegmentIDs.isEmpty, "Einer Änderung fehlt die zugehörige Textstelle.")
            try require(annotated.isDisjoint(with: change.targetSegmentIDs), "Eine Textstelle hat widersprüchliche Erklärungen.")
            let target = change.targetSegmentIDs.compactMap { segmentsByID[$0] }.joined()
            try require(nonempty(target), "Eine leere Textstelle kann nicht markiert werden.")
            if change.kind == .replacement {
                try require(change.originalText != nil && change.originalText != target, "Die beschriebene Ersetzung ändert keinen Text.")
            } else {
                try require(occurrences(target, in: response.prompt) > occurrences(target, in: original), "Die als neu beschriebene Passage ist bereits unverändert vorhanden.")
            }
            annotated.formUnion(change.targetSegmentIDs)
        }
    }

    static func validateInput(_ input: PromptInput, prompt: String) throws {
        try require(validID(input.id), "Eine Feldkennung ist ungültig.")
        try require(nonempty(input.label) && safeText(input.label, limit: 80), "Ein Feldname fehlt oder ist zu lang.")
        try require(nonempty(input.why) && safeText(input.why, limit: 240), "Ein Feld braucht eine kurze Begründung.")
        try require(validPlaceholder(input.placeholder) && safeText(input.placeholder, limit: 80), "Ein Platzhalter muss eine benannte Angabe in eckigen Klammern sein.")
        try require(prompt.contains(input.placeholder), "Ein Eingabefeld verweist auf einen Platzhalter, der im Vorschlag fehlt.")
        try require(input.options.count <= 8 && Set(input.options).count == input.options.count && input.options.allSatisfy { nonempty($0) && safeText($0, limit: 60) }, "Die Auswahl eines Feldes ist ungültig.")
        switch input.kind {
        case .choice, .multi_choice, .scale:
            try require(input.options.count >= 2, "Ein Auswahlfeld braucht mindestens zwei Optionen.")
        case .text, .long_text, .number, .date:
            break
        }
        if let suggestion = input.suggestion { try require(safeText(suggestion, limit: 400), "Ein Feldvorschlag ist zu lang.") }
    }

    static func validateExercise(_ exercise: CoachExercise) throws {
        try require(validID(exercise.id) && nonempty(exercise.question) && safeText(exercise.question, limit: 600) && nonempty(exercise.category) && safeText(exercise.category, limit: 80), "Die Übung ist ungültig.")
    }

    private static func validateShape(_ data: Data) throws {
        func keys(_ object: [String: Any], allowed: Set<String>, required: Set<String>) throws {
            let actual = Set(object.keys)
            guard actual.isSubset(of: allowed), required.isSubset(of: actual) else {
                throw CoachValidationError.invalid("Die Antwort enthält unbekannte oder fehlende Felder.")
            }
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoachValidationError.invalid("Die Antwort ist kein gültiges Objekt.")
        }
        try keys(object, allowed: ["schema_version", "status", "coach_message", "segments", "changes", "unknowns", "suggestions", "clarification", "exercise", "inputs"], required: ["schema_version", "status", "coach_message", "segments", "changes", "unknowns", "suggestions"])
        if let inputs = object["inputs"] as? [[String: Any]] {
            for input in inputs { try keys(input, allowed: ["id", "label", "kind", "placeholder", "options", "suggestion", "required", "why"], required: ["id", "label", "kind", "placeholder", "options", "required", "why"]) }
        }
        if let segments = object["segments"] as? [[String: Any]] {
            for segment in segments { try keys(segment, allowed: ["id", "text"], required: ["id", "text"]) }
        }
        if let changes = object["changes"] as? [[String: Any]] {
            for change in changes { try keys(change, allowed: ["id", "kind", "original_text", "target_segment_ids", "category", "title", "explanation", "rule_id"], required: ["id", "kind", "target_segment_ids", "category", "title", "explanation"]) }
        }
        if let clarification = object["clarification"] as? [String: Any] { try keys(clarification, allowed: ["question", "optional"], required: ["question", "optional"]) }
        if let exercise = object["exercise"] as? [String: Any] { try keys(exercise, allowed: ["id", "question", "category"], required: ["id", "question", "category"]) }
    }
}
