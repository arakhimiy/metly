import FeatureCards
import FeatureConnect
import FeatureHome
import FeatureProfile
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

@main
struct MetlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var router: AppRouter
    private let container: ModelContainer
    private let environment: MetlyEnvironment
    private let services: AppServices
    private let client: MetlyClient
    private let subscriptionManager = SubscriptionManager()

    init() {
        AppLanguage.applySavedChoice()   // before any string is read: the language picked in the app
        let container: ModelContainer
        do {
            container = try MetlyModelContainer.make()
        } catch {
            fatalError("Could not open the Nameshake store: \(error)")
        }
        #if DEBUG
        // `-MetlyDemoData` launch argument: start signed in with the prototype's demo account.
        if CommandLine.arguments.contains("-MetlyDemoData"), container.mainContext.currentProfile() == nil {
            PreviewSeed.insert(.full, into: container.mainContext)
        }
        #endif
        self.container = container
        WidgetSync.start(container: container)   // widget snapshot + pending widget actions
        // Keep the demo seeding above this call: the mock server mirrors the device store.
        let environment = MetlyServiceFactory.makeEnvironment(container: container)
        self.environment = environment
        services = environment.services
        client = environment.client
        environment.syncEngine.registerBackgroundTasks()   // BGTask "app.nameshake.ios.sync"
        AppDelegate.services = services
        subscriptionManager.start(services: services)

        let router = AppRouter()
        _router = State(initialValue: router)
        // Owns the UNUserNotificationCenter delegate; must be set before launch finishes.
        FollowUpNotificationScheduler.answerConnectRequest = { [client] requestID, accept in
            await ConnectRequestResponder.answer(requestID: requestID, accept: accept, client: client,
                                                 context: container.mainContext, router: router)
        }
        FollowUpNotificationScheduler.onRemoteNotification = { [client] in client.catchUpNow() }
        FollowUpNotificationScheduler.configure(router: router, container: container, services: services)
    }

    var body: some Scene {
        WindowGroup {
            RootView(checkAppleCredential: { [auth = environment.auth] in await auth.checkAppleCredentialState() })
                .environment(router)
                .environment(services)
                .environment(client)
                .environment(\.walletPassProvider, APIWalletPassProvider(client: client, container: container))
                .modelContainer(container)
                // Window-level override (also covers sheets/covers and reliably reverts to System).
                .onChange(of: services.preferences.appearance, initial: true) { _, appearance in
                    AppearanceApplier.apply(appearance)
                }
                .onOpenURL { url in DeepLinkHandler.handle(url, router: router, context: container.mainContext) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { DeepLinkHandler.handle(url, router: router, context: container.mainContext) }
                }
                .onChange(of: router.phase) { _, phase in
                    // Widget / Control / Siri cold launches arrive before the root phase is ready.
                    if phase == .main { DeepLinkHandler.handlePendingURL(router: router, context: container.mainContext) }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        services.sync.requestSync()
                        client.catchUpNow()
                    case .background: environment.syncEngine.scheduleBackgroundSync()
                    default: break
                    }
                }
        }
    }
}

/// `.preferredColorScheme(nil)` doesn't always revert after a forced scheme; UIKit's window override does.
enum AppearanceApplier {
    static func apply(_ appearance: AppAppearance) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.overrideUserInterfaceStyle = style }
        }
    }
}
