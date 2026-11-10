import Foundation
import Observation

/// Single source of navigation state. Injected with `.environment(router)`;
/// read with `@Environment(AppRouter.self) private var router`.
@MainActor
@Observable
public final class AppRouter {
    public var phase: RootPhase
    public var selectedTab: AppTab = .home
    public var paths: [AppTab: [PushDestination]] = [:]
    /// Stack of modal presentations; index 0 is presented from the tab root, each next one from the previous.
    public var presentations: [Presentation] = []
    public var toast: Toast?

    public init(phase: RootPhase = .launching) {
        self.phase = phase
    }

    // MARK: Push

    public func push(_ destination: PushDestination) {
        paths[selectedTab, default: []].append(destination)
    }

    /// Dismisses every modal, switches tab and pushes (e.g. after "Save" on a cover).
    public func open(_ destination: PushDestination, in tab: AppTab) {
        presentations.removeAll()
        selectedTab = tab
        paths[tab, default: []].append(destination)
    }

    public func pop() {
        _ = paths[selectedTab]?.popLast()
    }

    public func popToRoot(_ tab: AppTab? = nil) {
        paths[tab ?? selectedTab] = []
    }

    public func select(_ tab: AppTab) {
        presentations.removeAll()
        selectedTab = tab
    }

    // MARK: Modals

    public func present(_ sheet: SheetDestination) { presentations.append(.sheet(sheet)) }
    public func present(_ cover: CoverDestination) { presentations.append(.cover(cover)) }

    /// Replaces the top-most presentation (e.g. CONNECT → CONNECTED).
    public func replaceTop(with presentation: Presentation) {
        if !presentations.isEmpty { presentations.removeLast() }
        presentations.append(presentation)
    }

    public func dismiss() {
        _ = presentations.popLast()
    }

    public func dismissAll() {
        presentations.removeAll()
    }

    // MARK: Feedback

    public func showToast(_ message: String, systemImage: String? = nil, undo: (@MainActor () -> Void)? = nil) {
        toast = Toast(message: message, systemImage: systemImage, undo: undo)
    }

    /// A toast with its own button ("Add", "Open"…) — a light nudge instead of a sheet that pops up.
    public func showToast(_ message: String, systemImage: String? = nil, action title: String,
                          perform action: @escaping @MainActor () -> Void) {
        toast = Toast(message: message, systemImage: systemImage, action: ToastAction(title: title, perform: action))
    }

    // MARK: Phase helpers

    public func enterMain(presenting cover: CoverDestination? = nil) {
        paths = [:]
        presentations = []
        selectedTab = .home
        phase = .main
        if let cover { presentations = [.cover(cover)] }
    }

    public func signedOut() {
        paths = [:]
        presentations = []
        selectedTab = .home
        phase = .onboarding
    }
}

public struct Toast: Identifiable, Equatable {
    public let id = UUID()
    public var message: String
    public var systemImage: String?
    /// When set the HUD shows an "Undo" button and stays 4 s instead of 2 s.
    public var undo: (@MainActor () -> Void)?
    /// Any other button (stays 4 s too).
    public var action: ToastAction?

    public init(message: String, systemImage: String? = nil, undo: (@MainActor () -> Void)? = nil, action: ToastAction? = nil) {
        self.message = message
        self.systemImage = systemImage
        self.undo = undo
        self.action = action
    }

    /// Has a button, so it stays longer.
    public var isActionable: Bool { undo != nil || action != nil }

    public static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

public struct ToastAction {
    public var title: String
    public var perform: @MainActor () -> Void
}
