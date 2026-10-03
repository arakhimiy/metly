import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

/// SCAN tab root (SPEC §2.5.8).
public struct ScanView: View {
    public init() {}

    public var body: some View {
        ScanScreen()
    }
}

/// SCANNED_CARD (SPEC §2.5.9) — a scanned / pasted Metly link or a foreign vCard.
public struct ScannedCardView: View {
    public let payload: ScannedCardPayload

    public init(payload: ScannedCardPayload) {
        self.payload = payload
    }

    public var body: some View {
        ScannedCardScreen(payload: payload)
    }
}

/// PAPER_REVIEW (SPEC §2.5.10) — OCR result (or empty fields for "Enter Manually").
public struct PaperReviewView: View {
    public let draft: PaperCardDraft

    public init(draft: PaperCardDraft) {
        self.draft = draft
    }

    public var body: some View {
        PaperReviewScreen(draft: draft)
    }
}
