import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// the bodies host the real screens (files in List/, Detail/, AddContext/, JustMet/, Blocked/).

/// PEOPLE tab root.
public struct PeopleView: View {
    public init() {}

    public var body: some View {
        PeopleScreen()
    }
}

/// CONNECTION_DETAIL (push).
public struct ConnectionDetailView: View {
    public let connectionID: UUID

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    public var body: some View {
        ConnectionDetailScreen(connectionID: connectionID)
    }
}

/// ADD_CONTEXT (large sheet).
public struct AddContextSheet: View {
    public let connectionID: UUID

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    public var body: some View {
        AddContextScreen(connectionID: connectionID)
    }
}

/// JUST_MET (medium / large sheet).
public struct JustMetSheet: View {
    public let cardID: UUID?

    public init(cardID: UUID?) {
        self.cardID = cardID
    }

    public var body: some View {
        JustMetScreen(cardID: cardID)
    }
}

/// Settings › Blocked People (push).
public struct BlockedPeopleView: View {
    public init() {}

    public var body: some View {
        BlockedPeopleScreen()
    }
}
