import Foundation
import MetlyCore
import Synchronization

/// What an on-device language model read from a card's text. Plain values (no FoundationModels
/// types) so the merge and validation logic can be tested with a mock model.
nonisolated struct PaperModelOutput: Equatable, Sendable {
    struct Phone: Equatable, Sendable {
        var number: String
        var label: PhoneLabel?
    }

    var fullName = ""
    var jobTitle = ""
    var company = ""
    var phones: [Phone] = []
    var email = ""
    var telegram = ""
    var website = ""
    var linkedin = ""

    var isEmpty: Bool { self == PaperModelOutput() }
}

/// An on-device model that reads business-card text (Foundation Models on iOS 26+, a mock in tests).
nonisolated protocol PaperCardLanguageModel: Sendable {
    /// Loads the model ahead of time (SCAN calls it when Paper mode opens).
    @concurrent func prepare() async

    /// Reads the card. `partial` receives the fields finished so far while the answer streams in,
    /// so a time-boxed caller can still use the first ones.
    @concurrent func read(_ prompt: String, partial: @escaping @Sendable (PaperModelOutput) -> Void) async throws -> PaperModelOutput
}

/// Runs the model with a time box. A late answer never holds the scan up: when time runs out the
/// fields that were already complete are used, and errors (guardrails, refusals, unsupported
/// language, assets missing) simply mean "no model answer" — the heuristics carry on alone.
nonisolated enum PaperModelRunner {
    static func run(_ model: any PaperCardLanguageModel, prompt: String, timeout: Duration) async -> PaperModelOutput? {
        let race = PaperModelRace()
        let latest = LatestOutput()
        let reading = Task {
            do {
                let output = try await model.read(prompt) { snapshot in latest.set(snapshot) }
                await race.finish(.answered(output))
            } catch {
                await race.finish(.failed)
            }
        }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            await race.finish(.timedOut)
        }
        let outcome = await withTaskCancellationHandler {
            await race.outcome()
        } onCancel: {
            Task { await race.finish(.failed) }
        }
        reading.cancel()
        timer.cancel()
        switch outcome {
        case .answered(let output): return output
        case .timedOut: return latest.value
        case .failed: return nil
        }
    }
}

/// First outcome wins; later ones are ignored.
private actor PaperModelRace {
    nonisolated enum Outcome: Sendable {
        case answered(PaperModelOutput)
        case timedOut
        case failed
    }

    private var result: Outcome?
    private var waiter: CheckedContinuation<Outcome, Never>?

    func finish(_ outcome: Outcome) {
        guard result == nil else { return }
        result = outcome
        waiter?.resume(returning: outcome)
        waiter = nil
    }

    func outcome() async -> Outcome {
        if let result { return result }
        return await withCheckedContinuation { waiter = $0 }
    }
}

/// The fields finished so far, written while the model streams (from any thread).
private nonisolated final class LatestOutput: Sendable {
    private let storage = Mutex<PaperModelOutput?>(nil)

    func set(_ output: PaperModelOutput) { storage.withLock { $0 = output } }

    var value: PaperModelOutput? { storage.withLock { $0 } }
}
