import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

/// WIDGETS_GALLERY (push from Profile → Widgets).
public struct WidgetsGalleryView: View {
    public init() {}

    public var body: some View {
        WidgetsGalleryScreen()
    }
}
