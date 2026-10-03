import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// the bodies host the real screens.

/// CARD_CREATE (cover wizard, SPEC §2.5.23).
public struct CardCreateView: View {
    public let origin: CardCreateOrigin

    public init(origin: CardCreateOrigin) {
        self.origin = origin
    }

    public var body: some View {
        CardCreateScreen(origin: origin)
    }
}

/// CARD_EDITOR (cover, SPEC §2.5.24).
public struct CardEditorView: View {
    public let cardID: UUID

    public init(cardID: UUID) {
        self.cardID = cardID
    }

    public var body: some View {
        CardEditorScreen(cardID: cardID)
    }
}

/// CARD_SETTINGS (push, SPEC §2.5.22).
public struct CardSettingsView: View {
    public let cardID: UUID

    public init(cardID: UUID) {
        self.cardID = cardID
    }

    public var body: some View {
        CardSettingsScreen(cardID: cardID)
    }
}

/// CARD_EXPORT (cover, SPEC §2.5.25).
public struct CardExportView: View {
    public let cardID: UUID
    public let tab: CardExportTab

    public init(cardID: UUID,tab: CardExportTab) {
        self.cardID = cardID
        self.tab = tab
    }

    public var body: some View {
        CardExportScreen(cardID: cardID, initialTab: tab)
    }
}

/// QR_FULLSCREEN (cover, SPEC §2.5.28).
public struct QRFullscreenView: View {
    public let cardID: UUID

    public init(cardID: UUID) {
        self.cardID = cardID
    }

    public var body: some View {
        QRFullscreenScreen(initialCardID: cardID)
    }
}

/// SHARE_SHEET (sheet, SPEC §2.5.29).
public struct ShareCardSheet: View {
    public let cardID: UUID

    public init(cardID: UUID) {
        self.cardID = cardID
    }

    public var body: some View {
        ShareCardScreen(cardID: cardID)
    }
}
