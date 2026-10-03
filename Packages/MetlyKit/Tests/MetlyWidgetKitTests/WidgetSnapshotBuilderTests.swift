import Foundation
import MetlyCore
import Testing
@testable import MetlyWidgetKit

@Suite("Snapshot building")
struct WidgetSnapshotBuilderTests {
    // MARK: Privacy

    @Test("Card faces carry Public, design-visible, non-empty fields only, in display order")
    func publicFieldsOnly() throws {
        let snapshot = build(makeInput())
        let work = try #require(snapshot.card(id: workCardID))
        // Phone is Connections, website Private, Telegram hidden by the design.
        #expect(work.fields.map(\.kind) == [.email, .linkedin])
        #expect(work.fields.allSatisfy { $0.privacy == .public })
        #expect(work.fields.first?.value == "aziza@uzum.uz")   // trimmed
    }

    @Test("Never Connections or Private, even when the design shows every field")
    func audienceIsPublic() {
        let allVisible = CardDesign(visibleFields: Set(ContactFieldKind.allCases))
        let fields = WidgetSnapshotBuilder.publicFields(ownerFields, design: allVisible)
        #expect(fields.map(\.kind) == [.email, .telegram, .linkedin])
    }

    @Test("Empty values are skipped")
    func emptyFieldsSkipped() {
        let fields = [ContactField(kind: .email, value: "   ", privacy: .public), ContactField(kind: .linkedin, value: "in/x", privacy: .public)]
        let result = WidgetSnapshotBuilder.publicFields(fields, design: CardDesign(visibleFields: [.email, .linkedin]))
        #expect(result.map(\.kind) == [.linkedin])
    }

    // MARK: QR payloads

    @Test("Published cards encode their link")
    func publishedCardEncodesLink() throws {
        let work = try #require(build(makeInput()).card(id: workCardID))
        #expect(work.url == Brand.cardURL(slug: "aziza-k7m2"))
        #expect(work.qrPayload == "https://metly.link/c/aziza-k7m2")
        #expect(!work.usesOfflineQR)
    }

    @Test("Unpublished cards encode a public-only vCard")
    func unpublishedCardEncodesVCard() throws {
        let personal = try #require(build(makeInput()).card(id: personalCardID))
        #expect(personal.url == nil)
        #expect(personal.usesOfflineQR)
        #expect(personal.qrPayload.hasPrefix("BEGIN:VCARD"))
        #expect(personal.qrPayload.contains("FN:Aziza Karimova"))
        #expect(personal.qrPayload.contains("aziza@uzum.uz"))
        #expect(!personal.qrPayload.contains("123 45 67"))      // Connections-only phone
        #expect(!personal.qrPayload.contains("aziza.design"))   // Private website
    }

    // MARK: Cards

    @Test("Cards keep the user's order and mark the default")
    func cardOrderAndDefault() {
        let snapshot = build(makeInput())
        #expect(snapshot.cards.map(\.id) == [workCardID, personalCardID])
        #expect(snapshot.cards.map(\.isDefault) == [true, false])
    }

    @Test("Card to share: the event card, else the default, else the first card", arguments: [
        (share: Optional(personalCardID), defaultID: Optional(workCardID), expected: personalCardID),
        (share: Optional(eventCardID), defaultID: Optional(personalCardID), expected: personalCardID),   // unknown id
        (share: nil, defaultID: Optional(personalCardID), expected: personalCardID),
        (share: nil, defaultID: nil, expected: workCardID),                                               // first by sortOrder
    ])
    func shareCard(share: UUID?, defaultID: UUID?, expected: UUID) {
        let snapshot = build(makeInput(defaultCardID: defaultID, shareCardID: share))
        #expect(snapshot.shareCardID == expected)
        #expect(snapshot.shareCard?.id == expected)
    }

    @Test("Photo is embedded only when a card template shows it")
    func photoOnlyWhenRendered() {
        let photo = Data([1, 2, 3])
        let minimal = build(makeInput(photo: photo))
        #expect(minimal.owner?.photoThumbnail == nil)

        let modern = WidgetSnapshotInput.Card(id: workCardID, name: "Work", slug: "w", design: CardDesign(template: .modern, showPhoto: true))
        let withPhoto = build(makeInput(cards: [modern], photo: photo))
        #expect(withPhoto.owner?.photoThumbnail == photo)
    }

    @Test("Owner values are trimmed and the pause state carried over")
    func ownerValues() throws {
        var input = makeInput(paused: true, eventName: "  ")
        input.owner.fullName = "  Aziza Karimova "
        let snapshot = build(input)
        let owner = try #require(snapshot.owner)
        #expect(owner.fullName == "Aziza Karimova")
        #expect(owner.firstName == "Aziza")
        #expect(owner.role == "Product Manager · Uzum")
        #expect(owner.linksPaused)
        #expect(snapshot.activeEventName == nil)
    }

    // MARK: Follow-ups

    @Test("Follow-ups are sorted by due date and limited; every due date is kept for counts")
    func followUpOrderingAndLimit() {
        let dues = (0..<14).map { testNow.addingTimeInterval(Double(($0 * 5) % 14 - 5) * 86_400) }
        let input = makeInput(followUps: dues.enumerated().map { followUp($0.offset, due: $0.element) })
        let snapshot = build(input)
        #expect(snapshot.followUps.count == WidgetSnapshot.maxFollowUps)
        #expect(snapshot.followUps.map(\.dueAt) == Array(dues.sorted().prefix(WidgetSnapshot.maxFollowUps)))
        #expect(snapshot.openFollowUpDueDates == dues.sorted())
        #expect(snapshot.openFollowUpCount == 14)
    }

    @Test("Missing names and titles get readable fallbacks")
    func followUpFallbacks() throws {
        let input = makeInput(followUps: [followUp(1, due: testNow, person: "  ", title: " ", context: " Tashkent Tech Week ")])
        let row = try #require(build(input).followUps.first)
        #expect(row.personName == "Someone")
        #expect(row.title == "Follow up")
        #expect(row.context == "Tashkent Tech Week")
    }

    @Test("Due count covers overdue and today, not tomorrow")
    func dueCounts() {
        let input = makeInput(followUps: [
            followUp(1, due: date(2026, 9, 24)),          // overdue
            followUp(2, due: date(2026, 9, 26, 23, 50)),  // later today
            followUp(3, due: date(2026, 9, 27, 0, 5)),    // tomorrow
            followUp(4, due: date(2026, 10, 3)),
        ])
        let snapshot = build(input)
        #expect(snapshot.dueFollowUpCount(at: testNow, calendar: testCalendar) == 2)
        #expect(snapshot.dueFollowUps(at: testNow, calendar: testCalendar).map(\.id) == [input.openFollowUps[0].id, input.openFollowUps[1].id])
        #expect(snapshot.nextFollowUp(after: testNow, calendar: testCalendar)?.id == input.openFollowUps[2].id)
        // After midnight tomorrow's reminder is due too.
        #expect(snapshot.dueFollowUpCount(at: date(2026, 9, 27, 0, 1), calendar: testCalendar) == 3)
    }

    // MARK: Connections

    @Test("New connections count per calendar week; old ones are dropped")
    func newConnectionsThisWeek() {
        let input = makeInput(connectionDates: [
            date(2026, 9, 21, 9),    // Monday, this week
            date(2026, 9, 20, 18),   // Sunday, last week
            date(2026, 9, 26, 8),    // today
            date(2026, 9, 10),       // too old
        ])
        let snapshot = build(input)
        #expect(snapshot.recentConnectionDates == [date(2026, 9, 26, 8), date(2026, 9, 21, 9), date(2026, 9, 20, 18)])
        #expect(snapshot.newConnectionsThisWeek(at: testNow, calendar: testCalendar) == 2)
        #expect(snapshot.newConnectionsThisWeek(at: date(2026, 9, 28, 0, 1), calendar: testCalendar) == 0)
    }

    // MARK: Signed out

    @Test("No input means a signed-out snapshot with nothing personal")
    func signedOut() {
        let snapshot = build(nil)
        #expect(!snapshot.isSignedIn)
        #expect(snapshot.cards.isEmpty)
        #expect(snapshot.followUps.isEmpty)
        #expect(snapshot.openFollowUpDueDates.isEmpty)
        #expect(snapshot.generatedAt == testNow)
    }
}
