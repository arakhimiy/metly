import Foundation
import MetlyCore
import Testing
import UserNotifications
@testable import FeatureHome

struct NotificationPayloadTests {
    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func payload(channel: FollowUpChannel = .telegram, hasValue: Bool = true,
                         name: String = "Kamila Yusupova", what: String = "Send the pitch deck",
                         due: Date = date(2026, 9, 27)) -> FollowUpNotificationPayload {
        FollowUpNotificationPayload(followUpID: id, personName: name, what: what, channel: channel,
                                    hasChannelValue: hasValue, dueAt: due)
    }

    /// The widget's "Done" intent removes this request by identifier (MetlyWidgetKit's
    /// `WidgetFollowUpNotification.identifier(for:)`, pinned to the same literal there) — keep them identical.
    @Test func identifierRoundTrips() {
        let payload = payload()
        #expect(payload.identifier == "followup.11111111-2222-3333-4444-555555555555")
        #expect(FollowUpNotificationPayload.followUpID(fromIdentifier: payload.identifier) == id)
        #expect(FollowUpNotificationPayload.followUpID(fromIdentifier: "connect.\(id.uuidString)") == nil)
        #expect(FollowUpNotificationPayload.followUpID(fromIdentifier: "followup.not-a-uuid") == nil)
    }

    @Test func titleIsNameAndBodyIsWhatViaChannel() {
        let payload = payload(channel: .email, what: "  Intro to the design team ")
        #expect(payload.title == "Kamila Yusupova")
        #expect(payload.body == "Intro to the design team · via Email")
    }

    @Test func blankValuesFallBack() {
        let payload = payload(channel: .call, name: " ", what: "")
        #expect(payload.title == "Follow up")
        #expect(payload.body == "Follow up · via Call")
    }

    @Test(arguments: [
        (FollowUpChannel.telegram, true, "FOLLOW_UP_TELEGRAM"),
        (.email, true, "FOLLOW_UP_EMAIL"),
        (.call, true, "FOLLOW_UP_CALL"),
        (.telegram, false, "FOLLOW_UP"),
    ])
    func categoryDependsOnChannelValue(channel: FollowUpChannel, hasValue: Bool, expected: String) {
        #expect(payload(channel: channel, hasValue: hasValue).categoryIdentifier == expected)
    }

    @Test func userInfoCarriesIDAndReminderLink() {
        let info = payload().userInfo
        #expect(info["followUpID"] == id.uuidString)
        #expect(info["link"] == "tanishly://reminder/\(id.uuidString)")
        #expect(info["fingerprint"] != nil)
    }

    @Test func fingerprintChangesWithDueDateAndText() {
        let base = payload()
        #expect(base.fingerprint == payload().fingerprint)
        #expect(base.fingerprint != payload(due: date(2026, 9, 28)).fingerprint)
        #expect(base.fingerprint != payload(what: "Something else").fingerprint)
        #expect(base.fingerprint != payload(hasValue: false).fingerprint)
    }

    @Test func requestUsesCalendarTriggerAtDueTime() throws {
        let request = payload(due: date(2026, 9, 27, 10, 30)).makeRequest(calendar: testCalendar)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.day == 27)
        #expect(trigger.dateComponents.hour == 10)
        #expect(trigger.dateComponents.minute == 30)
        #expect(request.identifier == payload().identifier)
        #expect(request.content.title == "Kamila Yusupova")
        #expect(request.content.categoryIdentifier == "FOLLOW_UP_TELEGRAM")
        #expect(request.content.threadIdentifier == FollowUpNotificationPayload.threadIdentifier)
    }
}

struct NotificationCategoryTests {
    @Test func categoriesHaveOpenAndSnoozeActions() throws {
        let categories = FollowUpNotificationCategory.makeCategories()
        #expect(Set(categories.map(\.identifier)) == Set(FollowUpNotificationCategory.allIdentifiers))

        let telegram = try #require(categories.first { $0.identifier == "FOLLOW_UP_TELEGRAM" })
        #expect(telegram.actions.map(\.identifier) == ["FOLLOW_UP_OPEN_CHANNEL", "FOLLOW_UP_SNOOZE_1D"])
        #expect(telegram.actions[0].title == "Open Telegram")
        #expect(telegram.actions[0].options.contains(.foreground))
        #expect(!telegram.actions[1].options.contains(.foreground))
        #expect(telegram.actions[1].title == "Snooze 1 Day")

        let plain = try #require(categories.first { $0.identifier == "FOLLOW_UP" })
        #expect(plain.actions.map(\.identifier) == ["FOLLOW_UP_SNOOZE_1D"])
    }

    @Test func recognisesFollowUpCategories() {
        #expect(FollowUpNotificationCategory.isFollowUpCategory("FOLLOW_UP"))
        #expect(FollowUpNotificationCategory.isFollowUpCategory("FOLLOW_UP_CALL"))
        #expect(!FollowUpNotificationCategory.isFollowUpCategory("CONNECT_REQUEST"))
    }
}

struct NotificationActionTests {
    private let id = UUID()

    private func action(_ identifier: String, category: String = "FOLLOW_UP_TELEGRAM",
                        userInfo: [AnyHashable: Any]? = nil) -> FollowUpNotificationAction {
        FollowUpNotificationAction(actionIdentifier: identifier, categoryIdentifier: category,
                                   requestIdentifier: "followup.\(id.uuidString)",
                                   userInfo: userInfo ?? ["followUpID": id.uuidString])
    }

    @Test func tapOpensFollowUps() {
        #expect(action(UNNotificationDefaultActionIdentifier) == .openFollowUps(followUpID: id))
    }

    @Test func snoozeAndOpenChannelCarryTheReminder() {
        #expect(action("FOLLOW_UP_SNOOZE_1D") == .snooze(followUpID: id))
        #expect(action("FOLLOW_UP_OPEN_CHANNEL") == .openChannel(followUpID: id))
    }

    @Test func idFallsBackToRequestIdentifier() {
        #expect(action("FOLLOW_UP_SNOOZE_1D", userInfo: [:]) == .snooze(followUpID: id))
    }

    @Test func dismissIsIgnored() {
        #expect(action(UNNotificationDismissActionIdentifier) == .ignore)
    }

    @Test func otherNotificationsFollowTheirLink() {
        let other = FollowUpNotificationAction(actionIdentifier: UNNotificationDefaultActionIdentifier,
                                               categoryIdentifier: "CONNECT_REQUEST", requestIdentifier: "remote-1",
                                               userInfo: ["link": "tanishly://people"])
        #expect(other == .openLink(URL(string: "tanishly://people")!))
        let unknown = FollowUpNotificationAction(actionIdentifier: UNNotificationDefaultActionIdentifier,
                                                 categoryIdentifier: "", requestIdentifier: "remote-2", userInfo: [:])
        #expect(unknown == .ignore)
    }

    @Test func connectRequestActionsAnswerTheRequest() {
        let requestID = UUID()
        let info: [AnyHashable: Any] = ["requestId": requestID.uuidString, "link": "tanishly://people"]
        func answer(_ identifier: String, _ info: [AnyHashable: Any]) -> FollowUpNotificationAction {
            FollowUpNotificationAction(actionIdentifier: identifier, categoryIdentifier: "CONNECT_REQUEST",
                                       requestIdentifier: "remote-3", userInfo: info)
        }
        #expect(answer("CONNECT_REQUEST_ACCEPT", info) == .answerConnectRequest(requestID: requestID, accept: true))
        #expect(answer("CONNECT_REQUEST_DECLINE", info) == .answerConnectRequest(requestID: requestID, accept: false))
        #expect(answer(UNNotificationDefaultActionIdentifier, info) == .openLink(URL(string: "tanishly://people")!))
        // No request id: fall back to opening People.
        #expect(answer("CONNECT_REQUEST_ACCEPT", ["link": "tanishly://people"]) == .openLink(URL(string: "tanishly://people")!))
    }

    @Test func connectRequestCategoryHasAcceptAndDecline() {
        let category = ConnectRequestNotificationCategory.makeCategory()
        #expect(category.identifier == "CONNECT_REQUEST")
        #expect(category.actions.map(\.identifier) == ["CONNECT_REQUEST_ACCEPT", "CONNECT_REQUEST_DECLINE"])
        #expect(category.actions[0].options.contains(.foreground))
        #expect(!category.actions[1].options.contains(.foreground))
    }
}

struct NotificationPlannerTests {
    private func candidate(_ due: Date, open: Bool = true, name: String = "Kamila") -> FollowUpNotificationPlanner.Candidate {
        .init(id: UUID(), personName: name, what: "Follow up", channel: .telegram, hasChannelValue: true, dueAt: due, isOpen: open)
    }

    @Test func schedulesOnlyOpenFutureRemindersEarliestFirst() {
        let candidates = [
            candidate(date(2026, 9, 30), name: "c"),
            candidate(date(2026, 9, 25), name: "past"),
            candidate(date(2026, 9, 27), name: "a"),
            candidate(date(2026, 9, 28), open: false, name: "done"),
            candidate(date(2026, 9, 26, 16, 0), name: "today"),
        ]
        let payloads = FollowUpNotificationPlanner.payloads(for: candidates, now: testNow, enabled: true)
        #expect(payloads.map(\.title) == ["today", "a", "c"])
    }

    @Test func nothingWhenDisabled() {
        let payloads = FollowUpNotificationPlanner.payloads(for: [candidate(date(2026, 9, 30))], now: testNow, enabled: false)
        #expect(payloads.isEmpty)
    }

    @Test func capsPendingRequests() {
        let candidates = (1...80).map { candidate(testNow.addingTimeInterval(Double($0) * 3_600)) }
        let payloads = FollowUpNotificationPlanner.payloads(for: candidates, now: testNow, enabled: true)
        #expect(payloads.count == FollowUpNotificationPlanner.maxPending)
        #expect(payloads.first?.fireDate == candidates.first?.dueAt)
    }

    @Test func enabledWhenRemindersAreOn() {
        var prefs = NotificationPrefs()
        #expect(FollowUpNotificationPlanner.isEnabled(prefs: prefs))
        prefs.followUpReminders = false
        #expect(!FollowUpNotificationPlanner.isEnabled(prefs: prefs))
        // A profile stored while the Telegram bot existed still gets local reminders.
        prefs.followUpReminders = true
        prefs.delivery = .telegramBot
        #expect(FollowUpNotificationPlanner.isEnabled(prefs: prefs))
        #expect(!FollowUpNotificationPlanner.isEnabled(prefs: nil))
    }

    @Test func staleAndChangedRequests() {
        let keep = FollowUpNotificationPayload(followUpID: UUID(), personName: "A", what: "x", channel: .call,
                                               hasChannelValue: true, dueAt: date(2026, 9, 28))
        let moved = FollowUpNotificationPayload(followUpID: UUID(), personName: "B", what: "y", channel: .call,
                                                hasChannelValue: true, dueAt: date(2026, 9, 29))
        let goneID = FollowUpNotificationPayload.identifier(for: UUID())
        let pending = [keep.identifier, moved.identifier, goneID, "other-feature.123"]

        let stale = FollowUpNotificationPlanner.staleIdentifiers(pending: pending, desired: [keep, moved])
        #expect(stale == [goneID])

        let toAdd = FollowUpNotificationPlanner.payloadsToAdd(
            desired: [keep, moved],
            pendingFingerprints: [keep.identifier: keep.fingerprint, moved.identifier: "outdated"]
        )
        #expect(toAdd == [moved])
    }
}
