import Foundation

/// Turns a model answer that is almost right into one the strict validator accepts,
/// without inventing anything: it only strips wrappers, fills empty defaults, renames
/// broken IDs and drops single explanations, fields or exercises that do not hold.
/// The prompt text itself is never rewritten; if it is broken, validation still fails.
public enum CoachSanitizer {
    public static func clean(_ text: String, original: String) -> Data {
        guard let json = extractObject(text),
              let raw = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return Data(text.utf8)
        }
        let shaped = normalizeShape(raw)
        guard let data = try? JSONSerialization.data(withJSONObject: shaped),
              let decoded = try? JSONDecoder().decode(CoachResponse.self, from: data) else {
            return (try? JSONSerialization.data(withJSONObject: shaped)) ?? Data(text.utf8)
        }
        let pruned = prune(decoded, original: original)
        return (try? JSONEncoder().encode(pruned)) ?? data
    }

    // MARK: - Text wrapper

    /// Accepts a fenced block or a short lead-in sentence around the one JSON object.
    static func extractObject(_ text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return String(text[start...end])
    }

    // MARK: - Shape

    private static func normalizeShape(_ object: [String: Any]) -> [String: Any] {
        var result = object.filter { topLevelKeys.contains($0.key) }
        result["schema_version"] = 1
        for key in ["segments", "changes", "unknowns", "suggestions", "inputs"] where !(result[key] is [Any]) {
            result[key] = []
        }
        if !(result["coach_message"] is String) { result["coach_message"] = "" }
        if result["clarification"] is NSNull { result.removeValue(forKey: "clarification") }
        if result["exercise"] is NSNull { result.removeValue(forKey: "exercise") }
        result["segments"] = (result["segments"] as? [Any] ?? []).compactMap { item -> [String: Any]? in
            guard let segment = item as? [String: Any], let text = segment["text"] as? String else { return nil }
            return ["id": (segment["id"] as? String) ?? "", "text": text]
        }
        result["changes"] = (result["changes"] as? [Any] ?? []).compactMap { item -> [String: Any]? in
            guard var change = item as? [String: Any] else { return nil }
            change = change.filter { changeKeys.contains($0.key) }
            if !(change["target_segment_ids"] is [String]) { change["target_segment_ids"] = [] }
            for key in ["original_text", "rule_id"] where change[key] is NSNull { change.removeValue(forKey: key) }
            return change
        }
        result["inputs"] = (result["inputs"] as? [Any] ?? []).compactMap { item -> [String: Any]? in
            guard var input = item as? [String: Any] else { return nil }
            input = input.filter { inputKeys.contains($0.key) }
            if !(input["options"] is [String]) { input["options"] = [] }
            if !(input["required"] is Bool) { input["required"] = false }
            if !(input["why"] is String) { input["why"] = "" }
            if input["suggestion"] is NSNull { input.removeValue(forKey: "suggestion") }
            return input
        }
        for key in ["unknowns", "suggestions"] {
            result[key] = (result[key] as? [Any] ?? []).compactMap { $0 as? String }
        }
        if var clarification = result["clarification"] as? [String: Any] {
            clarification = clarification.filter { ["question", "optional"].contains($0.key) }
            if !(clarification["optional"] is Bool) { clarification["optional"] = false }
            result["clarification"] = clarification
        }
        if let exercise = result["exercise"] as? [String: Any] {
            result["exercise"] = exercise.filter { ["id", "question", "category"].contains($0.key) }
        }
        return result
    }

    private static let topLevelKeys: Set<String> = ["schema_version", "status", "coach_message", "segments", "changes", "unknowns", "suggestions", "clarification", "exercise", "inputs"]
    private static let changeKeys: Set<String> = ["id", "kind", "original_text", "target_segment_ids", "category", "title", "explanation", "rule_id"]
    private static let inputKeys: Set<String> = ["id", "label", "kind", "placeholder", "options", "suggestion", "required", "why"]

    // MARK: - Pruning

    static func prune(_ input: CoachResponse, original: String) -> CoachResponse {
        var response = input
        renameSegments(&response)
        response.coachMessage = trimmed(response.coachMessage, limit: 1_200)
        if !CoachValidator.nonempty(response.coachMessage) { response.coachMessage = "Hier ist dein klarer Prompt." }
        response.unknowns = notes(response.unknowns)
        response.suggestions = notes(response.suggestions)
        settleStatus(&response, original: original)
        pruneChanges(&response, original: original)
        pruneInputs(&response)
        if let exercise = response.exercise, (try? CoachValidator.validateExercise(exercise)) == nil { response.exercise = nil }
        if response.status == .needs_clarification { response.exercise = nil }
        return response
    }

    /// Empty segments disappear; missing, invalid or duplicate IDs get fresh ones and
    /// explanations follow the first segment that carried the old ID.
    private static func renameSegments(_ response: inout CoachResponse) {
        var mapping: [String: String] = [:]
        var used = Set<String>()
        var segments: [PromptSegment] = []
        for (index, segment) in response.segments.enumerated() where !segment.text.isEmpty {
            var id = segment.id
            if !CoachValidator.validID(id) || used.contains(id) {
                var counter = index + 1
                repeat { id = "seg\(counter)"; counter += 1 } while used.contains(id)
            }
            if mapping[segment.id] == nil { mapping[segment.id] = id }
            used.insert(id)
            segments.append(PromptSegment(id: id, text: segment.text))
        }
        response.segments = segments
        for index in response.changes.indices {
            response.changes[index].targetSegmentIDs = response.changes[index].targetSegmentIDs.compactMap { mapping[$0] }
        }
    }

    private static func settleStatus(_ response: inout CoachResponse, original: String) {
        switch response.status {
        case .needs_clarification:
            if response.clarification == nil || !CoachValidator.nonempty(response.clarification?.question ?? "") {
                response.clarification = nil
                response.status = response.segments.isEmpty ? .needs_clarification : (response.prompt == original ? .already_good : .improved)
            }
        case .already_good:
            if response.prompt != original {
                if response.prompt.trimmingCharacters(in: .whitespacesAndNewlines) == original.trimmingCharacters(in: .whitespacesAndNewlines) || response.segments.isEmpty {
                    response.segments = [PromptSegment(id: "s1", text: original)]
                } else {
                    response.status = .improved
                }
            }
        case .improved:
            if response.prompt == original { response.status = .already_good }
        }
        switch response.status {
        case .needs_clarification:
            response.segments = []; response.changes = []; response.inputs = []
        case .already_good:
            response.changes = []; response.inputs = []; response.clarification = nil
        case .improved:
            response.clarification = nil
        }
    }

    private static func pruneChanges(_ response: inout CoachResponse, original: String) {
        var kept: [PromptChange] = []
        var annotated = Set<String>()
        var usedIDs = Set<String>()
        for (index, candidate) in response.changes.enumerated() {
            var change = candidate
            if !CoachValidator.validID(change.id) || usedIDs.contains(change.id) { change.id = "c\(index + 1)x" }
            if let rule = change.ruleID, RuleRegistry.lookup(rule) == nil { change.ruleID = nil }
            change.title = trimmed(change.title, limit: 120)
            change.category = trimmed(change.category, limit: 80)
            change.explanation = trimmed(change.explanation, limit: 800)
            change.targetSegmentIDs = orderedUnique(change.targetSegmentIDs, in: response.segments)
            if change.kind == .addition, let quote = change.originalText, !original.contains(quote) { change.originalText = nil }
            var trial = annotated
            guard (try? CoachValidator.validateChange(change, in: response, original: original, annotated: &trial)) != nil else { continue }
            annotated = trial
            usedIDs.insert(change.id)
            kept.append(change)
            if kept.count == 40 { break }
        }
        response.changes = kept
    }

    private static func pruneInputs(_ response: inout CoachResponse) {
        guard response.status == .improved else { response.inputs = []; return }
        var kept: [PromptInput] = []
        var ids = Set<String>(), placeholders = Set<String>()
        for candidate in response.inputs {
            var input = candidate
            input.label = trimmed(input.label, limit: 80)
            input.why = trimmed(input.why, limit: 240)
            if !CoachValidator.nonempty(input.why) { input.why = "Damit die KI nicht nachfragen muss." }
            input.options = Array(input.options.map { trimmed($0, limit: 60) }.filter(CoachValidator.nonempty).prefix(8))
            if [.choice, .multi_choice, .scale].contains(input.kind) && input.options.count < 2 { input.kind = .text; input.options = [] }
            if let suggestion = input.suggestion { input.suggestion = CoachValidator.nonempty(suggestion) ? trimmed(suggestion, limit: 400) : nil }
            guard !ids.contains(input.id), !placeholders.contains(input.placeholder),
                  (try? CoachValidator.validateInput(input, prompt: response.prompt)) != nil else { continue }
            ids.insert(input.id); placeholders.insert(input.placeholder)
            kept.append(input)
            if kept.count == 12 { break }
        }
        response.inputs = kept
    }

    // MARK: - Helpers

    private static func notes(_ values: [String]) -> [String] {
        Array(values.map { trimmed($0, limit: 1_200) }.filter(CoachValidator.nonempty).prefix(20))
    }

    private static func orderedUnique(_ ids: [String], in segments: [PromptSegment]) -> [String] {
        let wanted = Set(ids)
        return segments.map(\.id).filter { wanted.contains($0) }
    }

    /// Removes control characters and shortens by whole characters.
    static func trimmed(_ text: String, limit: Int) -> String {
        var clean = String(String.UnicodeScalarView(text.unicodeScalars.filter { $0.value >= 32 || $0 == "\n" || $0 == "\t" || $0 == "\r" }))
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.utf16.count > limit { clean.removeLast() }
        return clean
    }
}
