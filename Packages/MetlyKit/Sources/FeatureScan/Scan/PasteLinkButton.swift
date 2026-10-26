import SwiftUI

/// Native `PasteButton` for Tanishly links (SCAN "Paste Link") — reads the clipboard without
/// the "Allow Paste" prompt because the user tapped the system button.
struct PasteLinkButton: View {
    let onPaste: (String) -> Void

    var body: some View {
        PasteButton(payloadType: PastedText.self) { items in
            if let text = items.first?.text { onPaste(text) }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .labelStyle(.titleAndIcon)
        .accessibilityHint("Opens a Tanishly card link from the clipboard")
    }
}
