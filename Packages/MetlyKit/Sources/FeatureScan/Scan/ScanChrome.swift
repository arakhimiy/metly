import MetlyCore
import SwiftUI

/// Dark navigation and tab bars over the camera (SPEC §2.2 "Tab bar on SCAN renders in dark/camera styling").
/// Only while the camera root is on screen: the tab bar reads the stack root's preference, so once a
/// screen is pushed (SCANNED_CARD, PAPER_REVIEW) the preference must go back to automatic.
struct ScanChrome: ViewModifier {
    @Environment(AppRouter.self) private var router

    private var isCameraVisible: Bool { router.paths[.scan, default: []].isEmpty }

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // Liquid Glass bars float over the feed; they only need the dark appearance.
            content.toolbarColorScheme(isCameraVisible ? .dark : nil, for: .navigationBar, .tabBar)
        } else {
            content
                .toolbarBackgroundVisibility(isCameraVisible ? .visible : .automatic, for: .navigationBar, .tabBar)
                .toolbarColorScheme(isCameraVisible ? .dark : nil, for: .navigationBar, .tabBar)
        }
    }
}
