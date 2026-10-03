import MetlyWidgetKit
import SwiftUI
import WidgetKit

/// WIDGET_LOCK_QR_RECT + WIDGET_LOCK_QR_CIRC. The widget draws the QR itself, so people can scan it
/// without the phone being unlocked (Q23). Tap → QR_FULLSCREEN (after unlocking).
struct LockScreenQRWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetKind.lockScreenQR, intent: SelectCardIntent.self, provider: CardTimelineProvider()) { entry in
            LockScreenQRWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("QR Code")
        .description("Your QR on the Lock Screen. Anyone can scan it.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

struct LockScreenQRWidgetEntryView: View {
    let entry: CardWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                LockQRCircularView(content: entry.content) { AccessoryWidgetBackground() }
            } else {
                LockQRRectangularView(content: entry.content) { AccessoryWidgetBackground() }
            }
        }
        .widgetURL(entry.content.url)
        .containerBackground(for: .widget) { Color.clear }
    }
}

#Preview("Lock · rectangular", as: .accessoryRectangular) {
    LockScreenQRWidget()
} timeline: {
    CardWidgetEntry(date: .now, content: CardWidgetContent.resolve(snapshot: .sample(), cardID: nil, at: .now))
    CardWidgetEntry(date: .now, content: .signedOut)
}

#Preview("Lock · circular", as: .accessoryCircular) {
    LockScreenQRWidget()
} timeline: {
    CardWidgetEntry(date: .now, content: CardWidgetContent.resolve(snapshot: .sample(), cardID: nil, at: .now))
    CardWidgetEntry(date: .now, content: .noCard)
}
