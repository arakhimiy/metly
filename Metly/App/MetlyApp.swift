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
        let container: ModelContainer
        do {
            container = try MetlyModelContainer.make()
        } catch {
            fatalError("Could not open the Metly store: \(error)")
        }
        #if DEBUG
        // `-MetlyDemoData` launch argument: start signed in with the prototype's demo account.
        if CommandLine.arguments.contains("-MetlyDemoData"), container.mainContext.currentProfile() == nil {
            PreviewSeed.insert(.full, into: container.mainContext)
        }
        #endif
        self.container = container
        // Keep the demo seeding above this call: the mock server mirrors the device store.
        let environment = MetlyServiceFactory.makeEnvironment(container: container)
        self.environment = environment
        services = environment.services
        client = environment.client
        environment.syncEngine.registerBackgroundTasks()   // BGTask "com.metly.app.sync"
        AppDelegate.services = services
        subscriptionManager.start(services: services)

        let router = AppRouter()
        _router = State(initialValue: router)
        // Owns the UNUserNotificationCenter delegate; must be set before launch finishes.
        FollowUpNotificationScheduler.configure(router: router, container: container, services: services)
    }

    var body: some Scene {
        WindowGroup {
            RootView(checkAppleCredential: { [auth = environment.auth] in await auth.checkAppleCredentialState() })
                .environment(router)
                .environment(services)
                .environment(client)
                .modelContainer(container)
                .preferredColorScheme(services.preferences.appearance.colorScheme)
                .onOpenURL { url in DeepLinkHandler.handle(url, router: router, context: container.mainContext) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { DeepLinkHandler.handle(url, router: router, context: container.mainContext) }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: services.sync.requestSync()
                    case .background: environment.syncEngine.scheduleBackgroundSync()
                    default: break
                    }
                }
        }
    }
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
