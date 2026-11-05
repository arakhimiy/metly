import Foundation
import MetlyCore
import MetlyData
import SwiftData
import UIKit
import UserNotifications

/// Local PUSH_FOLLOWUP notifications (SPEC §3.16, §7.3).
///
/// • One `UNNotificationRequest` per open reminder at its due date ("{Name}" / "{what} · via {channel}"),
///   with "Open {channel}" (foreground) and "Snooze 1 Day" (background) actions.
/// • Reschedules whenever any `ModelContext` saves (Home, Follow-ups, People, capture flows, sync),
///   when the app becomes active and when the time zone / clock changes (fingerprints include the
///   zone, so wall-clock triggers are rebuilt). Done, deleted and past reminders are removed — as are
///   reminders marked done on the widget whose queued completion isn't applied yet
///   (`pendingCompletionIDs`); nothing is scheduled when follow-up reminders are off in
///   Notification settings or delivered by the Telegram bot.
/// • Taps open FOLLOWUPS on the Home tab.
///
/// The app target calls `configure(router:container:services:)` once, before launch finishes
/// (the notification center delegate must be set early to receive cold-launch taps).
@MainActor
public final class FollowUpNotificationScheduler {
    public private(set) static var shared: FollowUpNotificationScheduler?

    private let router: AppRouter
    private let container: ModelContainer
    private let services: AppServices
    private let center: UNUserNotificationCenter
    private var delegate: FollowUpNotificationDelegate?
    private var observers: [any NSObjectProtocol] = []
    private var debounceTask: Task<Void, Never>?
    private lazy var passes = SerialPassRunner { [weak self] in await self?.performReschedule() }

    /// Follow-ups already marked done outside the store — widget "Done" taps waiting in the App Group
    /// queue until the app applies them. They get no notification although the store still has them open.
    /// The app target wires this to `WidgetSnapshotStore.pendingFollowUpCompletionIDs()`.
    public static var pendingCompletionIDs: @MainActor () -> Set<UUID> = { [] }
    /// "Accept" / "Decline" on a connect request push. The app target wires this to FeatureConnect.
    public static var answerConnectRequest: @MainActor (_ requestID: UUID, _ accept: Bool) async -> Void = { _, _ in }
    /// A push arrived while the app is open. The app target wires this to `MetlyClient.catchUpNow()`.
    public static var onRemoteNotification: @MainActor () -> Void = {}

    private init(router: AppRouter, container: ModelContainer, services: AppServices, center: UNUserNotificationCenter) {
        self.center = center
        self.router = router
        self.container = container
        self.services = services
    }

    // MARK: Setup

    /// Installs the notification delegate + categories and starts observing data changes. Idempotent.
    /// Returns nil (and does nothing) outside an app bundle, e.g. in unit tests.
    @discardableResult
    public static func configure(router: AppRouter, container: ModelContainer, services: AppServices) -> FollowUpNotificationScheduler? {
        if let shared { return shared }
        guard let center = notificationCenter else { return nil }
        let scheduler = FollowUpNotificationScheduler(router: router, container: container, services: services, center: center)
        shared = scheduler
        scheduler.start()
        return scheduler
    }

    private func start() {
        let delegate = FollowUpNotificationDelegate { [weak self] action in
            await self?.handle(action)
        } onRemoteNotification: {
            Self.onRemoteNotification()
        }
        self.delegate = delegate
        center.delegate = delegate
        center.setNotificationCategories(FollowUpNotificationCategory.makeCategories()
            .union([ConnectRequestNotificationCategory.makeCategory()]))

        for name in [ModelContext.didSave, UIApplication.didBecomeActiveNotification,
                     UIApplication.significantTimeChangeNotification, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setNeedsReschedule() }
            })
        }
        setNeedsReschedule()
    }

    // MARK: Scheduling

    /// Coalesced reschedule (call after changing reminders outside a `ModelContext.save()`).
    public static func setNeedsReschedule() {
        shared?.setNeedsReschedule()
    }

    public func setNeedsReschedule() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    /// Brings pending notifications in line with the store now. Calls made while a pass is
    /// running are folded into one more pass, so passes never interleave.
    public func reschedule() async {
        await passes.run()
    }

    private func performReschedule() async {
        let context = container.mainContext
        let calendar = Calendar.current
        let enabled = FollowUpNotificationPlanner.isEnabled(prefs: context.currentProfile()?.notificationPrefs)
        let open = (try? context.fetch(FollowUp.open)) ?? []
        let doneElsewhere = Self.pendingCompletionIDs()
        let candidates = open.compactMap { Self.candidate($0, doneElsewhere: doneElsewhere) }
        let desired = FollowUpNotificationPlanner.payloads(for: candidates, now: .now, enabled: enabled,
                                                           timeZone: calendar.timeZone)

        let pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(FollowUpNotificationPayload.identifierPrefix) }
        let stale = FollowUpNotificationPlanner.staleIdentifiers(pending: pending.map(\.identifier), desired: desired)
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }

        // Already-delivered reminders that are now done or deleted leave Notification Center too.
        let openIDs = Set(candidates.filter(\.isOpen).map { FollowUpNotificationPayload.identifier(for: $0.id) })
        let delivered = await center.deliveredNotifications()
            .map(\.request.identifier)
            .filter { $0.hasPrefix(FollowUpNotificationPayload.identifierPrefix) && !openIDs.contains($0) }
        if !delivered.isEmpty { center.removeDeliveredNotifications(withIdentifiers: delivered) }

        guard await Self.isAuthorized() else { return }
        var fingerprints: [String: String] = [:]
        for request in pending {
            fingerprints[request.identifier] = request.content.userInfo[FollowUpNotificationPayload.UserInfoKey.fingerprint] as? String
        }
        for payload in FollowUpNotificationPlanner.payloadsToAdd(desired: desired, pendingFingerprints: fingerprints) {
            try? await center.add(payload.makeRequest(calendar: calendar))
        }
    }

    /// - Parameter doneElsewhere: `pendingCompletionIDs()` — reminders done on the widget, not saved yet.
    static func candidate(_ followUp: FollowUp, doneElsewhere: Set<UUID> = []) -> FollowUpNotificationPlanner.Candidate? {
        let person = followUp.connection
        guard person?.isDeleted != true, person?.isBlocked != true else { return nil }
        return FollowUpNotificationPlanner.Candidate(
            id: followUp.id,
            personName: PersonText.displayName(person),
            what: followUp.title,
            channel: followUp.channel,
            hasChannelValue: ChannelLink.canOpen(followUp.channel, for: person),
            dueAt: followUp.dueAt,
            isOpen: !followUp.isDone && !followUp.isDeleted && !doneElsewhere.contains(followUp.id)
        )
    }

    // MARK: Authorization

    /// `UNUserNotificationCenter.current()` traps outside an app bundle (unit-test runner), so every
    /// static entry point goes through this.
    static var notificationCenter: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" ? UNUserNotificationCenter.current() : nil
    }

    static func isAuthorized() async -> Bool {
        guard let center = notificationCenter else { return false }
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied, .notDetermined: return false
        @unknown default: return false
        }
    }

    static func isDenied() async -> Bool {
        guard let center = notificationCenter else { return false }
        return await center.notificationSettings().authorizationStatus == .denied
    }

    /// Asks for notification permission in context — right after the user sets a reminder —
    /// when it was never asked (e.g. Permissions was skipped during setup).
    public static func requestAuthorizationIfNeeded() async {
        guard let center = notificationCenter,
              await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        shared?.setNeedsReschedule()
    }

    // MARK: Responses

    /// Performs a parsed notification response. Public so an app-level delegate can forward to it.
    public func handle(_ action: FollowUpNotificationAction) async {
        switch action {
        case .ignore:
            break
        case .snooze(let id):
            await snooze(id)
        case .openFollowUps:
            await openFollowUps()
        case .openChannel(let id):
            await openFollowUps()
            await openChannel(for: id)
        case .answerConnectRequest(let requestID, let accept):
            // Accept lands on CONNECTED, so wait for the UI; Decline runs in the background.
            if accept { guard await waitUntilMainPhase() else { return } }
            await Self.answerConnectRequest(requestID, accept)
        case .openLink(let url):
            guard await waitUntilMainPhase() else { return }
            await UIApplication.shared.open(url)
        }
    }

    /// "Snooze 1 Day": +1 day from max(due, today), keeping the time of day.
    private func snooze(_ id: UUID) async {
        let context = container.mainContext
        guard let followUp = context.record(FollowUp.self, id: id), !followUp.isDone, !followUp.isDeleted else { return }
        let newDate = SnoozeOption.snoozedDate(followUp.dueAt, byDays: 1, now: .now, calendar: .current)
        FollowUpMutations.reschedule(followUp, to: newDate, in: context)
        services.sync.requestSync()
        await reschedule()
    }

    private func openFollowUps() async {
        guard await waitUntilMainPhase() else { return }
        router.select(.home)
        if router.paths[.home]?.last != .followUps {
            router.push(.followUps)
        }
    }

    private func openChannel(for id: UUID) async {
        guard let followUp = container.mainContext.record(FollowUp.self, id: id),
              let target = ChannelLink.target(followUp.channel, for: followUp.connection) else { return }
        await waitUntilActive()
        if await UIApplication.shared.open(target.primary) == false, let fallback = target.fallback {
            await UIApplication.shared.open(fallback)
        }
    }

    /// Cold launch: wait for RootView's bootstrap to reach the main phase (max ~10 s).
    private func waitUntilMainPhase() async -> Bool {
        for _ in 0..<100 where router.phase != .main {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return router.phase == .main
    }

    private func waitUntilActive() async {
        for _ in 0..<50 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
