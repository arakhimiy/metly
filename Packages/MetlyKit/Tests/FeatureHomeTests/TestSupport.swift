import Foundation
import MetlyCore
import MetlyData
import SwiftData
@testable import FeatureHome

/// Fixed calendar so date math is deterministic (Tashkent, UTC+5, no DST).
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
    return calendar
}()

/// A calendar with a DST change: Europe/Berlin falls back on Sunday, Oct 25, 2026 (a 25-hour day).
let berlinCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

let usLocale = Locale(identifier: "en_US")

/// Saturday, Sep 26, 2026, 14:32 in Tashkent (the prototype's "today").
let testNow = date(2026, 9, 26, 14, 32)

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0,
          calendar: Calendar = testCalendar) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func components(_ date: Date, calendar: Calendar = testCalendar) -> DateComponents {
    calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
}

/// Plain value standing in for `FollowUp` in grouping / selection tests.
struct TestReminder: FollowUpItem, Equatable {
    var name: String
    var dueAt: Date
    var isDone = false
    var completedAt: Date?
}

/// Plain value standing in for `Connection` in Recent tests.
struct TestPerson: RecentPersonItem, Equatable {
    var name: String
    var metAt: Date
    var createdAt: Date
}

// MARK: SwiftData

@MainActor
func makeContext() throws -> ModelContext {
    let container = try MetlyModelContainer.make(inMemory: true)
    retainedContainers.append(container)
    return ModelContext(container)
}

/// Keeps in-memory containers alive for the duration of a test.
@MainActor private var retainedContainers: [ModelContainer] = []

@MainActor
@discardableResult
func insertPerson(_ name: String, in context: ModelContext, telegram: String = "", email: String = "",
                  phone: String = "") -> Connection {
    let person = Connection(fullName: name, source: .nearby, context: MeetingContext(metAt: testNow))
    person.telegram = telegram
    person.email = email
    person.phone = phone
    context.insert(person)
    return person
}

@MainActor
@discardableResult
func insertReminder(for person: Connection?, in context: ModelContext, dueAt: Date = date(2026, 9, 27),
                    title: String = "Follow up", channel: FollowUpChannel = .telegram) -> FollowUp {
    let reminder = FollowUp(title: title, channel: channel, dueAt: dueAt)
    context.insert(reminder)
    reminder.connection = person
    return reminder
}
