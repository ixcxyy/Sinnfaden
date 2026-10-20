import Foundation

/// Text conversion shared by the numeric field and its stepper.
enum PromptNumberInput {
    static func stepperValue(from text: String, locale: Locale = .current) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Double
        // Read the same localized format we write, including grouping and non-Latin digits.
        // A full formatting round trip rejects parsers that consume only a prefix ("12kg").
        if let localized = try? Double(trimmed, format: .number.locale(locale), lenient: false),
           localized.isFinite, self.text(for: localized, locale: locale) == trimmed {
            value = localized
        } else {
            value = Double(trimmed) ?? 0
        }
        guard value.isFinite else { return 0 }
        // The text remains editable verbatim; only the stepper's numeric state is bounded.
        return min(10_000, max(0, value))
    }

    static func text(for value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
}
