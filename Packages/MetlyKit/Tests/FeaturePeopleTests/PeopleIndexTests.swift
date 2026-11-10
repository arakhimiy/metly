import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeaturePeople

@MainActor
struct PeopleIndexTests {
    private func daysAgo(_ days: Int) -> Date {
        testCalendar.date(byAdding: .day, value: -days, to: testNow)!
    }

    /// Kamila + Sardor at the event (Tashkent), Jasur in Samarkand, Madina with no city.
    private func seed(_ context: ModelContext) -> (event: Event, people: [Connection]) {
        let event = Event(name: "Tashkent Tech Week", place: "Hyatt Regency", city: "Tashkent",
                          startDate: daysAgo(1), endDate: testNow)
        context.insert(event)
        let kamila = insertPerson("Kamila Yusupova", in: context,
                                  context: MeetingContext(eventID: event.id, eventName: event.name, place: "Hyatt Regency",
                                                          city: "Tashkent", metAt: daysAgo(0)))
        kamila.company = "Uzum"
        kamila.tags = ["Investor", "Partner"]
        kamila.note = "Pitch deck"
        kamila.event = event
        let sardor = insertPerson("Sardor Rashidov", in: context,
                                  context: MeetingContext(eventName: "tashkent tech week", city: "Tashkent", metAt: daysAgo(1)))
        sardor.company = "Payme"
        sardor.tags = ["partner"]
        insertOpenFollowUp(for: sardor, in: context)
        let jasur = insertPerson("Jasur Akhmedov", in: context,
                                 context: MeetingContext(eventName: "Product Meetup", place: "IT Park", city: "Samarkand",
                                                         metAt: daysAgo(30)))
        jasur.company = "Workly"
        let madina = insertPerson("Madina Alieva", in: context, context: MeetingContext(metAt: daysAgo(5)))
        madina.jobTitle = "Product Manager"
        return (event, [kamila, sardor, jasur, madina])
    }

    // MARK: Search

    @Test func searchMatchesNameCompanyEventCityAndTags() throws {
        let context = try makeContext()
        let people = seed(context).people
        #expect(PeopleIndex.search(people, query: "kamila").map(\.fullName) == ["Kamila Yusupova"])
        #expect(PeopleIndex.search(people, query: "payme").map(\.fullName) == ["Sardor Rashidov"])
        #expect(PeopleIndex.search(people, query: "Tech Week").count == 2)
        #expect(PeopleIndex.search(people, query: "samarkand").map(\.fullName) == ["Jasur Akhmedov"])
        #expect(PeopleIndex.search(people, query: "investor").map(\.fullName) == ["Kamila Yusupova"])
        #expect(PeopleIndex.search(people, query: "product manager").map(\.fullName) == ["Madina Alieva"])
        #expect(PeopleIndex.search(people, query: "  ").count == 4)
        #expect(PeopleIndex.search(people, query: "zebra").isEmpty)
    }

    @Test func searchFindsWordsFromThePrivateNote() throws {
        let context = try makeContext()
        let people = seed(context).people
        let kamila = try #require(people.first { $0.fullName == "Kamila Yusupova" })
        kamila.note = "Wants the pitch deck by Friday"
        #expect(PeopleIndex.search(people, query: "pitch deck").map(\.fullName) == ["Kamila Yusupova"])
    }

    @Test func placesFilterIsNotOffered() {
        #expect(!PeopleFilter.offered.contains(.places))
        #expect(PeopleFilter.offered.first == .all)
    }

    @Test func sortedPutsMostRecentMeetingFirst() throws {
        let context = try makeContext()
        let people = seed(context).people
        #expect(PeopleIndex.sorted(people.reversed()).map(\.fullName)
                == ["Kamila Yusupova", "Sardor Rashidov", "Madina Alieva", "Jasur Akhmedov"])
    }

    // MARK: Places

    @Test func placesGroupByCityWithOtherLast() throws {
        let context = try makeContext()
        let groups = PeopleIndex.groupedByCity(seed(context).people)
        #expect(groups.map(\.title) == ["Tashkent", "Samarkand", PeopleIndex.otherPlacesTitle])
        #expect(groups[0].people.map(\.fullName) == ["Kamila Yusupova", "Sardor Rashidov"])
        #expect(groups[2].people.map(\.fullName) == ["Madina Alieva"])
    }

    // MARK: Tags

    @Test func tagsGroupCaseInsensitivelyAndUntaggedLast() throws {
        let context = try makeContext()
        let groups = PeopleIndex.groupedByTag(seed(context).people)
        #expect(groups.first?.title == "Partner")
        #expect(groups.first?.people.count == 2)
        #expect(groups.contains { $0.title == "Investor" && $0.people.count == 1 })
        #expect(groups.last?.title == PeopleIndex.untaggedTitle)
        #expect(groups.last?.people.count == 2)
    }

    // MARK: Events

    @Test func eventsCombineRecordsAndNamesWithCounts() throws {
        let context = try makeContext()
        let (event, people) = seed(context)
        let summaries = PeopleIndex.eventSummaries(people: people, events: [event])

        #expect(summaries.map(\.name) == ["Tashkent Tech Week", "Product Meetup"])
        let tech = summaries[0]
        #expect(tech.isActive)
        #expect(tech.eventID == event.id)
        #expect(tech.people.count == 2)          // linked record + same name (case-insensitive)
        #expect(tech.notesCount == 1)
        #expect(tech.followUpsCount == 1)
        #expect(tech.place == "Hyatt Regency, Tashkent")

        let meetup = summaries[1]
        #expect(meetup.eventID == nil)           // only known from connections → not tappable
        #expect(meetup.people.map(\.fullName) == ["Jasur Akhmedov"])
    }

    @Test func activeEventShowsEvenWithoutPeople() throws {
        let context = try makeContext()
        let event = Event(name: "Founders Dinner", startDate: testNow, endDate: testNow)
        context.insert(event)
        let ended = Event(name: "Old Conference", startDate: daysAgo(90), endDate: daysAgo(88))
        ended.status = .ended
        context.insert(ended)
        let summaries = PeopleIndex.eventSummaries(people: [], events: [event, ended])
        #expect(summaries.map(\.name) == ["Founders Dinner"])
    }

    @Test func eventSearchKeepsMatchingPeopleOrMatchingNames() throws {
        let context = try makeContext()
        let (event, people) = seed(context)
        let byPerson = PeopleIndex.eventSummaries(people: people, events: [event], query: "Sardor")
        #expect(byPerson.map(\.name) == ["Tashkent Tech Week"])
        #expect(byPerson.first?.people.map(\.fullName) == ["Sardor Rashidov"])

        let byName = PeopleIndex.eventSummaries(people: people, events: [event], query: "meetup")
        #expect(byName.map(\.name) == ["Product Meetup"])
    }
}
