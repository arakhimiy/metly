import Foundation
import Testing
@testable import FeatureHome

struct SnoozeTests {
    @Test func overdueSnoozesFromTodayKeepingTimeOfDay() {
        let overdue = date(2026, 9, 23, 9, 15)
        let snoozed = SnoozeOption.snoozedDate(overdue, byDays: 1, now: testNow, calendar: testCalendar)
        let parts = components(snoozed)
        #expect(parts.month == 9)
        #expect(parts.day == 27)
        #expect(parts.hour == 9)
        #expect(parts.minute == 15)
    }

    @Test func dueTodaySnoozesToTomorrow() {
        let today = date(2026, 9, 26, 10, 0)
        #expect(components(SnoozeOption.tomorrow.snoozedDate(from: today, now: testNow, calendar: testCalendar)!).day == 27)
    }

    @Test func futureDueSnoozesFromItsOwnDay() {
        let future = date(2026, 9, 30, 18, 0)
        let snoozed = SnoozeOption.snoozedDate(future, byDays: 1, now: testNow, calendar: testCalendar)
        let parts = components(snoozed)
        #expect(parts.month == 10)
        #expect(parts.day == 1)
        #expect(parts.hour == 18)
    }

    @Test(arguments: [
        (SnoozeOption.tomorrow, 9, 27),
        (.inThreeDays, 9, 29),
        (.nextWeek, 10, 3),
    ])
    func menuOptionsAddDaysToToday(option: SnoozeOption, month: Int, day: Int) {
        let due = date(2026, 9, 25, 10, 0)
        let parts = components(option.snoozedDate(from: due, now: testNow, calendar: testCalendar)!)
        #expect(parts.month == month)
        #expect(parts.day == day)
        #expect(parts.hour == 10)
    }

    @Test func customHasNoDate() {
        #expect(SnoozeOption.custom.days == nil)
        #expect(SnoozeOption.custom.snoozedDate(from: testNow, now: testNow, calendar: testCalendar) == nil)
    }

    /// Berlin falls back on Oct 25, 2026; +1 day must still land at 10:00 local, not 09:00.
    @Test func snoozeKeepsWallClockAcrossDST() {
        let now = date(2026, 10, 24, 8, 0, calendar: berlinCalendar)
        let due = date(2026, 10, 24, 10, 0, calendar: berlinCalendar)
        let snoozed = SnoozeOption.snoozedDate(due, byDays: 1, now: now, calendar: berlinCalendar)
        let parts = components(snoozed, calendar: berlinCalendar)
        #expect(parts.day == 25)
        #expect(parts.hour == 10)
        #expect(snoozed.timeIntervalSince(due) == 25 * 3_600)
    }

    @Test func menuTitlesDependOnBase() {
        #expect(SnoozeOption.isRelativeToToday(dueAt: date(2026, 9, 20), now: testNow, calendar: testCalendar))
        #expect(SnoozeOption.isRelativeToToday(dueAt: date(2026, 9, 26, 22, 0), now: testNow, calendar: testCalendar))
        #expect(!SnoozeOption.isRelativeToToday(dueAt: date(2026, 9, 28), now: testNow, calendar: testCalendar))
        #expect(SnoozeOption.tomorrow.title(relativeToToday: true) == "Tomorrow")
        #expect(SnoozeOption.inThreeDays.title(relativeToToday: true) == "In 3 Days")
        #expect(SnoozeOption.nextWeek.title(relativeToToday: true) == "Next Week")
        #expect(SnoozeOption.tomorrow.title(relativeToToday: false) == "1 Day Later")
        #expect(SnoozeOption.custom.title(relativeToToday: false) == "Custom…")
    }
}
