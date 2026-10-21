import Foundation
import MetlyCore
import Testing
@testable import FeatureScan

@MainActor
@Suite("SCAN camera lifetime, result routing and Connect availability")
struct ScanScreenRulesTests {
    @Test("The camera runs only while SCAN is on screen")
    func cameraRunsWhileVisible() {
        #expect(ScanCameraPolicy.isCameraActive(isVisible: true, presentations: []))
        #expect(!ScanCameraPolicy.isCameraActive(isVisible: false, presentations: []))
    }

    /// Regression: `onDisappear` doesn't fire under a sheet (and not reliably under a cover), so a
    /// reminder sheet from a notification, EVENT_ENDED or QR from a widget left the camera (and its
    /// light) on behind the modal — still detecting codes and pushing SCANNED_CARD underneath.
    @Test("A sheet or cover on top stops the camera", arguments: [
        Presentation.sheet(.reminderEdit(followUpID: UUID(), connectionID: nil)),
        .cover(.qr(cardID: UUID())),
        .cover(.eventEnded(eventID: UUID())),
    ])
    func modalStopsCamera(presentation: Presentation) {
        #expect(!ScanCameraPolicy.isCameraActive(isVisible: true, presentations: [presentation]))
    }

    /// Regression: reading a paper card takes a moment; switching tabs meanwhile pushed PAPER_REVIEW
    /// onto the newly selected tab (e.g. People).
    @Test("Scan results land in the Scan tab even if another tab was selected meanwhile")
    func resultsStayInScanTab() {
        let router = AppRouter(phase: .main)
        router.selectedTab = .people
        let draft = PaperCardDraft(fullName: "Aziza Karimova")
        ScanCameraPolicy.show(.paperReview(draft), router: router)
        #expect(router.paths[.scan] == [.paperReview(draft)])
        #expect(router.paths[.people, default: []].isEmpty)
        #expect(router.selectedTab == .people)

        router.selectedTab = .scan
        ScanCameraPolicy.show(.scannedCard(ScannedCardPayload(vCard: "BEGIN:VCARD")), router: router)
        #expect(router.paths[.scan]?.count == 2)
    }

    /// Regression: after an offline Connect saved the person, the footer says "Connect again when
    /// you're back online" but the screen offered no Connect button any more.
    @Test("Connect is offered again after an offline save", arguments: [
        (ScannedCardModel.ConnectPhase.idle, true),
        (.noResponse, true),
        (.savedOffline, true),
        (.sending, false),
        (.waiting, false),
        (.requestSent, false),
        (.accepted, false),
    ])
    func connectOffered(phase: ScannedCardModel.ConnectPhase, offered: Bool) {
        #expect(ScannedCardModel(phase: .loading, connectPhase: phase).offersConnect == offered)
    }
}
