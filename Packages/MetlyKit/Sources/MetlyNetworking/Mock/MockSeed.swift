import Foundation
import MetlyCore

/// Deterministic demo data (the prototype's Aziza Karimova account + the people around her).
///
/// Single source of truth for `MockMetlyServer` **and** MetlyData's `PreviewSeed`, so a device
/// seeded with demo data and the mock server agree on every record id (no duplicates on sync).
public enum MockSeed {
    // MARK: Stable ids

    public static let ownerUserID = uuid("A0")
    public static let profileID = uuid("A1")
    public static let workCardID = uuid("C1")
    public static let personalCardID = uuid("C2")
    public static let eventID = uuid("E1")
    public static let connectionIDs = (1...6).map { uuid("D\($0)") }
    public static let followUpIDs = (1...4).map { uuid("F\($0)") }
    public static let incomingRequestID = uuid("CA01")
    public static let ownerEmail = "aziza@tezkor.uz"

    /// Everything the demo user owns, with dates relative to `now`.
    public struct Account: Sendable, Hashable {
        public var user: UserDTO
        public var profile: ProfileDTO?
        public var cards: [CardDTO]
        public var events: [EventDTO]
        public var connections: [ConnectionDTO]
        public var followUps: [FollowUpDTO]
        public var connectRequests: [ConnectRequestDTO]
        public var entitlement: EntitlementDTO

        public init(user: UserDTO, profile: ProfileDTO?, cards: [CardDTO] = [], events: [EventDTO] = [],
                    connections: [ConnectionDTO] = [], followUps: [FollowUpDTO] = [],
                    connectRequests: [ConnectRequestDTO] = [], entitlement: EntitlementDTO = .free) {
            self.user = user
            self.profile = profile
            self.cards = cards
            self.events = events
            self.connections = connections
            self.followUps = followUps
            self.connectRequests = connectRequests
            self.entitlement = entitlement
        }

        /// Profile + Work card only (PreviewSeed `.empty`).
        public var minimal: Account {
            Account(user: user, profile: profile, cards: cards.filter { $0.id == MockSeed.workCardID }, entitlement: entitlement)
        }
    }

    /// Another Metly user the mock world knows about (public profile, Nearby, connect behaviour).
    public struct Peer: Sendable, Hashable {
        public enum Behavior: Sendable, Hashable {
            /// Accepts connect requests after the server's accept delay.
            case accepts
            /// Never answers → the request expires ("didn't respond").
            case ignores
        }

        public var userID: UUID
        public var fullName: String
        public var jobTitle: String
        public var company: String
        public var slug: String
        public var nearbyToken: String
        public var design: CardDesign
        public var fields: [ContactField]
        public var behavior: Behavior
        public var isPaused: Bool

        public var firstName: String { String(fullName.split(separator: " ").first ?? Substring(fullName)) }

        public var card: CardSnapshot {
            CardSnapshot(cardName: "Work", design: design, fullName: fullName, jobTitle: jobTitle, company: company,
                         fields: fields.filter { $0.privacy == .public }, url: Brand.cardURL(slug: slug))
        }

        public var summary: PeerSummaryDTO {
            PeerSummaryDTO(userID: userID, fullName: fullName, jobTitle: jobTitle, company: company, card: card)
        }

        public var nearby: NearbyPeerDTO {
            NearbyPeerDTO(token: nearbyToken, userID: userID, fullName: fullName, jobTitle: jobTitle, company: company, card: card)
        }
    }

    /// Other users: scanned slugs (`kamila-x1y2`…), Nearby tokens (`mock-peer-…`) and connect behaviour.
    public static let peers: [Peer] = [
        Peer(userID: uuid("AB01"), fullName: "Kamila Yusupova", jobTitle: "Head of Partnerships", company: "Uzum",
             slug: "kamila-x1y2", nearbyToken: "mock-peer-kamila", design: CardDesign(template: .modern, palette: .graphite),
             fields: [ContactField(kind: .telegram, value: "@kamila.y", privacy: .public),
                      ContactField(kind: .email, value: "kamila@uzum.uz", privacy: .public),
                      ContactField(kind: .phone, value: "+998 90 555 12 34", privacy: .connections)],
             behavior: .accepts, isPaused: false),
        Peer(userID: uuid("AB02"), fullName: "Sardor Rashidov", jobTitle: "CTO", company: "Payme",
             slug: "sardor-r4t5", nearbyToken: "mock-peer-sardor", design: CardDesign(template: .terminal, palette: .snow, font: .mono),
             fields: [ContactField(kind: .telegram, value: "@sardor", privacy: .public),
                      ContactField(kind: .website, value: "payme.uz", privacy: .public)],
             behavior: .accepts, isPaused: false),
        Peer(userID: uuid("AB03"), fullName: "Bekzod Tursunov", jobTitle: "Growth Lead", company: "Alif",
             slug: "bekzod-b8n3", nearbyToken: "mock-peer-bekzod", design: CardDesign(template: .bold, palette: .ember),
             fields: [ContactField(kind: .telegram, value: "@bekzod.t", privacy: .public),
                      ContactField(kind: .email, value: "bekzod@alif.tj", privacy: .public)],
             behavior: .accepts, isPaused: false),
        Peer(userID: uuid("AB04"), fullName: "Nodira Usmonova", jobTitle: "Marketing Lead", company: "Humans",
             slug: "nodira-n5m1", nearbyToken: "mock-peer-nodira", design: CardDesign(template: .gradient, palette: .ocean, background: .gradient),
             fields: [ContactField(kind: .email, value: "nodira@humans.uz", privacy: .public)],
             behavior: .ignores, isPaused: false),
        Peer(userID: uuid("AB05"), fullName: "Lola Saidova", jobTitle: "Founder", company: "Lola Studio",
             slug: "lola-p0z3", nearbyToken: "mock-peer-lola", design: CardDesign(template: .split, palette: .sand),
             fields: [ContactField(kind: .website, value: "lola.studio", privacy: .public)],
             behavior: .accepts, isPaused: true),
    ]

    /// Nearby tokens a simulator build can feed into Connect (Nearby needs real devices otherwise).
    public static var nearbyTokens: [String] { peers.filter { !$0.isPaused }.map(\.nearbyToken) }

    public static func peer(slug: String) -> Peer? { peers.first { $0.slug == slug.lowercased() } }
    public static func peer(token: String) -> Peer? { peers.first { $0.nearbyToken == token } }
    public static func peer(userID: UUID) -> Peer? { peers.first { $0.userID == userID } }

    // MARK: Demo account

    public static func demoAccount(now: Date = .now, calendar: Calendar = .current) -> Account {
        let day = { (offset: Int) in calendar.date(byAdding: .day, value: offset, to: now)! }

        let profile = ProfileDTO(
            id: profileID, fullName: "Aziza Karimova", jobTitle: "Product Designer", company: "Tezkor",
            contactFields: [
                ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .private),
                ContactField(kind: .email, value: ownerEmail, privacy: .connections),
                ContactField(kind: .telegram, value: "@aziza.k", privacy: .connections),
                ContactField(kind: .website, value: "aziza.design", privacy: .public),
                ContactField(kind: .linkedin, value: "in/azizakarimova", privacy: .connections),
            ],
            defaultCardID: workCardID, linksPaused: false, notificationPrefs: NotificationPrefs(),
            privacySettings: PrivacySettings(), isSetupComplete: true, createdAt: day(-30), updatedAt: day(-1))

        let cards = [
            CardDTO(id: workCardID, name: "Work", slug: "aziza-w7k2", url: Brand.cardURL(slug: "aziza-w7k2"), sortOrder: 0,
                    design: CardDesign(template: .professional, palette: .ink, appearance: .dark), publishState: .published,
                    stats: CardStats(views: 128, saves: 41, shareBacks: 12, scans: 87), createdAt: day(-30), updatedAt: day(-2)),
            CardDTO(id: personalCardID, name: "Personal", slug: "aziza-p3x9", url: Brand.cardURL(slug: "aziza-p3x9"), sortOrder: 1,
                    design: CardDesign(template: .stack, palette: .sand, appearance: .light, font: .rounded),
                    publishState: .published, stats: CardStats(), createdAt: day(-20), updatedAt: day(-2)),
        ]

        let event = EventDTO(id: eventID, name: "Tashkent Tech Week", place: "Hyatt Regency", city: "Tashkent",
                             startDate: day(-1), endDate: day(1), cardID: workCardID, status: .active,
                             createdAt: day(-1), updatedAt: day(-1))

        // (name, title, company, source, telegram, tag, days ago, app user)
        let people: [(String, String, String, ConnectionSource, String, String, Int, UUID?)] = [
            ("Kamila Yusupova", "Head of Partnerships", "Uzum", .nearby, "@kamila.y", "Investor", 0, peers[0].userID),
            ("Sardor Rashidov", "CTO", "Payme", .tapPhones, "@sardor", "Partner", 0, peers[1].userID),
            ("Dilnoza Ergasheva", "Recruiter", "EPAM", .webShareBack, "@dilnoza.e", "Hiring", 1, nil),
            ("Jasur Akhmedov", "Founder", "Workly", .scanQR, "@jasur", "Client", 2, nil),
            ("Madina Alieva", "Product Manager", "Click", .paper, "", "", 5, nil),
            ("Timur Nazarov", "Engineer", "Yandex", .justMet, "@timurn", "Friend", 9, nil),
        ]
        let connections = people.enumerated().map { index, person -> ConnectionDTO in
            let metAt = day(-person.6)
            let inEvent = person.6 <= 1
            let first = person.0.split(separator: " ").first!.lowercased()
            var connection = ConnectionDTO(
                id: connectionIDs[index], remoteUserID: person.7, fullName: person.0, jobTitle: person.1, company: person.2,
                email: "\(first)@\(person.2.lowercased()).uz", telegram: person.4, source: person.3,
                context: MeetingContext(eventID: inEvent ? eventID : nil, eventName: inEvent ? event.name : nil,
                                        place: inEvent ? "Hyatt Regency" : "IT Park", city: "Tashkent", metAt: metAt),
                eventID: inEvent ? eventID : nil, tags: person.5.isEmpty ? [] : [person.5],
                // Newest first in People (ties broken by list order).
                createdAt: metAt.addingTimeInterval(-Double(index)), updatedAt: metAt)
            if index == 0 {
                connection.note = "Interested in a design partnership for Uzum Market. Send the pitch deck."
                connection.mySharedCardID = workCardID
                connection.theirCard = peers[0].card
            }
            return connection
        }

        // (person index, title, channel, due in days)
        let reminders: [(Int, String, FollowUpChannel, Int)] = [
            (0, "Send the pitch deck", .telegram, 0),
            (1, "Intro to the design team", .email, -1),
            (3, "Follow up", .call, 3),
            (2, "Share portfolio", .telegram, 6),
        ]
        let followUps = reminders.enumerated().map { index, item in
            FollowUpDTO(id: followUpIDs[index], connectionID: connectionIDs[item.0], title: item.1, channel: item.2,
                        dueAt: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day(item.3))!,
                        createdAt: day(-1), updatedAt: day(-1))
        }

        let bekzod = peers[2]
        let request = ConnectRequestDTO(id: incomingRequestID, direction: .incoming, peer: bekzod.summary, myCardID: nil,
                                        method: .nearby, status: .pending, eventName: event.name, place: event.place,
                                        createdAt: now.addingTimeInterval(-600), expiresAt: day(7),
                                        updatedAt: now.addingTimeInterval(-600))

        let user = UserDTO(id: ownerUserID, email: ownerEmail, authProviders: [.apple], createdAt: day(-30), profileComplete: true)
        return Account(user: user, profile: profile, cards: cards, events: [event], connections: connections,
                       followUps: followUps, connectRequests: [request])
    }

    /// Who you "met" for DEFERRED_WELCOME (`-MetlyDeferredInvite`).
    public static func deferredInvite(now: Date = .now) -> DeferredInviteDTO {
        let kamila = peers[0]
        return DeferredInviteDTO(inviteID: "inv_mock_kamila", owner: kamila.summary, cardSlug: kamila.slug, card: kamila.card,
                                 eventName: "Tashkent Tech Week", createdAt: now.addingTimeInterval(-3600))
    }

    private static func uuid(_ suffix: String) -> UUID {
        let padded = String(repeating: "0", count: 12 - suffix.count) + suffix
        return UUID(uuidString: "00000000-0000-0000-0000-\(padded)")!
    }
}
