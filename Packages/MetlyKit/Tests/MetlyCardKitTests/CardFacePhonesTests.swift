import Foundation
import MetlyCore
import Testing
@testable import MetlyCardKit

/// Contact lines on a card face (3.0.0): the card's entries in the owner's order, density limit, phone
/// labels, privacy, duplicates.
@Suite("CardFaceModel · contact list")
struct CardFacePhonesTests {
    private let mobile = ContactEntry(kind: .phone, label: .mobile, value: "+998 90 123 45 67", privacy: .public)
    private let work = ContactEntry(kind: .phone, label: .work, value: "+998 71 200 10 20", privacy: .public)
    private let home = ContactEntry(kind: .phone, label: .home, value: "+998 71 255 33 44", privacy: .public)
    private let email = ContactEntry(kind: .email, value: "kamola@tezkor.uz", privacy: .public)
    private let whatsapp = ContactEntry(kind: .whatsapp, value: "+998 90 123 45 67", privacy: .public)
    private let instagram = ContactEntry(kind: .instagram, value: "@kamola.design", privacy: .public)

    private func content(_ entries: [ContactEntry]) -> CardFaceContent {
        CardFaceContent(fullName: "Kamola Rashidova", contacts: entries)
    }

    @Test func linesFollowTheOwnersOrder() {
        let model = CardFaceModel(design: CardDesign(density: .detailed),
                                  content: content([email, mobile, instagram, work, whatsapp]))
        #expect(model.contacts.map(\.kind) == [.email, .phone, .instagram, .phone, .whatsapp])
        #expect(Set(model.contacts.map(\.id)).count == 5)
    }

    @Test func densityCutsTheListAtItsLimit() {
        let entries = [mobile, work, home, email, instagram]
        let minimal = CardFaceModel(design: CardDesign(density: .minimal), content: content(entries))
        #expect(minimal.contacts.map(\.value) == ["+998 90 123 45 67", "+998 71 200 10 20"])
        let balanced = CardFaceModel(design: CardDesign(density: .balanced), content: content(entries))
        #expect(balanced.contacts.count == 3)
        let detailed = CardFaceModel(design: CardDesign(density: .detailed), content: content(entries))
        #expect(detailed.contacts.count == 5)
    }

    @Test func labelsAppearOnlyWhenSeveralNumbersAreShown() {
        let several = CardFaceModel(design: CardDesign(density: .detailed), content: content([mobile, work, email]))
        #expect(several.contacts.map(\.phoneLabel) == [.mobile, .work, nil])

        let single = CardFaceModel(design: CardDesign(density: .detailed), content: content([mobile, email]))
        #expect(single.contacts.first?.phoneLabel == nil)

        // Only one number fits: no label even though the card has two.
        let cut = CardFaceModel(design: CardDesign(density: .minimal), content: content([mobile, email, work]))
        #expect(cut.contacts.first?.phoneLabel == nil)
    }

    @Test func contactLinesCountWhatDensityHides() {
        let lines = CardFaceModel.contactLines(from: [mobile, work, home, email], design: CardDesign(density: .minimal))
        #expect(lines.shown.count == 2)
        #expect(lines.hiddenPhoneCount == 1)
        #expect(lines.hiddenFieldCount == 1)
    }

    @Test func privateAndEmptyEntriesNeverShow() {
        let hidden = ContactEntry(kind: .phone, label: .home, value: "+998 71 999 99 99", privacy: .private)
        let empty = ContactEntry(kind: .telegram, value: "   ", privacy: .public)
        let model = CardFaceModel(design: CardDesign(density: .detailed), content: content([hidden, mobile, empty, email]))
        #expect(model.contacts.map(\.value) == ["+998 90 123 45 67", "kamola@tezkor.uz"])
    }

    @Test func duplicateNumbersAreShownOnce() {
        let same = ContactEntry(kind: .phone, label: .work, value: "+998901234567", privacy: .public)
        let model = CardFaceModel(design: CardDesign(density: .detailed), content: content([mobile, same, work]))
        #expect(model.contacts.map(\.value) == ["+998 90 123 45 67", "+998 71 200 10 20"])
        // WhatsApp on the same number is its own line.
        let withWhatsApp = CardFaceModel(design: CardDesign(density: .detailed), content: content([mobile, whatsapp]))
        #expect(withWhatsApp.contacts.map(\.kind) == [.phone, .whatsapp])
    }

    @Test func boldKeepsTwoLines() {
        let model = CardFaceModel(design: CardDesign(template: .bold, density: .detailed), content: content([mobile, work, email]))
        #expect(model.boldContacts.map(\.kind) == [.phone, .phone])
        #expect(model.boldContacts.map(\.phoneLabel) == [.mobile, .work])
    }

    @Test func terminalKeysNameTheLabelAndTheNewKinds() {
        let model = CardFaceModel(design: CardDesign(template: .terminal, density: .detailed),
                                  content: content([mobile, work, email, whatsapp, instagram]))
        #expect(model.contacts.map(\.terminalKey) == ["tel", "tel.work", "mail", "wa", "ig"])
        let single = CardFaceModel(design: CardDesign(template: .terminal), content: content([mobile]))
        #expect(single.contacts.first?.terminalKey == "tel")
    }

    @Test func voiceOverSaysWhichPhone() {
        let model = CardFaceModel(design: CardDesign(density: .detailed), content: content([mobile, work]))
        #expect(model.accessibilityDescription ==
            "Kamola Rashidova. Mobile phone: +998 90 123 45 67. Work phone: +998 71 200 10 20")
    }

    /// One-value-per-kind callers (cards from before 3.0.0) still filter by `visibleFields`.
    @Test func legacyFieldsAreFilteredByVisibleFields() {
        let design = CardDesign(density: .balanced, visibleFields: [.phone, .email, .telegram, .website])
        #expect(CardFaceModel.contacts(from: CardFaceContent.sample.fields, design: design).map(\.kind)
                == [.phone, .email, .telegram])
        let noPhones = CardDesign(density: .detailed, visibleFields: [.email])
        #expect(CardFaceModel.contacts(from: CardFaceContent.sample.fields, additionalPhones: [work.labeledPhone],
                                       design: noPhones).map(\.kind) == [.email])
    }

    /// A content built from legacy fields (another person's card) gets its list from them.
    @Test func legacyContentBuildsItsList() {
        let legacy = CardFaceContent(fullName: "Kamola", fields: [mobile.field, email.field],
                                     additionalPhones: [work.labeledPhone], phoneLabel: .mobile)
        let model = CardFaceModel(design: CardDesign(density: .detailed), content: legacy)
        #expect(model.contacts.map(\.kind) == [.phone, .phone, .email])
    }
}
