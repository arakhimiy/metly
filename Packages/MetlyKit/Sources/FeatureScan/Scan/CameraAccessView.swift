import MetlyDesign
import SwiftUI

/// SCAN when the camera can't run: not asked yet, denied (SPEC §7.4), restricted, or no camera.
/// Paste Link always works.
struct CameraAccessView<Extra: View>: View {
    let access: CameraAccess
    let onRequestAccess: () -> Void
    let onPaste: (String) -> Void
    /// Extra actions under "no camera" (DEBUG demo scans).
    @ViewBuilder var extra: Extra

    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            switch access {
            case .undetermined:
                Button("Allow Camera Access", action: onRequestAccess)
                    .prominentButtonStyle()
                    .controlSize(.large)
            case .denied:
                Button("Open Settings", action: openSettings)
                    .prominentButtonStyle()
                    .controlSize(.large)
            case .restricted, .noCamera, .authorized:
                EmptyView()
            }
            PasteLinkButton(onPaste: onPaste)
            if access == .noCamera {
                extra
            }
        }
    }

    private var title: String {
        switch access {
        case .undetermined: String(localized: "Scan Business Cards")
        case .denied, .authorized: String(localized: "Camera Access Needed")
        case .restricted: String(localized: "Camera Is Restricted")
        case .noCamera: String(localized: "Camera Unavailable")
        }
    }

    private var symbol: String {
        switch access {
        case .undetermined: "qrcode.viewfinder"
        case .denied, .restricted, .authorized: "camera.slash"
        case .noCamera: "video.slash"
        }
    }

    private var message: String {
        switch access {
        case .undetermined: String(localized: "Allow camera access to scan QR codes and paper business cards.")
        case .denied, .authorized: String(localized: "Allow camera access in Settings to scan cards. You can still paste a link.")
        case .restricted: String(localized: "Camera access is restricted on this iPhone. You can still paste a link.")
        case .noCamera: String(localized: "This device can't scan with a camera. You can still paste a link.")
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}
