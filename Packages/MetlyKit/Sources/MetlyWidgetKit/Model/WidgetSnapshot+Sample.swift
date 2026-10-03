import Foundation
import MetlyCore

/// Demo data for previews, widget placeholders and the gallery when nothing was published yet.
/// Mirrors the prototype's demo account (Aziza Karimova).
nonisolated public extension WidgetSnapshot {
    static let sampleWorkCardID = UUID(uuidString: "6F0C1E52-3B7A-4C1D-9E3F-6A7B8C9D0E11")!
    static let samplePersonalCardID = UUID(uuidString: "6F0C1E52-3B7A-4C1D-9E3F-6A7B8C9D0E12")!

    static var sampleOwner: WidgetOwner {
        WidgetOwner(fullName: "Aziza Karimova", jobTitle: "Product Manager", company: "Uzum")
    }

    static var sampleCards: [WidgetCard] {
        let fields = [
            ContactField(kind: .email, value: "aziza@uzum.uz", privacy: .public),
            ContactField(kind: .telegram, value: "@aziza_k", privacy: .public),
            ContactField(kind: .website, value: "aziza.design", privacy: .public),
        ]
        let workURL = Brand.cardURL(slug: "aziza-k7m2")
        let personalURL = Brand.cardURL(slug: "aziza-p3x9")
        return [
            WidgetCard(id: sampleWorkCardID, name: "Work",
                       design: CardDesign(template: .professional, palette: .ink, appearance: .dark),
                       url: workURL, fields: fields, qrPayload: workURL.absoluteString, isDefault: true),
            WidgetCard(id: samplePersonalCardID, name: "Personal",
                       design: CardDesign(template: .gradient, palette: .sand, appearance: .light, background: .gradient),
                       url: personalURL, fields: Array(fields.prefix(2)), qrPayload: personalURL.absoluteString),
        ]
    }

    static func sampleFollowUps(now: Date = .now, calendar: Calendar = .current) -> [WidgetFollowUp] {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: DateComponents(day: offset, hour: 10), to: today) ?? today
        }
        return [
            WidgetFollowUp(id: UUID(uuidString: "0B1E2D3C-0000-4000-8000-000000000001")!, title: "Send the pitch deck",
                           personName: "Kamila Yusupova", context: "Tashkent Tech Week", dueAt: day(-1), channel: .telegram),
            WidgetFollowUp(id: UUID(uuidString: "0B1E2D3C-0000-4000-8000-000000000002")!, title: "Intro to the design team",
                           personName: "Timur Sobirov", context: "Payme", dueAt: day(0), channel: .email),
            WidgetFollowUp(id: UUID(uuidString: "0B1E2D3C-0000-4000-8000-000000000003")!, title: "Book a demo call",
                           personName: "Dilnoza Rakhimova", context: "Tashkent Tech Week", dueAt: day(0), channel: .call),
            WidgetFollowUp(id: UUID(uuidString: "0B1E2D3C-0000-4000-8000-000000000004")!, title: "Share the event photos",
                           personName: "Bekzod Aliev", context: "Product Meetup", dueAt: day(2), channel: .telegram),
        ]
    }

    /// Signed in, two cards, reminders due, an active event.
    static func sample(now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        let followUps = sampleFollowUps(now: now, calendar: calendar)
        return WidgetSnapshot(
            generatedAt: now,
            owner: sampleOwner,
            cards: sampleCards,
            shareCardID: sampleWorkCardID,
            followUps: followUps,
            openFollowUpDueDates: followUps.map(\.dueAt),
            recentConnectionDates: [now.addingTimeInterval(-3_600), now.addingTimeInterval(-7_200), now.addingTimeInterval(-10_800)],
            activeEventName: "Tashkent Tech Week"
        )
    }

    /// Signed in with one card and no reminders or new connections (empty states).
    static func sampleEmpty(now: Date = .now) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: now, owner: sampleOwner, cards: Array(sampleCards.prefix(1)), shareCardID: sampleWorkCardID)
    }

    /// Signed in, nothing due today, one reminder later this week.
    static func sampleNothingDue(now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        let later = sampleFollowUps(now: now, calendar: calendar).filter { $0.dueAt >= startOfNextDay(after: now, calendar: calendar) }
        var snapshot = sampleEmpty(now: now)
        snapshot.followUps = later
        snapshot.openFollowUpDueDates = later.map(\.dueAt)
        return snapshot
    }
}
