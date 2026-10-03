import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureScan

@MainActor
@Suite("Connections created from scans")
struct ScanConnectionFactoryTests {
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try MetlyModelContainer.make(inMemory: true)
        context = container.mainContext
    }

    private var kamilaCard: CardSnapshot {
        CardSnapshot(cardName: "Work", design: CardDesign(template: .modern, palette: .graphite),
                     fullName: "Kamila Yusupova", jobTitle: "Head of Partnerships", company: "Uzum",
                     fields: [ContactField(kind: .telegram, value: "@kamila.y", privacy: .public),
                              ContactField(kind: .email, value: "kamila@uzum.uz", privacy: .public)],
                     url: Brand.cardURL(slug: "kamila-x1y2"))
    }

    @Test("Add to People keeps their card, values and the active event")
    func fromMetlyCard() {
        let event = Event(name: "Tashkent Tech Week", place: "Hyatt Regency", city: "Tashkent")
        context.insert(event)
        let userID = UUID()

        let person = ScanConnectionFactory.insertConnection(from: kamilaCard, remoteUserID: userID, in: context)

        #expect(person.source == .scanQR)
        #expect(person.remoteUserID == userID)
        #expect(person.fullName == "Kamila Yusupova")
        #expect(person.company == "Uzum")
        #expect(person.telegram == "@kamila.y")
        #expect(person.email == "kamila@uzum.uz")
        #expect(person.theirCard == kamilaCard)
        #expect(person.mySharedCardID == nil)
        #expect(person.context.eventName == "Tashkent Tech Week")
        #expect(person.context.place == "Hyatt Regency")
        #expect(person.event?.id == event.id)
        #expect(person.syncState == .pendingUpsert)
    }

    @Test("Offline Connect records the card that was offered")
    func offlineConnectSharesCard() {
        let cardID = UUID()
        let person = ScanConnectionFactory.insertConnection(from: kamilaCard, remoteUserID: UUID(), sharedCardID: cardID, in: context)
        #expect(person.mySharedCardID == cardID)
        #expect(person.event == nil)
        #expect(person.context.eventName == nil)
    }

    @Test("Paper cards and vCards become plain connections; a company card uses the company as name")
    func fromDraft() {
        let paper = PaperCardDraft(fullName: "  Dilshod Rakhimov ", jobTitle: "Head of Sales", company: "Tezkor",
                                   fields: [ContactField(kind: .phone, value: "+998 90 987 65 43"),
                                            ContactField(kind: .website, value: "")])
        let person = ScanConnectionFactory.insertConnection(from: paper, source: .paper, in: context)
        #expect(person.source == .paper)
        #expect(person.fullName == "Dilshod Rakhimov")
        #expect(person.phone == "+998 90 987 65 43")
        #expect(person.website.isEmpty)
        #expect(person.theirCard == nil)

        let companyOnly = PaperCardDraft(company: "Humo Payments", fields: [ContactField(kind: .email, value: "info@humo.uz")])
        #expect(ScanConnectionFactory.insertConnection(from: companyOnly, source: .scanQR, in: context).fullName == "Humo Payments")
    }

    @Test("Already in People: same Metly user, or same phone / email / Telegram")
    func matching() {
        let userID = UUID()
        let known = Connection(fullName: "Kamila Yusupova", source: .nearby)
        known.remoteUserID = userID
        known.phone = "+998 90 555 12 34"
        known.telegram = "@Kamila.Y"
        context.insert(known)
        let removed = Connection(fullName: "Removed Person", source: .paper)
        removed.email = "gone@example.com"
        context.insert(removed)
        removed.markDeleted()
        let people = [known, removed]

        #expect(ScanConnectionFactory.existing(remoteUserID: userID, among: people) === known)
        #expect(ScanConnectionFactory.existing(remoteUserID: UUID(), among: people) == nil)
        #expect(ScanConnectionFactory.existing(remoteUserID: nil, among: people) == nil)

        #expect(ScanConnectionFactory.existing(matching: [ContactField(kind: .phone, value: "90 555-12-34")], among: people) === known)
        #expect(ScanConnectionFactory.existing(matching: [ContactField(kind: .telegram, value: "t.me/kamila.y")], among: people) === known)
        #expect(ScanConnectionFactory.existing(matching: [ContactField(kind: .email, value: "gone@example.com")], among: people) == nil)
        #expect(ScanConnectionFactory.existing(matching: [ContactField(kind: .phone, value: "+998 91 000 00 00")], among: people) == nil)
        #expect(ScanConnectionFactory.existing(matching: [], among: people) == nil)
    }

    @Test("Paper review details round-trip into a trimmed draft")
    func paperDetails() {
        var details = PaperCardDetails(draft: PaperCardParser.parse(text: ["Aziza Karimova", "aziza@tezkor.uz"]))
        #expect(details.canSave)
        details[.telegram] = " @aziza.k "
        details[.name] = "   "
        #expect(!details.canSave)
        #expect(details.draft.fields.map(\.kind) == [.email, .telegram])
        #expect(details.draft.fields.last?.value == "@aziza.k")
    }
}
