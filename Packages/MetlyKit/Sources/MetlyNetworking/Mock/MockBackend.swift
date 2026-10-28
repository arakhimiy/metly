import Foundation
import MetlyCore

/// The mock server's data and rules, as a plain value type (the actor around it adds latency,
/// timers and realtime). Behaviour mirrors what docs/api/README.md asks of the real backend:
/// LWW on `updatedAt`, tombstones, server-owned fields, Free limits and slug assignment.
struct MockBackend: Sendable {
    var user: UserDTO?
    var profile: ProfileDTO?
    var cards: [UUID: CardDTO] = [:]
    var events: [UUID: EventDTO] = [:]
    var connections: [UUID: ConnectionDTO] = [:]
    var followUps: [UUID: FollowUpDTO] = [:]
    var requests: [UUID: ConnectRequestDTO] = [:]
    var tombstones: [UUID: TombstoneDTO] = [:]
    var entitlement: EntitlementDTO = .free
    var blocks: [UUID: BlockDTO] = [:]
    var devices: [String: DeviceRegistrationRequest] = [:]
    var pendingUploads: [String: Data] = [:]
    var assets: [URL: Data] = [:]
    /// Slugs of deleted cards (public page shows "unavailable", never reassigned).
    var retiredSlugs: Set<String> = []
    /// Duplicate connection id → the twin it was merged into (children follow the survivor).
    var mergedConnectionIDs: [UUID: UUID] = [:]

    /// Change feed: record id → sequence number of its latest change (records and tombstones).
    private(set) var changeLog: [UUID: (seq: Int, type: SyncRecordType)] = [:]
    private(set) var sequence = 0

    init() {}

    init(account: MockSeed.Account) {
        user = account.user
        profile = account.profile
        entitlement = account.entitlement
        for card in account.cards { cards[card.id] = card; touch(.card, card.id) }
        for event in account.events { events[event.id] = event; touch(.event, event.id) }
        for connection in account.connections { connections[connection.id] = connection; touch(.connection, connection.id) }
        for followUp in account.followUps { followUps[followUp.id] = followUp; touch(.followUp, followUp.id) }
        for request in account.connectRequests { requests[request.id] = request; touch(.connectRequest, request.id) }
        if let profile { touch(.profile, profile.id) }
    }

    var limits: PlanLimitsDTO { entitlement.limits }

    mutating func touch(_ type: SyncRecordType, _ id: UUID) {
        sequence += 1
        changeLog[id] = (sequence, type)
    }

    // MARK: Pull

    func pull(since cursor: String?, limit: Int, now: Date) throws -> SyncPullResponse {
        let since: Int
        if let cursor {
            guard cursor.hasPrefix("mock:"), let value = Int(cursor.dropFirst(5)), value <= sequence else {
                throw APIError.mock(410, .cursorExpired, "The sync cursor is no longer valid. Pull again without `since`.")
            }
            since = value
        } else {
            since = 0
        }
        let pending = changeLog.filter { $0.value.seq > since }.sorted { $0.value.seq < $1.value.seq }
        let page = pending.prefix(max(1, limit))
        var changes = SyncChanges()
        for (id, entry) in page {
            if let tombstone = tombstones[id] {
                if cursor != nil { changes.tombstones.append(tombstone) }   // full snapshots skip tombstones
                continue
            }
            append(entry.type, id: id, to: &changes)
        }
        let hasMore = pending.count > page.count
        let nextCursor = hasMore ? (page.last?.value.seq ?? sequence) : sequence
        return SyncPullResponse(changes: changes, cursor: "mock:\(nextCursor)", hasMore: hasMore, serverTime: now,
                                entitlement: entitlement)
    }

    private func append(_ type: SyncRecordType, id: UUID, to changes: inout SyncChanges) {
        switch type {
        case .profile: if let profile, profile.id == id { changes.profile = profile }
        case .card: if let card = cards[id] { changes.cards.append(card) }
        case .event: if let event = events[id] { changes.events.append(event) }
        case .connection: if let connection = connections[id] { changes.connections.append(connection) }
        case .followUp: if let followUp = followUps[id] { changes.followUps.append(followUp) }
        case .connectRequest: if let request = requests[id] { changes.connectRequests.append(request) }
        }
    }

    // MARK: Push

    mutating func push(_ changes: SyncChanges, now: Date) -> SyncPushResponse {
        var results: [SyncResultDTO] = []
        var canonical = SyncChanges()
        if let profile = changes.profile { results.append(upsertProfile(profile, canonical: &canonical)) }
        for card in changes.cards { results.append(upsertCard(card, now: now, canonical: &canonical)) }
        for event in changes.events { results.append(upsertEvent(event, canonical: &canonical)) }
        for connection in changes.connections { results.append(upsertConnection(connection, canonical: &canonical)) }
        for followUp in changes.followUps { results.append(upsertFollowUp(followUp, canonical: &canonical)) }
        // Children first so a parent's cascade never hides a child's explicit tombstone.
        let order: [SyncRecordType] = [.followUp, .connection, .event, .card, .connectRequest, .profile]
        let tombstones = changes.tombstones.sorted { order.firstIndex(of: $0.type)! < order.firstIndex(of: $1.type)! }
        for tombstone in tombstones { results.append(delete(tombstone, canonical: &canonical)) }
        return SyncPushResponse(results: results, records: canonical, serverTime: now)
    }

    /// LWW: returns a `stale` result (and the newer canonical state) when the server wins.
    private func staleResult<T: SyncRecordDTO>(_ incoming: T, existing: T?, into keyPath: WritableKeyPath<SyncChanges, [T]>,
                                               canonical: inout SyncChanges) -> SyncResultDTO? {
        if let tombstone = tombstones[incoming.id], incoming.updatedAt <= tombstone.deletedAt {
            canonical.tombstones.append(tombstone)
            return SyncResultDTO(type: T.recordType, id: incoming.id, status: .stale)
        }
        if let existing, existing.updatedAt > incoming.updatedAt {
            canonical[keyPath: keyPath].append(existing)
            return SyncResultDTO(type: T.recordType, id: incoming.id, status: .stale)
        }
        return nil
    }

    private func rejected<T: SyncRecordDTO>(_ record: T, _ error: APIError) -> SyncResultDTO {
        SyncResultDTO(type: T.recordType, id: record.id, status: .rejected, error: error.problem)
    }

    /// `contacts`: at most `ContactEntry.maxCount`, values within their kind's limit (422 validation_failed,
    /// like the server).
    private func invalidContacts<T: SyncRecordDTO>(_ record: T, _ contacts: [ContactEntry]) -> SyncResultDTO? {
        guard let problem = ContactEntry.validationProblem(contacts) else { return nil }
        return rejected(record, .mock(422, .validationFailed, problem, details: ["contacts": problem]))
    }

    mutating func upsertProfile(_ incoming: ProfileDTO, canonical: inout SyncChanges) -> SyncResultDTO {
        if let invalid = invalidContacts(incoming, incoming.contacts) { return invalid }
        if let tombstone = tombstones[incoming.id], incoming.updatedAt <= tombstone.deletedAt {
            canonical.tombstones.append(tombstone)
            return SyncResultDTO(type: .profile, id: incoming.id, status: .stale)
        }
        // One profile per user: the stored id stays canonical even if another device invented its own.
        if let existing = profile, existing.updatedAt > incoming.updatedAt {
            canonical.profile = existing
            return SyncResultDTO(type: .profile, id: incoming.id, status: .stale)
        }
        var stored = incoming
        if let existing = profile {
            stored.id = existing.id
            stored.photoURL = existing.photoURL
            stored.logoURL = existing.logoURL
            stored.createdAt = existing.createdAt
        } else {
            stored.photoURL = nil
            stored.logoURL = nil
        }
        let pauseChanged = profile?.linksPaused != stored.linksPaused
        profile = stored
        user?.profileComplete = stored.isSetupComplete
        touch(.profile, stored.id)
        if pauseChanged {
            for (id, var card) in cards where card.isPaused != stored.linksPaused {
                card.isPaused = stored.linksPaused
                cards[id] = card
                touch(.card, id)
            }
        }
        canonical.profile = stored
        return SyncResultDTO(type: .profile, id: incoming.id, status: .applied)
    }

    mutating func upsertCard(_ incoming: CardDTO, now: Date, canonical: inout SyncChanges) -> SyncResultDTO {
        let existing = cards[incoming.id]
        if let stale = staleResult(incoming, existing: existing, into: \.cards, canonical: &canonical) { return stale }
        if existing == nil, let max = limits.maxCards, cards.count >= max {
            return rejected(incoming, .mock(403, .planLimitReached, "The Free plan includes \(max) cards.", details: ["limit": "\(max)"]))
        }
        if incoming.design.usesProFeatures, entitlement.plan == .free, existing?.design != incoming.design {
            return rejected(incoming, .mock(403, .proRequired, "Editorial and the Ocean and Ember palettes need \(Brand.proName)."))
        }
        var card = incoming
        let slug = existing?.slug ?? makeSlug()
        card.slug = slug
        card.url = Brand.cardURL(slug: slug)
        card.publishState = .published
        card.isReadOnly = existing?.isReadOnly ?? false
        card.isPaused = profile?.linksPaused ?? false
        card.stats = existing?.stats ?? CardStats()
        card.createdAt = existing?.createdAt ?? incoming.createdAt
        card.deletedAt = nil
        cards[card.id] = card
        tombstones[card.id] = nil
        touch(.card, card.id)
        canonical.cards.append(card)
        return SyncResultDTO(type: .card, id: card.id, status: .applied)
    }

    mutating func upsertEvent(_ incoming: EventDTO, canonical: inout SyncChanges) -> SyncResultDTO {
        let existing = events[incoming.id]
        if let stale = staleResult(incoming, existing: existing, into: \.events, canonical: &canonical) { return stale }
        if incoming.status == .active, existing?.status != .active, let max = limits.maxActiveEvents,
           events.values.filter({ $0.status == .active && $0.id != incoming.id }).count >= max {
            return rejected(incoming, .mock(403, .planLimitReached, "The Free plan includes \(max) active event.", details: ["limit": "\(max)"]))
        }
        var event = incoming
        event.deletedAt = nil
        events[event.id] = event
        tombstones[event.id] = nil
        touch(.event, event.id)
        // Rename cascades to tagged connections (SPEC §3.17).
        if let existing, existing.name != event.name {
            for (id, var connection) in connections where connection.eventID == event.id {
                connection.context.eventName = event.name
                connection.updatedAt = max(connection.updatedAt, event.updatedAt)
                connections[id] = connection
                touch(.connection, id)
            }
        }
        canonical.events.append(event)
        return SyncResultDTO(type: .event, id: event.id, status: .applied)
    }

    mutating func upsertConnection(_ incoming: ConnectionDTO, canonical: inout SyncChanges) -> SyncResultDTO {
        if let invalid = invalidContacts(incoming, incoming.contacts) { return invalid }
        let existing = connections[incoming.id]
        if let stale = staleResult(incoming, existing: existing, into: \.connections, canonical: &canonical) { return stale }
        // One connection per Tanishly user: a second record for the same remoteUserID (e.g. created
        // optimistically offline while the server already made one on accept) merges into the
        // existing record; the pushed id is tombstoned.
        if existing == nil, let remoteID = incoming.remoteUserID,
           let twin = connections.values.first(where: { $0.remoteUserID == remoteID && $0.id != incoming.id }) {
            var merged = twin
            if incoming.updatedAt >= twin.updatedAt {
                merged = incoming
                merged.id = twin.id
                merged.createdAt = min(twin.createdAt, incoming.createdAt)
                merged.avatarURL = twin.avatarURL
                if merged.theirCard == nil { merged.theirCard = twin.theirCard }
                if merged.note.isEmpty { merged.note = twin.note }
                merged.contacts.merge(twin.contacts)
            }
            connections[twin.id] = merged
            touch(.connection, twin.id)
            let tombstone = TombstoneDTO(type: .connection, id: incoming.id, deletedAt: incoming.updatedAt)
            tombstones[incoming.id] = tombstone
            touch(.connection, incoming.id)
            mergedConnectionIDs[incoming.id] = twin.id
            // Follow-ups of the duplicate (this push or later ones) belong to the survivor.
            for (id, var followUp) in followUps where followUp.connectionID == incoming.id {
                followUp.connectionID = twin.id
                followUps[id] = followUp
                touch(.followUp, id)
                canonical.followUps.append(followUp)
            }
            canonical.connections.append(merged)
            canonical.tombstones.append(tombstone)
            return SyncResultDTO(type: .connection, id: incoming.id, status: .applied)
        }
        var connection = incoming
        connection.avatarURL = existing?.avatarURL
        connection.deletedAt = nil
        connections[connection.id] = connection
        tombstones[connection.id] = nil
        touch(.connection, connection.id)
        canonical.connections.append(connection)
        return SyncResultDTO(type: .connection, id: connection.id, status: .applied)
    }

    mutating func upsertFollowUp(_ incoming: FollowUpDTO, canonical: inout SyncChanges) -> SyncResultDTO {
        let existing = followUps[incoming.id]
        if let stale = staleResult(incoming, existing: existing, into: \.followUps, canonical: &canonical) { return stale }
        let opensNew = !incoming.isDone && (existing == nil || existing?.isDone == true)
        if opensNew, let max = limits.maxOpenFollowUps,
           followUps.values.filter({ !$0.isDone && $0.id != incoming.id }).count >= max {
            return rejected(incoming, .mock(403, .planLimitReached, "The Free plan includes \(max) active reminders.", details: ["limit": "\(max)"]))
        }
        var followUp = incoming
        followUp.deletedAt = nil
        if let survivor = followUp.connectionID.flatMap({ mergedConnectionIDs[$0] }) { followUp.connectionID = survivor }
        followUps[followUp.id] = followUp
        tombstones[followUp.id] = nil
        touch(.followUp, followUp.id)
        canonical.followUps.append(followUp)
        return SyncResultDTO(type: .followUp, id: followUp.id, status: .applied)
    }

    /// Applies a tombstone (LWW against the live record) and cascades to children.
    mutating func delete(_ tombstone: TombstoneDTO, canonical: inout SyncChanges) -> SyncResultDTO {
        let id = tombstone.id
        if let existingTombstone = tombstones[id] {
            canonical.tombstones.append(existingTombstone)
            return SyncResultDTO(type: tombstone.type, id: id, status: .applied)
        }
        if let liveUpdatedAt = updatedAt(of: tombstone.type, id: id), liveUpdatedAt > tombstone.deletedAt {
            append(tombstone.type, id: id, to: &canonical)
            return SyncResultDTO(type: tombstone.type, id: id, status: .stale)
        }
        remove(tombstone)
        canonical.tombstones.append(tombstone)
        switch tombstone.type {
        case .connection:
            for followUp in followUps.values where followUp.connectionID == id {
                let child = TombstoneDTO(type: .followUp, id: followUp.id, deletedAt: tombstone.deletedAt)
                remove(child)
                canonical.tombstones.append(child)
            }
        case .event:
            for (connectionID, var connection) in connections where connection.eventID == id {
                connection.eventID = nil
                connections[connectionID] = connection
                touch(.connection, connectionID)
            }
        default:
            break
        }
        return SyncResultDTO(type: tombstone.type, id: id, status: .applied)
    }

    private func updatedAt(of type: SyncRecordType, id: UUID) -> Date? {
        switch type {
        case .profile: profile?.id == id ? profile?.updatedAt : nil
        case .card: cards[id]?.updatedAt
        case .event: events[id]?.updatedAt
        case .connection: connections[id]?.updatedAt
        case .followUp: followUps[id]?.updatedAt
        case .connectRequest: requests[id]?.updatedAt
        }
    }

    private mutating func remove(_ tombstone: TombstoneDTO) {
        switch tombstone.type {
        case .profile: if profile?.id == tombstone.id { profile = nil }
        case .card:
            if let slug = cards[tombstone.id]?.slug { retiredSlugs.insert(slug) }
            cards[tombstone.id] = nil
        case .event: events[tombstone.id] = nil
        case .connection: connections[tombstone.id] = nil
        case .followUp: followUps[tombstone.id] = nil
        case .connectRequest: requests[tombstone.id] = nil
        }
        tombstones[tombstone.id] = tombstone
        touch(tombstone.type, tombstone.id)
    }

    // MARK: Helpers

    /// `{firstname}-{4 chars}` — lowercase ASCII, unique.
    func makeSlug() -> String {
        let first = profile?.fullName.split(separator: " ").first.map(String.init) ?? "card"
        let folded = first.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "en_US_POSIX"))
            .lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let stem = folded.isEmpty ? "card" : String(folded.prefix(20))
        let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
        let taken = Set(cards.values.compactMap(\.slug) + MockSeed.peers.map(\.slug)).union(retiredSlugs)
        while true {
            let candidate = stem + "-" + String((0..<4).map { _ in alphabet.randomElement()! })
            if !taken.contains(candidate) { return candidate }
        }
    }

    func card(slug: String) -> CardDTO? { cards.values.first { $0.slug == slug } }
}

extension APIError {
    static func mock(_ status: Int, _ code: APIErrorCode, _ message: String, details: [String: String]? = nil) -> APIError {
        .server(status: status, problem: APIProblem(code: code.rawValue, message: message, requestID: "req_mock", details: details))
    }

    static func notFound(_ what: String) -> APIError { .mock(404, .notFound, "\(what) not found.") }
}
