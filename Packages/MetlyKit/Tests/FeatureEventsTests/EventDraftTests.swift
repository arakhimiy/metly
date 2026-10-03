import Foundation
import MetlyCore
import MetlyData
import Testing
@testable import FeatureEvents

@MainActor
struct EventDraftTests {
    private func draft(name: String = "Tech Week", start: Date, end: Date) -> EventDraft {
        var draft = EventDraft(now: testNow, calendar: testCalendar)
        draft.name = name
        draft.startDate = start
        draft.endDate = end
        return draft
    }

    // MARK: Validation

    @Test func newDraftStartsTodayAndNeedsAName() {
        let draft = EventDraft(cardID: nil, now: testNow, calendar: testCalendar)
        #expect(draft.startDate == date(2026, 9, 26))
        #expect(draft.endDate == date(2026, 9, 26))
        #expect(draft.issues(mode: .new, now: testNow, calendar: testCalendar) == [.missingName])
    }

    @Test func whitespaceNameIsMissing() {
        let blank = draft(name: "   ", start: date(2026, 9, 26), end: date(2026, 9, 26))
        #expect(blank.issues(mode: .new, now: testNow, calendar: testCalendar) == [.missingName])
    }

    @Test func endBeforeStartIsInvalid() {
        let backwards = draft(start: date(2026, 9, 28), end: date(2026, 9, 27))
        #expect(backwards.issues(mode: .new, now: testNow, calendar: testCalendar) == [.endBeforeStart])
    }

    @Test func sameDayIsValidRegardlessOfTime() {
        let sameDay = draft(start: date(2026, 9, 26, 18), end: date(2026, 9, 26, 9))
        #expect(sameDay.isValid(mode: .new, now: testNow, calendar: testCalendar))
    }

    @Test func newEventsCannotStartInThePast() {
        let yesterday = draft(start: date(2026, 9, 25), end: date(2026, 9, 27))
        #expect(yesterday.issues(mode: .new, now: testNow, calendar: testCalendar) == [.startInPast])
        // Editing a running event that started yesterday is fine.
        #expect(yesterday.isValid(mode: .editActive, now: testNow, calendar: testCalendar))
    }

    @Test func runningEventMustStillRunToday() {
        let over = draft(start: date(2026, 9, 20), end: date(2026, 9, 25))
        #expect(over.issues(mode: .editActive, now: testNow, calendar: testCalendar) == [.endInPast])
        #expect(over.isValid(mode: .editEnded, now: testNow, calendar: testCalendar))
    }

    @Test func pickerBounds() {
        let running = draft(start: date(2026, 9, 20), end: date(2026, 9, 27))
        #expect(EventDraft.earliestStart(mode: .new, now: testNow, calendar: testCalendar) == date(2026, 9, 26))
        #expect(EventDraft.earliestStart(mode: .editActive, now: testNow, calendar: testCalendar) == .distantPast)
        #expect(running.earliestEnd(mode: .editActive, now: testNow, calendar: testCalendar) == date(2026, 9, 26))
        #expect(running.earliestEnd(mode: .editEnded, now: testNow, calendar: testCalendar) == date(2026, 9, 20))
    }

    @Test func movingTheStartPastTheEndMovesTheEnd() {
        var moved = draft(start: date(2026, 9, 26), end: date(2026, 9, 27))
        moved.startDate = date(2026, 9, 30)
        moved.keepEndAfterStart(calendar: testCalendar)
        #expect(moved.endDate == date(2026, 9, 30))
        #expect(moved.dayCount(calendar: testCalendar) == 1)
    }

    // MARK: Writing

    @Test func savedDatesCoverWholeDays() {
        let event = draft(name: "  Tech Week  ", start: date(2026, 9, 26, 9), end: date(2026, 9, 28, 18))
            .makeEvent(calendar: testCalendar)
        #expect(event.name == "Tech Week")
        #expect(event.startDate == date(2026, 9, 26))
        #expect(event.endDate == date(2026, 9, 28, 23, 59, 59))
        #expect(event.isActive)
        #expect(event.syncState == .pendingUpsert)
    }

    @Test func roundTripsAnEvent() {
        let event = Event(name: "Meetup", place: "IT Park", city: "Tashkent", startDate: date(2026, 9, 26),
                          endDate: date(2026, 9, 26, 23, 59, 59), cardID: PreviewSeed.workCardID)
        event.calendarEventIdentifier = "cal-1"
        let draft = EventDraft(event: event)
        #expect(draft.name == "Meetup")
        #expect(draft.place == "IT Park")
        #expect(draft.cardID == PreviewSeed.workCardID)
        #expect(draft.calendarEventIdentifier == "cal-1")
        #expect(draft.dayCount(calendar: testCalendar) == 1)
    }

    // MARK: Calendar suggestions

    @Test func suggestionFillsNamePlaceAndDates() {
        var form = EventDraft(now: testNow, calendar: testCalendar)
        let suggestion = CalendarSuggestion(eventIdentifier: "ek-1", title: "Product Meetup",
                                            location: "IT Park, Tashkent",
                                            startDate: date(2026, 9, 28, 18), endDate: date(2026, 9, 28, 21),
                                            calendar: testCalendar)
        form.apply(suggestion, now: testNow, calendar: testCalendar)
        #expect(form.name == "Product Meetup")
        #expect(form.place == "IT Park")
        #expect(form.city == "Tashkent")
        #expect(form.startDate == date(2026, 9, 28))
        #expect(form.endDate == date(2026, 9, 28))
        #expect(form.calendarEventIdentifier == "ek-1")
        #expect(form.isValid(mode: .new, now: testNow, calendar: testCalendar))
    }

    @Test func runningSuggestionStartsTodayAndKeepsItsLastDay() {
        var form = EventDraft(now: testNow, calendar: testCalendar)
        // All-day, Sep 25–27 (EventKit end = midnight after the last day).
        let suggestion = CalendarSuggestion(eventIdentifier: "ek-2", title: "Tech Week", startDate: date(2026, 9, 25),
                                            endDate: date(2026, 9, 28), isAllDay: true, calendar: testCalendar)
        form.apply(suggestion, now: testNow, calendar: testCalendar)
        #expect(form.startDate == date(2026, 9, 26))
        #expect(form.endDate == date(2026, 9, 27))
        #expect(form.isValid(mode: .new, now: testNow, calendar: testCalendar))
        #expect(suggestion.dayLabel(now: testNow, calendar: testCalendar) == "Now")
    }

    @Test func suggestionWithoutLocationKeepsTypedPlace() {
        var form = EventDraft(now: testNow, calendar: testCalendar)
        form.place = "Hyatt Regency"
        form.apply(CalendarSuggestion(eventIdentifier: "ek-3", title: "Call", startDate: testNow,
                                      endDate: testNow.addingTimeInterval(3600), calendar: testCalendar),
                   now: testNow, calendar: testCalendar)
        #expect(form.place == "Hyatt Regency")
    }

    @Test(arguments: [
        ("Hyatt Regency, Tashkent", "Hyatt Regency", "Tashkent"),
        ("Hyatt Regency", "Hyatt Regency", ""),
        ("Congress Hall\nAmir Temur Square 1, Tashkent", "Congress Hall", ""),
        ("Hyatt Regency, 1A Navoi St, Tashkent, Uzbekistan", "Hyatt Regency", ""),
        ("", "", ""),
    ])
    func splitsCalendarLocations(location: String, place: String, city: String) {
        let split = EventDraft.splitLocation(location)
        #expect(split.place == place)
        #expect(split.city == city)
    }

    @Test func suggestionDayLabels() {
        func suggestion(_ start: Date) -> CalendarSuggestion {
            CalendarSuggestion(eventIdentifier: "x", title: "x", startDate: start, endDate: start.addingTimeInterval(3600),
                               calendar: testCalendar)
        }
        #expect(suggestion(date(2026, 9, 26, 18)).dayLabel(now: testNow, calendar: testCalendar) == "Today")
        #expect(suggestion(date(2026, 9, 27, 18)).dayLabel(now: testNow, calendar: testCalendar) == "Tomorrow")
    }
}
