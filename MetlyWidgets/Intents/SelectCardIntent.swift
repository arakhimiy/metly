import AppIntents
import WidgetKit

/// Configuration of the My QR, Card and Lock Screen QR widgets: which card to show.
struct SelectCardIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Choose Card"
    static let description = IntentDescription("Choose which card the widget shows.")
    static let isDiscoverable = false

    /// nil or "Card to Share" follow the default / active event card.
    @Parameter(title: "Card")
    var card: CardEntity?

    init() {}

    init(card: CardEntity?) {
        self.card = card
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$card)")
    }
}
