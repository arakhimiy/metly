import SwiftUI

/// The live camera (AVFoundation), or a stand-in in previews.
struct ScanCameraFeed: View {
    let mode: ScanMode
    let camera: ScanCamera
    let onCode: (String) -> Void

    var body: some View {
        switch camera.backend {
        case .captureSession:
            // One session for both modes: switching never restarts the camera.
            CaptureSessionView(mode: mode, camera: camera, onCode: onCode)
        case .placeholder:
            LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
        case .none:
            Color.black
        }
    }
}
