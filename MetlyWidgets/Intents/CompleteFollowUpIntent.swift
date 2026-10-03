import AppIntents
import Foundation
import MetlyWidgetKit

/// Follow-ups widget "Done" button.
///
/// Runs in the widget extension, which must not write the SwiftData store: it queues the completion in
/// the App Group (applied by the app's `WidgetSnapshotPublisher` on next launch / activation) and
/// removes the row from the snapshot right away. WidgetKit reloads the widget when `perform()` returns.
struct CompleteFollowUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark Follow-up Done"
    static let isDiscoverable = false

    @Parameter(title: "Follow-up ID")
    var followUpID: String

    init() {}

    init(followUpID: UUID) {
        self.followUpID = followUpID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: followUpID) else { return .result() }
        try WidgetSnapshotStore.appGroup.enqueueFollowUpCompletion(id)
        return .result()
    }
}
