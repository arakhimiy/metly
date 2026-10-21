import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import MetlyCapture

/// Regression: "Hyatt Regency, Tashkent, Tashkent" — the city must never be saved or shown twice.
@MainActor
struct PlaceDedupeTests {
    @Test func typedPlaceEndingInTheCityIsSavedWithoutIt() throws {
        let context = try makeContext()
        let person = insertPerson("Madina", in: context)
        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        draft.place = "Hyatt Regency, Tashkent"
        draft.city = "Tashkent"
        draft.apply(to: person, in: context, limits: .free, now: testNow, calendar: testCalendar)
        #expect(person.context.place == "Hyatt Regency")
        #expect(person.context.city == "Tashkent")
    }

    @Test func stampedContextIsDedupedWhenTheFormOpens() {
        // Older clients sent "place, city" as one string next to the city.
        let draft = CaptureDraft(context: MeetingContext(place: "Hyatt Regency, Tashkent", city: "Tashkent", metAt: testNow))
        #expect(draft.place == "Hyatt Regency")
        #expect(draft.city == "Tashkent")
    }

    @Test func activeEventPlaceIsDedupedInTheCapture() throws {
        let context = try makeContext()
        context.insert(Event(name: "Tashkent Tech Week", place: "Hyatt Regency, Tashkent", city: "Tashkent"))
        let draft = CaptureDraft.capture(for: nil, in: context, now: testNow)
        #expect(draft.place == "Hyatt Regency")
        #expect(draft.meetingContext.place == "Hyatt Regency")
        #expect(draft.meetingContext.city == "Tashkent")
    }

    @Test func placeThatIsTheCityIsNotRepeated() {
        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        draft.place = "tashkent"
        draft.city = "Tashkent"
        #expect(draft.meetingContext.place == nil)
        #expect(draft.meetingContext.city == "Tashkent")
    }

    @Test func differentPlaceAndCityAreKept() {
        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        draft.place = "Hyatt Regency Tashkent"
        draft.city = "Tashkent"
        #expect(draft.meetingContext.place == "Hyatt Regency Tashkent")
    }

    // MARK: PlaceText

    @Test func placeTextJoinsPlaceAndCityOnce() {
        #expect(PlaceText.joined(place: "Hyatt Regency, Tashkent", city: "Tashkent") == "Hyatt Regency, Tashkent")
        #expect(PlaceText.joined(place: "Hyatt Regency, TASHKENT, Tashkent", city: "tashkent") == "Hyatt Regency, tashkent")
        #expect(PlaceText.joined(place: "Tashkent", city: "Tashkent") == "Tashkent")
        #expect(PlaceText.joined(place: "IT Park", city: "Samarkand") == "IT Park, Samarkand")
        #expect(PlaceText.joined(place: "IT Park", city: nil) == "IT Park")
        #expect(PlaceText.joined(place: nil, city: "Samarkand") == "Samarkand")
        #expect(PlaceText.joined(place: "  ", city: "") == nil)
        #expect(PlaceText.normalizedPlace("Toshkent, Tashkent", city: "Tashkent") == "Toshkent")
        #expect(PlaceText.normalizedPlace("Café Bon, Tashkent", city: "Tashkent") == "Café Bon")
    }

    // MARK: Location auto-fill

    @Test func locationSuggestionEndingInTheCityIsDeduped() {
        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        let filled = draft.applyLocationSuggestion(PlaceSuggestion(place: "Amir Temur Ave 107B, Tashkent", city: "Tashkent"))
        #expect(filled)
        #expect(draft.place == "Amir Temur Ave 107B")
        #expect(draft.city == "Tashkent")
        #expect(draft.isAutoFilled)
    }

    @Test func locationNeverOverwritesATypedPlace() {
        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        draft.place = "Plov Center"
        let filled = draft.applyLocationSuggestion(PlaceSuggestion(place: "Hyatt Regency", city: "Tashkent"))
        #expect(!filled)
        #expect(draft.place == "Plov Center")
        #expect(draft.city.isEmpty)
    }

    /// Regression: the location resolving after the user typed an event marked their event "Auto".
    @Test func locationKeepsTheUsersEditsOutOfTheAutoBadge() {
        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        draft.markAutoFilled()
        draft.eventName = "Founders Dinner"   // typed while the location was resolving
        draft.applyLocationSuggestion(PlaceSuggestion(place: "Plov Center", city: "Tashkent"))
        #expect(draft.place == "Plov Center")
        #expect(draft.eventName == "Founders Dinner")
        #expect(!draft.isAutoFilled)
    }

    @Test func locationKeepsATypedCity() {
        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        draft.city = "Samarkand"
        draft.applyLocationSuggestion(PlaceSuggestion(place: "Registan", city: "Samarqand"))
        #expect(draft.city == "Samarkand")
        #expect(draft.place == "Registan")
    }

    /// Regression: the silent fill ran every time the section scrolled back into view and refilled a
    /// Place the user had cleared on purpose.
    @Test func silentLocationFillRunsOncePerForm() {
        #expect(LocationAutoFill.shouldFillSilently(isAuthorized: true, status: .idle, place: ""))
        #expect(!LocationAutoFill.shouldFillSilently(isAuthorized: true, status: .resolved(PlaceSuggestion(place: "Hyatt", city: "")),
                                                     place: ""))
        #expect(!LocationAutoFill.shouldFillSilently(isAuthorized: true, status: .failed, place: ""))
        #expect(!LocationAutoFill.shouldFillSilently(isAuthorized: false, status: .idle, place: ""))
        #expect(!LocationAutoFill.shouldFillSilently(isAuthorized: true, status: .idle, place: "Hyatt"))
    }
}
