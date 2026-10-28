import Foundation
import MetlyCore
import Synchronization
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which on-device model reads paper cards on this device (nil = heuristics only).
nonisolated enum PaperCardModels {
    /// Foundation Models on iOS 26+ when Apple Intelligence is turned on and its model is ready.
    static func available() -> (any PaperCardLanguageModel)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.availability == .available {
            return FoundationModelsCardReader()
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)

/// Reads business-card text with Apple's on-device foundation model (guided generation into
/// `GeneratedBusinessCard`). Nothing leaves the device.
@available(iOS 26.0, *)
nonisolated final class FoundationModelsCardReader: PaperCardLanguageModel {
    /// A session prewarmed by `prepare()`, used by the next `read` (sessions keep a transcript,
    /// so each card gets a fresh one).
    private let prepared = Mutex<LanguageModelSession?>(nil)

    private static let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 360)

    @concurrent func prepare() async {
        let session = Self.makeSession()
        session.prewarm()
        prepared.withLock { $0 = session }
    }

    @concurrent func read(_ prompt: String, partial: @escaping @Sendable (PaperModelOutput) -> Void) async throws -> PaperModelOutput {
        let session = prepared.withLock { stored in
            defer { stored = nil }
            return stored
        } ?? Self.makeSession()
        let stream = session.streamResponse(to: prompt, generating: GeneratedBusinessCard.self, options: Self.options)
        var latest: GeneratedBusinessCard.PartiallyGenerated?
        for try await snapshot in stream {
            try Task.checkCancellation()
            latest = snapshot.content
            partial(Self.output(from: snapshot.content, isComplete: false))
        }
        guard let latest else { throw CancellationError() }
        return Self.output(from: latest, isComplete: true)
    }

    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: .default, instructions: PaperModelPrompt.instructions)
    }

    /// Fields are generated in declaration order, so while streaming a field is final once a
    /// later one has started; the last one in progress is left out.
    static func output(from card: GeneratedBusinessCard.PartiallyGenerated, isComplete: Bool) -> PaperModelOutput {
        let started: [Bool] = [card.fullName != nil, card.jobTitle != nil, card.company != nil, card.phones != nil,
                               card.email != nil, card.telegram != nil, card.website != nil, card.linkedin != nil]
        func done(_ index: Int) -> Bool { isComplete || started[(index + 1)...].contains(true) }
        var output = PaperModelOutput()
        if done(0) { output.fullName = clean(card.fullName) }
        if done(1) { output.jobTitle = clean(card.jobTitle) }
        if done(2) { output.company = clean(card.company) }
        if done(3) {
            output.phones = (card.phones ?? []).compactMap { phone in
                let number = clean(phone.number)
                return number.isEmpty ? nil : PaperModelOutput.Phone(number: number, label: phone.label.flatMap(PhoneLabel.init(rawValue:)))
            }
        }
        if done(4) { output.email = clean(card.email) }
        if done(5) { output.telegram = clean(card.telegram) }
        if done(6) { output.website = clean(card.website) }
        if done(7) { output.linkedin = clean(card.linkedin) }
        return output
    }

    private static func clean(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The model's structured answer. Property order is generation order: the roles first (they matter
/// most and finish within the time box), contacts after.
@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedBusinessCard {
    @Guide(description: "The person's full name copied from the card, or empty")
    var fullName: String
    @Guide(description: "The person's job title copied from the card, or empty")
    var jobTitle: String
    @Guide(description: "The company or brand name copied from the card, or empty")
    var company: String
    @Guide(description: "Phone numbers on the card, fax excluded", .maximumCount(5))
    var phones: [GeneratedPhone]
    @Guide(description: "Email address, or empty")
    var email: String
    @Guide(description: "Telegram username or t.me link, or empty")
    var telegram: String
    @Guide(description: "Website, or empty")
    var website: String
    @Guide(description: "LinkedIn profile, or empty")
    var linkedin: String
}

@available(iOS 26.0, *)
@Generable
nonisolated struct GeneratedPhone {
    @Guide(description: "The number as printed, without its label")
    var number: String
    @Guide(description: "Kind of number", .anyOf(["mobile", "work", "home", "other"]))
    var label: String
}

#endif
