import Foundation
import MetlyCore
@testable import MetlyWidgetKit

/// Fixed calendar (Tashkent, UTC+5, no DST; weeks start on Monday) so date math is deterministic.
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
    calendar.firstWeekday = 2
    return calendar
}()

let usLocale = Locale(identifier: "en_US")

/// Saturday, Sep 26, 2026, 14:32 in Tashkent (the prototype's "today"). Its week is Mon Sep 21 – Sun Sep 27.
let testNow = date(2026, 9, 26, 14, 32)

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

let workCardID = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
let personalCardID = UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!
let eventCardID = UUID(uuidString: "00000000-0000-4000-8000-0000000000A3")!

/// Phone = Connections, email = Public, Telegram = Public, website = Private, LinkedIn = Public.
let ownerFields = [
    ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .connections),
    ContactField(kind: .email, value: " aziza@uzum.uz ", privacy: .public),
    ContactField(kind: .telegram, value: "@aziza_k", privacy: .public),
    ContactField(kind: .website, value: "aziza.design", privacy: .private),
    ContactField(kind: .linkedin, value: "in/aziza", privacy: .public),
]

func makeOwner(photo: Data? = nil, paused: Bool = false) -> WidgetSnapshotInput.Owner {
    WidgetSnapshotInput.Owner(fullName: "Aziza Karimova", jobTitle: "Product Manager", company: "Uzum",
                              photoData: photo, contactFields: ownerFields, linksPaused: paused)
}

/// Shows phone, email, website and LinkedIn — not Telegram.
let designWithoutTelegram = CardDesign(template: .minimal, visibleFields: [.phone, .email, .website, .linkedin])

func makeInput(cards: [WidgetSnapshotInput.Card]? = nil, defaultCardID: UUID? = workCardID, shareCardID: UUID? = nil,
               followUps: [WidgetSnapshotInput.FollowUp] = [], connectionDates: [Date] = [],
               photo: Data? = nil, paused: Bool = false, eventName: String? = nil) -> WidgetSnapshotInput {
    WidgetSnapshotInput(
        owner: makeOwner(photo: photo, paused: paused),
        cards: cards ?? [
            WidgetSnapshotInput.Card(id: personalCardID, name: "Personal", slug: "", sortOrder: 1, design: designWithoutTelegram),
            WidgetSnapshotInput.Card(id: workCardID, name: "Work", slug: "aziza-k7m2", sortOrder: 0, design: designWithoutTelegram),
        ],
        defaultCardID: defaultCardID,
        shareCardID: shareCardID,
        openFollowUps: followUps,
        connectionDates: connectionDates,
        activeEventName: eventName
    )
}

func followUp(_ index: Int, due: Date, person: String? = "Person \(UUID().uuidString.prefix(4))",
              title: String = "Follow up", context: String? = nil) -> WidgetSnapshotInput.FollowUp {
    WidgetSnapshotInput.FollowUp(id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012ld", index))!,
                                 title: title, dueAt: due, channel: .telegram, personName: person,
                                 personContext: context)
}

/// Builds with an identity thumbnailer (no image decoding in logic tests).
func build(_ input: WidgetSnapshotInput?, now: Date = testNow) -> WidgetSnapshot {
    WidgetSnapshotBuilder.build(from: input, now: now, thumbnail: { $0 })
}

/// A fresh store in a unique temporary directory.
func makeTemporaryStore() -> WidgetSnapshotStore {
    WidgetSnapshotStore(directory: FileManager.default.temporaryDirectory
        .appending(path: "MetlyWidgetKitTests-\(UUID().uuidString)", directoryHint: .isDirectory))
}
