import PassKit
import SwiftUI

/// Apple's official "Add to Apple Wallet" button (`PKAddPassButton`). The pass is fetched on tap,
/// so SwiftUI's `AddPassToWalletButton` (which needs the pass up front) doesn't fit.
struct AddToWalletButton: UIViewRepresentable {
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: style)
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateUIView(_ button: PKAddPassButton, context: Context) {
        context.coordinator.action = action
        button.addPassButtonStyle = style
        button.isEnabled = context.environment.isEnabled
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    /// Black on light backgrounds, outlined black on dark ones (Apple Wallet guidelines).
    private var style: PKAddPassButtonStyle {
        colorScheme == .dark ? .blackOutline : .black
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func tapped() {
            action()
        }
    }
}
