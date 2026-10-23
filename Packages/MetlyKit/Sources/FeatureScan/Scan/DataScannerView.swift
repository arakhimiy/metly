import SwiftUI
import Vision
import VisionKit

/// VisionKit's live scanner, one instance for both modes. It only looks for QR codes; Paper mode
/// ignores them and the shutter takes a still that is read on device (`PaperCardReader`).
///
/// Every VisionKit option is fixed at init, so a scanner per mode meant tearing the camera down and
/// loading the text-recognition models on each mode switch — the screen froze. Live text
/// highlighting isn't worth that: the still photo is what gets read anyway.
struct DataScannerView: UIViewControllerRepresentable {
    let mode: ScanMode
    let camera: ScanCamera
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [VNBarcodeSymbology.qr])],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        context.coordinator.token = camera.attach { [weak scanner] in
            guard let scanner else { throw ScanCamera.CaptureError.unavailable }
            return try await scanner.capturePhoto()
        }
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.hasStarted else { return }
        context.coordinator.hasStarted = true
        // `startScanning()` spins the camera up on the main thread; let the screen finish appearing
        // first so the tab switch stays smooth, then start (unless the screen already went away).
        Task { @MainActor [weak scanner] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let scanner, scanner.view.window != nil, !scanner.isScanning else { return }
            do {
                try scanner.startScanning()
            } catch {
                camera.dataScannerFailed = true
            }
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
        if let token = coordinator.token { coordinator.parent.camera.detach(token) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: DataScannerView
        var hasStarted = false
        var token: UUID?

        init(parent: DataScannerView) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            // Paper mode ignores QR codes in frame.
            guard parent.mode == .qr else { return }
            for case .barcode(let barcode) in addedItems {
                if let payload = barcode.payloadStringValue { parent.onCode(payload) }
            }
        }

        /// A code already in frame when switching back to QR mode only ever arrives as an update
        /// (SCAN's debouncer drops the repeats).
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard parent.mode == .qr else { return }
            for case .barcode(let barcode) in updatedItems {
                if let payload = barcode.payloadStringValue { parent.onCode(payload) }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard parent.mode == .qr else { return }
            if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                parent.onCode(payload)
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            parent.camera.dataScannerFailed = true
        }
    }
}
