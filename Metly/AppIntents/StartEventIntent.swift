import AppIntents
import MetlyWidgetKit

/// "Start an event in Nameshake" — opens START_EVENT (`nameshake://event/start`).
///
/// Requires the `event` host in `DeepLinkHandler` (see the Widgets & Intents report); START_EVENT itself
/// enforces the Free plan's one-active-event limit.
nonisolated struct StartEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Event"
    static let description = IntentDescription("Starts event mode so everyone you meet is added to the event.")

    init() {}

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(WidgetDeepLink.startEvent))
    }
}
