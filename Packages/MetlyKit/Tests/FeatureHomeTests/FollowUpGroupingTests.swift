import Foundation
import Testing
@testable import FeatureHome

struct FollowUpGroupingTests {
    @Test(arguments: [
        (date(2026, 9, 25, 18, 0), FollowUpBucket.overdue),
        (date(2026, 9, 20), .overdue),
        (date(2026, 9, 26, 9, 0), .today),     // earlier today is still "Today", not overdue
        (date(2026, 9, 26, 23, 59), .today),
        (date(2026, 9, 27, 0, 0), .thisWeek),
        (date(2026, 10, 2), .thisWeek),         // +6 days
        (date(2026, 10, 3, 0, 1), .later),      // +7 days
        (date(2026, 12, 31), .later),
    ])
    func bucketsByCalendarDay(dueAt: Date, expected: FollowUpBucket) {
        #expect(FollowUpBucket.bucket(dueAt: dueAt, isDone: false, now: testNow, calendar: testCalendar) == expected)
    }

    @Test func doneWinsOverDueDate() {
        let overdue = date(2026, 9, 1)
        #expect(FollowUpBucket.bucket(dueAt: overdue, isDone: true, now: testNow, calendar: testCalendar) == .done)
    }

    @Test func groupsInDisplayOrderSkippingEmptyBuckets() {
        let items = [
            TestReminder(name: "later", dueAt: date(2026, 10, 10)),
            TestReminder(name: "today", dueAt: date(2026, 9, 26, 16, 0)),
            TestReminder(name: "overdue", dueAt: date(2026, 9, 24)),
        ]
        let groups = FollowUpGrouping.groups(items, now: testNow, calendar: testCalendar)
        #expect(groups.map(\.bucket) == [.overdue, .today, .later])
    }

    @Test func openBucketsSortEarliestFirst() {
        let items = [
            TestReminder(name: "c", dueAt: date(2026, 9, 30)),
            TestReminder(name: "a", dueAt: date(2026, 9, 27, 9, 0)),
            TestReminder(name: "b", dueAt: date(2026, 9, 27, 15, 0)),
        ]
        let groups = FollowUpGrouping.groups(items, now: testNow, calendar: testCalendar)
        #expect(groups.count == 1)
        #expect(groups[0].bucket == .thisWeek)
        #expect(groups[0].items.map(\.name) == ["a", "b", "c"])
    }

    @Test func doneSortsMostRecentlyCompletedFirst() {
        let items = [
            TestReminder(name: "old", dueAt: date(2026, 9, 1), isDone: true, completedAt: date(2026, 9, 2)),
            TestReminder(name: "new", dueAt: date(2026, 9, 3), isDone: true, completedAt: date(2026, 9, 25)),
            TestReminder(name: "noDate", dueAt: date(2026, 9, 10), isDone: true),
        ]
        let groups = FollowUpGrouping.groups(items, now: testNow, calendar: testCalendar)
        #expect(groups.map(\.bucket) == [.done])
        #expect(groups[0].items.map(\.name) == ["new", "noDate", "old"])
    }

    @Test func emptyInputHasNoGroups() {
        #expect(FollowUpGrouping.groups([TestReminder](), now: testNow, calendar: testCalendar).isEmpty)
    }

    /// Oct 25, 2026 in Berlin lasts 25 hours: 00:30 → 23:59 is more than 24 h but still the same day.
    @Test func dayOffsetIsCalendarAwareAcrossDST() {
        let now = date(2026, 10, 25, 0, 30, calendar: berlinCalendar)
        let lateSameDay = date(2026, 10, 25, 23, 59, calendar: berlinCalendar)
        #expect(lateSameDay.timeIntervalSince(now) > 86_400)
        #expect(FollowUpDates.dayOffset(from: now, to: lateSameDay, calendar: berlinCalendar) == 0)
        #expect(FollowUpBucket.bucket(dueAt: lateSameDay, isDone: false, now: now, calendar: berlinCalendar) == .today)
    }

    @Test func emphasisFollowsBuckets() {
        #expect(DueEmphasis.of(dueAt: date(2026, 9, 25), isDone: false, now: testNow, calendar: testCalendar) == .overdue)
        #expect(DueEmphasis.of(dueAt: date(2026, 9, 26), isDone: false, now: testNow, calendar: testCalendar) == .today)
        #expect(DueEmphasis.of(dueAt: date(2026, 9, 29), isDone: false, now: testNow, calendar: testCalendar) == .upcoming)
        #expect(DueEmphasis.of(dueAt: date(2026, 9, 25), isDone: true, now: testNow, calendar: testCalendar) == .done)
    }
}

struct DueLabelTests {
    @Test(arguments: [
        (date(2026, 9, 26, 8, 0), "Today"),
        (date(2026, 9, 27, 23, 0), "Tomorrow"),
        (date(2026, 9, 25, 1, 0), "Yesterday"),
        (date(2026, 9, 29), "Tue, Sep 29"),
        (date(2026, 9, 20), "Sun, Sep 20"),
        (date(2026, 10, 3), "Sat, Oct 3"),
    ])
    func dueLabel(due: Date, expected: String) {
        #expect(FollowUpDates.dueLabel(due, now: testNow, calendar: testCalendar, locale: usLocale) == expected)
    }

    @Test func combineKeepsDayAndTakesClockFromTime() {
        let day = date(2026, 10, 12, 23, 59)
        let time = date(2026, 1, 1, 16, 45)
        let parts = components(FollowUpDates.combine(day: day, time: time, calendar: testCalendar))
        #expect(parts.year == 2026)
        #expect(parts.month == 10)
        #expect(parts.day == 12)
        #expect(parts.hour == 16)
        #expect(parts.minute == 45)
    }
}
