import MetlyCore
import SwiftUI

private struct FollowUpLimitAlertModifier: ViewModifier {
    @Binding var isPresented: Bool
    let openCount: Int
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.alert("Follow-up Limit Reached", isPresented: $isPresented) {
            Button("Not Now", role: .cancel) {}
            Button("Upgrade", action: upgrade)
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("The Free plan includes 5 active reminders. You have \(openCount). Mark one done, or upgrade for unlimited reminders.")
        }
    }

    private func upgrade() {
        router.present(.paywall(trigger: .followUpLimit))
    }
}

public extension View {
    /// ALERT_FU_LIMIT — "Follow-up Limit Reached" [Not Now · Upgrade → PAYWALL(.followUpLimit)].
    func followUpLimitAlert(isPresented: Binding<Bool>, openCount: Int) -> some View {
        modifier(FollowUpLimitAlertModifier(isPresented: isPresented, openCount: openCount))
    }
}
