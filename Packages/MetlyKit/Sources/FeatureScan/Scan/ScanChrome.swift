import SwiftUI

/// Dark navigation and tab bars over the camera (SPEC §2.2 "Tab bar on SCAN renders in dark/camera styling").
struct ScanChrome: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            // Liquid Glass bars float over the feed; they only need the dark appearance.
            content.toolbarColorScheme(.dark, for: .navigationBar, .tabBar)
        } else {
            content
                .toolbarBackgroundVisibility(.visible, for: .navigationBar, .tabBar)
                .toolbarColorScheme(.dark, for: .navigationBar, .tabBar)
        }
    }
}
