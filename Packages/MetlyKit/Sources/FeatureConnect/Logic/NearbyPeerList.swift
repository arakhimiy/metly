import Foundation
import MetlyNetworking

/// The live "Nearby on Metly" list: resolved peers de-duplicated by user, blocked people and
/// yourself filtered out, kept in first-seen order so rows don't jump around.
nonisolated struct NearbyPeerList: Equatable, Sendable {
    private(set) var people: [NearbyPerson] = []

    init(people: [NearbyPerson] = []) {
        self.people = people
    }

    var isEmpty: Bool { people.isEmpty }

    func person(withToken token: String) -> NearbyPerson? {
        people.first { $0.tokens.contains(token) }
    }

    func person(withID userID: UUID) -> NearbyPerson? {
        people.first { $0.userID == userID }
    }

    func contains(token: String) -> Bool {
        person(withToken: token) != nil
    }

    /// Adds peers the server resolved. Blocked users, your own token and your own account are skipped;
    /// a user seen under several tokens becomes one row (details refreshed, tokens merged).
    mutating func merge(_ resolved: [NearbyPeerDTO], blocked: Set<UUID>, ownToken: String? = nil, ownUserID: UUID? = nil) {
        for dto in resolved {
            guard !blocked.contains(dto.userID), dto.token != ownToken, dto.userID != ownUserID else { continue }
            if let index = people.firstIndex(where: { $0.userID == dto.userID }) {
                var person = people[index]
                person.tokens.removeAll { $0 == dto.token }
                person.tokens.append(dto.token)
                person.fullName = dto.fullName
                person.jobTitle = dto.jobTitle
                person.company = dto.company
                person.avatarURL = dto.avatarURL ?? person.avatarURL
                person.card = dto.card ?? person.card
                people[index] = person
            } else {
                people.append(NearbyPerson(dto))
            }
        }
    }

    /// A token went out of range: the person disappears once none of their tokens is left.
    /// Returns the removed person, if any.
    @discardableResult
    mutating func remove(token: String) -> NearbyPerson? {
        guard let index = people.firstIndex(where: { $0.tokens.contains(token) }) else { return nil }
        people[index].tokens.removeAll { $0 == token }
        guard people[index].tokens.isEmpty else { return nil }
        return people.remove(at: index)
    }

    /// Re-applies the block list (someone was blocked while Connect is open).
    mutating func removeBlocked(_ blocked: Set<UUID>) {
        people.removeAll { blocked.contains($0.userID) }
    }
}
