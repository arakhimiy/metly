#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// SCAN states (SPEC Appendix A: 30 Scan, 31 Scan · paper card, 34 Camera denied, 35 Invalid QR,
// 33 Paper card · not read). Previews fake the camera with a dark placeholder feed.

#Preview("Scan · QR") {
    NavigationStack { ScanScreen(camera: ScanCamera(previewAccess: .authorized)) }
        .metlyPreview(.full)
}

#Preview("Scan · Paper card") {
    NavigationStack { ScanScreen(mode: .paper, camera: ScanCamera(previewAccess: .authorized)) }
        .metlyPreview(.full)
}

#Preview("Scan · no active event") {
    NavigationStack { ScanScreen(camera: ScanCamera(previewAccess: .authorized)) }
        .metlyPreview(.empty)
}

#Preview("Scan · in tab bar") {
    TabView {
        Tab("Scan", systemImage: "qrcode.viewfinder") {
            NavigationStack { ScanScreen(camera: ScanCamera(previewAccess: .authorized)) }
        }
        Tab("Home", systemImage: "house") { Text("Home") }
        Tab("People", systemImage: "person.2") { Text("People") }
    }
    .metlyPreview(.full)
}

#Preview("Scan · camera denied") {
    NavigationStack { ScanScreen(camera: ScanCamera(previewAccess: .denied)) }
        .metlyPreview(.full)
}

#Preview("Scan · camera restricted") {
    NavigationStack { ScanScreen(camera: ScanCamera(previewAccess: .restricted)) }
        .metlyPreview(.full)
}

#Preview("Scan · not asked yet") {
    NavigationStack { ScanScreen(camera: ScanCamera(previewAccess: .undetermined)) }
        .metlyPreview(.full)
}

#Preview("Scan · no camera (Simulator)") {
    NavigationStack { ScanScreen(camera: ScanCamera(previewAccess: .noCamera)) }
        .metlyPreview(.full)
}

#Preview("Scan · invalid QR (web link)") {
    NavigationStack {
        ScanScreen(camera: ScanCamera(previewAccess: .authorized),
                   invalidCode: InvalidCodeAlert(source: .camera, url: URL(string: "https://example.com/menu"),
                                                 domain: "example.com"))
    }
    .metlyPreview(.full)
}

#Preview("Scan · invalid QR (text)") {
    NavigationStack {
        ScanScreen(camera: ScanCamera(previewAccess: .authorized), invalidCode: InvalidCodeAlert(source: .camera))
    }
    .metlyPreview(.full)
}

#Preview("Scan · paper not read") {
    NavigationStack {
        ScanScreen(mode: .paper, camera: ScanCamera(previewAccess: .authorized),
                   paperNotRead: PaperNotReadAlert(imageData: ScanSamples.sampleCardImage))
    }
    .metlyPreview(.full)
}

#Preview("Scan · accessibility size") {
    NavigationStack { ScanScreen(mode: .paper, camera: ScanCamera(previewAccess: .authorized)) }
        .metlyPreview(.full)
        .dynamicTypeSize(.accessibility2)
}
#endif
