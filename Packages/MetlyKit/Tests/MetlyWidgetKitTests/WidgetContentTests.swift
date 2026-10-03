import Foundation
import MetlyCore
import Testing
@testable import MetlyWidgetKit

@Suite("Widget content")
struct WidgetContentTests {
    // MARK: Card widgets

    @Test("No snapshot or signed out → signed-out state; no cards → no-card state")
    func cardEmptyStates() {
        #expect(CardWidgetContent.resolve(snapshot: nil, cardID: nil, at: testNow) == .signedOut)
        #expect(CardWidgetContent.resolve(snapshot: .signedOut(), cardID: nil, at: testNow) == .signedOut)
        let noCards = build(makeInput(cards: []))
        #expect(CardWidgetContent.resolve(snapshot: noCards, cardID: nil, at: testNow) == .noCard)
        #expect(CardWidgetContent.signedOut.url == WidgetDeepLink.app)
    }

    @Test("Automatic widgets follow the card to share and let the app pick it at tap time")
    func automaticCard() throws {
        let snapshot = build(makeInput(shareCardID: personalCardID))
        let content = CardWidgetContent.resolve(snapshot: snapshot, cardID: nil, at: testNow, calendar: testCalendar)
        let display = try #require(content.display)
        #expect(display.card.id == personalCardID)
        #expect(display.followsShareCard)
        #expect(content.url.absoluteString == "metly://qr")
    }

    @Test("A configured card opens its own QR; a deleted one falls back to the card to share")
    func configuredCard() throws {
        let snapshot = build(makeInput())
        let chosen = CardWidgetContent.resolve(snapshot: snapshot, cardID: personalCardID, at: testNow)
        #expect(chosen.display?.card.id == personalCardID)
        #expect(chosen.display?.followsShareCard == false)
        #expect(chosen.url.absoluteString == "metly://qr/\(personalCardID.uuidString)")

        let stale = CardWidgetContent.resolve(snapshot: snapshot, cardID: eventCardID, at: testNow)
        #expect(stale.display?.card.id == workCardID)
        #expect(stale.display?.followsShareCard == true)
    }

    @Test("Paused only matters for link QR codes")
    func pausedState() throws {
        let snapshot = build(makeInput(paused: true))
        let work = try #require(CardWidgetContent.resolve(snapshot: snapshot, cardID: workCardID, at: testNow).display)
        let personal = try #require(CardWidgetContent.resolve(snapshot: snapshot, cardID: personalCardID, at: testNow).display)
        #expect(work.isPaused)
        #expect(!personal.isPaused)   // offline vCard keeps working
    }

    @Test("New-connections line", arguments: [(0, "No new connections this week"), (1, "1 new connection this week"),
                                              (4, "4 new connections this week")])
    func newConnectionsText(count: Int, expected: String) {
        let display = CardWidgetDisplay(card: WidgetSnapshot.sampleCards[0], owner: WidgetSnapshot.sampleOwner,
                                        newConnectionsThisWeek: count)
        #expect(display.newConnectionsText == expected)
    }

    @Test("Card names read as \"{Card} Card\" without doubling", arguments: [("Work", "Work Card"), ("Business card", "Business card"),
                                                                             ("  ", "Card")])
    func cardDisplayName(name: String, expected: String) {
        var card = WidgetSnapshot.sampleCards[0]
        card.name = name
        #expect(card.displayName == expected)
    }

    // MARK: Follow-ups widget

    @Test("Follow-ups summary: due rows, count, next reminder; pending taps already hidden")
    func followUpsSummary() throws {
        let input = makeInput(followUps: [
            followUp(1, due: date(2026, 9, 25)),
            followUp(2, due: date(2026, 9, 26, 9)),
            followUp(3, due: date(2026, 9, 26, 18)),
            followUp(4, due: date(2026, 9, 29)),
        ])
        let snapshot = build(input)
        let pending = [WidgetPendingAction.completeFollowUp(input.openFollowUps[1].id)]
        guard case .reminders(let summary) = FollowUpsWidgetContent.resolve(snapshot: snapshot, pending: pending, at: testNow,
                                                                          calendar: testCalendar)
        else { Issue.record("expected reminders"); return }

        #expect(summary.due.map(\.id) == [input.openFollowUps[0].id, input.openFollowUps[2].id])
        #expect(summary.dueCount == 2)
        #expect(summary.next?.id == input.openFollowUps[3].id)
        #expect(summary.openCount == 3)
        #expect(!summary.isEmpty)
    }

    @Test("Follow-ups empty states")
    func followUpsEmptyStates() {
        #expect(FollowUpsWidgetContent.resolve(snapshot: nil, at: testNow) == .signedOut)
        #expect(FollowUpsWidgetContent.resolve(snapshot: .signedOut(), at: testNow) == .signedOut)
        guard case .reminders(let summary) = FollowUpsWidgetContent.resolve(snapshot: build(makeInput()), at: testNow) else {
            Issue.record("expected reminders"); return
        }
        #expect(summary.isEmpty)
        #expect(summary.due.isEmpty)
        #expect(summary.next == nil)
    }

    // MARK: Formatting & scheduling

    @Test("Due labels", arguments: [
        (date(2026, 9, 26, 18), "Today", WidgetDueLabel.Emphasis.today),
        (date(2026, 9, 27, 9), "Tomorrow", .upcoming),
        (date(2026, 9, 25, 9), "Yesterday", .overdue),
        (date(2026, 9, 29, 9), "Tue, Sep 29", .upcoming),
        (date(2026, 9, 20, 9), "Sun, Sep 20", .overdue),
    ])
    func dueLabels(due: Date, text: String, emphasis: WidgetDueLabel.Emphasis) {
        let label = WidgetDueLabel(due: due, now: testNow, calendar: testCalendar, locale: usLocale)
        #expect(label.text == text)
        #expect(label.emphasis == emphasis)
    }

    @Test("Timelines refresh now and at the next two midnights")
    func timelineSchedule() {
        let dates = WidgetTimelineSchedule.entryDates(from: testNow, calendar: testCalendar)
        #expect(dates == [testNow, date(2026, 9, 27, 0, 0), date(2026, 9, 28, 0, 0)])
    }

    @Test("Deep links match DeepLinkHandler's hosts")
    func deepLinks() {
        let id = UUID(uuidString: "6F0C1E52-3B7A-4C1D-9E3F-6A7B8C9D0E11")!
        #expect(WidgetDeepLink.qr().absoluteString == "metly://qr")
        #expect(WidgetDeepLink.qr(cardID: id).absoluteString == "metly://qr/6F0C1E52-3B7A-4C1D-9E3F-6A7B8C9D0E11")
        #expect(WidgetDeepLink.followUps.absoluteString == "metly://followups")
        #expect(WidgetDeepLink.reminder(id).absoluteString == "metly://reminder/6F0C1E52-3B7A-4C1D-9E3F-6A7B8C9D0E11")
        #expect(WidgetDeepLink.startEvent.absoluteString == "metly://event/start")
        #expect(WidgetDeepLink.qr(cardID: id).pathComponents.filter { $0 != "/" } == [id.uuidString])
    }

    // MARK: Card choices (widget configuration / Shortcuts parameter)

    @Test("Card choices: Card to Share first, then every card; deleted ids are omitted")
    func cardChoices() {
        let snapshot = build(makeInput())
        let all = WidgetCardChoice.all(in: snapshot)
        #expect(all.map(\.id) == [WidgetCardChoice.automaticID, workCardID.uuidString, personalCardID.uuidString])
        #expect(all.map(\.subtitle).dropFirst() == ["Default card", "Not published yet"])
        #expect(all.first?.cardID == nil)

        let resolved = WidgetCardChoice.choices(for: [personalCardID.uuidString, eventCardID.uuidString], in: snapshot)
        #expect(resolved.map(\.cardID) == [personalCardID])
        #expect(WidgetCardChoice.matching("pers", in: snapshot).map(\.cardID) == [personalCardID])
        #expect(WidgetCardChoice.all(in: nil).map(\.id) == [WidgetCardChoice.automaticID])
    }
}
