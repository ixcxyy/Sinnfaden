import XCTest
import AppKit
@testable import KlarApp

/// The send and loading motion: reproducible per seed, different between runs, within its
/// phase windows, bounded in pieces, and shortened (never cut) when the answer is fast.
final class SendChoreographyTests: XCTestCase {
    @MainActor
    func testNativeCaptureKeepsPunctuationCurrencyEmojiAndWrappedGeometry() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 480))
        window.contentView?.addSubview(text)
        text.font = NSFont.systemFont(ofSize: 19)
        text.textContainerInset = .zero
        text.textContainer?.containerSize = NSSize(width: 200, height: 10000)
        text.string = "Nur 25 €! 🙂\nKeine Pilze,   kein Ofen.\nhttps://example.org/verylongwordwithoutspacesabcdefghijk"
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        let words = PromptEditorHandle.captureWords(in: text)
        let expected = text.string.filter { !$0.isWhitespace }
        XCTAssertEqual(words.map(\.text).joined(), expected, "Every visible character must leave with the words")
        XCTAssertTrue(words.allSatisfy { $0.frame.height < 40 }, "A wrapped token is captured per line, not as a multi-line rectangle")
        XCTAssertFalse(words.isEmpty)
    }

    private func words(_ count: Int) -> [CapturedWord] {
        (0..<count).map { index in
            CapturedWord(id: index, text: "Wort\(index)", frame: CGRect(x: 40 + CGFloat(index % 8) * 70, y: 300 + CGFloat(index / 8) * 26, width: 60, height: 22))
        }
    }

    private let start = Date(timeIntervalSinceReferenceDate: 1_000)
    private let target = CGPoint(x: 400, y: 160)

    private func snapshot(_ launch: WordLaunch, at elapsed: Double) -> [CGPoint] {
        launch.words.enumerated().map { WordVortex.state(for: $0.element, index: $0.offset, launch: launch, elapsed: elapsed, origin: .zero, target: target).center }
    }

    func testSameSeedReproducesTheRunAndOtherSeedsVary() {
        let a = WordLaunch(words: words(14), fontSize: 19, start: start, seed: 42)
        let b = WordLaunch(words: words(14), fontSize: 19, start: start, seed: 42)
        for elapsed in [0.05, 0.2, 0.45, 0.6] { XCTAssertEqual(snapshot(a, at: elapsed), snapshot(b, at: elapsed)) }
        XCTAssertEqual(LiquidVariation(seed: 42), LiquidVariation(seed: 42))

        let others = [43, 44, 45].map { WordLaunch(words: words(14), fontSize: 19, start: start, seed: UInt64($0)) }
        for other in others { XCTAssertNotEqual(snapshot(a, at: 0.45), snapshot(other, at: 0.45), "Runs must not repeat") }
        XCTAssertEqual(Set([42, 43, 44, 45].map { LiquidVariation(seed: UInt64($0)).breathe }).count, 4)
    }

    func testPhasesKeepTheirWindowsWithoutAFirstFrameJump() {
        for count in [3, 12, 60, 200] {
            let launch = WordLaunch(words: words(count), fontSize: 19, start: start, seed: UInt64(count))
            XCTAssertLessThanOrEqual(launch.words.count, WordLaunch.maximumPieces, "Bounded pieces for \(count) words")
            if count > 8 { XCTAssertLessThan(launch.words.count, count, "Neighbours travel together") }
            for (index, piece) in launch.words.enumerated() {
                // First frame: exactly where the editor drew them.
                let first = WordVortex.state(for: piece, index: index, launch: launch, elapsed: 0, origin: .zero, target: target)
                XCTAssertEqual(first.center.x, piece.frame.midX, accuracy: 0.01)
                XCTAssertEqual(first.center.y, piece.frame.midY, accuracy: 0.01)
                XCTAssertEqual(first.textOpacity, 1)
                // A: lifted together within 100 ms, nothing has left its place yet.
                let lifted = WordVortex.state(for: piece, index: index, launch: launch, elapsed: 0.1, origin: .zero, target: target)
                XCTAssertEqual(lifted.center.x, piece.frame.midX, accuracy: 0.01)
                XCTAssertLessThan(lifted.center.y, piece.frame.midY)
                // B: detaching between 100 and 300 ms; C: every contact before ~700 ms.
                XCTAssertGreaterThanOrEqual(launch.delay(index), 0.1)
                XCTAssertLessThanOrEqual(launch.delay(index), 0.3 + 1e-9)
                XCTAssertLessThanOrEqual(launch.arrival(index) - start.timeIntervalSinceReferenceDate, 0.7)
            }
            XCTAssertLessThanOrEqual(launch.duration, 0.75)
        }
    }

    func testGroupedWordsKeepTheirIndividualTypographyAndLinePositions() {
        let captured = (0..<40).map { index in
            CapturedWord(id: index, text: "Wort\(index),", frame: CGRect(x: 40 + CGFloat(index % 2) * 130,
                                                                       y: 100 + CGFloat(index / 2) * 30,
                                                                       width: 75, height: 22))
        }
        let launch = WordLaunch(words: captured, fontSize: 19, start: start, seed: 42)
        XCTAssertLessThanOrEqual(launch.words.count, WordLaunch.maximumPieces)
        let fragments = launch.words.flatMap(\.sourceFragments)
        XCTAssertEqual(fragments.map(\.text), captured.map(\.text), "No normalized spaces, missing punctuation or merged line text")
        XCTAssertEqual(fragments.map(\.frame), captured.map(\.frame), "Every glyph group retains its actual starting frame")
    }

    func testDropsBecomeThreadsBeforeMerging() {
        let launch = WordLaunch(words: words(4), fontSize: 19, start: start, seed: 7)
        let late = WordVortex.state(for: launch.words[0], index: 0, launch: launch, elapsed: launch.delay(0) + WordLaunch.flight * 0.85, origin: .zero, target: target)
        XCTAssertLessThan(late.textOpacity, 0.05, "Letters have become liquid")
        XCTAssertGreaterThan(late.stretch, 2, "The drop is drawn out into a thread")
        XCTAssertEqual(WordVortex.beads(for: late, offset: .zero).count, 4)
    }

    func testLoadingVariationStaysCalm() {
        for seed in 1...300 {
            let variation = LiquidVariation(seed: UInt64(seed))
            XCTAssertTrue((2...4).contains(variation.regions.count))
            XCTAssertTrue((0.02...0.04).contains(variation.breathe), "Breathing 2–4 %")
            XCTAssertTrue((0.10...0.16).contains(variation.outgrowthReach))
            XCTAssertLessThanOrEqual(variation.regions.map(\.amplitude).reduce(0, +), 0.08 + 1e-9)
        }
    }

    func testOutgrowthFormsStretchesAndFlowsBack() {
        let variation = LiquidVariation(seed: 9)
        XCTAssertNil(variation.outgrowth(at: variation.outgrowthFirst - 0.1))
        let peak = variation.outgrowth(at: variation.outgrowthFirst + 1.0)
        XCTAssertGreaterThan(peak?.extent ?? 0, 0.9)
        XCTAssertNil(variation.outgrowth(at: variation.outgrowthFirst + 2.5), "It has merged back")
        let next = variation.outgrowth(at: variation.outgrowthFirst + variation.outgrowthInterval + 1.0)
        XCTAssertNotNil(next)
        XCTAssertNotEqual(next?.angle, peak?.angle, "Each reach goes its own way")
    }

    func testFastAnswerShortensTheRestInsteadOfCuttingIt() {
        let launch = WordLaunch(words: words(12), fontSize: 19, start: start, seed: 3)
        let early = start.addingTimeInterval(0.2)
        let remaining = GatheringStage.remaining(launch, answerAt: early)
        XCTAssertGreaterThan(remaining, 0.1)
        XCTAssertLessThan(remaining, 0.25, "Never more than a short beat")
        // From the answer on, time runs three times as fast: the last drop still lands.
        let after = GatheringStage.elapsed(at: early.addingTimeInterval(remaining), launch: launch, hurryFrom: early)
        XCTAssertGreaterThanOrEqual(after, launch.arrival(launch.words.count - 1) - start.timeIntervalSinceReferenceDate)
        XCTAssertEqual(GatheringStage.remaining(launch, answerAt: start.addingTimeInterval(3)), 0)
    }
}
