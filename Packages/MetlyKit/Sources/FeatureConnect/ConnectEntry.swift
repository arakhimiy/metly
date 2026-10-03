import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

/// CONNECT cover (SPEC §2.5.26). `cardID` preselects the card to share (QR "Connect Nearby",
/// a card's menu); nil uses the active event's card, else the default card.
public struct ConnectView: View {
    public let cardID: UUID?

    public init(cardID: UUID?) {
        self.cardID = cardID
    }

    public var body: some View {
        ConnectScreen(requestedCardID: cardID)
    }
}

/// CONNECTED cover (SPEC §2.5.27) for a connection that was just made.
public struct ConnectedView: View {
    public let connectionID: UUID

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    public var body: some View {
        ConnectedScreen(connectionID: connectionID)
    }
}
