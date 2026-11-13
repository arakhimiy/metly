import Foundation

/// What a QR / Card / Lock Screen widget shows for one timeline entry.
nonisolated public enum CardWidgetContent: Hashable, Sendable {
    case card(CardWidgetDisplay)
    /// Signed in but no card yet.
    case noCard
    case signedOut

    /// - Parameters:
    ///   - cardID: the widget's configured card; nil = card to share (default / active event card).
    public static func resolve(snapshot: WidgetSnapshot?, cardID: UUID?, at date: Date,
                               calendar: Calendar = .current) -> CardWidgetContent {
        guard let snapshot, let owner = snapshot.owner else { return .signedOut }
        guard let card = snapshot.resolveCard(id: cardID) else { return .noCard }
        let followsShareCard = cardID.flatMap(snapshot.card(id:)) == nil
        return .card(CardWidgetDisplay(
            card: card,
            owner: owner,
            newConnectionsThisWeek: snapshot.newConnectionsThisWeek(at: date, calendar: calendar),
            followsShareCard: followsShareCard
        ))
    }

    public var display: CardWidgetDisplay? {
        if case .card(let display) = self { return display }
        return nil
    }

    /// Where a tap goes.
    public var url: URL {
        guard let display else { return WidgetDeepLink.app }
        // Automatic widgets let the app pick the card at tap time (an event may have started since).
        return WidgetDeepLink.qr(cardID: display.followsShareCard ? nil : display.card.id)
    }
}

nonisolated public struct CardWidgetDisplay: Hashable, Sendable {
    public var card: WidgetCard
    public var owner: WidgetOwner
    public var newConnectionsThisWeek: Int
    /// The widget is set to "Card to Share" (or its card was deleted).
    public var followsShareCard: Bool

    public init(card: WidgetCard, owner: WidgetOwner, newConnectionsThisWeek: Int = 0, followsShareCard: Bool = true) {
        self.card = card
        self.owner = owner
        self.newConnectionsThisWeek = newConnectionsThisWeek
        self.followsShareCard = followsShareCard
    }

    /// Paused links show an inactive page — only relevant when the QR encodes the link.
    public var isPaused: Bool { owner.linksPaused && !card.usesOfflineQR }

    /// "3 new connections this week".
    public var newConnectionsText: String {
        switch newConnectionsThisWeek {
        case 0: String(localized: "No new connections this week", bundle: .appStrings)
        case 1: String(localized: "1 new connection this week", bundle: .appStrings)
        default: String(localized: "\(newConnectionsThisWeek) new connections this week", bundle: .appStrings)
        }
    }
}

/// What the Follow-ups widget shows for one timeline entry.
nonisolated public enum FollowUpsWidgetContent: Hashable, Sendable {
    case reminders(FollowUpsWidgetSummary)
    case signedOut

    /// - Parameter pending: queued widget actions not applied by the app yet (shown as done already).
    public static func resolve(snapshot: WidgetSnapshot?, pending: [WidgetPendingAction] = [], at date: Date,
                               calendar: Calendar = .current) -> FollowUpsWidgetContent {
        guard let snapshot, snapshot.isSignedIn else { return .signedOut }
        let current = snapshot.applying(pending)
        return .reminders(FollowUpsWidgetSummary(
            due: current.dueFollowUps(at: date, calendar: calendar),
            dueCount: current.dueFollowUpCount(at: date, calendar: calendar),
            next: current.nextFollowUp(after: date, calendar: calendar),
            openCount: current.openFollowUpCount
        ))
    }
}

nonisolated public struct FollowUpsWidgetSummary: Hashable, Sendable {
    /// Due today or overdue, earliest first.
    public var due: [WidgetFollowUp]
    /// All open follow-ups due today or earlier (may exceed `due.count`).
    public var dueCount: Int
    /// First reminder after today ("Next: …").
    public var next: WidgetFollowUp?
    public var openCount: Int

    public init(due: [WidgetFollowUp], dueCount: Int, next: WidgetFollowUp?, openCount: Int) {
        self.due = due
        self.dueCount = dueCount
        self.next = next
        self.openCount = openCount
    }

    /// No reminders at all (SPEC empty state "No Follow-ups Yet").
    public var isEmpty: Bool { openCount == 0 }
}
