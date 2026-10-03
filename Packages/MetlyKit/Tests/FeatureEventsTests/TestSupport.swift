import Foundation
import MetlyCore
import MetlyData
import SwiftData
@testable import FeatureEvents

/// Fixed calendar so date math is deterministic (Tashkent, UTC+5, no DST).
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
    return calendar
}()

/// Saturday, Sep 26, 2026, 14:32 in Tashkent (the prototype's "today").
let testNow: Date = date(2026, 9, 26, 14, 32)

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

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
func insertEvent(_ name: String = "Tashkent Tech Week", in context: ModelContext,
                 start: Date = date(2026, 9, 25), end: Date = date(2026, 9, 27, 23, 59, 59),
                 status: EventStatus = .active) -> Event {
    let event = Event(name: name, place: "Hyatt Regency", city: "Tashkent", startDate: start, endDate: end)
    event.status = status
    context.insert(event)
    return event
}

/// A person met at `event` (linked through the relationship and the stamped context, like capture flows do).
@MainActor
@discardableResult
func insertPerson(_ name: String, at event: Event? = nil, in context: ModelContext, note: String = "",
                  telegram: String = "", email: String = "", phone: String = "",
                  metAt: Date = testNow) -> Connection {
    let meeting = MeetingContext(eventID: event?.id, eventName: event?.name, place: event?.place,
                                 city: event?.city, metAt: metAt)
    let person = Connection(fullName: name, source: .nearby, context: meeting)
    person.note = note
    person.telegram = telegram
    person.email = email
    person.phone = phone
    context.insert(person)
    person.event = event
    return person
}

@MainActor
@discardableResult
func insertFollowUp(for person: Connection?, in context: ModelContext, dueInDays days: Int = 1,
                    done: Bool = false) -> FollowUp {
    let due = testCalendar.date(byAdding: .day, value: days, to: testNow)!
    let followUp = FollowUp(title: "Follow up", channel: .telegram, dueAt: due)
    followUp.isDone = done
    context.insert(followUp)
    followUp.connection = person
    return followUp
}
