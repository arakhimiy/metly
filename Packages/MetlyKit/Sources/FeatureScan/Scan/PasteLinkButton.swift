import SwiftUI
import UIKit

/// Native `PasteButton` for Tanishly links (SCAN "Paste Link") — reads the clipboard without
/// the "Allow Paste" prompt because the user tapped the system button.
///
/// Shown only while something was copied (a card link sent in Telegram, say): an always-disabled
/// "Paste" next to the camera only raised questions. Checking `hasStrings` / `hasURLs` doesn't read the
/// clipboard, so no prompt appears.
struct PasteLinkButton: View {
    let onPaste: (String) -> Void

    @State private var hasCopiedText = Self.clipboardHasText

    var body: some View {
        Group {
            if hasCopiedText {
                PasteButton(payloadType: PastedText.self) { items in
                    if let text = items.first?.text { onPaste(text) }
                }
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .labelStyle(.titleAndIcon)
                .accessibilityHint("Opens a Tanishly card link from the clipboard")
                .transition(.opacity)
            }
        }
        .onAppear { hasCopiedText = Self.clipboardHasText }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            hasCopiedText = Self.clipboardHasText
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            hasCopiedText = Self.clipboardHasText
        }
        .animation(.smooth, value: hasCopiedText)
    }

    private static var clipboardHasText: Bool {
        UIPasteboard.general.hasStrings || UIPasteboard.general.hasURLs
    }
}
