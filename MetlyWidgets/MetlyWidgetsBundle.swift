import SwiftUI
import WidgetKit

/// Nameshake widgets (SPEC §2.5.16) + the "Show My QR" control (Q23).
///
/// Data flow: the app publishes `WidgetSnapshot` JSON into the App Group (`WidgetSnapshotPublisher`);
/// providers only read it. Interactive actions are queued for the app — this extension never opens
/// the SwiftData store.
@main
struct MetlyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MyQRWidget()
        CardWidget()
        FollowUpsWidget()
        LockScreenQRWidget()
        ShowMyQRControl()
    }
}
