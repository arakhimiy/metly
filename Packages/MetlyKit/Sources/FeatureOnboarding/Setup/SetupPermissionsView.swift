import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

/// SETUP_PERMISSIONS — "Allow Access". Ends setup and enters the app with CARD_CREATE
/// (with a pending deferred invite's card waiting in the Scan tab, see `OnboardingCoordinator`).
struct SetupPermissionsView: View {
    let store: OnboardingStore

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: PermissionsModel

    init(provider: any PermissionProviding = SystemPermissionProvider(), store: OnboardingStore = OnboardingStore()) {
        self.store = store
        _model = State(initialValue: PermissionsModel(provider: provider))
    }

    var body: some View {
        List {
            Section {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind,
                                  status: model.status(of: kind),
                                  isRequesting: model.requesting == kind,
                                  onAllow: { allow(kind) },
                                  onOpenSettings: { openSettings(for: kind) })
                }
            } footer: {
                Text("\(Brand.appName) only uses these when you connect or scan. Change them anytime in Settings.")
            }
        }
        .navigationTitle("Allow Access")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Skip", action: finish)
            }
        }
        .bottomActionBar {
            Button(action: finish) {
                // CARD_CREATE follows in every case (a pending invite's card waits in the Scan tab).
                Text("Create My First Card")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .controlSize(.large)
        }
        .disabled(model.requesting != nil)
        .task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in
            // Picks up changes made in iOS Settings.
            if phase == .active {
                Task { await model.refresh() }
            }
        }
        .sensoryFeedback(trigger: model.grantedCount) { old, new in
            new > old ? .success : nil
        }
    }

    private func allow(_ kind: PermissionKind) {
        Task { await model.request(kind) }
    }

    private func openSettings(for kind: PermissionKind) {
        if let url = kind.settingsURL {
            openURL(url)
        }
    }

    private func finish() {
        OnboardingCoordinator.finishSetup(context: modelContext,
                                          notificationsGranted: model.status(of: .notifications) == .granted,
                                          router: router, services: services, store: store)
    }
}

#Preview("Permissions · not asked") {
    NavigationStack {
        SetupPermissionsView(provider: PreviewPermissionProvider(statuses: [:]), store: .preview())
    }
    .metlyPreview(.signedOut)
}

#Preview("Permissions · mixed") {
    NavigationStack {
        SetupPermissionsView(provider: PreviewPermissionProvider(statuses: [
            .notifications: .granted,
            .camera: .denied,
            .localNetwork: .notDetermined,
        ]), store: .preview())
    }
    .metlyPreview(.signedOut)
}

#Preview("Permissions · all allowed, dark") {
    NavigationStack {
        SetupPermissionsView(provider: PreviewPermissionProvider(statuses: [
            .notifications: .granted, .camera: .granted, .localNetwork: .granted,
        ]), store: .preview(pendingInviteSlug: "jasur-p4y1"))
    }
    .metlyPreview(.signedOut)
    .preferredColorScheme(.dark)
}

#Preview("Permissions · accessibility size") {
    NavigationStack {
        SetupPermissionsView(provider: PreviewPermissionProvider(statuses: [.camera: .denied]), store: .preview())
    }
    .metlyPreview(.signedOut)
    .dynamicTypeSize(.accessibility3)
}
