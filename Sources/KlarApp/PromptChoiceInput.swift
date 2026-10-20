import Foundation

enum PromptChoiceInput {
    static let separator = " oder "

    static func uniqueOptions(_ options: [String]) -> [String] {
        var seen = Set<String>()
        return options.filter { seen.insert($0).inserted }
    }

    static func selected(in text: String, options: [String], saved: [String]? = nil) -> Set<String>? {
        guard (1...8).contains(options.count), Set(options).count == options.count,
              options.allSatisfy({ !$0.isEmpty && $0.utf16.count <= 60 }) else { return nil }
        if text.isEmpty { return [] }
        if let saved {
            let selected = Set(saved)
            if selected.count == saved.count, selected.isSubset(of: Set(options)),
               options.filter({ selected.contains($0) }).joined(separator: separator) == text { return selected }
        }
        guard text.utf16.count <= options.reduce(0, { $0 + $1.utf16.count }) + (options.count - 1) * separator.utf16.count else { return nil }

        // Older records have only the sentence. Accept it only if exactly one ordered
        // subset explains it; labels may themselves contain the joining word.
        var matches: [Set<String>] = []
        func visit(_ index: Int, selected: [String], rendered: String) {
            guard matches.count < 2 else { return }
            if index == options.count {
                if rendered == text { matches.append(Set(selected)) }
                return
            }
            visit(index + 1, selected: selected, rendered: rendered)
            let next = rendered + (selected.isEmpty ? "" : separator) + options[index]
            if text.hasPrefix(next) { visit(index + 1, selected: selected + [options[index]], rendered: next) }
        }
        visit(0, selected: [], rendered: "")
        return matches.count == 1 ? matches[0] : nil
    }
}
