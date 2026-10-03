import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

public struct ScanView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Scan", specID: "SCAN")
    }
}
public struct ScannedCardView: View {
    public let payload: ScannedCardPayload

    public init(payload: ScannedCardPayload) {
        self.payload = payload
    }

    public var body: some View {
        FeaturePlaceholder("Scanned Card", specID: "SCANNED_CARD")
    }
}
public struct PaperReviewView: View {
    public let draft: PaperCardDraft

    public init(draft: PaperCardDraft) {
        self.draft = draft
    }

    public var body: some View {
        FeaturePlaceholder("Paper Card", specID: "PAPER_REVIEW")
    }
}
