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

    let context: ModelContext
    let mode: Mode
    private(set) var seenIDs: Set<UUID> = []
    /// The latest server profile seen (photo/logo URLs live only on the DTO).
    private(set) var profile: ProfileDTO?

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
        merge(dto, local: context.matchConnection(for: dto), insert: { Connection(dto: dto, in: context) },
              applyAll: { $0.apply(dto, in: context) }, applyServerOwned: { $0.applyServerOwned(dto) })
    }

    mutating func apply(_ dto: FollowUpDTO) {
        let context = context
        merge(dto, local: context.record(FollowUp.self, id: dto.id), insert: { FollowUp(dto: dto, in: context) },
              applyAll: { $0.apply(dto, in: context) }, applyServerOwned: { $0.applyServerOwned(dto) })
    }

    mutating func apply(_ dto: ConnectRequestDTO) {
        let context = context
        merge(dto, local: context.record(ConnectRequest.self, id: dto.id), insert: {
            let request = ConnectRequest(dto: dto)
            context.insert(request)
            return request
        }, applyAll: { $0.apply(dto) }, applyServerOwned: { $0.applyServerOwned(dto) })
    }

    private mutating func merge<Model: SyncedRecord, DTO: SyncRecordDTO>(
        _ dto: DTO, local: Model?, insert: () -> Model, applyAll: (Model) -> Void, applyServerOwned: (Model) -> Void
    ) {
        seenIDs.insert(dto.id)
        if let deletedAt = dto.deletedAt {
            apply(TombstoneDTO(type: DTO.recordType, id: dto.id, deletedAt: deletedAt))
            return
        }
        guard let local else {
            insert().syncState = .synced
            return
        }
        if local.syncState == .synced {
            guard dto.updatedAt >= local.updatedAt else { return }   // stale delivery
            applyAll(local)
        } else if serverWins(local, remoteUpdatedAt: dto.updatedAt) {
            applyAll(local)
            local.syncState = .synced
        } else {
            applyServerOwned(local)
        }
    }

    /// For records with unsynced local changes.
    private func serverWins(_ local: some SyncedRecord, remoteUpdatedAt: Date) -> Bool {
        if case .echo(let pushed) = mode, let sent = pushed[local.id], sent == local.updatedAt { return true }
        return remoteUpdatedAt > local.updatedAt
    }

    // MARK: Tombstones

    mutating func apply(_ tombstone: TombstoneDTO) {
        seenIDs.insert(tombstone.id)
        guard let local = record(of: tombstone.type, id: tombstone.id) else { return }
        if local.syncState != .pendingUpsert || serverWins(local, remoteUpdatedAt: tombstone.deletedAt) {
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
}

/// Everything dirty in the local store, as one `/v1/sync/push` body.
@MainActor
struct SyncPushBatch {
    var changes = SyncChanges()
    /// `updatedAt` of every record sent — lets the echo tell "unchanged since push" apart.
    var pushed: [UUID: Date] = [:]
    var types: [UUID: SyncRecordType] = [:]
    var hasMore = false

    var isEmpty: Bool { changes.isEmpty }

    static func collect(from context: ModelContext, state: SyncStateStore, limit: Int = 200) -> SyncPushBatch {
        var batch = SyncPushBatch()
        batch.add(dirty(Profile.self, in: context), type: .profile, state: state, limit: limit) { batch, profile in
            batch.changes.profile = profile.dto
        }
        batch.add(dirty(Card.self, in: context), type: .card, state: state, limit: limit) { $0.changes.cards.append($1.dto) }
        batch.add(dirty(Event.self, in: context), type: .event, state: state, limit: limit) { $0.changes.events.append($1.dto) }
        batch.add(dirty(Connection.self, in: context), type: .connection, state: state, limit: limit) {
            $0.changes.connections.append($1.dto)
        }
        batch.add(dirty(FollowUp.self, in: context), type: .followUp, state: state, limit: limit) {
            $0.changes.followUps.append($1.dto)
        }
        return batch
    }

    private mutating func add<Model: SyncedRecord>(_ records: [Model], type: SyncRecordType, state: SyncStateStore, limit: Int,
                                                   upsert: (inout SyncPushBatch, Model) -> Void) {
        for record in records {
            guard changes.count < limit else {
                hasMore = true
                return
            }
            switch record.syncState {
            case .synced:
                continue
            case .pendingDelete:
                changes.tombstones.append(TombstoneDTO(type: type, id: record.id, deletedAt: record.deletedAt ?? record.updatedAt))
            case .pendingUpsert:
                if state.isRejected(record.id, updatedAt: record.updatedAt) { continue }
                upsert(&self, record)
            }
            pushed[record.id] = record.updatedAt
            types[record.id] = type
        }
    }

    static func dirty<Model: SyncedRecord>(_ type: Model.Type, in context: ModelContext) -> [Model] {
        let synced = SyncState.synced.rawValue
        let descriptor = FetchDescriptor<Model>(predicate: #Predicate { $0.syncStateRaw != synced })
        return ((try? context.fetch(descriptor)) ?? []).sorted { $0.updatedAt < $1.updatedAt }
    }
}
