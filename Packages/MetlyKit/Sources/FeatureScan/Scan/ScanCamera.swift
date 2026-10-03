@preconcurrency import AVFoundation
import Observation
import UIKit
import VisionKit

/// Takes a still photo with whichever camera backend is on screen.
typealias PhotoCapturer = @MainActor () async throws -> UIImage

/// SCAN's camera state: permission, which backend runs, torch, still capture and live text.
/// The backend views (`DataScannerView`, `CaptureSessionView`) register themselves here.
@Observable
final class ScanCamera {
    enum Backend: Equatable {
        /// VisionKit live scanner (A12+, camera authorised).
        case dataScanner
        /// AVFoundation fallback (`AVCaptureMetadataOutput` + photo output).
        case captureSession
        /// Previews: a dark stand-in for the camera feed.
        case placeholder
        case none
    }

    enum CaptureError: Error { case unavailable }

    var access: CameraAccess
    var isTorchOn = false
    /// VisionKit reported it can't run (e.g. camera taken by another app) → AVFoundation takes over.
    var dataScannerFailed = false

    @ObservationIgnored private var photoCapturer: PhotoCapturer?
    @ObservationIgnored private var attachedToken: UUID?
    @ObservationIgnored private let isPreview: Bool
    /// Text VisionKit currently sees in Paper mode — fallback when the still photo reads nothing.
    @ObservationIgnored var liveLines: [OCRLine] = []

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
        if isPreview { return .placeholder }
        if !dataScannerFailed, DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            return .dataScanner
        }
        return .captureSession
    }

    var hasTorch: Bool {
        guard !isPreview else { return true }
        return AVCaptureDevice.default(for: .video)?.hasTorch == true
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
    func applyTorch() {
        guard !isPreview else { return }
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            isTorchOn = false
            return
        }
        let mode: AVCaptureDevice.TorchMode = isTorchOn ? .on : .off
        guard device.isTorchModeSupported(mode), !isTorchOn || device.isTorchAvailable else {
            isTorchOn = false
            return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = mode
            device.unlockForConfiguration()
        } catch {
            isTorchOn = false
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
        liveLines = []
    }

    func capturePhoto() async throws -> UIImage {
        guard let photoCapturer else { throw CaptureError.unavailable }
        return try await photoCapturer()
    }
}
