import MetlyCore
import MetlyData
import StoreKit
import SwiftData
import SwiftUI

/// SETTINGS_DELETE_ACCOUNT (SPEC §2.5.21).
struct DeleteAccountScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(Card.live) private var cards: [Card]
    @Query(Connection.live) private var people: [Connection]
    @State private var isConfirming = false
    @State private var isDeleting = false
    @State private var isManagingSubscription = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Delete Your Account?")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    Text(AccountCopy.deleteAccountMessage(cardCount: cards.count, peopleCount: people.count))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            Section {
                DataExportButton(title: String(localized: "Download My Data First"))
            } footer: {
                Text("You’ll get an email with a copy of everything.")
            }

            if services.entitlements.isPro {
                Section {
                    Button("Manage Subscription", action: manageSubscription)
                } footer: {
                    Text("Deleting your account doesn’t cancel \(Brand.proName). Cancel it in your App Store subscriptions first.")
                }
            }

            Section {
                Button(role: .destructive, action: confirmDeletion) {
                    HStack {
                        Text("Delete Account")
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isDeleting)
                .alert("Delete Account?", isPresented: $isConfirming) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive, action: deleteAccount)
                } message: {
                    Text("This can’t be undone.")
                }
            }
        }
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $isManagingSubscription)
        .alert("Couldn’t Delete Account", isPresented: $isShowingError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private func confirmDeletion() {
        isConfirming = true
    }

    private func manageSubscription() {
        isManagingSubscription = true
    }

    private func deleteAccount() {
        guard services.network.isOnline else {
            show(String(localized: "You’re offline. Connect to the internet and try again."))
            return
        }
        Task {
            isDeleting = true
            defer { isDeleting = false }
            do {
                try await services.auth.deleteAccount()
                // Make sure nothing personal stays on the device even if the service didn't wipe.
                try? MetlyModelContainer.wipe(modelContext)
                services.preferences.reset()
                router.signedOut()
                router.showToast(String(localized: "Account Deleted"), systemImage: "checkmark.circle")
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    private func show(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}

#Preview("Delete Account · Free") {
    NavigationStack { DeleteAccountScreen() }
        .metlyPreview(.full)
}

#Preview("Delete Account · Pro, offline") {
    NavigationStack { DeleteAccountScreen() }
        .metlyPreview(.full, plan: .pro, online: false)
}
