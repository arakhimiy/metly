import Foundation
import MetlyCore
import SwiftData
import SwiftUI

/// Demo data mirroring the prototype (SPEC Appendix A). Used by previews, UI tests and the mock server.
public enum PreviewSeed {
    public enum Variant: Sendable {
        /// Profile + 2 cards + people, follow-ups, an active event, requests.
        case full
        /// Profile + 1 card, nothing else (empty states).
        case empty
        /// Nothing (onboarding / setup).
        case signedOut
    }

    public static let profileID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    public static let workCardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
    public static let personalCardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
    public static let eventID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
    public static let firstConnectionID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!

    public static func insert(_ variant: Variant, into context: ModelContext) {
        guard variant != .signedOut else { return }
        let calendar = Calendar.current
        let now = Date.now

        let profile = Profile(id: profileID, fullName: "Aziza Karimova", jobTitle: "Product Designer", company: "Tezkor",
                              contactFields: [
                                  ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .private),
                                  ContactField(kind: .email, value: "aziza@tezkor.uz", privacy: .connections),
                                  ContactField(kind: .telegram, value: "@aziza.k", privacy: .connections),
                                  ContactField(kind: .website, value: "aziza.design", privacy: .public),
                                  ContactField(kind: .linkedin, value: "in/azizakarimova", privacy: .connections),
                              ],
                              isSetupComplete: true)
        profile.defaultCardID = workCardID
        context.insert(profile)

        let work = Card(id: workCardID, name: "Work", slug: "aziza-w7k2", sortOrder: 0,
                        design: CardDesign(template: .professional, palette: .ink, appearance: .dark))
        work.publishState = .published
        work.stats = CardStats(views: 128, saves: 41, shareBacks: 12, scans: 87)
        context.insert(work)

        guard variant == .full else { return }

        let personal = Card(id: personalCardID, name: "Personal", slug: "aziza-p3x9", sortOrder: 1,
                            design: CardDesign(template: .stack, palette: .sand, appearance: .light, font: .rounded))
        personal.publishState = .published
        context.insert(personal)

        let event = Event(id: eventID, name: "Tashkent Tech Week", place: "Hyatt Regency", city: "Tashkent",
                          startDate: calendar.date(byAdding: .day, value: -1, to: now)!,
                          endDate: calendar.date(byAdding: .day, value: 1, to: now)!, cardID: workCardID)
        context.insert(event)

        let people: [(String, String, String, ConnectionSource, String, String, Int)] = [
            ("Kamila Yusupova", "Head of Partnerships", "Uzum", .nearby, "@kamila.y", "Investor", 0),
            ("Sardor Rashidov", "CTO", "Payme", .tapPhones, "@sardor", "Partner", 0),
            ("Dilnoza Ergasheva", "Recruiter", "EPAM", .webShareBack, "@dilnoza.e", "Hiring", 1),
            ("Jasur Akhmedov", "Founder", "Workly", .scanQR, "@jasur", "Client", 2),
            ("Madina Alieva", "Product Manager", "Click", .paper, "", "", 5),
            ("Timur Nazarov", "Engineer", "Yandex", .justMet, "@timurn", "Friend", 9),
        ]
        var connections: [Connection] = []
        for (index, person) in people.enumerated() {
            let metAt = calendar.date(byAdding: .day, value: -person.6, to: now)!
            let inEvent = person.6 <= 1
            let connection = Connection(
                id: index == 0 ? firstConnectionID : UUID(),
                fullName: person.0, jobTitle: person.1, company: person.2, source: person.3,
                context: MeetingContext(eventID: inEvent ? eventID : nil, eventName: inEvent ? event.name : nil,
                                        place: inEvent ? "Hyatt Regency" : "IT Park", city: "Tashkent", metAt: metAt))
            connection.telegram = person.4
            connection.email = person.0.split(separator: " ").first!.lowercased() + "@" + person.2.lowercased() + ".uz"
            if !person.5.isEmpty { connection.tags = [person.5] }
            if index == 0 {
                connection.note = "Interested in a design partnership for Uzum Market. Send the pitch deck."
                connection.mySharedCardID = workCardID
                connection.theirCard = CardSnapshot(cardName: "Work", design: CardDesign(template: .modern, palette: .graphite),
                                                    fullName: person.0, jobTitle: person.1, company: person.2,
                                                    fields: [ContactField(kind: .telegram, value: person.4)])
            }
            if inEvent { connection.event = event }
            connection.syncState = .synced
            context.insert(connection)
            connections.append(connection)
        }

        let followUps: [(Int, String, FollowUpChannel, Int)] = [
            (0, "Send the pitch deck", .telegram, 0),
            (1, "Intro to the design team", .email, -1),
            (3, "Follow up", .call, 3),
            (2, "Share portfolio", .telegram, 6),
        ]
        for item in followUps {
            let due = calendar.date(bySettingHour: 10, minute: 0, second: 0,
                                    of: calendar.date(byAdding: .day, value: item.3, to: now)!)!
            let followUp = FollowUp(title: item.1, channel: item.2, dueAt: due, connection: connections[item.0])
            followUp.syncState = .synced
            context.insert(followUp)
        }

        let request = ConnectRequest(direction: .incoming, peerUserID: UUID(), peerName: "Bekzod Tursunov",
                                     peerTitle: "Growth Lead", peerCompany: "Alif",
                                     peerCard: CardSnapshot(cardName: "Work", design: CardDesign(template: .bold, palette: .ember),
                                                            fullName: "Bekzod Tursunov", jobTitle: "Growth Lead", company: "Alif"),
                                     method: .nearby, eventName: event.name)
        context.insert(request)

        for model in [profile] as [any SyncedRecord] { model.syncState = .synced }
        work.syncState = .synced
        personal.syncState = .synced
        event.syncState = .synced
        try? context.save()
    }
}

@MainActor
public extension View {
    /// Injects router, services and an in-memory seeded store. Use in every `#Preview`.
    func metlyPreview(_ seed: PreviewSeed.Variant = .full, plan: Plan = .free, online: Bool = true) -> some View {
        self
            .modelContainer(MetlyModelContainer.preview(seed))
            .environment(AppRouter(phase: .main))
            .environment(AppServices.preview(plan: plan, online: online))
    }
}
