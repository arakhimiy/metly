import Foundation
import MetlyCore

// Non-sync behaviour of the mock backend: auth, public profiles, connect, cards & events helpers.
extension MockBackend {

    // MARK: Auth

    mutating func signIn(provider: AuthProvider, email: String?, suggestedName: String?, now: Date) -> AuthResponse {
        let isNewUser = user == nil
        let account = user ?? UserDTO(id: UUID(), email: email ?? "you@privaterelay.appleid.com", authProviders: [provider],
                                      createdAt: now, profileComplete: false)
        var updated = account
        if !updated.authProviders.contains(provider) { updated.authProviders.append(provider) }
        updated.profileComplete = profile?.isSetupComplete ?? false
        user = updated
        let tokens = SessionTokens(accessToken: "mock-access-\(UUID().uuidString)", refreshToken: "mock-refresh-\(UUID().uuidString)",
                                   accessTokenExpiresAt: now.addingTimeInterval(3600),
                                   refreshTokenExpiresAt: now.addingTimeInterval(60 * 86_400))
        return AuthResponse(session: tokens, user: updated, isNewUser: isNewUser,
                            suggestedName: suggestedName ?? profile?.fullName)
    }

    mutating func deleteAccount() {
        self = MockBackend()
    }

    // MARK: Public profiles

    func publicCard(slug rawSlug: String) throws -> PublicCardDTO {
        let slug = rawSlug.lowercased()
        if let card = card(slug: slug), let profile {
            guard !profile.linksPaused else { return PublicCardDTO(slug: slug, status: .paused) }
            let fields = profile.contactFields.filter {
                !$0.isEmpty && $0.privacy != .private && card.design.visibleFields.contains($0.kind)
            }
            let first = profile.fullName.split(separator: " ").first.map(String.init) ?? profile.fullName
            return PublicCardDTO(slug: slug, status: .available, url: Brand.cardURL(slug: slug), cardName: card.name,
                                 owner: PublicOwnerDTO(userID: user?.id, fullName: profile.fullName, firstName: first,
                                                       jobTitle: profile.jobTitle, company: profile.company, photoURL: profile.photoURL),
                                 design: card.design, fields: fields,
                                 viewer: ViewerRelationDTO(isSelf: true, isConnected: false, connectionID: nil))
        }
        if retiredSlugs.contains(slug) { return PublicCardDTO(slug: slug, status: .deleted) }
        guard let peer = MockSeed.peer(slug: slug) else { throw APIError.notFound("Card") }
        guard !peer.isPaused else { return PublicCardDTO(slug: slug, status: .paused) }
        // Only an accepted, mutual connect unlocks connections-only fields — a one-sided "Add to People"
        // (scan, paper, share-back) carries the remoteUserID but must not reveal them.
        let mutualSources: Set<ConnectionSource> = [.nearby, .tapPhones, .connectRequest, .deferredLink]
        let connection = connections.values.first {
            $0.remoteUserID == peer.userID && !$0.isBlocked && mutualSources.contains($0.source)
        }
        let fields = peer.fields.filter { $0.privacy == .public || ($0.privacy == .connections && connection != nil) }
        return PublicCardDTO(slug: slug, status: .available, url: Brand.cardURL(slug: slug), cardName: "Work",
                             owner: PublicOwnerDTO(userID: peer.userID, fullName: peer.fullName, firstName: peer.firstName,
                                                   jobTitle: peer.jobTitle, company: peer.company),
                             design: peer.design, fields: fields,
                             viewer: ViewerRelationDTO(isSelf: false, isConnected: connection != nil, connectionID: connection?.id))
    }

    // MARK: Connect

    func peer(for request: SendConnectRequest) throws -> MockSeed.Peer {
        let peer = request.toToken.flatMap(MockSeed.peer(token:))
            ?? request.toUserID.flatMap(MockSeed.peer(userID:))
            ?? request.toSlug.flatMap(MockSeed.peer(slug:))
        guard let peer, !peer.isPaused else {
            throw APIError.mock(404, .peerUnavailable, "This person isn't available to connect right now.")
        }
        return peer
    }

    mutating func createOutgoingRequest(_ body: SendConnectRequest, peer: MockSeed.Peer, lifetime: TimeInterval, now: Date) -> ConnectRequestDTO {
        let request = ConnectRequestDTO(id: UUID(), direction: .outgoing, peer: PeerSummaryDTO(userID: peer.userID, fullName: peer.fullName,
                                                                                             jobTitle: peer.jobTitle, company: peer.company),
                                        myCardID: body.cardID, method: body.method, status: .pending, eventName: body.eventName,
                                        place: body.place, createdAt: now, expiresAt: now.addingTimeInterval(lifetime), updatedAt: now)
        requests[request.id] = request
        touch(.connectRequest, request.id)
        return request
    }

    /// Live methods (Nearby, Tap Phones) expire after `liveLifetime` (60 s on the real server); the
    /// others after 7 days.
    mutating func createIncomingRequest(from peer: MockSeed.Peer, method: ConnectMethod, liveLifetime: TimeInterval,
                                        now: Date) -> ConnectRequestDTO {
        let event = events.values.first { $0.status == .active }
        let lifetime = Self.isLive(method) ? liveLifetime : 7 * 86_400
        let request = ConnectRequestDTO(id: UUID(), direction: .incoming, peer: peer.summary, myCardID: nil, method: method,
                                        status: .pending, eventName: event?.name, place: event?.place, createdAt: now,
                                        expiresAt: now.addingTimeInterval(lifetime), updatedAt: now)
        requests[request.id] = request
        touch(.connectRequest, request.id)
        return request
    }

    static func isLive(_ method: ConnectMethod) -> Bool { method == .nearby || method == .tapPhones }

    /// Marks a request accepted and creates the owner's connection to the peer.
    mutating func completeRequest(id: UUID, myCardID: UUID?, now: Date) throws -> ConnectAcceptResponse {
        guard var request = requests[id] else { throw APIError.notFound("Request") }
        guard request.status == .pending else {
            throw APIError.mock(409, .requestExpired, "This request is no longer pending.")
        }
        let peer = MockSeed.peer(userID: request.peer.userID)
        request.status = .accepted
        request.respondedAt = now
        request.updatedAt = now
        request.myCardID = myCardID ?? request.myCardID
        request.peer.card = peer?.card ?? request.peer.card
        requests[id] = request
        touch(.connectRequest, id)

        let event = events.values.first { $0.status == .active }
        let source: ConnectionSource = switch request.method {
        case .nearby: .nearby
        case .tapPhones: .tapPhones
        case .scan: .scanQR
        case .deferred: .deferredLink
        case .emailLookup: .connectRequest
        }
        // Reuse an existing connection to the same app user (connecting twice updates it).
        let existing = connections.values.first { $0.remoteUserID == request.peer.userID }
        var connection = existing ?? ConnectionDTO(id: UUID(), fullName: request.peer.fullName, source: source,
                                                   context: MeetingContext(), createdAt: now, updatedAt: now)
        connection.remoteUserID = request.peer.userID
        connection.fullName = request.peer.fullName
        connection.jobTitle = request.peer.jobTitle
        connection.company = request.peer.company
        connection.theirCard = request.peer.card
        connection.mySharedCardID = request.myCardID
        for field in request.peer.card?.fields ?? [] where connection.value(for: field.kind).isEmpty {
            connection.setValue(field.value, for: field.kind)
        }
        if let peer {
            for field in peer.fields where field.privacy != .private && connection.value(for: field.kind).isEmpty {
                connection.setValue(field.value, for: field.kind)
            }
        }
        // The owner's side of the meeting: their own active event as a whole (name, venue, city) —
        // never the requester's venue next to the owner's city. Without one: what the request carried.
        let context = if let event {
            MeetingContext(eventID: event.id, eventName: event.name, place: event.place.isEmpty ? nil : event.place,
                           city: event.city.isEmpty ? nil : event.city, metAt: now)
        } else {
            MeetingContext(eventName: request.eventName, place: request.place, metAt: now)
        }
        if existing != nil, connection.context.eventName != context.eventName {
            connection.previousMeetings.insert(connection.context, at: 0)
        }
        connection.context = context
        connection.eventID = event?.id
        connection.updatedAt = now
        connection.deletedAt = nil
        connections[connection.id] = connection
        tombstones[connection.id] = nil
        touch(.connection, connection.id)
        // Now connected: any other pending request between the two people is settled too.
        for (id, other) in requests where id != request.id && other.status == .pending && other.peer.userID == request.peer.userID {
            var settled = other
            settled.status = .accepted
            settled.respondedAt = now
            settled.updatedAt = now
            requests[id] = settled
            touch(.connectRequest, id)
        }
        return ConnectAcceptResponse(request: request, connection: connection)
    }

    mutating func setStatus(_ status: ConnectRequestStatus, requestID: UUID, expected direction: ConnectRequestDirection,
                            now: Date) throws -> ConnectRequestDTO {
        guard var request = requests[requestID], request.direction == direction else { throw APIError.notFound("Request") }
        guard request.status == .pending else { throw APIError.mock(409, .requestExpired, "This request is no longer pending.") }
        request.status = status
        request.respondedAt = now
        request.updatedAt = now
        requests[requestID] = request
        touch(.connectRequest, requestID)
        return request
    }

    // MARK: Cards

    mutating func duplicateCard(id: UUID, _ body: DuplicateCardRequest, now: Date) throws -> CardDTO {
        guard let source = cards[id] else { throw APIError.notFound("Card") }
        let copy = CardDTO(id: body.newCardID, name: body.name, sortOrder: (cards.values.map(\.sortOrder).max() ?? 0) + 1,
                           design: source.design, createdAt: now, updatedAt: now)
        var canonical = SyncChanges()
        let result = upsertCard(copy, now: now, canonical: &canonical)
        if result.status == .rejected { throw APIError.server(status: 403, problem: result.error) }
        return canonical.cards.first ?? copy
    }

    mutating func reorderCards(_ ids: [UUID], now: Date) -> [CardDTO] {
        for (index, id) in ids.enumerated() {
            guard var card = cards[id], card.sortOrder != index else { continue }
            card.sortOrder = index
            card.updatedAt = now
            cards[id] = card
            touch(.card, id)
        }
        return cards.values.sorted { $0.sortOrder < $1.sortOrder }
    }

    func stats(cardID: UUID, now: Date) throws -> CardStatsDTO {
        guard let card = cards[cardID] else { throw APIError.notFound("Card") }
        let stats = card.stats ?? CardStats()
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let newThisWeek = connections.values.filter { $0.createdAt >= weekAgo }.count
        return CardStatsDTO(cardID: cardID, views: stats.views, saves: stats.saves, shareBacks: stats.shareBacks,
                            scans: stats.scans, newConnectionsThisWeek: newThisWeek, asOf: now)
    }

    // MARK: Events

    mutating func setEventStatus(id: UUID, active: Bool, now: Date) throws -> EventDTO {
        guard var event = events[id] else { throw APIError.notFound("Event") }
        event.status = active ? .active : .ended
        event.endedAt = active ? nil : now
        event.updatedAt = now
        var canonical = SyncChanges()
        let result = upsertEvent(event, canonical: &canonical)
        if result.status == .rejected { throw APIError.server(status: 403, problem: result.error) }
        return canonical.events.first ?? event
    }

    func summary(eventID: UUID) throws -> EventSummaryDTO {
        guard let event = events[eventID] else { throw APIError.notFound("Event") }
        let people = connections.values.filter { $0.eventID == eventID }
        let peopleIDs = Set(people.map(\.id))
        let open = followUps.values.filter { !$0.isDone && $0.connectionID.map(peopleIDs.contains) == true }.count
        let withoutNotes = people.filter { $0.note.isEmpty }.map(\.id)
        return EventSummaryDTO(eventID: eventID, people: people.count, withNotes: people.count - withoutNotes.count,
                               openFollowUps: open, unnotedConnectionIDs: withoutNotes, startedAt: event.startDate,
                               endedAt: event.endedAt)
    }

    // MARK: Subscriptions

    /// Reads `productId` / `expiresDate` from the JWS payload when it is a real StoreKit transaction.
    mutating func verify(_ jws: String, now: Date) -> EntitlementDTO {
        var productID = "app.tanishly.ios.pro.yearly"
        var expiresAt = now.addingTimeInterval(365 * 86_400)
        var originalTransactionID: String?
        var environment = "Xcode"
        let parts = jws.split(separator: ".")
        if parts.count == 3, let payload = Data(base64URLEncoded: String(parts[1])),
           let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
            productID = json["productId"] as? String ?? productID
            if let millis = json["expiresDate"] as? Double { expiresAt = Date(timeIntervalSince1970: millis / 1000) }
            originalTransactionID = (json["originalTransactionId"] as? String) ?? (json["originalTransactionId"] as? Int).map(String.init)
            environment = json["environment"] as? String ?? environment
        }
        // Account-level state: an older/expired transaction (an upgraded-from plan, a refund replayed by
        // `Transaction.updates`) never replaces a subscription that is active for longer.
        if entitlement.plan == .pro, let activeUntil = entitlement.expiresAt, activeUntil > now, expiresAt < activeUntil {
            return entitlement
        }
        entitlement = EntitlementDTO(plan: expiresAt > now ? .pro : .free, productID: productID, expiresAt: expiresAt,
                                     willRenew: true, renewsAt: expiresAt, originalTransactionID: originalTransactionID,
                                     environment: environment)
        return entitlement
    }

    // MARK: Pages

    static func page<T>(_ items: [T], cursor: String?, limit: Int) -> Page<T> {
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(items.count, start + max(1, limit))
        guard start < end else { return Page(items: [], nextCursor: nil) }
        return Page(items: Array(items[start..<end]), nextCursor: end < items.count ? String(end) : nil)
    }
}

extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}

extension ConnectionDTO {
    func value(for kind: ContactFieldKind) -> String {
        switch kind {
        case .phone: phone
        case .email: email
        case .telegram: telegram
        case .website: website
        case .linkedin: linkedin
        }
    }

    mutating func setValue(_ value: String, for kind: ContactFieldKind) {
        switch kind {
        case .phone: phone = value
        case .email: email = value
        case .telegram: telegram = value
        case .website: website = value
        case .linkedin: linkedin = value
        }
    }
}

// MARK: Web share-back (SPEC §3.10 + PLAN Q18 — the real backend must implement the same)
extension MockBackend {
    mutating func receiveShareBack(name: String, phone: String?, telegram: String?, metAtText: String?, cardID: UUID?,
                                   now: Date) -> ShareBackNoticeDTO {
        let digits = { (value: String) in value.filter(\.isNumber) }
        let phoneDigits = phone.map(digits) ?? ""
        let handle = telegram?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let firstName = name.split(separator: " ").first.map { $0.lowercased() } ?? name.lowercased()
        let event = events.values.first { $0.status == .active }
        let card = cardID.flatMap { cards[$0] } ?? cards.values.min { $0.sortOrder < $1.sortOrder }

        let result: ShareBackMergeResult
        var connection: ConnectionDTO
        var candidate: UUID?
        if let duplicate = connections.values.first(where: {
            (!phoneDigits.isEmpty && digits($0.phone) == phoneDigits) || (!handle.isEmpty && $0.telegram.lowercased() == handle)
        }) {
            // 1. Same phone (digits only) or Telegram (case-insensitive) → fill gaps silently.
            result = .dedupedByPhoneOrTelegram
            connection = duplicate
        } else {
            // 2. New connection. A "Who did you just meet?" placeholder with the same first name is only
            //    suggested — the app confirms and merges (PLAN Q18).
            result = .created
            candidate = connections.values.first(where: {
                $0.isPendingMerge && $0.fullName.split(separator: " ").first.map({ $0.lowercased() }) == firstName
            })?.id
            connection = ConnectionDTO(id: UUID(), fullName: name, jobTitle: "Contact", company: "Shared from your web page",
                                       source: .webShareBack,
                                       context: MeetingContext(eventID: event?.id, eventName: event?.name ?? metAtText,
                                                               place: event?.place, city: event?.city, metAt: now),
                                       eventID: event?.id, createdAt: now, updatedAt: now)
        }
        if connection.phone.isEmpty, let phone { connection.phone = phone }
        if connection.telegram.isEmpty, let telegram { connection.telegram = telegram }
        connection.updatedAt = now
        connections[connection.id] = connection
        touch(.connection, connection.id)
        if var card {
            var stats = card.stats ?? CardStats()
            stats.shareBacks += 1
            card.stats = stats
            cards[card.id] = card
            touch(.card, card.id)
        }
        return ShareBackNoticeDTO(shareBackID: UUID(), cardID: card?.id ?? UUID(), connection: connection,
                                  mergeResult: result, mergeCandidateID: candidate, eventName: event?.name)
    }
}
