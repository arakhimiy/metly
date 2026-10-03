import Foundation
import MetlyCore

// MARK: Profile images (presigned upload)

public enum ProfileImageKind: String, Codable, Sendable, CaseIterable { case photo, logo }

public struct UploadTicketRequest: Codable, Sendable, Hashable {
    public var contentType: String
    public var byteSize: Int
    public init(contentType: String, byteSize: Int) {
        self.contentType = contentType
        self.byteSize = byteSize
    }
}

/// Presigned PUT target. Upload the bytes with exactly `headers`, no Authorization header.
public struct UploadTicket: Codable, Sendable, Hashable {
    public var uploadID: String
    public var uploadURL: URL
    public var method: String
    public var headers: [String: String]
    public var expiresAt: Date
    public var maxBytes: Int

    public init(uploadID: String, uploadURL: URL, method: String = "PUT", headers: [String: String] = [:],
                expiresAt: Date, maxBytes: Int = 5_000_000) {
        self.uploadID = uploadID
        self.uploadURL = uploadURL
        self.method = method
        self.headers = headers
        self.expiresAt = expiresAt
        self.maxBytes = maxBytes
    }
}

public struct CommitUploadRequest: Codable, Sendable, Hashable {
    public var uploadID: String
    public init(uploadID: String) { self.uploadID = uploadID }
}

// MARK: Cards

public struct DuplicateCardRequest: Codable, Sendable, Hashable {
    /// Client-generated id of the copy (offline-first).
    public var newCardID: UUID
    public var name: String
    public init(newCardID: UUID, name: String) {
        self.newCardID = newCardID
        self.name = name
    }
}

public struct ReorderCardsRequest: Codable, Sendable, Hashable {
    public var cardIDs: [UUID]
    public init(cardIDs: [UUID]) { self.cardIDs = cardIDs }
}

/// `GET /v1/cards/{id}/stats`.
public struct CardStatsDTO: Codable, Sendable, Hashable {
    public var cardID: UUID
    /// Web page views ("Viewed").
    public var views: Int
    /// "Save to Contacts" taps on the web page ("Saved").
    public var saves: Int
    /// Web share-backs received ("Shared back").
    public var shareBacks: Int
    /// QR scans (page views with `?src=qr`).
    public var scans: Int
    /// New connections in the last 7 days (widget).
    public var newConnectionsThisWeek: Int
    public var asOf: Date

    public init(cardID: UUID, views: Int, saves: Int, shareBacks: Int, scans: Int, newConnectionsThisWeek: Int, asOf: Date) {
        self.cardID = cardID
        self.views = views
        self.saves = saves
        self.shareBacks = shareBacks
        self.scans = scans
        self.newConnectionsThisWeek = newConnectionsThisWeek
        self.asOf = asOf
    }

    public var stats: CardStats { CardStats(views: views, saves: saves, shareBacks: shareBacks, scans: scans) }
}

// MARK: Events

/// `GET /v1/events/{id}/summary` (EVENT_ENDED / EVENT_DETAIL stats).
public struct EventSummaryDTO: Codable, Sendable, Hashable {
    public var eventID: UUID
    public var people: Int
    public var withNotes: Int
    public var openFollowUps: Int
    public var connectionIDsWithoutNotes: [UUID]
    public var startedAt: Date
    public var endedAt: Date?

    public init(eventID: UUID, people: Int, withNotes: Int, openFollowUps: Int, connectionIDsWithoutNotes: [UUID],
                startedAt: Date, endedAt: Date?) {
        self.eventID = eventID
        self.people = people
        self.withNotes = withNotes
        self.openFollowUps = openFollowUps
        self.connectionIDsWithoutNotes = connectionIDsWithoutNotes
        self.startedAt = startedAt
        self.endedAt = endedAt
    }
}

// MARK: Blocks

public struct BlockDTO: Codable, Sendable, Hashable {
    public var userID: UUID?
    public var connectionID: UUID?
    public var fullName: String
    public var blockedAt: Date

    public init(userID: UUID?, connectionID: UUID?, fullName: String, blockedAt: Date) {
        self.userID = userID
        self.connectionID = connectionID
        self.fullName = fullName
        self.blockedAt = blockedAt
    }
}

/// Block by app user, by connection (resolves its `remoteUserID`), or both.
public struct BlockRequest: Codable, Sendable, Hashable {
    public var userID: UUID?
    public var connectionID: UUID?
    public init(userID: UUID? = nil, connectionID: UUID? = nil) {
        self.userID = userID
        self.connectionID = connectionID
    }
}

// MARK: Subscriptions

public struct PlanLimitsDTO: Codable, Sendable, Hashable {
    /// nil = unlimited.
    public var maxCards: Int?
    public var maxOpenFollowUps: Int?
    public var maxActiveEvents: Int?

    public init(maxCards: Int?, maxOpenFollowUps: Int?, maxActiveEvents: Int?) {
        self.maxCards = maxCards
        self.maxOpenFollowUps = maxOpenFollowUps
        self.maxActiveEvents = maxActiveEvents
    }

    public static let free = PlanLimitsDTO(maxCards: 2, maxOpenFollowUps: 5, maxActiveEvents: 1)
    public static let pro = PlanLimitsDTO(maxCards: nil, maxOpenFollowUps: nil, maxActiveEvents: nil)
}

public struct EntitlementDTO: Codable, Sendable, Hashable {
    public var plan: Plan
    public var productID: String?
    public var expiresAt: Date?
    public var willRenew: Bool
    public var renewsAt: Date?
    public var originalTransactionID: String?
    /// `Production` | `Sandbox` | `Xcode` (StoreKit environment).
    public var environment: String?
    public var isInBillingRetry: Bool
    public var limits: PlanLimitsDTO

    public init(plan: Plan, productID: String? = nil, expiresAt: Date? = nil, willRenew: Bool = false, renewsAt: Date? = nil,
                originalTransactionID: String? = nil, environment: String? = nil, isInBillingRetry: Bool = false,
                limits: PlanLimitsDTO? = nil) {
        self.plan = plan
        self.productID = productID
        self.expiresAt = expiresAt
        self.willRenew = willRenew
        self.renewsAt = renewsAt
        self.originalTransactionID = originalTransactionID
        self.environment = environment
        self.isInBillingRetry = isInBillingRetry
        self.limits = limits ?? (plan == .pro ? .pro : .free)
    }

    public static let free = EntitlementDTO(plan: .free)
}

/// `POST /v1/subscriptions/verify` — StoreKit 2 `Transaction.jwsRepresentation`.
public struct VerifyTransactionRequest: Codable, Sendable, Hashable {
    public var signedTransaction: String
    public var appAccountToken: UUID?

    public init(signedTransaction: String, appAccountToken: UUID? = nil) {
        self.signedTransaction = signedTransaction
        self.appAccountToken = appAccountToken
    }
}

// MARK: Devices (APNs)

public struct DeviceRegistrationRequest: Codable, Sendable, Hashable {
    /// Stable per install (generated by the app, not IDFV).
    public var deviceID: String
    /// Hex-encoded APNs token.
    public var apnsToken: String
    /// `sandbox` | `production`.
    public var apnsEnvironment: String
    public var platform: String
    public var appVersion: String
    public var osVersion: String
    public var locale: String
    /// IANA zone, e.g. `Asia/Tashkent` (follow-up reminders are scheduled in it).
    public var timeZone: String

    public init(deviceID: String, apnsToken: String, apnsEnvironment: String, platform: String = "ios",
                appVersion: String, osVersion: String, locale: String, timeZone: String) {
        self.deviceID = deviceID
        self.apnsToken = apnsToken
        self.apnsEnvironment = apnsEnvironment
        self.platform = platform
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.locale = locale
        self.timeZone = timeZone
    }
}

// MARK: Deferred deep links

public struct DeviceFingerprint: Codable, Sendable, Hashable {
    public var model: String
    public var osVersion: String
    public var locale: String
    public var timeZone: String
    public var preferredLanguages: [String]

    public init(model: String, osVersion: String, locale: String, timeZone: String, preferredLanguages: [String]) {
        self.model = model
        self.osVersion = osVersion
        self.locale = locale
        self.timeZone = timeZone
        self.preferredLanguages = preferredLanguages
    }
}

/// `POST /v1/deferred-links/claim` (unauthenticated, first launch only).
public struct DeferredLinkClaimRequest: Codable, Sendable, Hashable {
    public var installID: String
    /// Explicit token when available (App Clip / pasteboard opt-in); otherwise the server matches the fingerprint.
    public var token: String?
    public var fingerprint: DeviceFingerprint

    public init(installID: String, token: String? = nil, fingerprint: DeviceFingerprint) {
        self.installID = installID
        self.token = token
        self.fingerprint = fingerprint
    }
}

public struct DeferredInviteDTO: Codable, Sendable, Hashable {
    public var inviteID: String
    public var owner: PeerSummaryDTO
    public var cardSlug: String
    public var card: CardSnapshot
    public var eventName: String?
    public var createdAt: Date

    public init(inviteID: String, owner: PeerSummaryDTO, cardSlug: String, card: CardSnapshot, eventName: String?, createdAt: Date) {
        self.inviteID = inviteID
        self.owner = owner
        self.cardSlug = cardSlug
        self.card = card
        self.eventName = eventName
        self.createdAt = createdAt
    }

    /// The MetlyCore value shown by DEFERRED_WELCOME.
    public var invite: DeferredInvite {
        DeferredInvite(ownerName: owner.fullName,
                       ownerTitle: [owner.jobTitle, owner.company].filter { !$0.isEmpty }.joined(separator: " · "),
                       eventName: eventName, card: card, cardSlug: cardSlug)
    }
}

/// `{ "invite": … | null }` — `null` when nothing matched.
public struct DeferredLinkClaimResponse: Codable, Sendable, Hashable {
    public var invite: DeferredInviteDTO?
    public init(invite: DeferredInviteDTO?) { self.invite = invite }
}
