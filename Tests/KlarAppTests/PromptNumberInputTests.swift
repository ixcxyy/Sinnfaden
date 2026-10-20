import XCTest
@testable import KlarApp

final class PromptNumberInputTests: XCTestCase {
    func testConsecutiveStepsKeepTheirValueAcrossLocalizedThousandsSeparators() {
        for identifier in ["de_AT", "de_DE", "en_US", "fr_FR", "ar_EG"] {
            let locale = Locale(identifier: identifier)
            var text = "999"
            for expected in 1000...1002 {
                let next = PromptNumberInput.stepperValue(from: text, locale: locale) + 1
                text = PromptNumberInput.text(for: next, locale: locale)
                XCTAssertEqual(PromptNumberInput.stepperValue(from: text, locale: locale), Double(expected), identifier)
            }
            let maximum = PromptNumberInput.text(for: 10_000, locale: locale)
            XCTAssertEqual(PromptNumberInput.stepperValue(from: maximum, locale: locale), 10_000, identifier)
        }
    }

    func testManualPlainNumbersStillWorkWithoutAcceptingPartialNumbers() {
        for identifier in ["de_AT", "de_DE", "en_US", "fr_FR"] {
            let locale = Locale(identifier: identifier)
            XCTAssertEqual(PromptNumberInput.stepperValue(from: "1234", locale: locale), 1234)
            XCTAssertEqual(PromptNumberInput.stepperValue(from: "12.5", locale: locale), 12.5)
            XCTAssertEqual(PromptNumberInput.stepperValue(from: "12kg", locale: locale), 0)
            XCTAssertEqual(PromptNumberInput.stepperValue(from: "", locale: locale), 0)
        }
    }

    func testStepperValueStaysFiniteAndWithinItsBounds() {
        for text in ["nan", "NaN", "inf", "-infinity", "1e400"] {
            XCTAssertEqual(PromptNumberInput.stepperValue(from: text), 0)
        }
        XCTAssertEqual(PromptNumberInput.stepperValue(from: "-5"), 0)
        XCTAssertEqual(PromptNumberInput.stepperValue(from: "20000"), 10_000)
    }
}
