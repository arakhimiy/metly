import FeatureEvents
import FeatureHome
import FeaturePeople
import FeatureProfile
import FeatureScan
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// Native tab bar (Liquid Glass automatically on iOS 26). Each tab owns a NavigationStack
/// bound to the router; modals are layered by `PresentationLayer`.
struct MainTabView: View {
    @Environment(AppRouter.self) private var router
    @Query(ConnectRequest.pendingIncoming) private var pendingRequests: [ConnectRequest]

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                TabStack(tab: .home) { HomeView() }
            }
            Tab("Scan", systemImage: "qrcode.viewfinder", value: AppTab.scan) {
                TabStack(tab: .scan) { ScanView() }
            }
            Tab("People", systemImage: "person.2", value: AppTab.people) {
                TabStack(tab: .people) { PeopleView() }
            }
            .badge(pendingRequests.count)
            Tab("Profile", systemImage: "person.crop.circle", value: AppTab.profile) {
                TabStack(tab: .profile) { ProfileView() }
            }
        }
        .presentationLayer(level: 0)
        .endsExpiredEvents()   // auto-end past events on appear/foreground → EVENT_ENDED
    }
}

private struct TabStack<Root: View>: View {
    @Environment(AppRouter.self) private var router
    let tab: AppTab
    @ViewBuilder let root: () -> Root

    var body: some View {
        NavigationStack(path: Binding(
            get: { router.paths[tab] ?? [] },
            set: { router.paths[tab] = $0 }
        )) {
            root()
                .navigationDestination(for: PushDestination.self) { RouteResolver.view(for: $0) }
        }
    }
}
