import SwiftUI

/// The live camera: VisionKit when available, AVFoundation otherwise, a stand-in in previews.
struct ScanCameraFeed: View {
    let mode: ScanMode
    let camera: ScanCamera
    let onCode: (String) -> Void

    var body: some View {
        switch camera.backend {
        case .dataScanner:
            DataScannerView(mode: mode, camera: camera, onCode: onCode)
                .id(mode)
        case .captureSession:
            CaptureSessionView(mode: mode, camera: camera, onCode: onCode)
        case .placeholder:
            LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
        case .none:
            Color.black
        }
    }
}
