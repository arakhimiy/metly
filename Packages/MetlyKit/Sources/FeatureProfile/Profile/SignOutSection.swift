import MetlyCore
import SwiftUI

/// Sign Out (ALERT_SIGN_OUT) → wipes local data → ONB_WELCOME.
struct SignOutSection: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @State private var isConfirming = false

    var body: some View {
        Section {
            Button("Sign Out", role: .destructive) {
                isConfirming = true
            }
            .frame(maxWidth: .infinity)
            .confirmationDialog("Sign Out?", isPresented: $isConfirming, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive, action: signOut)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(AccountCopy.signOutMessage)
            }
        } footer: {
            if let email = services.auth.accountEmail {
                Text("Signed in as \(email)")
            }
        }
    }

    private func signOut() {
        let services = services
        // Leave the signed-in UI first so no screen keeps rendering models while the store is wiped.
        router.signedOut()
        Task {
            await services.auth.signOut()   // wipes Keychain + the local store (Q46)
            services.preferences.reset()
        }
    }
}
