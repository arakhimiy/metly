import Foundation
import Testing
@testable import FeatureHome

struct HomeSelectionTests {
    private let reminders = [
        TestReminder(name: "later", dueAt: date(2026, 10, 9)),
        TestReminder(name: "today-late", dueAt: date(2026, 9, 26, 18, 0)),
        TestReminder(name: "overdue-old", dueAt: date(2026, 9, 20)),
        TestReminder(name: "tomorrow", dueAt: date(2026, 9, 27)),
        TestReminder(name: "today-early", dueAt: date(2026, 9, 26, 9, 0)),
        TestReminder(name: "overdue", dueAt: date(2026, 9, 25)),
        TestReminder(name: "done", dueAt: date(2026, 9, 24), isDone: true),
    ]

    @Test func dueTodayIsOverduePlusTodaySortedByDue() {
        let due = HomeSelection.dueToday(reminders, now: testNow, calendar: testCalendar)
        #expect(due.map(\.name) == ["overdue-old", "overdue", "today-early", "today-late"])
    }

    @Test func homeShowsTopThree() {
        let due = HomeSelection.dueToday(reminders, now: testNow, calendar: testCalendar)
        #expect(due.prefix(HomeSelection.followUpLimit).map(\.name) == ["overdue-old", "overdue", "today-early"])
    }

    @Test func upcomingCountsOpenRemindersAfterToday() {
        #expect(HomeSelection.upcomingCount(reminders, now: testNow, calendar: testCalendar) == 2)
    }

    @Test func todayStateCopy() {
        #expect(FollowUpTodayState.make(dueCount: 4, upcoming: 2) == .due(count: 3, overflow: 1))
        #expect(FollowUpTodayState.make(dueCount: 2, upcoming: 0) == .due(count: 2, overflow: 0))
        #expect(FollowUpTodayState.make(dueCount: 0, upcoming: 3) == .nothingDue(upcoming: 3))
        #expect(FollowUpTodayState.make(dueCount: 0, upcoming: 0) == .noFollowUps)
    }

    @Test func recentIsMostRecentlyMetFirst() {
        let people = [
            TestPerson(name: "Madina", metAt: date(2026, 9, 21), createdAt: date(2026, 9, 21)),
            TestPerson(name: "Kamila", metAt: date(2026, 9, 26, 14, 0), createdAt: date(2026, 9, 26, 14, 0)),
            // Met again today, although the record is old.
            TestPerson(name: "Timur", metAt: date(2026, 9, 26, 12, 0), createdAt: date(2026, 9, 1)),
            TestPerson(name: "Jasur", metAt: date(2026, 9, 24), createdAt: date(2026, 9, 24)),
        ]
        #expect(HomeSelection.recent(people).map(\.name) == ["Kamila", "Timur", "Jasur"])
        #expect(HomeSelection.recent(people, limit: 5).map(\.name) == ["Kamila", "Timur", "Jasur", "Madina"])
    }

    @Test func recentBreaksTiesByNewestRecord() {
        let sameMeeting = date(2026, 9, 26, 11, 0)
        let people = [
            TestPerson(name: "first", metAt: sameMeeting, createdAt: date(2026, 9, 26, 11, 1)),
            TestPerson(name: "second", metAt: sameMeeting, createdAt: date(2026, 9, 26, 11, 2)),
        ]
        #expect(HomeSelection.recent(people).map(\.name) == ["second", "first"])
    }

    static let relativeCases: [(TimeInterval, String)] = [
        (0, "now"),
        (45, "now"),
        (300, "5m"),
        (10_800, "3h"),
        (172_800, "2d"),
        (2_505_600, "29d"),
        (3_456_000, "1mo"),
        (34_560_000, "1y"),
    ]

    @Test(arguments: relativeCases)
    func compactRelativeTime(secondsAgo: TimeInterval, expected: String) {
        let then = testNow.addingTimeInterval(-secondsAgo)
        #expect(CompactRelativeTime.string(from: then, now: testNow) == expected)
    }

    @Test func futureDatesReadAsNow() {
        #expect(CompactRelativeTime.string(from: testNow.addingTimeInterval(600), now: testNow) == "now")
    }
}
