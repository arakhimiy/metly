import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

public struct CardCreateView: View {
    public let origin: CardCreateOrigin

    public init(origin: CardCreateOrigin) {
        self.origin = origin
    }

    public var body: some View {
        FeaturePlaceholder("New Card", specID: "CARD_CREATE")
    }
}
public struct CardEditorView: View {
    public let cardID: UUID

    public init(cardID: UUID) {
        self.cardID = cardID
    }

    public var body: some View {
        FeaturePlaceholder("Edit Card", specID: "CARD_EDITOR")
    }
}
public struct CardSettingsView: View {
    public let cardID: UUID

    public init(cardID: UUID) {
        self.cardID = cardID
    }

    public var body: some View {
        FeaturePlaceholder("Card Settings", specID: "CARD_SETTINGS")
    }
}
public struct CardExportView: View {
    public let cardID: UUID
    public let tab: CardExportTab

    public init(cardID: UUID,tab: CardExportTab) {
        self.cardID = cardID
        self.tab = tab
    }

    public var body: some View {
        FeaturePlaceholder("Export", specID: "CARD_EXPORT")
    }
}
public struct QRFullscreenView: View {
    public let cardID: UUID

    public init(cardID: UUID) {
        self.cardID = cardID
    }

    public var body: some View {
        FeaturePlaceholder("QR Code", specID: "QR_FULLSCREEN")
    }
}
public struct ShareCardSheet: View {
    public let cardID: UUID

    public init(cardID: UUID) {
        self.cardID = cardID
    }

    public var body: some View {
        FeaturePlaceholder("Share", specID: "SHARE_SHEET")
    }
}
