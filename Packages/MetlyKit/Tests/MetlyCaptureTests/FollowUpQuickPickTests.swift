import Foundation
import Testing
@testable import MetlyCapture

@MainActor
struct FollowUpQuickPickTests {
    private func components(_ date: Date) -> DateComponents {
        testCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test(arguments: [
        (FollowUpQuickPick.tomorrow, 27),
        (.inThreeDays, 29),
        (.nextWeek, 3),
    ])
    func quickPicksLandAtTenLocal(pick: FollowUpQuickPick, expectedDay: Int) {
        let time = FollowUpQuickPick.defaultTime(now: testNow, calendar: testCalendar)
        let due = pick.dueDate(customDate: testNow, time: time, now: testNow, calendar: testCalendar)
        let parts = components(due)
        #expect(parts.day == expectedDay)
        #expect(parts.hour == 10)
        #expect(parts.minute == 0)
    }

    @Test func nextWeekRollsIntoNextMonth() {
        let time = FollowUpQuickPick.defaultTime(now: testNow, calendar: testCalendar)
        let due = FollowUpQuickPick.nextWeek.dueDate(customDate: testNow, time: time, now: testNow, calendar: testCalendar)
        #expect(components(due).month == 10)
    }

    @Test func customDateIsNeverBeforeToday() {
        let lastWeek = testCalendar.date(byAdding: .day, value: -7, to: testNow)!
        let time = FollowUpQuickPick.defaultTime(now: testNow, calendar: testCalendar)
        let due = FollowUpQuickPick.custom.dueDate(customDate: lastWeek, time: time, now: testNow, calendar: testCalendar)
        let parts = components(due)
        #expect(parts.day == 26)
        #expect(parts.month == 9)
        #expect(parts.hour == 10)
    }

    @Test func customDateKeepsChosenDayAndTime() {
        let chosen = testCalendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        let time = testCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 16, minute: 45))!
        let due = FollowUpQuickPick.custom.dueDate(customDate: chosen, time: time, now: testNow, calendar: testCalendar)
        let parts = components(due)
        #expect(parts.month == 10)
        #expect(parts.day == 12)
        #expect(parts.hour == 16)
        #expect(parts.minute == 45)
    }

    @Test func defaultCustomDateIsFiveDaysOut() {
        let date = FollowUpQuickPick.defaultCustomDate(now: testNow, calendar: testCalendar)
        #expect(components(date).day == 1)
        #expect(components(date).month == 10)
    }

    @Test func draftUsesDefaults() {
        let draft = FollowUpDraft(pick: .tomorrow, channel: .email, now: testNow, calendar: testCalendar)
        #expect(components(draft.time).hour == 10)
        #expect(draft.trimmedTitle == nil)
        #expect(components(draft.dueDate(now: testNow, calendar: testCalendar)).day == 27)
    }

    @Test func matchingRecognizesQuickPickDays() {
        let inThree = testCalendar.date(byAdding: .day, value: 3, to: testNow)!
        let inFive = testCalendar.date(byAdding: .day, value: 5, to: testNow)!
        #expect(FollowUpQuickPick.matching(inThree, now: testNow, calendar: testCalendar) == .inThreeDays)
        #expect(FollowUpQuickPick.matching(inFive, now: testNow, calendar: testCalendar) == .custom)
    }

    @Test func footerSaysTomorrowOrWeekday() {
        let tomorrow = testCalendar.date(byAdding: .day, value: 1, to: testNow)!
        #expect(FollowUpSummary.dayPhrase(for: tomorrow, now: testNow, calendar: testCalendar) == "tomorrow")
        #expect(FollowUpSummary.dayPhrase(for: testNow, now: testNow, calendar: testCalendar) == "today")
        let later = testCalendar.date(byAdding: .day, value: 3, to: testNow)!
        #expect(FollowUpSummary.dayPhrase(for: later, now: testNow, calendar: testCalendar).hasPrefix("on "))
    }
}
