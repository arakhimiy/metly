import MetlyWidgetKit
import SwiftUI
import WidgetKit

/// Control Center (also Lock Screen / Action button) control: "Show My QR" opens QR_FULLSCREEN.
struct ShowMyQRControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetKind.showQRControl) {
            ControlWidgetButton(action: ShowMyQRControlIntent()) {
                Label("Show My QR", systemImage: "qrcode")
            }
        }
        .displayName("Show My QR")
        .description("Opens your QR code full screen.")
    }
}
