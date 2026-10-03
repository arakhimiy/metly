@preconcurrency import AVFoundation
import SwiftUI

/// Camera preview + QR detection on AVFoundation (fallback when VisionKit can't run).
struct CaptureSessionView: UIViewRepresentable {
    let mode: ScanMode
    let camera: ScanCamera
    let onCode: (String) -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        let scanner = context.coordinator.scanner
        guard scanner.configure() else { return view }
        view.previewLayer.session = scanner.session
        view.previewLayer.videoGravity = .resizeAspectFill
        context.coordinator.token = camera.attach { [weak scanner] in
            guard let scanner else { throw ScanCamera.CaptureError.unavailable }
            return try await scanner.capturePhoto()
        }
        Task { await scanner.start() }
        return view
    }

    func updateUIView(_ view: CameraPreviewView, context: Context) {
        context.coordinator.camera = camera
        // Paper mode ignores QR codes in frame.
        context.coordinator.scanner.onCode = mode == .qr ? onCode : nil
    }

    static func dismantleUIView(_ view: CameraPreviewView, coordinator: Coordinator) {
        let scanner = coordinator.scanner
        scanner.onCode = nil
        if let token = coordinator.token { coordinator.camera.detach(token) }
        Task { await scanner.stop() }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(camera: camera)
    }

    final class Coordinator {
        let scanner = CaptureSessionScanner()
        var camera: ScanCamera
        var token: UUID?

        init(camera: ScanCamera) {
            self.camera = camera
        }
    }
}
