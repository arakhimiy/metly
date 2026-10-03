#if DEBUG
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// Runs `prepare` once against the preview store, then shows `content`.
struct EventPreviewPrepared<Content: View>: View {
    var prepare: (ModelContext) -> Void
    @ViewBuilder var content: Content

    @Environment(\.modelContext) private var modelContext
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                content
            } else {
                ProgressView()
            }
        }
        .task {
            prepare(modelContext)
            try? modelContext.save()
            isReady = true
        }
    }
}

/// Adjustments on top of `PreviewSeed.full` (Tashkent Tech Week with Kamila, Sardor and Dilnoza).
enum EventPreviewData {
    static let emptyEventID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E9")!

    /// Two more people at the seeded event without notes or reminders, so "No Note Yet" and
    /// "Follow Up with Everyone I Haven't Yet" show.
    static func addEventPeople(in context: ModelContext) {
        guard let event = context.record(Event.self, id: PreviewSeed.eventID) else { return }
        let people: [(String, String, String, String)] = [
            ("Bobur Karimov", "iOS Engineer", "Uzum", "@bobur.k"),
            ("Nilufar Saidova", "Designer", "Humans", ""),
        ]
        for (index, person) in people.enumerated() {
            let metAt = Calendar.current.date(byAdding: .hour, value: -(index + 1), to: .now) ?? .now
            let connection = Connection(fullName: person.0, jobTitle: person.1, company: person.2, source: .scanQR,
                                        context: MeetingContext(eventID: event.id, eventName: event.name,
                                                                place: event.place, city: event.city, metAt: metAt))
            connection.telegram = person.3
            connection.email = person.0.split(separator: " ").first.map { "\($0.lowercased())@example.com" } ?? ""
            context.insert(connection)
            connection.event = event
        }
    }

    /// Ends the seeded event (as if "End Event" was tapped an hour ago).
    static func endSeedEvent(in context: ModelContext) {
        guard let event = context.record(Event.self, id: PreviewSeed.eventID) else { return }
        EventLifecycle.end(event, at: Calendar.current.date(byAdding: .hour, value: -1, to: .now) ?? .now)
    }

    /// A fresh active event nobody has been added to yet (the seeded one is ended first).
    static func insertEmptyEvent(in context: ModelContext) {
        endSeedEvent(in: context)
        let today = Calendar.current.startOfDay(for: .now)
        let event = Event(id: emptyEventID, name: "Product Meetup", place: "IT Park", city: "Tashkent",
                          startDate: today, endDate: today.addingTimeInterval(86_399), cardID: PreviewSeed.personalCardID)
        context.insert(event)
    }

    /// "From Your Calendar" rows.
    static var calendarSuggestions: [CalendarSuggestion] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int, hour: Int) -> Date {
            calendar.date(byAdding: DateComponents(day: offset, hour: hour), to: today) ?? today
        }
        return [
            CalendarSuggestion(eventIdentifier: "preview-1", title: "Tashkent Tech Week",
                               location: "Hyatt Regency, Tashkent", startDate: day(0, hour: 0), endDate: day(3, hour: 0),
                               isAllDay: true),
            CalendarSuggestion(eventIdentifier: "preview-2", title: "Product Meetup", location: "IT Park, Tashkent",
                               startDate: day(2, hour: 18), endDate: day(2, hour: 21)),
            CalendarSuggestion(eventIdentifier: "preview-3", title: "Design Systems Summit",
                               location: "Congress Hall\nAmir Temur Square 1, Tashkent",
                               startDate: day(9, hour: 9), endDate: day(10, hour: 18)),
        ]
    }
}
#endif
