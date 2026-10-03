import AppIntents
import MetlyCore
import MetlyWidgetKit
import SwiftUI
import WidgetKit

/// WIDGET_FOLLOWUPS_M — "Follow Up Today": reminders due today or overdue. Rows open REMINDER_EDIT,
/// the circle marks one done (interactive), anywhere else opens FOLLOWUPS.
struct FollowUpsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.followUps, provider: FollowUpsTimelineProvider()) { entry in
            FollowUpsWidgetView(content: entry.content, now: entry.date) { followUp in
                Button(intent: CompleteFollowUpIntent(followUpID: followUp.id)) {
                    FollowUpDoneGlyph()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Mark \(followUp.title) done"))
            }
            .widgetURL(entry.content == .signedOut ? WidgetDeepLink.app : WidgetDeepLink.followUps)
            .containerBackground(WidgetBackgrounds.standard, for: .widget)
        }
        .configurationDisplayName("Follow-ups")
        .description(Text("Reminders due today. Tap one to open it in \(Brand.appName)."))
        .supportedFamilies([.systemMedium])
    }
}

#Preview("Follow-ups", as: .systemMedium) {
    FollowUpsWidget()
} timeline: {
    FollowUpsWidgetEntry(date: .now, content: FollowUpsWidgetContent.resolve(snapshot: .sample(), at: .now))
}

#Preview("Follow-ups · all caught up / none", as: .systemMedium) {
    FollowUpsWidget()
} timeline: {
    FollowUpsWidgetEntry(date: .now, content: FollowUpsWidgetContent.resolve(snapshot: .sampleNothingDue(), at: .now))
    FollowUpsWidgetEntry(date: .now, content: FollowUpsWidgetContent.resolve(snapshot: .sampleEmpty(), at: .now))
}

#Preview("Follow-ups · signed out", as: .systemMedium) {
    FollowUpsWidget()
} timeline: {
    FollowUpsWidgetEntry(date: .now, content: .signedOut)
}
