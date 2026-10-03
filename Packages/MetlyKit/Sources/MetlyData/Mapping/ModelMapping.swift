import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData

// DTO ⇄ SwiftData model mapping. `dto` builds the wire value; `apply(_:)` copies every
// server value onto the model; `applyServerOwned(_:)` copies only fields the server owns
// (used while the local record still has unsynced user edits).

// MARK: Profile

public extension Profile {
    var dto: ProfileDTO {
        ProfileDTO(id: id, fullName: fullName, jobTitle: jobTitle, company: company, contactFields: contactFields,
                   defaultCardID: defaultCardID, linksPaused: linksPaused, notificationPrefs: notificationPrefs,
                   privacySettings: privacySettings, isSetupComplete: isSetupComplete, createdAt: createdAt,
                   updatedAt: updatedAt, deletedAt: deletedAt)
    }

    /// Photo/logo bytes are synced separately (presigned uploads), never through this.
    func apply(_ dto: ProfileDTO) {
        if id != dto.id { id = dto.id }   // a profile created offline adopts the server's canonical id
        fullName = dto.fullName
        jobTitle = dto.jobTitle
        company = dto.company
        contactFields = dto.contactFields
        defaultCardID = dto.defaultCardID
        linksPaused = dto.linksPaused
        notificationPrefs = dto.notificationPrefs
        privacySettings = dto.privacySettings
        isSetupComplete = dto.isSetupComplete
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        deletedAt = dto.deletedAt
    }

    func applyServerOwned(_ dto: ProfileDTO) {
        if id != dto.id { id = dto.id }
    }
}

// MARK: Card

public extension Card {
    var dto: CardDTO {
        CardDTO(id: id, name: name, slug: slug.isEmpty ? nil : slug, url: url, sortOrder: sortOrder, design: design,
                publishState: publishState, isReadOnly: isReadOnly, stats: stats, createdAt: createdAt,
                updatedAt: updatedAt, deletedAt: deletedAt)
    }

    convenience init(dto: CardDTO) {
        self.init(id: dto.id, name: dto.name)
        apply(dto)
    }

    func apply(_ dto: CardDTO) {
        name = dto.name
        sortOrder = dto.sortOrder
        design = dto.design
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        deletedAt = dto.deletedAt
        applyServerOwned(dto)
    }

    func applyServerOwned(_ dto: CardDTO) {
        if let slug = dto.slug, !slug.isEmpty { self.slug = slug }
        publishState = dto.publishState
        isReadOnly = dto.isReadOnly
        if let stats = dto.stats { self.stats = stats }
    }
}

// MARK: Event

public extension Event {
    var dto: EventDTO {
        EventDTO(id: id, name: name, place: place, city: city, startDate: startDate, endDate: endDate, cardID: cardID,
                 status: status, calendarEventIdentifier: calendarEventIdentifier, endedAt: endedAt,
                 createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    convenience init(dto: EventDTO) {
        self.init(id: dto.id, name: dto.name)
        apply(dto)
    }

    func apply(_ dto: EventDTO) {
        name = dto.name
        place = dto.place
        city = dto.city
        startDate = dto.startDate
        endDate = dto.endDate
        cardID = dto.cardID
        status = dto.status
        calendarEventIdentifier = dto.calendarEventIdentifier
        endedAt = dto.endedAt
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        deletedAt = dto.deletedAt
    }

    func applyServerOwned(_ dto: EventDTO) {}
}

// MARK: Connection

public extension Connection {
    var dto: ConnectionDTO {
        ConnectionDTO(id: id, remoteUserID: remoteUserID, fullName: fullName, jobTitle: jobTitle, company: company,
                      phone: phone, email: email, telegram: telegram, website: website, linkedin: linkedin,
                      theirCard: theirCard, mySharedCardID: mySharedCardID, source: source, context: context,
                      previousMeetings: previousMeetings, eventID: event?.id ?? context.eventID, note: note, tags: tags,
                      isMerged: isMerged, isPendingMerge: isPendingMerge, isBlocked: isBlocked, createdAt: createdAt,
                      updatedAt: updatedAt, deletedAt: deletedAt)
    }

    convenience init(dto: ConnectionDTO, in context: ModelContext) {
        self.init(id: dto.id, fullName: dto.fullName, source: dto.source)
        context.insert(self)
        apply(dto, in: context)
    }

    /// Resolves the `event` relationship by id in `context`.
    func apply(_ dto: ConnectionDTO, in modelContext: ModelContext) {
        remoteUserID = dto.remoteUserID
        fullName = dto.fullName
        jobTitle = dto.jobTitle
        company = dto.company
        phone = dto.phone
        email = dto.email
        telegram = dto.telegram
        website = dto.website
        linkedin = dto.linkedin
        theirCard = dto.theirCard
        mySharedCardID = dto.mySharedCardID
        source = dto.source
        context = dto.context
        previousMeetings = dto.previousMeetings
        note = dto.note
        tags = dto.tags
        isMerged = dto.isMerged
        isPendingMerge = dto.isPendingMerge
        isBlocked = dto.isBlocked
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        deletedAt = dto.deletedAt
        if event?.id != dto.eventID {
            event = dto.eventID.flatMap { modelContext.record(Event.self, id: $0) }
        }
    }

    func applyServerOwned(_ dto: ConnectionDTO) {}
}

// MARK: FollowUp

public extension FollowUp {
    var dto: FollowUpDTO {
        FollowUpDTO(id: id, connectionID: connection?.id, title: title, channel: channel, dueAt: dueAt, isDone: isDone,
                    completedAt: completedAt, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    convenience init(dto: FollowUpDTO, in context: ModelContext) {
        self.init(id: dto.id, title: dto.title, channel: dto.channel, dueAt: dto.dueAt)
        context.insert(self)
        apply(dto, in: context)
    }

    func apply(_ dto: FollowUpDTO, in context: ModelContext) {
        title = dto.title
        channel = dto.channel
        dueAt = dto.dueAt
        isDone = dto.isDone
        completedAt = dto.completedAt
        createdAt = dto.createdAt
        updatedAt = dto.updatedAt
        deletedAt = dto.deletedAt
        if connection?.id != dto.connectionID {
            connection = dto.connectionID.flatMap { context.record(Connection.self, id: $0) }
        }
    }

    func applyServerOwned(_ dto: FollowUpDTO) {}
}

// MARK: ConnectRequest

public extension ConnectRequest {
    var dto: ConnectRequestDTO {
        ConnectRequestDTO(id: id, direction: direction,
                          peer: PeerSummaryDTO(userID: peerUserID, fullName: peerName, jobTitle: peerTitle,
                                               company: peerCompany, card: peerCard),
                          myCardID: myCardID, method: method, status: status, eventName: eventName, createdAt: createdAt,
                          respondedAt: respondedAt, expiresAt: expiresAt, updatedAt: updatedAt, deletedAt: deletedAt)
    }

    convenience init(dto: ConnectRequestDTO) {
        self.init(id: dto.id, direction: dto.direction, peerUserID: dto.peer.userID, peerName: dto.peer.fullName,
                  method: dto.method)
        apply(dto)
    }

    func apply(_ dto: ConnectRequestDTO) {
        direction = dto.direction
        peerUserID = dto.peer.userID
        peerName = dto.peer.fullName
        peerTitle = dto.peer.jobTitle
        peerCompany = dto.peer.company
        peerCard = dto.peer.card
        myCardID = dto.myCardID
        method = dto.method
        status = dto.status
        eventName = dto.eventName
        createdAt = dto.createdAt
        respondedAt = dto.respondedAt
        expiresAt = dto.expiresAt
        updatedAt = dto.updatedAt
        deletedAt = dto.deletedAt
    }

    /// Everything about a request is server-driven.
    func applyServerOwned(_ dto: ConnectRequestDTO) { apply(dto) }
}

// MARK: Context helpers

public extension ModelContext {
    /// Inserts or overwrites records from server DTOs and marks them synced (no LWW — use for
    /// server-authoritative results such as connect accept responses and realtime events).
    @discardableResult
    func upsert(_ dto: ConnectionDTO) -> Connection {
        let connection: Connection
        if let existing = record(Connection.self, id: dto.id) {
            existing.apply(dto, in: self)
            connection = existing
        } else {
            connection = Connection(dto: dto, in: self)
        }
        connection.syncState = .synced
        return connection
    }

    @discardableResult
    func upsert(_ dto: ConnectRequestDTO) -> ConnectRequest {
        let request: ConnectRequest
        if let existing = record(ConnectRequest.self, id: dto.id) {
            existing.apply(dto)
            request = existing
        } else {
            request = ConnectRequest(dto: dto)
            insert(request)
        }
        request.syncState = .synced
        return request
    }

    /// Snapshot of the whole local store as server DTOs (seeds `MockMetlyServer` from the device).
    func mockAccountSnapshot(email: String?) -> MockSeed.Account? {
        guard let profile = currentProfile() else { return nil }
        let live = #Predicate<Card> { $0.deletedAt == nil }
        let cards = ((try? fetch(FetchDescriptor(predicate: live))) ?? []).map(\.dto)
        let events = ((try? fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []).map(\.dto)
        let connections = ((try? fetch(FetchDescriptor<Connection>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []).map(\.dto)
        let followUps = ((try? fetch(FetchDescriptor<FollowUp>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []).map(\.dto)
        let requests = ((try? fetch(FetchDescriptor<ConnectRequest>(predicate: #Predicate { $0.deletedAt == nil }))) ?? []).map(\.dto)
        let user = UserDTO(id: MockSeed.ownerUserID, email: email ?? MockSeed.ownerEmail, authProviders: [.apple],
                           createdAt: profile.createdAt, profileComplete: profile.isSetupComplete)
        return MockSeed.Account(user: user, profile: profile.dto, cards: cards, events: events, connections: connections,
                                followUps: followUps, connectRequests: requests)
    }
}
