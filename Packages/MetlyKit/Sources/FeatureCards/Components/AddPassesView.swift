import PassKit
import SwiftUI

/// The system "Add to Apple Wallet" review sheet for one pass.
struct AddPassesView: UIViewControllerRepresentable {
    let pass: PKPass
    /// Called when the sheet closes; `true` when the pass is now in Wallet.
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard let controller = PKAddPassesViewController(pass: pass) else {
            // Unreachable in practice (`canAddPasses()` is checked first); close straight away.
            Task { @MainActor in onFinish(false) }
            return UIViewController()
        }
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.onFinish = onFinish
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(pass: pass, onFinish: onFinish)
    }

    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let pass: PKPass
        var onFinish: (Bool) -> Void

        init(pass: PKPass, onFinish: @escaping (Bool) -> Void) {
            self.pass = pass
            self.onFinish = onFinish
        }

        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
            onFinish(PKPassLibrary().containsPass(pass))
        }
    }
}

extension View {
    /// Hosts the Wallet review sheet and the failure alert for a `WalletAddFlow`.
    func walletAddFlow(_ flow: WalletAddFlow) -> some View {
        modifier(WalletAddFlowModifier(flow: flow))
    }
}

private struct WalletAddFlowModifier: ViewModifier {
    @Bindable var flow: WalletAddFlow

    func body(content: Content) -> some View {
        content
            .sheet(item: $flow.pendingPass) { item in
                AddPassesView(pass: item.pass, onFinish: flow.finish(added:))
                    .ignoresSafeArea()
            }
            .alert("Couldn’t Add to Wallet", isPresented: $flow.isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(flow.errorMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: flow.addedCount)
    }
}
