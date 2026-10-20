import Foundation

/// Placeholders and their fields. Every bracketed token shown in orange must have exactly one
/// field; a token the model left without a matching field gets one here, deterministically.
extension CoachResponse {
    /// Bracketed tokens in the prompt, in order of first appearance, without duplicates.
    public var placeholderTokens: [String] {
        let text = prompt as NSString
        let pattern = try! NSRegularExpression(pattern: "\\[[^\\[\\]\\r\\n]+\\]")
        var seen = Set<String>()
        return pattern.matches(in: prompt, range: NSRange(location: 0, length: text.length)).compactMap { match in
            let token = text.substring(with: match.range)
            guard CoachValidator.validPlaceholder(token), token.utf16.count <= 80, seen.insert(token).inserted else { return nil }
            return token
        }
    }

    /// Tokens that still have no usable value: these block a complete copy.
    public func unfilledPlaceholders(with values: [String: String]) -> [String] {
        guard status == .improved else { return [] }
        let filled = Set(inputs.compactMap { input -> String? in
            guard let value = values[input.id], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return input.placeholder
        })
        return placeholderTokens.filter { !filled.contains($0) }
    }

    /// Adds a field for every token without one. A single unmatched field can supply the
    /// wording and id for a single orphan, but never a suggested value. Ambiguous matches
    /// get plain multi-line fields. Stable: repeating it changes nothing.
    public func coveringPlaceholders(unmatched: [PromptInput] = []) -> CoachResponse {
        guard status == .improved else { return self }
        var copy = self
        let covered = Set(inputs.map(\.placeholder))
        let orphans = placeholderTokens.filter { !covered.contains($0) }
        guard !orphans.isEmpty else { return self }
        var ids = Set(inputs.map(\.id))
        // Multiple differently named fields cannot be matched by array position safely.
        let reuse = unmatched.count == 1 && orphans.count == 1
        for (index, token) in orphans.enumerated() where copy.inputs.count < 12 {
            if reuse, !ids.contains(unmatched[index].id) {
                var input = unmatched[index]
                input.placeholder = token
                // A mismatched token gives no evidence that its proposed value belongs here.
                input.suggestion = nil
                if [.choice, .multi_choice, .scale].contains(input.kind) && input.options.count < 2 { input.kind = .long_text; input.options = [] }
                ids.insert(input.id)
                copy.inputs.append(input)
                continue
            }
            let label = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            var id = "slot-" + Self.slug(label)
            var counter = 2
            while ids.contains(id) { id = "slot-" + Self.slug(label) + "-\(counter)"; counter += 1 }
            ids.insert(id)
            copy.inputs.append(PromptInput(id: id, label: String(label.prefix(80)), kind: .long_text, placeholder: token,
                                           required: true, why: "Wird an der orangen Stelle in deinen Prompt eingesetzt."))
        }
        return copy
    }

    static func slug(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "de_DE")).lowercased()
        let parts = folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let joined = parts.joined(separator: "-")
        let ascii = String(joined.unicodeScalars.filter { $0.isASCII }.map(Character.init))
        let trimmed = String(ascii.prefix(40))
        return trimmed.isEmpty ? "angabe" : trimmed
    }
}
