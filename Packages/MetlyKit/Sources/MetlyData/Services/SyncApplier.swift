import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData

/// Applies server records to the local store with last-write-wins on `updatedAt`.
///
/// Rules (per record, matched by `id`):
/// - not local → insert (unless it is a tombstone) and mark `synced`;
/// - local `synced` → overwrite with the server version, unless it is older than what we already
///   have (realtime events and HTTP responses can arrive out of order);
/// - local dirty → overwrite only if the server version is newer, or if this is the push echo
///   for exactly the version we sent; otherwise keep the user's edit and take server-owned
///   fields only (slug, publish state, stats…). A dirty record is never overwritten by older data.
/// - tombstone → hard-delete unless the local record has a newer unsynced edit (it will be
///   re-created on the next push).
@MainActor
struct SyncApplier {
    enum Mode {
        case pull
        /// Canonical records returned by a push; `pushed` = `updatedAt` of each record we sent.
        case echo(pushed: [UUID: Date])
    }

    /// A relationship whose target wasn't in the store when the child was applied (paged pulls
    /// order records by change sequence, so a parent edited later arrives on a later page).
    struct PendingLink: Hashable, Sendable {
        enum Kind: Hashable, Sendable { case connectionEvent, followUpConnection }
        var kind: Kind
        var childID: UUID
        var parentID: UUID
    }

    let context: ModelContext
    let mode: Mode
    private(set) var seenIDs: Set<UUID> = []
    /// The latest server profile seen (photo/logo URLs live only on the DTO).
    private(set) var profile: ProfileDTO?
    /// Server-owned `avatarUrl` of every connection applied (nil = none), keyed by local id.
    private(set) var avatarURLs: [UUID: URL?] = [:]
    /// Connections removed by tombstones.
    private(set) var deletedConnectionIDs: Set<UUID> = []
    /// Links to resolve once their parent arrives — see `resolve(_:in:)`.
    private(set) var pendingLinks: [PendingLink] = []

    init(context: ModelContext, mode: Mode) {
        self.context = context
        self.mode = mode
    }

    mutating func apply(_ changes: SyncChanges) {
        if let profile = changes.profile { apply(profile) }
        for card in changes.cards { apply(card) }
        for event in changes.events { apply(event) }
        for connection in changes.connections { apply(connection) }
        for followUp in changes.followUps { apply(followUp) }
        for request in changes.connectRequests { apply(request) }
        for tombstone in changes.tombstones { apply(tombstone) }
    }

    // MARK: Records

    mutating func apply(_ dto: ProfileDTO) {
        profile = dto
        seenIDs.insert(dto.id)
        let context = context
        // Singleton: match by id, else adopt whatever profile exists locally.
        let local = context.record(Profile.self, id: dto.id) ?? context.currentProfile()
        merge(dto, local: local, insert: {
            let profile = Profile(id: dto.id)
            context.insert(profile)
            profile.apply(dto)
            return profile
        }, applyAll: { $0.apply(dto) }, applyServerOwned: { $0.applyServerOwned(dto) })
    }

    mutating func apply(_ dto: CardDTO) {
        let context = context
        merge(dto, local: context.record(Card.self, id: dto.id), insert: {
            let card = Card(dto: dto)
            context.insert(card)
            return card
        }, applyAll: { $0.apply(dto) }, applyServerOwned: { $0.applyServerOwned(dto) })
    }

    mutating func apply(_ dto: EventDTO) {
        let context = context
        merge(dto, local: context.record(Event.self, id: dto.id), insert: {
            let event = Event(dto: dto)
            context.insert(event)
            return event
        }, applyAll: { $0.apply(dto) }, applyServerOwned: { $0.applyServerOwned(dto) })
    }

    mutating func apply(_ dto: ConnectionDTO) {
        let context = context
        // An optimistic local record for the same Metly user is re-keyed to the server id; a push
        // echo still knows it by the id it was sent with.
        let match = context.matchConnectionReportingRekey(for: dto)
        var tookServerVersion = false
        let merged = merge(dto, local: match.connection, pushedAs: match.previousID, insert: {
            tookServerVersion = true
            return Connection(dto: dto, in: context)
        }, applyAll: {
            $0.apply(dto, in: context)
            tookServerVersion = true
        }, applyServerOwned: { $0.applyServerOwned(dto) })
        guard let merged else { return }
        avatarURLs.updateValue(dto.avatarURL, forKey: merged.id)
        if tookServerVersion, let eventID = dto.eventID, merged.event == nil {
            pendingLinks.append(PendingLink(kind: .connectionEvent, childID: merged.id, parentID: eventID))
        }
    }

    mutating func apply(_ dto: FollowUpDTO) {
        let context = context
        var tookServerVersion = false
        let merged = merge(dto, local: context.record(FollowUp.self, id: dto.id), insert: {
            tookServerVersion = true
            return FollowUp(dto: dto, in: context)
        }, applyAll: {
            $0.apply(dto, in: context)
            tookServerVersion = true
        }, applyServerOwned: { $0.applyServerOwned(dto) })
        if tookServerVersion, let merged, let connectionID = dto.connectionID, merged.connection == nil {
            pendingLinks.append(PendingLink(kind: .followUpConnection, childID: merged.id, parentID: connectionID))
        }
    }

    mutating func apply(_ dto: ConnectRequestDTO) {
        let context = context
        merge(dto, local: context.record(ConnectRequest.self, id: dto.id), insert: {
            let request = ConnectRequest(dto: dto)
            context.insert(request)
            return request
        }, applyAll: { $0.apply(dto) }, applyServerOwned: { $0.applyServerOwned(dto) })
    }

    /// Returns the local record after applying `dto`, or nil when nothing was applied (tombstone,
    /// stale delivery). `pushedAs`: the id the local record had when it was pushed, if different.
    @discardableResult
    private mutating func merge<Model: SyncedRecord, DTO: SyncRecordDTO>(
        _ dto: DTO, local: Model?, pushedAs pushedID: UUID? = nil, insert: () -> Model, applyAll: (Model) -> Void,
        applyServerOwned: (Model) -> Void
    ) -> Model? {
        seenIDs.insert(dto.id)
        if let deletedAt = dto.deletedAt {
            apply(TombstoneDTO(type: DTO.recordType, id: dto.id, deletedAt: deletedAt))
            return nil
        }
        guard let local else {
            let inserted = insert()
            inserted.syncState = .synced
            return inserted
        }
        if local.syncState == .synced {
            guard dto.updatedAt >= local.updatedAt else { return nil }   // stale delivery
            applyAll(local)
        } else if serverWins(local, pushedAs: pushedID ?? local.id, remoteUpdatedAt: dto.updatedAt) {
            applyAll(local)
            local.syncState = .synced
        } else {
            applyServerOwned(local)
        }
        return local
    }

    /// For records with unsynced local changes.
    private func serverWins(_ local: some SyncedRecord, pushedAs pushedID: UUID, remoteUpdatedAt: Date) -> Bool {
        if case .echo(let pushed) = mode, let sent = pushed[pushedID], sent == local.updatedAt { return true }
        return remoteUpdatedAt > local.updatedAt
    }

    // MARK: Tombstones

    mutating func apply(_ tombstone: TombstoneDTO) {
        seenIDs.insert(tombstone.id)
        guard let local = record(of: tombstone.type, id: tombstone.id) else { return }
        if local.syncState != .pendingUpsert || serverWins(local, pushedAs: local.id, remoteUpdatedAt: tombstone.deletedAt) {
            if tombstone.type == .connection { deletedConnectionIDs.insert(tombstone.id) }
            context.delete(local)
        }
    }

    func record(of type: SyncRecordType, id: UUID) -> (any SyncedRecord)? {
        switch type {
        case .profile: context.record(Profile.self, id: id)
        case .card: context.record(Card.self, id: id)
        case .event: context.record(Event.self, id: id)
        case .connection: context.record(Connection.self, id: id)
        case .followUp: context.record(FollowUp.self, id: id)
        case .connectRequest: context.record(ConnectRequest.self, id: id)
        }
    }

    // MARK: Deferred relationships

    /// Sets the relationships whose parent has arrived since; returns the ones still waiting.
    /// Links of records edited locally in the meantime are dropped (the edit decides).
    static func resolve(_ links: [PendingLink], in context: ModelContext) -> [PendingLink] {
        links.filter { link in
            switch link.kind {
            case .connectionEvent:
                guard let connection = context.record(Connection.self, id: link.childID),
                      connection.syncState == .synced, connection.event == nil else { return false }
                guard let event = context.record(Event.self, id: link.parentID) else { return true }
                connection.event = event
                return false
            case .followUpConnection:
                guard let followUp = context.record(FollowUp.self, id: link.childID),
                      followUp.syncState == .synced, followUp.connection == nil else { return false }
                guard let connection = context.record(Connection.self, id: link.parentID) else { return true }
                followUp.connection = connection
                return false
            }
        }
    }
}

/// Everything dirty in the local store, as one `/v1/sync/push` body.
@MainActor
struct SyncPushBatch {
    var changes = SyncChanges()
    /// `updatedAt` of every record sent — lets the echo tell "unchanged since push" apart.
    var pushed: [UUID: Date] = [:]
    var types: [UUID: SyncRecordType] = [:]
    var hasMore = false
    /// `deletedAt` of the oldest tombstone held back by `cutoff` (it goes out once due).
    var earliestHeldDeletion: Date?

    var isEmpty: Bool { changes.isEmpty }

    /// - Parameter cutoff: tombstones deleted after it stay local for now (Undo window).
    static func collect(from context: ModelContext, state: SyncStateStore, limit: Int = 200,
                        tombstonesDeletedBefore cutoff: Date = .distantFuture) -> SyncPushBatch {
        var batch = SyncPushBatch()
        batch.add(dirty(Profile.self, in: context), type: .profile, state: state, limit: limit, cutoff: cutoff) { batch, profile in
            batch.changes.profile = profile.dto
        }
        batch.add(dirty(Card.self, in: context), type: .card, state: state, limit: limit, cutoff: cutoff) {
            $0.changes.cards.append($1.dto)
        }
        batch.add(dirty(Event.self, in: context), type: .event, state: state, limit: limit, cutoff: cutoff) {
            $0.changes.events.append($1.dto)
        }
        batch.add(dirty(Connection.self, in: context), type: .connection, state: state, limit: limit, cutoff: cutoff) {
            $0.changes.connections.append($1.dto)
        }
        batch.add(dirty(FollowUp.self, in: context), type: .followUp, state: state, limit: limit, cutoff: cutoff) {
            $0.changes.followUps.append($1.dto)
        }
        return batch
    }

    private mutating func add<Model: SyncedRecord>(_ records: [Model], type: SyncRecordType, state: SyncStateStore, limit: Int,
                                                   cutoff: Date, upsert: (inout SyncPushBatch, Model) -> Void) {
        for record in records {
            guard changes.count < limit else {
                hasMore = true
                return
            }
            switch record.syncState {
            case .synced:
                continue
            case .pendingDelete:
                guard Self.isDue(record, cutoff: cutoff) else {
                    let deletedAt = record.deletedAt ?? record.updatedAt
                    earliestHeldDeletion = min(earliestHeldDeletion ?? deletedAt, deletedAt)
                    continue
                }
                changes.tombstones.append(TombstoneDTO(type: type, id: record.id, deletedAt: record.deletedAt ?? record.updatedAt))
            case .pendingUpsert:
                if state.isRejected(record.id, updatedAt: record.updatedAt) { continue }
                upsert(&self, record)
            }
            pushed[record.id] = record.updatedAt
            types[record.id] = type
        }
    }

    /// A local delete is pushed once it is older than `cutoff`.
    static func isDue(_ record: some SyncedRecord, cutoff: Date) -> Bool {
        (record.deletedAt ?? record.updatedAt) <= cutoff
    }

    static func dirty<Model: SyncedRecord>(_ type: Model.Type, in context: ModelContext) -> [Model] {
        let synced = SyncState.synced.rawValue
        let descriptor = FetchDescriptor<Model>(predicate: #Predicate { $0.syncStateRaw != synced })
        return ((try? context.fetch(descriptor)) ?? []).sorted { $0.updatedAt < $1.updatedAt }
    }

    /// When the earliest held-back tombstone leaves its Undo window (nil: none waiting).
    static func nextHeldTombstone(in context: ModelContext, grace: TimeInterval, now: Date = .now) -> Date? {
        guard grace > 0 else { return nil }
        let cutoff = now.addingTimeInterval(-grace)
        let pendingDelete = SyncState.pendingDelete.rawValue
        func earliest<Model: SyncedRecord>(_ type: Model.Type) -> Date? {
            let descriptor = FetchDescriptor<Model>(predicate: #Predicate { $0.syncStateRaw == pendingDelete })
            return ((try? context.fetch(descriptor)) ?? [])
                .filter { !isDue($0, cutoff: cutoff) }
                .map { ($0.deletedAt ?? $0.updatedAt).addingTimeInterval(grace) }
                .min()
        }
        return [earliest(Profile.self), earliest(Card.self), earliest(Event.self), earliest(Connection.self),
                earliest(FollowUp.self)].compactMap { $0 }.min()
    }
}
