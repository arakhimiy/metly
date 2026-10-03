import AppIntents
import MetlyWidgetKit

/// Control Center / Lock Screen / Action button "Show My QR": opens QR_FULLSCREEN (Q23) through
/// `metly://qr`, so the app shows the card to share at that moment.
nonisolated struct ShowMyQRControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Show My QR"
    static let description = IntentDescription("Opens your QR code full screen.")
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetDeepLink.qr()))
    }
}
