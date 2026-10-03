@preconcurrency import AVFoundation
import UIKit

/// AVFoundation fallback for devices where VisionKit's `DataScannerViewController` isn't
/// available: QR codes via `AVCaptureMetadataOutput`, stills via `AVCapturePhotoOutput`.
final class CaptureSessionScanner: NSObject {
    let runner = CaptureSessionRunner()
    /// Called on the main actor for every QR payload in a frame (debounced by SCAN).
    var onCode: ((String) -> Void)?

    private let metadataOutput = AVCaptureMetadataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var inFlightCaptures: [PhotoCaptureDelegate] = []
    private var isConfigured = false

    var session: AVCaptureSession { runner.session }

    /// Adds the back camera and outputs. Returns false when the camera can't be used.
    func configure() -> Bool {
        guard !isConfigured else { return true }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(metadataOutput), session.canAddOutput(photoOutput) else {
            return false
        }
        session.addInput(input)
        session.addOutput(metadataOutput)
        session.addOutput(photoOutput)

        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
        if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
            metadataOutput.metadataObjectTypes = [.qr]
        }
        // The app is portrait-only.
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            device.unlockForConfiguration()
        }
        isConfigured = true
        return true
    }

    func start() async { await runner.start() }

    func stop() async { await runner.stop() }

    func capturePhoto() async throws -> UIImage {
        let delegate = PhotoCaptureDelegate()
        inFlightCaptures.append(delegate)   // the photo output doesn't retain its delegate
        defer { inFlightCaptures.removeAll { $0 === delegate } }
        let data = try await delegate.capture(from: photoOutput)
        guard let image = UIImage(data: data) else { throw PhotoCaptureDelegate.CaptureError.noImage }
        return image
    }
}

extension CaptureSessionScanner: AVCaptureMetadataOutputObjectsDelegate {
    // Delivered on the main queue (see `setMetadataObjectsDelegate(_:queue:)`).
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        let payloads = metadataObjects.compactMap { ($0 as? AVMetadataMachineReadableCodeObject)?.stringValue }
        guard !payloads.isEmpty else { return }
        MainActor.assumeIsolated {
            for payload in payloads { onCode?(payload) }
        }
    }
}
