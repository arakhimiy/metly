import AppIntents
import MetlyWidgetKit

/// "Show my Tanishly QR" — opens QR_FULLSCREEN (Q23) for the card to share, or the chosen card.
///
/// Routes through `tanishly://qr[/cardID]` (handled by `DeepLinkHandler`), the same link the widgets use,
/// so Siri, Shortcuts, Spotlight and the Action button all land on one code path.
struct ShowMyQRIntent: AppIntent {
    static let title: LocalizedStringResource = "Show My QR"
    static let description = IntentDescription("Opens your QR code full screen so someone can scan it.")

    @Parameter(title: "Card", description: "Leave empty to show the card you share right now.")
    var card: ShareCardEntity?

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary("Show QR for \(\.$card)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetDeepLink.qr(cardID: card?.cardID)))
    }
}
