import MetlyWidgetKit
import SwiftUI
import WidgetKit

/// WIDGET_CARD_M — the card face with its QR, "{N} new connections this week", Show QR.
struct CardWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.card, intent: SelectCardIntent.self, provider: CardTimelineProvider()) { entry in
            CardWidgetView(content: entry.content)
                .widgetURL(entry.content.url)
                .containerBackground(WidgetBackgrounds.standard, for: .widget)
        }
        .configurationDisplayName("Card")
        .description("Your card and this week's new connections. Tap to show your QR.")
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Card", as: .systemMedium) {
    CardWidget()
} timeline: {
    CardWidgetEntry(date: .now, content: CardWidgetContent.resolve(snapshot: .sample(), cardID: nil, at: .now))
    CardWidgetEntry(date: .now, content: CardWidgetContent.resolve(snapshot: .sample(),
                                                                   cardID: WidgetSnapshot.samplePersonalCardID, at: .now))
}

#Preview("Card · empty week", as: .systemMedium) {
    CardWidget()
} timeline: {
    CardWidgetEntry(date: .now, content: CardWidgetContent.resolve(snapshot: .sampleEmpty(), cardID: nil, at: .now))
}

#Preview("Card · no card / signed out", as: .systemMedium) {
    CardWidget()
} timeline: {
    CardWidgetEntry(date: .now, content: .noCard)
    CardWidgetEntry(date: .now, content: .signedOut)
}
