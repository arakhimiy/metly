import MetlyCardKit
import MetlyWidgetKit
import SwiftUI
import WidgetKit

/// WIDGET_QR_S — "Your QR, one tap away." Tap → QR_FULLSCREEN.
struct MyQRWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.myQR, intent: SelectCardIntent.self, provider: CardTimelineProvider()) { entry in
            MyQRWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("My QR")
        .description("Your QR, one tap away.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct MyQRWidgetEntryView: View {
    let entry: CardWidgetEntry

    var body: some View {
        MyQRWidgetView(content: entry.content)
            .padding(12)
            .widgetURL(entry.content.url)
            .containerBackground(for: .widget) {
                if let design = entry.content.display?.card.design {
                    WidgetBackgrounds.card(design)
                } else {
                    WidgetBackgrounds.standard
                }
            }
    }
}

#Preview("My QR", as: .systemSmall) {
    MyQRWidget()
} timeline: {
    CardWidgetEntry(date: .now, content: CardWidgetContent.resolve(snapshot: .sample(), cardID: nil, at: .now))
    CardWidgetEntry(date: .now, content: CardWidgetContent.resolve(snapshot: .sample(),
                                                                   cardID: WidgetSnapshot.samplePersonalCardID, at: .now))
}

#Preview("My QR · paused", as: .systemSmall) {
    MyQRWidget()
} timeline: {
    CardWidgetEntry(date: .now, content: .card(CardWidgetDisplay(
        card: WidgetSnapshot.sampleCards[0],
        owner: WidgetOwner(fullName: "Aziza Karimova", linksPaused: true))))
}

#Preview("My QR · no card / signed out", as: .systemSmall) {
    MyQRWidget()
} timeline: {
    CardWidgetEntry(date: .now, content: .noCard)
    CardWidgetEntry(date: .now, content: .signedOut)
}
