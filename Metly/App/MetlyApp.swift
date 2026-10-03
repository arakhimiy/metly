import FeatureProfile
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

@main
struct MetlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var router = AppRouter()
    private let container: ModelContainer
    private let services: AppServices
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
        services = MetlyServiceFactory.makeServices(container: container)
        AppDelegate.services = services
        subscriptionManager.start(services: services)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(services)
                .modelContainer(container)
                .preferredColorScheme(services.preferences.appearance.colorScheme)
                .onOpenURL { url in DeepLinkHandler.handle(url, router: router, context: container.mainContext) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { DeepLinkHandler.handle(url, router: router, context: container.mainContext) }
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
