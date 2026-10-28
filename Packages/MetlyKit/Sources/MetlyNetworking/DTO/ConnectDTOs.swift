import Foundation
import MetlyCore

// MARK: Connect sessions & peers

/// `POST /v1/connect/sessions` — opened while CONNECT is on screen.
public struct ConnectSessionRequest: Codable, Sendable, Hashable {
    public var cardID: UUID
    public var eventID: UUID?
    public var method: ConnectMethod

    public init(cardID: UUID, eventID: UUID? = nil, method: ConnectMethod = .nearby) {
        self.cardID = cardID
        self.eventID = eventID
        self.method = method
    }
}

public struct ConnectSessionDTO: Codable, Sendable, Hashable {
    public var sessionID: String
    /// Ephemeral token to advertise over MultipeerConnectivity / NearbyInteraction (rotates per session).
    public var discoveryToken: String
    public var expiresAt: Date

    public init(sessionID: String, discoveryToken: String, expiresAt: Date) {
        self.sessionID = sessionID
        self.discoveryToken = discoveryToken
        self.expiresAt = expiresAt
    }
}

/// `GET /v1/connect/peers?tokens=a,b` — tokens discovered nearby resolved to people.
public struct NearbyPeerDTO: Codable, Sendable, Hashable, Identifiable {
    public var token: String
    public var userID: UUID
    public var fullName: String
    public var jobTitle: String
    public var company: String
    public var avatarURL: URL?
    public var card: CardSnapshot?

    public var id: String { token }

    public init(token: String, userID: UUID, fullName: String, jobTitle: String, company: String,
                avatarURL: URL? = nil, card: CardSnapshot? = nil) {
        self.token = token
        self.userID = userID
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.avatarURL = avatarURL
        self.card = card
    }
}

/// `POST /v1/connect/requests` — exactly one of `toToken`, `toUserID`, `toSlug`.
public struct SendConnectRequest: Codable, Sendable, Hashable {
    public var toToken: String?
    public var toUserID: UUID?
    public var toSlug: String?
    public var cardID: UUID
    public var method: ConnectMethod
    public var eventID: UUID?
    public var eventName: String?
    public var place: String?

    public init(toToken: String? = nil, toUserID: UUID? = nil, toSlug: String? = nil, cardID: UUID, method: ConnectMethod,
                eventID: UUID? = nil, eventName: String? = nil, place: String? = nil) {
        self.toToken = toToken
        self.toUserID = toUserID
        self.toSlug = toSlug
        self.cardID = cardID
        self.method = method
        self.eventID = eventID
        self.eventName = eventName
        self.place = place
    }
}

public struct AcceptConnectRequest: Codable, Sendable, Hashable {
    /// The card returned to the requester.
    public var cardID: UUID
    public init(cardID: UUID) { self.cardID = cardID }
}

/// Accepting creates a connection on both sides; this is the caller's.
public struct ConnectAcceptResponse: Codable, Sendable, Hashable {
    public var request: ConnectRequestDTO
    public var connection: ConnectionDTO

    public init(request: ConnectRequestDTO, connection: ConnectionDTO) {
        self.request = request
        self.connection = connection
    }
}

// MARK: Public cards (scanned slugs, web page)

public enum PublicCardStatus: String, Codable, Sendable { case available, paused, deleted }

public struct PublicOwnerDTO: Codable, Sendable, Hashable {
    /// Only on the authenticated `/v1/public-profiles/{slug}` route.
    public var userID: UUID?
    public var fullName: String
    public var firstName: String
    public var jobTitle: String
    public var company: String
    public var photoURL: URL?

    public init(userID: UUID?, fullName: String, firstName: String, jobTitle: String, company: String, photoURL: URL? = nil) {
        self.userID = userID
        self.fullName = fullName
        self.firstName = firstName
        self.jobTitle = jobTitle
        self.company = company
        self.photoURL = photoURL
    }
}

/// The viewer's relationship to the card owner (authenticated route only).
public struct ViewerRelationDTO: Codable, Sendable, Hashable {
    public var isSelf: Bool
    public var isConnected: Bool
    public var connectionID: UUID?

    public init(isSelf: Bool, isConnected: Bool, connectionID: UUID?) {
        self.isSelf = isSelf
        self.isConnected = isConnected
        self.connectionID = connectionID
    }
}

/// `GET /v1/public-profiles/{slug}` (app) and `GET /api/public/cards/{slug}` (web).
/// When `status != available` only `slug` and `status` are present — no personal data.
public struct PublicCardDTO: Codable, Sendable, Hashable {
    public var slug: String
    public var status: PublicCardStatus
    public var url: URL?
    public var cardName: String?
    public var owner: PublicOwnerDTO?
    public var design: CardDesign?
    /// Public fields ∩ the card's visible fields; Connections fields too when `viewer.isConnected`.
    public var fields: [ContactField]
    /// Label of the phone in `fields` (`.mobile` when the server doesn't send one).
    public var phoneLabel: PhoneLabel
    /// The owner's extra phones, filtered like `fields` (Public, + Connections for connected viewers; only
    /// when the card shows phones). Not part of `snapshot` — copy them with `Connection.mergePhones(from:)`.
    public var additionalPhones: [LabeledPhone]
    /// The visible contact entries in the owner's order (3.0.0) — what the card shows to this viewer.
    /// Missing on the wire → rebuilt from `fields` / `phoneLabel` / `additionalPhones`.
    public var contacts: [ContactEntry]
    public var viewer: ViewerRelationDTO?

    public init(slug: String, status: PublicCardStatus, url: URL? = nil, cardName: String? = nil, owner: PublicOwnerDTO? = nil,
                design: CardDesign? = nil, fields: [ContactField] = [], phoneLabel: PhoneLabel = .mobile,
                additionalPhones: [LabeledPhone] = [], contacts: [ContactEntry]? = nil, viewer: ViewerRelationDTO? = nil) {
        self.slug = slug
        self.status = status
        self.url = url
        self.cardName = cardName
        self.owner = owner
        self.design = design
        self.fields = fields
        self.phoneLabel = phoneLabel
        self.additionalPhones = additionalPhones
        self.contacts = contacts ?? .fromLegacy(fields: fields, phoneLabel: phoneLabel, additionalPhones: additionalPhones)
        self.viewer = viewer
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        status = try container.decode(PublicCardStatus.self, forKey: .status)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        cardName = try container.decodeIfPresent(String.self, forKey: .cardName)
        owner = try container.decodeIfPresent(PublicOwnerDTO.self, forKey: .owner)
        design = try container.decodeIfPresent(CardDesign.self, forKey: .design)
        fields = try container.decodeIfPresent([ContactField].self, forKey: .fields) ?? []
        phoneLabel = try container.decodePhoneLabel(forKey: .phoneLabel)
        additionalPhones = try container.decodeLabeledPhones(forKey: .additionalPhones)
        contacts = try container.decodeContacts(forKey: .contacts)
            ?? .fromLegacy(fields: fields, phoneLabel: phoneLabel, additionalPhones: additionalPhones)
        viewer = try container.decodeIfPresent(ViewerRelationDTO.self, forKey: .viewer)
    }

    /// SCANNED_CARD preview / `Connection.theirCard`. nil when unavailable.
    public var snapshot: CardSnapshot? {
        guard status == .available, let owner else { return nil }
        return CardSnapshot(cardName: cardName ?? String(localized: "Card"), design: design ?? CardDesign(), fullName: owner.fullName,
                            jobTitle: owner.jobTitle, company: owner.company, fields: fields,
                            url: url ?? Brand.cardURL(slug: slug))
    }

    /// SCANNED_CARD card face: `snapshot.faceContent` plus the phone label and extra phones. nil when unavailable.
    public var faceContent: CardFaceContent? {
        guard let snapshot else { return nil }
        var content = snapshot.faceContent
        content.phoneLabel = phoneLabel
        content.additionalPhones = additionalPhones.filter { !$0.isEmpty }
        content.contacts = contacts.filter { !$0.isEmpty }
        content.isSelection = true   // the server already applied the card's selection and the audience
        return content
    }
}

// MARK: Share-back notices (realtime + push payload)

/// `mergedWithJustMet` is reserved: in v1 the server never merges into a "just met" record by
/// itself — the app asks the owner first (PLAN Q18) using `mergeCandidateID`.
public enum ShareBackMergeResult: String, Codable, Sendable { case created, dedupedByPhoneOrTelegram, mergedWithJustMet }

public struct ShareBackNoticeDTO: Codable, Sendable, Hashable {
    public var shareBackID: UUID
    public var cardID: UUID
    public var connection: ConnectionDTO
    public var mergeResult: ShareBackMergeResult
    /// A `isPendingMerge` connection with the same first name — offer "Is this the person you met at …?".
    public var mergeCandidateID: UUID?
    public var eventName: String?

    public init(shareBackID: UUID, cardID: UUID, connection: ConnectionDTO, mergeResult: ShareBackMergeResult,
                mergeCandidateID: UUID? = nil, eventName: String?) {
        self.shareBackID = shareBackID
        self.cardID = cardID
        self.connection = connection
        self.mergeResult = mergeResult
        self.mergeCandidateID = mergeCandidateID
        self.eventName = eventName
    }
}
