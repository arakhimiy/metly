import Foundation
import MetlyData
import SwiftData

/// Names and words a voice note is likely to contain — the people you meet, their companies, your events
/// and tags — handed to the recognizer so "Payme" or "Kamila" come out spelled the way you know them.
nonisolated enum DictationVocabulary {
    /// Recognizers work best with a short list.
    static let limit = 100

    /// Most specific first (this meeting, then recent people), without blanks or repeats.
    static func make(_ groups: [[String]]) -> [String] {
        var seen = Set<String>()
        var words: [String] = []
        for word in groups.joined() {
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 1, seen.insert(trimmed.lowercased()).inserted else { continue }
            words.append(trimmed)
            if words.count == limit { break }
        }
        return words
    }

    /// The draft's event, place, city and tags; your company; then recent people's names and companies.
    @MainActor
    static func gather(for draft: CaptureDraft, in context: ModelContext) -> [String] {
        var recent = Connection.live   // newest first
        recent.fetchLimit = 40
        let people = (try? context.fetch(recent)) ?? []
        let events = (try? context.fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []
        return make([
            [draft.eventName, draft.place, draft.city],
            draft.tags,
            [context.currentProfile()?.company ?? ""],
            people.flatMap { [$0.fullName, $0.company] },
            events.map(\.name),
        ])
    }
}
