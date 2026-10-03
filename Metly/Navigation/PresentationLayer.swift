import MetlyCore
import SwiftUI

/// Renders `router.presentations[level]` as a sheet or full-screen cover, and recursively
/// attaches the next level inside it — so a sheet can sit on top of a cover (QR → Share).
struct PresentationLayer: ViewModifier {
    @Environment(AppRouter.self) private var router
    let level: Int

    func body(content: Content) -> some View {
        content
            .sheet(item: binding(covers: false)) { presentation in
                RouteResolver.view(for: presentation)
                    .presentationLayer(level: level + 1)
                    .toastHost(level: level + 1)   // toasts appear on the top-most modal
            }
            .fullScreenCover(item: binding(covers: true)) { presentation in
                RouteResolver.view(for: presentation)
                    .presentationLayer(level: level + 1)
                    .toastHost(level: level + 1)
            }
    }

    private func binding(covers: Bool) -> Binding<Presentation?> {
        Binding(
            get: {
                guard router.presentations.indices.contains(level) else { return nil }
                let presentation = router.presentations[level]
                return presentation.isCover == covers ? presentation : nil
            },
            set: { newValue in
                // Interactive dismiss (swipe down) drops this level and everything above it.
                if newValue == nil, router.presentations.count > level {
                    router.presentations.removeSubrange(level...)
                }
            }
        )
    }
}

extension View {
    func presentationLayer(level: Int) -> some View { modifier(PresentationLayer(level: level)) }
}
