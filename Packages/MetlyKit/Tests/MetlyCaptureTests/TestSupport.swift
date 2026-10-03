import Foundation
import MetlyCore
import MetlyData
import SwiftData

/// Fixed calendar so date math is deterministic (Tashkent, UTC+5, no DST).
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
    return calendar
}()

/// Saturday, Sep 26, 2026, 14:32 in Tashkent (the prototype's "today").
let testNow: Date = {
    testCalendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 14, minute: 32))!
}()

@MainActor
func makeContext() throws -> ModelContext {
    let container = try MetlyModelContainer.make(inMemory: true)
    let context = ModelContext(container)
    retainedContainers.append(container)
    return context
}

/// Keeps in-memory containers alive for the duration of a test.
@MainActor private var retainedContainers: [ModelContainer] = []

@MainActor
@discardableResult
func insertPerson(_ name: String, in context: ModelContext, telegram: String = "", email: String = "",
                  phone: String = "", context meeting: MeetingContext = MeetingContext(metAt: testNow)) -> Connection {
    let person = Connection(fullName: name, source: .nearby, context: meeting)
    person.telegram = telegram
    person.email = email
    person.phone = phone
    context.insert(person)
    return person
}

@MainActor
@discardableResult
func insertOpenFollowUp(for person: Connection?, in context: ModelContext, dueInDays days: Int = 1) -> FollowUp {
    let due = testCalendar.date(byAdding: .day, value: days, to: testNow)!
    let followUp = FollowUp(title: "Follow up", channel: .telegram, dueAt: due)
    context.insert(followUp)
    followUp.connection = person
    return followUp
}
