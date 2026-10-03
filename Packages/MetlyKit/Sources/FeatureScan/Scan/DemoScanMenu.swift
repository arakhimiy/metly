#if DEBUG
import MetlyCore
import MetlyDesign
import SwiftUI

/// DEBUG-only stand-in for the camera (Simulator): tap scans Kamila's card, touch and hold
/// for the other mock-server people, foreign codes and paper cards.
struct DemoScanMenu: View {
    let onPayload: (String) -> Void
    let onPaperDraft: (PaperCardDraft) -> Void

    var body: some View {
        Menu {
            Section("\(Brand.appName) Cards") {
                Button("Kamila · Already Connected") { onPayload(ScanSamples.kamilaURL) }
                Button("Bekzod · Accepts Requests") { onPayload("https://metly.link/c/bekzod-b8n3") }
                Button("Nodira · Never Answers") { onPayload("https://metly.link/c/nodira-n5m1") }
                Button("Lola · Paused Card") { onPayload("https://metly.link/c/lola-p0z3") }
                Button("My Work Card") { onPayload("https://metly.link/c/aziza-w7k2") }
            }
            Section("Other QR Codes") {
                Button("vCard Contact") { onPayload(ScanSamples.vCard) }
                Button("Website") { onPayload("https://example.com/menu") }
                Button("Plain Text") { onPayload("Table 12 · Wi-Fi: cafe2026") }
            }
            Section("Paper Cards") {
                Button("Sample Card") { onPaperDraft(ScanSamples.paperDraft) }
                Button("Unreadable Card") { onPaperDraft(PaperCardDraft()) }
            }
        } label: {
            Label("Scan Demo Card", systemImage: "ladybug")
        } primaryAction: {
            onPayload(ScanSamples.kamilaURL)
        }
        .secondaryButtonStyle()
        .controlSize(.large)
    }
}
#endif
