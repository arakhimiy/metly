@preconcurrency import AVFoundation
import Observation
import UIKit

/// Takes a still photo with whichever camera backend is on screen.
typealias PhotoCapturer = @MainActor () async throws -> UIImage

/// SCAN's camera state: permission, which backend runs, torch and still capture.
/// The camera view (`CaptureSessionView`) registers itself here.
@Observable
final class ScanCamera {
    enum Backend: Equatable {
        /// AVFoundation: `AVCaptureMetadataOutput` for QR codes + photo output for paper cards.
        /// Not VisionKit's DataScannerViewController: it owns the camera, so the torch (set on the
        /// device from outside) froze its preview in the dark.
        case captureSession
        /// Previews: a dark stand-in for the camera feed.
        case placeholder
        case none
    }

    enum CaptureError: Error { case unavailable }

    var access: CameraAccess
    var isTorchOn = false

    @ObservationIgnored private var photoCapturer: PhotoCapturer?
    @ObservationIgnored private var attachedToken: UUID?
    @ObservationIgnored private let isPreview: Bool
    @ObservationIgnored private var cachedBackCamera: AVCaptureDevice?
    @ObservationIgnored private var didLookUpBackCamera = false
    @ObservationIgnored private let torchQueue = DispatchQueue(label: "app.tanishly.ios.scan.torch")

    init() {
        access = .current
        isPreview = false
    }

    /// Previews: pretend the camera is in `access` state; `.authorized` shows a placeholder feed.
    init(previewAccess: CameraAccess) {
        access = previewAccess
        isPreview = true
    }

    var backend: Backend {
        guard access == .authorized else { return .none }
        return isPreview ? .placeholder : .captureSession
    }

    var hasTorch: Bool {
        guard !isPreview else { return true }
        return backCamera?.hasTorch == true
    }

    /// Looked up once: device discovery is too slow to repeat on every SwiftUI update.
    private var backCamera: AVCaptureDevice? {
        if !didLookUpBackCamera {
            didLookUpBackCamera = true
            cachedBackCamera = AVCaptureDevice.default(for: .video)
        }
        return cachedBackCamera
    }

    // MARK: Permission

    func refreshAccess() {
        guard !isPreview else { return }
        access = .current
    }

    func requestAccessIfNeeded() async {
        guard !isPreview, access == .undetermined else { return }
        access = await CameraAccess.request()
    }

    // MARK: Torch

    /// Applies `isTorchOn` to the back camera; resets it when the torch can't turn on (e.g. overheated).
    /// The device is configured on a serial background queue: `lockForConfiguration()` waits while the
    /// running scanner holds the camera, and doing that on the main thread froze SCAN.
    func applyTorch() {
        guard !isPreview else { return }
        guard let device = backCamera, device.hasTorch else {
            isTorchOn = false
            return
        }
        let on = isTorchOn
        torchQueue.async { [weak self] in
            guard !Self.setTorch(on, on: device), on else { return }
            Task { @MainActor in
                if self?.isTorchOn == true { self?.isTorchOn = false }
            }
        }
    }

    nonisolated private static func setTorch(_ on: Bool, on device: AVCaptureDevice) -> Bool {
        let mode: AVCaptureDevice.TorchMode = on ? .on : .off
        guard device.isTorchModeSupported(mode), !on || device.isTorchAvailable else { return false }
        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    // MARK: Still capture

    /// Registers the on-screen backend; returns a token for `detach(_:)`.
    func attach(photoCapturer: @escaping PhotoCapturer) -> UUID {
        let token = UUID()
        attachedToken = token
        self.photoCapturer = photoCapturer
        return token
    }

    /// Unregisters a backend — ignored when a newer one (e.g. after a mode switch) already attached.
    func detach(_ token: UUID) {
        guard attachedToken == token else { return }
        attachedToken = nil
        photoCapturer = nil
    }

    func capturePhoto() async throws -> UIImage {
        guard let photoCapturer else { throw CaptureError.unavailable }
        return try await photoCapturer()
    }
}
