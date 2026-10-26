import Foundation

// Every cross-feature destination in the app. Features navigate ONLY through these
// (via `AppRouter`); the app target's RouteResolver maps each case to a feature view.
// Adding a case is a contract change — ask the orchestrator.

public enum AppTab: String, Hashable, CaseIterable, Sendable {
    case home, scan, people, profile
}

public enum RootPhase: Hashable, Sendable {
    case launching
    /// Welcome pages + sign-in (FeatureOnboarding).
    case onboarding
    /// Signed in, profile not completed (SETUP_PROFILE → SETUP_PERMISSIONS).
    case setup
    /// First launch after install from a web card (DEFERRED_WELCOME), before onboarding.
    case deferredWelcome(DeferredInvite)
    case main
}

/// Pushed onto the current tab's NavigationStack.
public enum PushDestination: Hashable, Sendable {
    case connectionDetail(id: UUID)
    case followUps
    case eventDetail(id: UUID)
    case scannedCard(ScannedCardPayload)
    case paperReview(PaperCardDraft)
    case widgetsGallery
    case cardSettings(id: UUID)
    case settingsNotifications
    case settingsPrivacy
    case settingsSubscription
    case settingsHelp
    case settingsDeleteAccount
    case settingsBlockedPeople
}

/// Presented as a sheet (detents decided by the destination view).
public enum SheetDestination: Hashable, Sendable {
    case share(cardID: UUID)
    case startEvent(eventID: UUID?)
    case addContext(connectionID: UUID)
    case justMet(cardID: UUID?)
    case reminderEdit(followUpID: UUID?, connectionID: UUID?)
    case eventExport(eventID: UUID)
}

/// Presented full screen.
public enum CoverDestination: Hashable, Sendable {
    case cardCreate(origin: CardCreateOrigin)
    case cardEditor(cardID: UUID)
    case cardExport(cardID: UUID, tab: CardExportTab)
    case connect(cardID: UUID?)
    case connected(connectionID: UUID)
    case qr(cardID: UUID)
    case paywall(trigger: PaywallTrigger)
    case eventEnded(eventID: UUID)
}

public enum Presentation: Hashable, Identifiable, Sendable {
    case sheet(SheetDestination)
    case cover(CoverDestination)

    public var id: Self { self }

    public var isCover: Bool {
        if case .cover = self { return true }
        return false
    }
}

public enum CardCreateOrigin: String, Hashable, Sendable { case setup, home }

public enum CardExportTab: String, Hashable, Sendable, CaseIterable { case image, pdf, wallet, lockScreen }

public enum PaywallTrigger: String, Hashable, Sendable {
    case settings, cardLimit, followUpLimit, eventLimit, proTemplate, proPalette, eventExport
}

/// What the scanner found (Tanishly link or a foreign vCard).
public struct ScannedCardPayload: Hashable, Sendable {
    public var url: URL?
    public var slug: String?
    public var vCard: String?

    public init(url: URL? = nil, slug: String? = nil, vCard: String? = nil) {
        self.url = url
        self.slug = slug
        self.vCard = vCard
    }
}

/// OCR result of a paper business card, editable on PAPER_REVIEW.
public struct PaperCardDraft: Hashable, Sendable {
    public var fullName: String
    public var jobTitle: String
    public var company: String
    public var fields: [ContactField]
    public var imageData: Data?

    public init(fullName: String = "", jobTitle: String = "", company: String = "",
                fields: [ContactField] = [], imageData: Data? = nil) {
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.fields = fields
        self.imageData = imageData
    }
}
