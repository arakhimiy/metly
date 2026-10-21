import MetlyCore
import MetlyData
import SwiftData
import SwiftUI
import UIKit

public extension View {
    /// App-level: when someone sends a connect request while CONNECT is closed (scanned your QR, found you
    /// by email, a Nearby request that arrived as you closed Connect), shows a non-blocking banner at the top
    /// with **Accept** (→ CONNECTED), **View** (→ People › Requests) and **Later**.
    ///
    /// Attach once to the signed-in root (inside `.environment(router)`, `.environment(client)` and
    /// `.modelContainer(_:)`), e.g. `MainTabView`'s `TabView`. The banner floats above sheets and covers
    /// in its own pass-through window; touches outside it reach the app as usual.
    func incomingConnectRequestBanner() -> some View {
        modifier(IncomingConnectRequestBannerModifier())
    }
}

private struct IncomingConnectRequestBannerModifier: ViewModifier {
    @Environment(MetlyClient.self) private var client
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @State private var model = IncomingRequestBannerModel()
    @State private var overlay = BannerOverlayWindow()

    func body(content: Content) -> some View {
        content
            .background {
                WindowSceneReader { scene, appWindow in
                    overlay.install(in: scene, above: appWindow) {
                        BannerOverlayContent(model: model, overlay: overlay)
                            .modelContext(modelContext)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onAppear {
                // Lives with this view's state (sign-out drops it), not with `.task`/`onDisappear`, which
                // also fire whenever a full-screen cover hides the root.
                model.attach(client: client, modelContext: modelContext, router: router)
                model.onVisibilityChange = { [overlay] visible in overlay.setVisible(visible) }
                model.start()
            }
            .onChange(of: colorScheme, initial: true) { overlay.setColorScheme(colorScheme) }
    }
}

/// The hosted SwiftUI content of the overlay window: the banner pinned to the top safe area.
private struct BannerOverlayContent: View {
    let model: IncomingRequestBannerModel
    let overlay: BannerOverlayWindow

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    var body: some View {
        VStack(spacing: 0) {
            if let item = model.current {
                IncomingRequestBanner(item: item, sharedCardName: sharedCardName(for: item),
                                      isAccepting: model.isAccepting,
                                      onAccept: { Task { await model.accept() } },
                                      onView: model.view, onLater: model.later)
                    .padding(.top, 4)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        overlay.setInteractiveFrame(frame)
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task(id: item.id) { await autoDismiss(item) }
                    .onAppear {
                        AccessibilityNotification.Announcement("\(item.firstName) wants to connect").post()
                    }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .default : .spring(duration: 0.4), value: model.current?.id)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.appearanceCount)
        .onChange(of: model.current == nil) { _, isEmpty in
            if isEmpty { overlay.setInteractiveFrame(.null) }
        }
    }

    private func sharedCardName(for item: IncomingRequestBannerItem) -> String? {
        let request = modelContext.record(ConnectRequest.self, id: item.id)
        if let id = request?.myCardID, let card = modelContext.record(Card.self, id: id), !card.isDeleted {
            return card.name
        }
        return modelContext.cardToShare()?.name
    }

    /// Like a notification banner it goes away by itself (not while VoiceOver users are reading it).
    private func autoDismiss(_ item: IncomingRequestBannerItem) async {
        guard !voiceOverEnabled else { return }
        let expiresAt = modelContext.record(ConnectRequest.self, id: item.id)?.expiresAt
        do {
            try await Task.sleep(for: IncomingRequestBannerPolicy.displayDuration(expiresAt: expiresAt, now: .now))
        } catch {
            return
        }
        if model.current?.id == item.id, !model.isAccepting { model.later() }
    }
}

// MARK: - Overlay window

/// A window above the app's own (so the banner shows over sheets and covers) that only takes touches
/// inside the banner; everything else passes through to the app. Hidden while there's no banner.
@MainActor
final class BannerOverlayWindow {
    private var window: PassthroughWindow?
    private var hideTask: Task<Void, Never>?
    private var isVisible = false
    private var colorScheme: ColorScheme?

    func install(in scene: UIWindowScene, above appWindow: UIWindow, @ViewBuilder content: () -> some View) {
        if let window, window.windowScene === scene { return }
        remove()
        let controller = BannerHostingController(rootView: AnyView(content()))
        controller.appWindow = appWindow
        controller.view.backgroundColor = .clear
        let window = PassthroughWindow(windowScene: scene)
        window.windowLevel = appWindow.windowLevel + 1
        window.backgroundColor = .clear
        window.rootViewController = controller
        window.isHidden = !isVisible
        self.window = window
        if let colorScheme { setColorScheme(colorScheme) }
    }

    func setVisible(_ visible: Bool) {
        isVisible = visible
        hideTask?.cancel()
        guard let window else { return }
        if visible {
            window.isHidden = false
        } else {
            window.interactiveFrame = .null
            // Let the banner's removal animation finish before hiding the window.
            hideTask = Task { [weak window] in
                do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
                window?.isHidden = true
            }
        }
    }

    func setInteractiveFrame(_ frame: CGRect) {
        window?.interactiveFrame = frame
    }

    func setColorScheme(_ scheme: ColorScheme) {
        colorScheme = scheme
        window?.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
    }

    func remove() {
        hideTask?.cancel()
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
    }
}

/// Only the banner's frame is touchable; touches anywhere else go to the windows below.
final class PassthroughWindow: UIWindow {
    var interactiveFrame: CGRect = .null

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard interactiveFrame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
}

/// Leaves the status bar to whatever the app is showing underneath.
private final class BannerHostingController: UIHostingController<AnyView> {
    weak var appWindow: UIWindow?

    private var appTopController: UIViewController? {
        var top = appWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    override var prefersStatusBarHidden: Bool { appTopController?.prefersStatusBarHidden ?? false }
    override var preferredStatusBarStyle: UIStatusBarStyle { appTopController?.preferredStatusBarStyle ?? .default }
}

/// Reports the window scene (and app window) the modified view lives in.
private struct WindowSceneReader: UIViewRepresentable {
    let onWindow: (UIWindowScene, UIWindow) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onWindow = onWindow
    }

    final class ReaderView: UIView {
        var onWindow: ((UIWindowScene, UIWindow) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, let scene = window.windowScene else { return }
            onWindow?(scene, window)
        }
    }
}
