import XCTest
@testable import KlarCore

/// All generations here are local fixtures. No network, model-quality or account-availability claim.
final class CoachPipelineTests: XCTestCase {
    private enum FixtureError: Error, Equatable { case transport }

    private actor Script {
        var inputs: [(instructions: String, input: String)] = []
        let outputs: [Result<String, FixtureError>]
        init(_ outputs: [Result<String, FixtureError>]) { self.outputs = outputs }
        func generate(instructions: String, input: String) throws -> String {
            inputs.append((instructions, input))
            guard inputs.count <= outputs.count else { throw FixtureError.transport }
            return try outputs[inputs.count - 1].get()
        }
    }

    private final class Stages: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [CoachPipelineStage] = []
        func add(_ value: CoachPipelineStage) { lock.lock(); values.append(value); lock.unlock() }
        var all: [CoachPipelineStage] { lock.lock(); defer { lock.unlock() }; return values }
    }

    private actor LateResponse {
        private var called = false
        private var startWaiter: CheckedContinuation<Void, Never>?
        private var responseWaiter: CheckedContinuation<String, Never>?
        func generate() async -> String {
            called = true
            startWaiter?.resume(); startWaiter = nil
            return await withCheckedContinuation { responseWaiter = $0 }
        }
        func waitUntilCalled() async {
            if called { return }
            await withCheckedContinuation { startWaiter = $0 }
        }
        func complete(_ text: String) { responseWaiter?.resume(returning: text); responseWaiter = nil }
    }

    private func goodJSON(_ original: String) throws -> String {
        let response = CoachResponse(status: .already_good, coachMessage: "Dein Prompt ist schon klar.", segments: [PromptSegment(id: "s1", text: original)])
        return String(decoding: try JSONEncoder().encode(response), as: UTF8.self)
    }

    func testValidResponsePreservesInputAndDoesNotRepair() async throws {
        let original = "Erkläre ä, e\u{301} und 👩🏽‍💻.\nBleib bei 3 Sätzen."
        let script = Script([.success(try goodJSON(original))])
        let stages = Stages()
        let result = try await CoachPipeline.run(original: original, generate: { instructions, input in
            try await script.generate(instructions: instructions, input: input)
        }, onStage: { stages.add($0) })
        let inputs = await script.inputs
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].input, original)
        XCTAssertEqual(result.prompt, original)
        XCTAssertEqual(stages.all, [.requesting, .validating])
    }

    func testInvalidFormatAnnouncesExactlyOneRepairKeepingOriginal() async throws {
        let original = "Nenne 3 Beispiele für Café-Kultur."
        let script = Script([.success("{invalid"), .success(try goodJSON(original))])
        let stages = Stages()
        let result = try await CoachPipeline.run(original: original, generate: { instructions, input in
            try await script.generate(instructions: instructions, input: input)
        }, onStage: { stages.add($0) })
        let inputs = await script.inputs
        XCTAssertEqual(inputs.count, 2)
        XCTAssertEqual(inputs[0].input, original)
        let repair = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(inputs[1].input.utf8)) as? [String: Any])
        XCTAssertEqual(repair["original_prompt"] as? String, original)
        XCTAssertEqual(repair["invalid_response"] as? String, "{invalid")
        XCTAssertTrue(inputs[1].instructions.contains("nicht vertrauenswürdiges Prüfmaterial"))
        XCTAssertEqual(result.prompt, original)
        XCTAssertEqual(stages.all, [.requesting, .validating, .repairing, .validating])
    }

    func testCollidingExplanationIDsAreRepairedWithoutAnotherGeneration() async throws {
        let original = "Erkläre Regen."
        let response = CoachResponse(status: .improved, coachMessage: "Zwei Hinweise machen das Ergebnis klarer.", segments: [
            PromptSegment(id: "s1", text: original + " "),
            PromptSegment(id: "s2", text: "Nutze drei Sätze. "),
            PromptSegment(id: "s3", text: "Nenne ein Beispiel.")
        ], changes: [
            PromptChange(id: "c2x", kind: .addition, targetSegmentIDs: ["s2"], category: "Länge", title: "Kurz", explanation: "Die Antwort bleibt kurz."),
            PromptChange(id: "bad id", kind: .addition, targetSegmentIDs: ["s3"], category: "Beispiel", title: "Anschaulich", explanation: "Ein Beispiel hilft beim Verstehen.")
        ])
        let script = Script([.success(String(decoding: try JSONEncoder().encode(response), as: UTF8.self))])
        let stages = Stages()
        let result = try await CoachPipeline.run(original: original, generate: { instructions, input in
            try await script.generate(instructions: instructions, input: input)
        }, onStage: { stages.add($0) })
        let inputs = await script.inputs
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(result.prompt, response.prompt)
        XCTAssertEqual(result.changes.map(\.explanation), response.changes.map(\.explanation))
        XCTAssertEqual(stages.all, [.requesting, .validating])
    }

    func testSecondInvalidFormatFailsWithoutThirdGeneration() async {
        let script = Script([.success("{"), .success("not json")])
        let stages = Stages()
        do {
            _ = try await CoachPipeline.run(original: "Erkläre Regen.", generate: { instructions, input in
                try await script.generate(instructions: instructions, input: input)
            }, onStage: { stages.add($0) })
            XCTFail("Invalid output must not be published")
        } catch { XCTAssertTrue(error is CoachValidationError) }
        let inputs = await script.inputs
        XCTAssertEqual(inputs.count, 2)
        XCTAssertEqual(stages.all.filter { $0 == .repairing }.count, 1)
    }

    func testTransportFailureDoesNotRetryOrChangeInput() async {
        let original = "Mein Entwurf bleibt erhalten."
        let script = Script([.failure(.transport)])
        let stages = Stages()
        do {
            _ = try await CoachPipeline.run(original: original, generate: { instructions, input in
                try await script.generate(instructions: instructions, input: input)
            }, onStage: { stages.add($0) })
            XCTFail("Transport failure must propagate")
        } catch { XCTAssertEqual(error as? FixtureError, .transport) }
        let inputs = await script.inputs
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs.first?.input, original)
        XCTAssertEqual(stages.all, [.requesting])
    }

    func testUTF16LimitBlocksBeforeNetwork() async {
        // Each emoji uses two UTF-16 units; Character.count alone would incorrectly accept this input.
        let original = String(repeating: "😀", count: 12_001)
        let script = Script([])
        let stages = Stages()
        do {
            _ = try await CoachPipeline.run(original: original, generate: { instructions, input in
                try await script.generate(instructions: instructions, input: input)
            }, onStage: { stages.add($0) })
            XCTFail("Oversized input must not generate")
        } catch { XCTAssertTrue(error is CoachValidationError) }
        let inputs = await script.inputs
        XCTAssertTrue(inputs.isEmpty)
        XCTAssertTrue(stages.all.isEmpty)
    }

    func testCancelledLateCompletionCannotReturnAResult() async throws {
        let original = "Erkläre Regen."
        let json = try goodJSON(original)
        let late = LateResponse()
        let stages = Stages()
        let task = Task {
            try await CoachPipeline.run(original: original, generate: { _, _ in await late.generate() }, onStage: { stages.add($0) })
        }
        await late.waitUntilCalled()
        task.cancel()
        await late.complete(json)
        do { _ = try await task.value; XCTFail("Cancelled response must not be published") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(stages.all, [.requesting])
    }

    func testCancelledInvalidCompletionCannotStartRepair() async {
        let late = LateResponse()
        let stages = Stages()
        let task = Task {
            try await CoachPipeline.run(original: "Erkläre Regen.", generate: { _, _ in await late.generate() }, onStage: { stages.add($0) })
        }
        await late.waitUntilCalled()
        task.cancel()
        await late.complete("{invalid")
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(stages.all, [.requesting])
    }
}
