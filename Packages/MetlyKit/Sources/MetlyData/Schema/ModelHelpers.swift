import Foundation
import MetlyCore
import SwiftData

// Shared fetch descriptors / predicates so every feature filters tombstones the same way.

public extension Card {
    static var live: FetchDescriptor<Card> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.sortOrder)])
    }

    /// Profile entries this card shows, in the profile's order, before the audience filter.
    func selectedContacts(of profile: Profile) -> [ContactEntry] {
        profile.contacts(selectedBy: visibleContactIDs, design: design)
    }

    /// Stores a selection of profile entries, keeping `design.visibleFields` in step with it.
    func setSelectedContacts(_ ids: [UUID], of profile: Profile) {
        visibleContactIDs = ids
        design.syncVisibleFields(with: ids, in: profile.contacts)
    }

    /// Values rendered on this card's face for the given audience.
    func faceContent(profile: Profile?, audience: CardAudience, qrPayload: String? = nil) -> CardFaceContent {
        guard let profile else { return CardFaceContent(fullName: name) }
        let visible = selectedContacts(of: profile).filter { audience.allows($0.privacy) }
        return CardFaceContent(
            fullName: profile.fullName,
            jobTitle: profile.jobTitle,
            company: profile.company,
            photoData: profile.photoData,
            logoData: profile.logoData,
            fields: ContactFieldKind.allCases.compactMap { visible.first(of: $0)?.field },
            // Unpublished cards have no link yet: never encode a fake card URL (CardKit falls back to the site).
            qrPayload: qrPayload ?? url?.absoluteString ?? "",
            additionalPhones: Array(visible.entries(of: .phone).dropFirst().map(\.labeledPhone)),
            phoneLabel: visible.legacyPhoneLabel,
            contacts: visible
        )
    }
}

public extension Connection {
    static var live: FetchDescriptor<Connection> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil && !$0.isBlocked },
                        sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    }
}

public extension FollowUp {
    static var open: FetchDescriptor<FollowUp> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil && !$0.isDone }, sortBy: [SortDescriptor(\.dueAt)])
    }
}

public extension Event {
    static var active: FetchDescriptor<Event> {
        let active = EventStatus.active.rawValue
        return FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil && $0.statusRaw == active },
                               sortBy: [SortDescriptor(\.startDate)])
    }
}

public extension ConnectRequest {
    static var pendingIncoming: FetchDescriptor<ConnectRequest> {
        let incoming = ConnectRequestDirection.incoming.rawValue
        let pending = ConnectRequestStatus.pending.rawValue
        return FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil && $0.directionRaw == incoming && $0.statusRaw == pending },
                               sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
    }
}

public extension ModelContext {
    /// The signed-in user's profile (nil before setup).
    func currentProfile() -> Profile? {
        var descriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }

    func defaultCard() -> Card? {
        let cards = (try? fetch(Card.live)) ?? []
        if let id = currentProfile()?.defaultCardID, let card = cards.first(where: { $0.id == id }) { return card }
        return cards.first
    }

    func activeEvent() -> Event? {
        try? fetch(Event.active).first
    }

    /// Card to share right now: the active event's card, else the default card.
    func cardToShare() -> Card? {
        if let id = activeEvent()?.cardID, let card = try? fetch(Card.live).first(where: { $0.id == id }) { return card }
        return defaultCard()
    }

    func record<T: SyncedRecord>(_ type: T.Type, id: UUID) -> T? {
        var descriptor = FetchDescriptor<T>(predicate: T.idPredicate(id))
        descriptor.fetchLimit = 1
        return try? fetch(descriptor).first
    }
}
