import XCTest
@testable import KlarApp

final class PromptChoiceInputTests: XCTestCase {
    func testLegacyOptionContainingTheSeparatorIsKeptWhole() {
        let options = ["vormittags oder nachmittags", "abends"]
        XCTAssertEqual(PromptChoiceInput.selected(in: options[0], options: options), Set([options[0]]))
        XCTAssertEqual(PromptChoiceInput.selected(in: options.joined(separator: " oder "), options: options), Set(options))
    }

    func testAmbiguousLegacySentencesAreNotGuessed() {
        let options = ["A", "B", "A oder B"]
        XCTAssertNil(PromptChoiceInput.selected(in: "A oder B", options: options))
        XCTAssertEqual(PromptChoiceInput.selected(in: "A oder B", options: options, saved: ["A", "B"]), Set(["A", "B"]))
        XCTAssertEqual(PromptChoiceInput.selected(in: "A oder B", options: options, saved: ["A oder B"]), Set(["A oder B"]))
    }

    func testUnknownTextAndStaleMetadataDoNotBecomeSelections() {
        let options = ["A", "B"]
        XCTAssertNil(PromptChoiceInput.selected(in: "Meine eigene Antwort", options: options, saved: ["A"]))
        XCTAssertEqual(PromptChoiceInput.selected(in: "B", options: options, saved: ["A"]), Set(["B"]))
        XCTAssertEqual(PromptChoiceInput.selected(in: "", options: options, saved: ["A"]), [])
        XCTAssertEqual(PromptChoiceInput.selected(in: "A oder B", options: options), Set(options))
    }

    func testMalformedOrOversizedOptionSetsAreNotEnumerated() {
        XCTAssertEqual(PromptChoiceInput.uniqueOptions(["B", "A", "B", "A"]), ["B", "A"])
        XCTAssertNil(PromptChoiceInput.selected(in: "A", options: ["A", "A"]))
        XCTAssertNil(PromptChoiceInput.selected(in: "A", options: ["A", ""]))
        XCTAssertNil(PromptChoiceInput.selected(in: "1", options: (1...100).map(String.init)))
    }
}
