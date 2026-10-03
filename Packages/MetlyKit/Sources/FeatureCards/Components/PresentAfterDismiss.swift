import MetlyCore
import SwiftUI

extension AppRouter {
    /// Presents either kind of route.
    func present(_ presentation: Presentation) {
        switch presentation {
        case .sheet(let sheet): present(sheet)
        case .cover(let cover): present(cover)
        }
    }
}

extension View {
    /// Presents `next` once this modal has fully disappeared.
    ///
    /// Swapping a full-screen cover for a sheet (or a sheet for a cover) in one step makes UIKit
    /// present while a dismissal is still running, so the new modal can be dropped. Set `next`,
    /// call `router.dismiss()`, and the follow-up appears after the transition (QR → JUST_MET,
    /// Create → Share, Share → Export).
    func presentAfterDismiss(_ next: Binding<Presentation?>) -> some View {
        modifier(PresentAfterDismissModifier(next: next))
    }
}

private struct PresentAfterDismissModifier: ViewModifier {
    @Binding var next: Presentation?
    @Environment(AppRouter.self) private var router

    func body(content: Content) -> some View {
        content.onDisappear(perform: presentNext)
    }

    private func presentNext() {
        guard let presentation = next else { return }
        next = nil
        router.present(presentation)
    }
}
