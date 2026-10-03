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
///   when the app becomes active and when the time zone / clock changes. Done, deleted and
///   past reminders are removed; nothing is scheduled when follow-up reminders are off in
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
    private var isRescheduling = false
    private var needsAnotherPass = false

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
        }
        self.delegate = delegate
        center.delegate = delegate
        center.setNotificationCategories(FollowUpNotificationCategory.makeCategories())

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
        needsAnotherPass = true
        guard !isRescheduling else { return }
        isRescheduling = true
        defer { isRescheduling = false }
        while needsAnotherPass {
            needsAnotherPass = false
            await performReschedule()
        }
    }

    private func performReschedule() async {
        let context = container.mainContext
        let enabled = FollowUpNotificationPlanner.isEnabled(prefs: context.currentProfile()?.notificationPrefs)
        let open = (try? context.fetch(FollowUp.open)) ?? []
        let candidates = open.compactMap(Self.candidate)
        let desired = FollowUpNotificationPlanner.payloads(for: candidates, now: .now, enabled: enabled)

        let pending = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(FollowUpNotificationPayload.identifierPrefix) }
        let stale = FollowUpNotificationPlanner.staleIdentifiers(pending: pending.map(\.identifier), desired: desired)
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }

        // Already-delivered reminders that are now done or deleted leave Notification Center too.
        let openIDs = Set(candidates.map { FollowUpNotificationPayload.identifier(for: $0.id) })
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
            try? await center.add(payload.makeRequest(calendar: .current))
        }
    }

    private static func candidate(_ followUp: FollowUp) -> FollowUpNotificationPlanner.Candidate? {
        let person = followUp.connection
        guard person?.isDeleted != true, person?.isBlocked != true else { return nil }
        return FollowUpNotificationPlanner.Candidate(
            id: followUp.id,
            personName: PersonText.displayName(person),
            what: followUp.title,
            channel: followUp.channel,
            hasChannelValue: ChannelLink.canOpen(followUp.channel, for: person),
            dueAt: followUp.dueAt,
            isOpen: !followUp.isDone && !followUp.isDeleted
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
        guard let followUp = container.mainContext.record(FollowUp.self, id: id) else { return }
        let value = ChannelLink.value(for: followUp.channel, of: followUp.connection)
        guard let url = ChannelLink.primaryURL(followUp.channel, value: value) else { return }
        await waitUntilActive()
        if await UIApplication.shared.open(url) == false, let fallback = ChannelLink.fallbackURL(followUp.channel, value: value) {
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
