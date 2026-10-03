import MetlyCore
import SwiftUI

/// ALERT_ONE_EVENT — "One Active Event on Free" [Not Now · Upgrade → PAYWALL(.eventLimit)].
private struct OneActiveEventAlert: ViewModifier {
    @Binding var isPresented: Bool
    let activeEventName: String

    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.alert("One Active Event on Free", isPresented: $isPresented) {
            Button("Not Now", role: .cancel) {}
            Button("Upgrade", action: upgrade)
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("End \(activeEventName) first, or upgrade to run several events at once.")
        }
    }

    private func upgrade() {
        router.present(.paywall(trigger: .eventLimit))
    }
}

extension View {
    func oneActiveEventAlert(isPresented: Binding<Bool>, activeEventName: String) -> some View {
        modifier(OneActiveEventAlert(isPresented: isPresented, activeEventName: activeEventName))
    }
}
