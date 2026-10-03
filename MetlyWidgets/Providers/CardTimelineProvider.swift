import Foundation
import MetlyWidgetKit
import WidgetKit

nonisolated struct CardWidgetEntry: TimelineEntry {
    let date: Date
    let content: CardWidgetContent

    /// Gallery placeholder (redacted by the system).
    static var placeholder: CardWidgetEntry {
        CardWidgetEntry(date: .now, content: CardWidgetContent.resolve(snapshot: .sample(), cardID: nil, at: .now))
    }
}

/// Timelines for My QR, Card and Lock Screen QR. Data comes from the snapshot the app publishes; the app
/// reloads all timelines when it changes. Entries at midnight keep "this week" honest in between.
nonisolated struct CardTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CardWidgetEntry {
        .placeholder
    }

    func snapshot(for configuration: SelectCardIntent, in context: Context) async -> CardWidgetEntry {
        let stored = WidgetSnapshotStore.appGroup.load()
        // The widget gallery shows sample data until the user has a card.
        let snapshot = context.isPreview && stored?.shareCard == nil ? .sample() : stored
        return CardWidgetEntry(date: .now, content: CardWidgetContent.resolve(snapshot: snapshot, cardID: configuration.card?.cardID, at: .now))
    }

    func timeline(for configuration: SelectCardIntent, in context: Context) async -> Timeline<CardWidgetEntry> {
        let snapshot = WidgetSnapshotStore.appGroup.load()
        let cardID = configuration.card?.cardID
        let entries = WidgetTimelineSchedule.entryDates(from: .now).map { date in
            CardWidgetEntry(date: date, content: CardWidgetContent.resolve(snapshot: snapshot, cardID: cardID, at: date))
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}
