import Foundation

/// Keeps the date control tied to the same text used in the prompt and history.
enum PromptDateInput {
    static func selection(from text: String, fallback: Date, timeZone: TimeZone = .current) -> Date {
        parsed(text, timeZone: timeZone) ?? fallback
    }

    static func requiresTextEntry(for text: String, timeZone: TimeZone = .current) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsed(text, timeZone: timeZone) == nil
    }

    static func text(for date: Date, timeZone: TimeZone = .current) -> String {
        style(timeZone: timeZone).format(date)
    }

    private static func parsed(_ text: String, timeZone: TimeZone) -> Date? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= 128 else { return nil }
        let style = style(timeZone: timeZone)
        // Foundation can normalize an impossible date or consume only a prefix.
        // Require the complete date to round trip before showing it in the picker.
        if let date = try? style.parseStrategy.parse(text), style.format(date) == text { return date }

        // Common date-only suggestions use the local day, not UTC midnight.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.isLenient = false
        for format in ["yyyy-MM-dd", "dd.MM.yyyy", "d.M.yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text), formatter.string(from: date) == text { return date }
        }
        return nil
    }

    private static func style(timeZone: TimeZone) -> Date.FormatStyle {
        var style = Date.FormatStyle.dateTime.day().month(.wide).year().locale(Locale(identifier: "de_DE"))
        style.timeZone = timeZone
        return style
    }
}
