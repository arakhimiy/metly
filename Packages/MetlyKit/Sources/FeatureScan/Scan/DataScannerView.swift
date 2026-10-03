import SwiftUI
import Vision
import VisionKit

/// VisionKit's live scanner. QR mode recognises QR codes only; Paper mode highlights text so the
/// user sees the card is readable, and the shutter takes a still for accurate OCR.
/// Recreate it (`.id(mode)`) when the mode changes — its data types are fixed at init.
struct DataScannerView: UIViewControllerRepresentable {
    let mode: ScanMode
    let camera: ScanCamera
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let qr: [VNBarcodeSymbology] = [.qr]
        // Latin (English / Uzbek) and Cyrillic (Russian) cards, limited to what this device supports.
        let languages = ["en-US", "ru-RU"].filter(DataScannerViewController.supportedTextRecognitionLanguages.contains)
        let types: Set<DataScannerViewController.RecognizedDataType> = mode == .qr
            ? [.barcode(symbologies: qr)]
            : [.text(languages: languages)]
        let scanner = DataScannerViewController(
            recognizedDataTypes: types,
            qualityLevel: mode == .qr ? .fast : .balanced,
            recognizesMultipleItems: mode == .paper,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: mode == .paper
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
        // Start once SwiftUI has put the controller on screen.
        guard !context.coordinator.hasStarted else { return }
        context.coordinator.hasStarted = true
        Task { @MainActor in
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
            for case .barcode(let barcode) in addedItems {
                if let payload = barcode.payloadStringValue { parent.onCode(payload) }
            }
            updateLiveText(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            updateLiveText(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            updateLiveText(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                parent.onCode(payload)
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            parent.camera.dataScannerFailed = true
        }

        /// Paper mode: keep what VisionKit reads (top to bottom) as an OCR fallback for the shutter.
        private func updateLiveText(_ items: [RecognizedItem]) {
            guard parent.mode == .paper else { return }
            let texts = items.compactMap { item -> RecognizedItem.Text? in
                if case .text(let text) = item { return text }
                return nil
            }
            parent.camera.liveLines = texts
                .sorted { $0.bounds.topLeft.y < $1.bounds.topLeft.y }
                .map { OCRLine($0.transcript, height: Double(abs($0.bounds.bottomLeft.y - $0.bounds.topLeft.y))) }
        }
    }
}
