#if DEBUG
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

#Preview("Connection · with note") {
    NavigationStack { ConnectionDetailView(connectionID: PreviewSeed.firstConnectionID) }
        .metlyPreview(.full)
}

#Preview("Connection · no note") {
    NavigationStack {
        PreviewPerson(name: "Madina Alieva") { ConnectionDetailView(connectionID: $0) }
    }
    .metlyPreview(.full)
}

#Preview("Connection · merged") {
    NavigationStack {
        PreviewPerson(name: "Timur Nazarov", prepare: { person, _ in
            person.isMerged = true
            person.note = "Met at the coffee line. Builds infra at Yandex; wants to try Tanishly for their team."
            person.phone = "+998 93 555 12 34"
            person.previousMeetings = [MeetingContext(eventName: "Product Meetup", place: "IT Park", city: "Tashkent",
                                                      metAt: .now.addingTimeInterval(-40 * 86_400))]
        }) { ConnectionDetailView(connectionID: $0) }
    }
    .metlyPreview(.full)
}

#Preview("Connection · web share-back") {
    NavigationStack {
        PreviewPerson(name: "Dilnoza Ergasheva") { ConnectionDetailView(connectionID: $0) }
    }
    .metlyPreview(.full)
}

#Preview("Connection · not found") {
    NavigationStack { ConnectionDetailView(connectionID: UUID()) }
        .metlyPreview(.full)
}

#Preview("Add Context · edit") {
    AddContextSheet(connectionID: PreviewSeed.firstConnectionID)
        .metlyPreview(.full)
}

#Preview("Add Context · web share-back merge") {
    PreviewPerson(name: "Dilnoza Ergasheva", prepare: { _, context in
        PreviewData.addPendingJustMet(named: "Dilnoza", in: context)
    }) { AddContextSheet(connectionID: $0) }
    .metlyPreview(.full)
}

#Preview("Add Context · limit reached (Free)") {
    PreviewPerson(name: "Madina Alieva", prepare: { person, context in
        context.insert(FollowUp(title: "Coffee", channel: .call, dueAt: .now.addingTimeInterval(86_400),
                                connection: nil))
    }) { AddContextSheet(connectionID: $0) }
    .metlyPreview(.full)
}

#Preview("Just Met") {
    JustMetSheet(cardID: PreviewSeed.workCardID)
        .metlyPreview(.full)
}

#Preview("Just Met · no event, Pro") {
    JustMetSheet(cardID: nil)
        .metlyPreview(.empty, plan: .pro)
}

#Preview("Blocked People") {
    NavigationStack {
        PreviewPrepared(prepare: { context in
            let people = (try? context.fetch(FetchDescriptor<Connection>())) ?? []
            people.prefix(2).forEach { $0.isBlocked = true }
        }) {
            BlockedPeopleView()
        }
    }
    .metlyPreview(.full)
}

#Preview("Blocked People · empty") {
    NavigationStack { BlockedPeopleView() }
        .metlyPreview(.full)
}
#endif
