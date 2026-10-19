import Foundation

public enum ComparisonKind: String, Codable, Sendable { case isolated, wholePrompt }

public struct ComparisonPlan: Codable, Equatable, Sendable {
    public let kind: ComparisonKind
    public let baseline: String
    public let variant: String
    public let criterion: String
    public let title: String
    public let note: String
    public let changeID: String?

    public init(kind: ComparisonKind, baseline: String, variant: String, criterion: String, title: String, note: String, changeID: String? = nil) {
        self.kind = kind; self.baseline = baseline; self.variant = variant; self.criterion = criterion
        self.title = title; self.note = note; self.changeID = changeID
    }

    /// Reconstructs one literal edit only when its location and sentence boundaries are unambiguous.
    /// Never silently labels an entire rewrite as an isolated change.
    public static func make(original: String, response: CoachResponse, changeID: String? = nil) throws -> ComparisonPlan {
        try CoachValidator.validate(response, original: original)
        guard response.status == .improved else {
            throw LearningDataError.invalid("Für einen Vergleich braucht es einen tatsächlich geänderten Vorschlag.")
        }
        let change = changeID.flatMap { id in response.changes.first { $0.id == id } }
        let criterion = comparisonCriterion(change?.category)
        if let change, let variant = isolatedVariant(original: original, response: response, change: change), variant != original {
            return ComparisonPlan(kind: .isolated, baseline: original, variant: variant, criterion: criterion,
                                  title: change.title, note: "Nur die ausgewählte Textänderung unterscheidet die beiden Prompts. Ein Antwortpaar ist ein Beispiel; Antworten können bei Wiederholung variieren.", changeID: change.id)
        }
        return ComparisonPlan(kind: .wholePrompt, baseline: original, variant: response.prompt, criterion: "Welche Antwort erfüllt dein ursprüngliches Anliegen besser – und woran erkennst du das?",
                              title: "Den ganzen Prompt vergleichen", note: "Diese Änderung lässt sich nicht sicher allein einsetzen. Hier werden Original und gesamter Vorschlag verglichen; Unterschiede können mehrere Ursachen haben. Ein Antwortpaar beweist keine allgemeine Regel.", changeID: change?.id)
    }

    private static func isolatedVariant(original: String, response: CoachResponse, change: PromptChange) -> String? {
        let positions = change.targetSegmentIDs.compactMap { id in response.segments.firstIndex { $0.id == id } }
        if !positions.isEmpty && positions != Array(positions[0]...(positions[0] + positions.count - 1)) { return nil }
        let target = positions.map { response.segments[$0].text }.joined()
        switch change.kind {
        case .replacement, .deletion:
            guard let source = change.originalText, let range = uniqueRange(source, in: original), safeWordBoundaries(range, in: original) else { return nil }
            if change.kind == .replacement {
                // Different clause/sentence casing or punctuation requires broader grammatical rewriting.
                guard boundarySignature(source) == boundarySignature(target) else { return nil }
            }
            var result = original
            result.replaceSubrange(range, with: change.kind == .deletion ? "" : target)
            return result
        case .addition:
            guard let first = positions.first, let last = positions.last else { return nil }
            let before = response.segments[..<first].map(\.text).joined()
            let after = response.segments[(last + 1)...].map(\.text).joined()
            if before + after == original { return before + target + after }
            // Require both immediate neighbours to occur together uniquely in the original.
            let left = first > 0 ? response.segments[first - 1].text : ""
            let right = last + 1 < response.segments.count ? response.segments[last + 1].text : ""
            guard !left.isEmpty || !right.isEmpty,
                  let anchor = uniqueRange(left + right, in: original) else { return nil }
            if left.isEmpty && anchor.lowerBound != original.startIndex { return nil }
            if right.isEmpty && anchor.upperBound != original.endIndex { return nil }
            var result = original
            result.replaceSubrange(anchor, with: left + target + right)
            return result
        }
    }

    private static func uniqueRange(_ needle: String, in text: String) -> Range<String.Index>? {
        guard !needle.isEmpty, let first = text.range(of: needle, options: .literal),
              text.range(of: needle, options: .literal, range: first.upperBound..<text.endIndex) == nil else { return nil }
        return first
    }

    private static func safeWordBoundaries(_ range: Range<String.Index>, in text: String) -> Bool {
        let boundaries = Set(text.indices).union([text.endIndex])
        guard boundaries.contains(range.lowerBound), boundaries.contains(range.upperBound), !range.isEmpty else { return false }
        func word(_ character: Character) -> Bool { character.isLetter || character.isNumber }
        if range.lowerBound > text.startIndex, word(text[range.lowerBound]), word(text[text.index(before: range.lowerBound)]) { return false }
        if range.upperBound < text.endIndex, word(text[text.index(before: range.upperBound)]), word(text[range.upperBound]) { return false }
        return true
    }

    private static func boundarySignature(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = trimmed.first.map { $0.isUppercase ? "upper" : "lower" } ?? "empty"
        let terminal = trimmed.last.map { ".!?;,:".contains($0) ? String($0) : "word" } ?? "empty"
        return initial + ":" + terminal
    }

    private static func comparisonCriterion(_ category: String?) -> String {
        let text = category?.lowercased() ?? ""
        if text.contains("person") || text.contains("empfänger") || text.contains("zielgruppe") || text.contains("ton") { return "Ist die Antwort jetzt für die richtige Person und im passenden Ton geschrieben?" }
        if text.contains("format") || text.contains("ausgabe") || text.contains("länge") { return "Ist die gewünschte Form oder Länge in der tatsächlichen Antwort erkennbar?" }
        if text.contains("grenze") || text.contains("anforder") { return "Hält die Antwort die ausdrücklich genannte Grenze ein?" }
        if text.contains("kontext") { return "Passt die Antwort zu den ergänzten Umständen, ohne etwas dazuzuerfinden?" }
        return "Wird deutlicher beantwortet, was du mit deiner Anfrage erreichen möchtest?"
    }
}

public enum ComparisonAnswerStatus: String, Codable, Sendable { case pending, running, completed, failed, interrupted }

public struct ComparisonAnswer: Codable, Equatable, Sendable {
    public var status: ComparisonAnswerStatus
    public var text: String
    public var error: String?
    public init(status: ComparisonAnswerStatus = .pending, text: String = "", error: String? = nil) {
        self.status = status; self.text = text; self.error = error
    }
}

public struct ComparisonRun: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let plan: ComparisonPlan
    public let model: String
    public var prediction: String
    public var baselineAnswer: ComparisonAnswer
    public var variantAnswer: ComparisonAnswer
    public init(id: UUID = UUID(), createdAt: Date = Date(), plan: ComparisonPlan, model: String, prediction: String = "", baselineAnswer: ComparisonAnswer = ComparisonAnswer(), variantAnswer: ComparisonAnswer = ComparisonAnswer()) {
        self.id = id; self.createdAt = createdAt; self.plan = plan; self.model = model; self.prediction = prediction
        self.baselineAnswer = baselineAnswer; self.variantAnswer = variantAnswer
    }
    public var isComplete: Bool { baselineAnswer.status == .completed && variantAnswer.status == .completed }
    public mutating func markInterruptedAfterRestart() {
        if baselineAnswer.status == .running { baselineAnswer.status = .interrupted; baselineAnswer.error = "Die Erzeugung wurde unterbrochen. Diese Antwort ist nicht vollständig." }
        if variantAnswer.status == .running { variantAnswer.status = .interrupted; variantAnswer.error = "Die Erzeugung wurde unterbrochen. Diese Antwort ist nicht vollständig." }
    }
}
