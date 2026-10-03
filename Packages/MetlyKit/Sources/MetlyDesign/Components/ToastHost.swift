import MetlyCore
import SwiftUI

/// Shows `router.toast` as a compact HUD above the tab bar (2 s, or 4 s with Undo).
/// Attached once by the app root — features only call `router.showToast(...)`.
public struct ToastHostModifier: ViewModifier {
    @Environment(AppRouter.self) private var router
    /// Presentation level this host sits on; only the top-most level shows the toast (nil = always).
    let level: Int?

    public init(level: Int? = nil) { self.level = level }

    private var isTopMost: Bool {
        guard let level else { return true }
        return router.presentations.count == level
    }

    public func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = router.toast, isTopMost {
                ToastView(toast: toast) { router.toast = nil }
                    .id(toast.id)
                    .padding(.bottom, 112) // clears the floating tab bar (iOS 26) and the classic one
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(toast.undo == nil ? 2 : 4))
                        if router.toast?.id == toast.id { router.toast = nil }
                    }
            }
        }
        .animation(.spring(duration: 0.35), value: router.toast)
    }
}

struct ToastView: View {
    let toast: Toast
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage = toast.systemImage {
                Image(systemName: systemImage).foregroundStyle(.tint)
            }
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            if let undo = toast.undo {
                Button("Undo") {
                    undo()
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .glassOrMaterial(in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .onAppear { AccessibilityNotification.Announcement(toast.message).post() }
    }
}

public extension View {
    func toastHost(level: Int? = nil) -> some View { modifier(ToastHostModifier(level: level)) }
}
