import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

public struct ConnectView: View {
    public let cardID: UUID?

    public init(cardID: UUID?) {
        self.cardID = cardID
    }

    public var body: some View {
        FeaturePlaceholder("Connect", specID: "CONNECT")
    }
}
public struct ConnectedView: View {
    public let connectionID: UUID

    public init(connectionID: UUID) {
        self.connectionID = connectionID
    }

    public var body: some View {
        FeaturePlaceholder("You're Connected", specID: "CONNECTED")
    }
}
