import XCTest
@testable import KlarApp

final class PromptDateInputTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int, in timeZone: TimeZone) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    func testSavedDateRestoresInsteadOfShowingTodaysFallbackAcrossTimeZones() throws {
        for identifier in ["Europe/Vienna", "America/Los_Angeles", "Pacific/Auckland"] {
            let zone = try XCTUnwrap(TimeZone(identifier: identifier))
            let saved = try date(2028, 2, 29, in: zone)
            let fallback = try date(2026, 10, 20, in: zone)
            let text = PromptDateInput.text(for: saved, timeZone: zone)
            XCTAssertEqual(PromptDateInput.selection(from: text, fallback: fallback, timeZone: zone), saved, identifier)
            XCTAssertFalse(PromptDateInput.requiresTextEntry(for: text, timeZone: zone))
        }
    }

    func testChangingHistoryEntriesUsesTheNewEntriesDate() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Vienna"))
        let first = try date(2026, 12, 24, in: zone)
        let second = try date(2027, 1, 5, in: zone)
        let firstText = PromptDateInput.text(for: first, timeZone: zone)
        let secondText = PromptDateInput.text(for: second, timeZone: zone)
        let selected = PromptDateInput.selection(from: firstText, fallback: second, timeZone: zone)
        XCTAssertEqual(selected, first)
        XCTAssertEqual(PromptDateInput.selection(from: secondText, fallback: selected, timeZone: zone), second)
    }

    func testCommonUnambiguousSuggestedDatesUseTheSameLocalCalendarDay() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let expected = try date(2026, 12, 24, in: zone)
        let fallback = try date(2026, 10, 20, in: zone)
        for text in ["2026-12-24", "24.12.2026"] {
            XCTAssertEqual(PromptDateInput.selection(from: text, fallback: fallback, timeZone: zone), expected)
            XCTAssertFalse(PromptDateInput.requiresTextEntry(for: text, timeZone: zone))
        }
    }

    func testUnknownAndInvalidDatesStayEditableAsTextWithoutGuessingADate() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Vienna"))
        let fallback = try date(2026, 10, 20, in: zone)
        for text in ["nächsten Freitag", "31. Februar 2026", "2026-02-31", "24. Dezember 2026 und später"] {
            XCTAssertTrue(PromptDateInput.requiresTextEntry(for: text, timeZone: zone), text)
            XCTAssertEqual(PromptDateInput.selection(from: text, fallback: fallback, timeZone: zone), fallback)
        }
        XCTAssertFalse(PromptDateInput.requiresTextEntry(for: "", timeZone: zone))
        XCTAssertEqual(PromptDateInput.selection(from: "", fallback: fallback, timeZone: zone), fallback)
    }
}
