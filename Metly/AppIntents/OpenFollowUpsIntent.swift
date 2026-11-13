import AppIntents
import MetlyWidgetKit

/// "Show my follow-ups in Nameshake" — opens FOLLOWUPS (`tanishly://followups`).
nonisolated struct OpenFollowUpsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Follow-ups"
    static let description = IntentDescription("Shows your follow-up reminders.")

    init() {}

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetDeepLink.followUps))
    }
}
