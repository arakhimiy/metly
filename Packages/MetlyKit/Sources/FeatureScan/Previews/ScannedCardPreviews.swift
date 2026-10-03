#if DEBUG
import MetlyCore
import MetlyData
import MetlyNetworking
import SwiftUI

// SCANNED_CARD states (SPEC Appendix A: 36 Scanned card). "Loaded" previews hit the mock server:
// bekzod-b8n3 (not connected, accepts requests), kamila-x1y2 (already connected in the demo
// data), lola-p0z3 (paused).

private func payload(_ slug: String) -> ScannedCardPayload {
    ScannedCardPayload(url: Brand.cardURL(slug: slug), slug: slug)
}

/// A mock-world public card without a network round trip.
private func publicCard(_ slug: String, connected: Bool = false) -> PublicCardDTO {
    guard let peer = MockSeed.peer(slug: slug) else { return PublicCardDTO(slug: slug, status: .deleted) }
    return PublicCardDTO(slug: slug, status: .available, url: Brand.cardURL(slug: slug), cardName: "Work",
                         owner: PublicOwnerDTO(userID: peer.userID, fullName: peer.fullName, firstName: peer.firstName,
                                               jobTitle: peer.jobTitle, company: peer.company),
                         design: peer.design, fields: peer.fields.filter { connected || $0.privacy == .public },
                         viewer: ViewerRelationDTO(isSelf: false, isConnected: connected, connectionID: nil))
}

#Preview("Scanned · loading") {
    NavigationStack { ScannedCardScreen(payload: payload("bekzod-b8n3"), previewPhase: .loading) }
        .metlyPreview(.full)
}

#Preview("Scanned · loaded (live mock)") {
    NavigationStack { ScannedCardView(payload: payload("bekzod-b8n3")) }
        .metlyPreview(.full)
}

#Preview("Scanned · loaded") {
    NavigationStack { ScannedCardScreen(payload: payload("bekzod-b8n3"), previewPhase: .metly(publicCard("bekzod-b8n3"))) }
        .metlyPreview(.full)
}

#Preview("Scanned · waiting for answer") {
    NavigationStack {
        ScannedCardScreen(payload: payload("bekzod-b8n3"), previewPhase: .metly(publicCard("bekzod-b8n3")),
                          previewConnectPhase: .waiting)
    }
    .metlyPreview(.full)
}

#Preview("Scanned · request sent") {
    NavigationStack {
        ScannedCardScreen(payload: payload("nodira-n5m1"), previewPhase: .metly(publicCard("nodira-n5m1")),
                          previewConnectPhase: .requestSent)
    }
    .metlyPreview(.full)
}

#Preview("Scanned · no response") {
    NavigationStack {
        ScannedCardScreen(payload: payload("nodira-n5m1"), previewPhase: .metly(publicCard("nodira-n5m1")),
                          previewConnectPhase: .noResponse)
    }
    .metlyPreview(.full)
}

#Preview("Scanned · already connected") {
    NavigationStack {
        ScannedCardScreen(payload: payload("kamila-x1y2"), previewPhase: .metly(publicCard("kamila-x1y2", connected: true)))
    }
    .metlyPreview(.full)
}

#Preview("Scanned · already connected (live mock)") {
    NavigationStack { ScannedCardView(payload: payload("kamila-x1y2")) }
        .metlyPreview(.full)
}

#Preview("Scanned · unavailable") {
    NavigationStack { ScannedCardView(payload: payload("lola-p0z3")) }
        .metlyPreview(.full)
}

#Preview("Scanned · offline") {
    NavigationStack { ScannedCardView(payload: payload("bekzod-b8n3")) }
        .metlyPreview(.full, online: false)
}

#Preview("Scanned · vCard") {
    NavigationStack { ScannedCardView(payload: ScannedCardPayload(vCard: ScanSamples.vCard)) }
        .metlyPreview(.full)
}

#Preview("Scanned · vCard already in People") {
    NavigationStack {
        ScannedCardView(payload: ScannedCardPayload(vCard: "BEGIN:VCARD\nVERSION:3.0\nFN:Kamila Yusupova\nX-TELEGRAM:@kamila.y\nEND:VCARD"))
    }
    .metlyPreview(.full)
}

#Preview("Scanned · unreadable vCard") {
    NavigationStack { ScannedCardView(payload: ScannedCardPayload(vCard: "BEGIN:VCARD\nVERSION:3.0\nEND:VCARD")) }
        .metlyPreview(.full)
}

#Preview("Scanned · dark, large type") {
    NavigationStack { ScannedCardScreen(payload: payload("bekzod-b8n3"), previewPhase: .metly(publicCard("bekzod-b8n3"))) }
        .metlyPreview(.full)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility1)
}
#endif
