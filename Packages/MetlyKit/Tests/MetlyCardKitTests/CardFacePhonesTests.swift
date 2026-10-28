import Foundation
import MetlyCore
import Testing
@testable import MetlyCardKit

/// Several labelled phones on a card face: grouping, density, labels, privacy.
@Suite("CardFaceModel · phones")
struct CardFacePhonesTests {
    private let allVisible = Set(ContactFieldKind.allCases)

    private func content(primary: String? = "+998 90 123 45 67", primaryPrivacy: FieldPrivacy = .public,
                         extras: [LabeledPhone], email: Bool = true) -> CardFaceContent {
        var fields: [ContactField] = []
        if let primary { fields.append(ContactField(kind: .phone, value: primary, privacy: primaryPrivacy)) }
        if email { fields.append(ContactField(kind: .email, value: "kamola@tezkor.uz", privacy: .public)) }
        return CardFaceContent(fullName: "Kamola Rashidova", fields: fields, additionalPhones: extras, phoneLabel: .mobile)
    }

    private let work = LabeledPhone(label: .work, value: "+998 71 200 10 20", privacy: .public)
    private let home = LabeledPhone(label: .home, value: "+998 71 255 33 44", privacy: .public)

    @Test func extraPhonesFollowThePrimaryAndComeBeforeEmail() {
        let model = CardFaceModel(design: CardDesign(density: .detailed, visibleFields: allVisible),
                                  content: content(extras: [work, home]))
        #expect(model.contacts.map(\.kind) == [.phone, .phone, .phone, .email])
        #expect(model.contacts.map(\.value) == ["+998 90 123 45 67", "+998 71 200 10 20", "+998 71 255 33 44", "kamola@tezkor.uz"])
        #expect(Set(model.contacts.map(\.id)).count == 4)
    }

    @Test func labelsAppearOnlyWhenSeveralNumbersAreShown() {
        let several = CardFaceModel(design: CardDesign(density: .detailed, visibleFields: allVisible),
                                    content: content(extras: [work]))
        #expect(several.contacts.prefix(2).map(\.phoneLabel) == [.mobile, .work])
        #expect(several.contacts.last?.phoneLabel == nil)   // email

        let single = CardFaceModel(design: CardDesign(density: .detailed, visibleFields: allVisible),
                                   content: content(extras: []))
        #expect(single.contacts.first?.phoneLabel == nil)
    }

    /// Extras only use lines left free after one line per kind: a second number never pushes the email off.
    @Test func extraPhonesNeverCrowdOutOtherKinds() {
        let minimal = CardFaceModel(design: CardDesign(density: .minimal, visibleFields: allVisible),
                                    content: content(extras: [work, home]))
        #expect(minimal.contacts.map(\.kind) == [.phone, .email])
        #expect(minimal.contacts.first?.phoneLabel == nil)

        let balanced = CardFaceModel(design: CardDesign(density: .balanced, visibleFields: allVisible),
                                     content: content(extras: [work, home]))
        #expect(balanced.contacts.map(\.kind) == [.phone, .phone, .email])
        #expect(balanced.contacts.map(\.phoneLabel) == [.mobile, .work, nil])
    }

    @Test func contactLinesCountWhatDensityHides() {
        let lines = CardFaceModel.contactLines(from: content(extras: [work, home]).fields,
                                               additionalPhones: [work, home], phoneLabel: .mobile,
                                               design: CardDesign(density: .minimal, visibleFields: allVisible))
        #expect(lines.shown.count == 2)
        #expect(lines.hiddenFieldCount == 0)
        #expect(lines.hiddenPhoneCount == 2)

        let fields = CardFaceContent.sample.fields
        let crowded = CardFaceModel.contactLines(from: fields, additionalPhones: [work], phoneLabel: .mobile,
                                                 design: CardDesign(density: .balanced, visibleFields: allVisible))
        #expect(crowded.hiddenFieldCount == 2)   // website + LinkedIn
        #expect(crowded.hiddenPhoneCount == 1)
    }

    @Test func privateAndEmptyExtrasNeverShow() {
        let hidden = LabeledPhone(label: .home, value: "+998 71 999 99 99", privacy: .private)
        let empty = LabeledPhone(label: .other, value: "   ", privacy: .public)
        let model = CardFaceModel(design: CardDesign(density: .detailed, visibleFields: allVisible),
                                  content: content(extras: [hidden, empty, work]))
        #expect(model.contacts.map(\.value) == ["+998 90 123 45 67", "+998 71 200 10 20", "kamola@tezkor.uz"])
    }

    @Test func hidingPhonesOnTheCardHidesEveryNumber() {
        let model = CardFaceModel(design: CardDesign(density: .detailed, visibleFields: [.email]),
                                  content: content(extras: [work, home]))
        #expect(model.contacts.map(\.kind) == [.email])
    }

    @Test func anExtraNumberStandsInForAPrivatePrimary() {
        let model = CardFaceModel(design: CardDesign(density: .minimal, visibleFields: allVisible),
                                  content: content(primaryPrivacy: .private, extras: [work]))
        #expect(model.contacts.map(\.value) == ["+998 71 200 10 20", "kamola@tezkor.uz"])
        #expect(model.contacts.first?.phoneLabel == nil)
    }

    @Test func duplicateNumbersAreShownOnce() {
        let same = LabeledPhone(label: .work, value: "+998901234567", privacy: .public)
        let model = CardFaceModel(design: CardDesign(density: .detailed, visibleFields: allVisible),
                                  content: content(extras: [same, work]))
        #expect(model.contacts.map(\.value) == ["+998 90 123 45 67", "+998 71 200 10 20", "kamola@tezkor.uz"])
    }

    @Test func boldKeepsTwoLinesWithOneNumber() {
        let model = CardFaceModel(design: CardDesign(template: .bold, density: .detailed, visibleFields: allVisible),
                                  content: content(extras: [work, home]))
        #expect(model.boldContacts.map(\.kind) == [.phone, .email])
        #expect(model.boldContacts.first?.phoneLabel == nil)

        let phonesOnly = CardFaceModel(design: CardDesign(template: .bold, density: .detailed, visibleFields: [.phone]),
                                       content: content(extras: [work, home]))
        #expect(phonesOnly.boldContacts.map(\.phoneLabel) == [.mobile, .work])
    }

    @Test func terminalKeysNameTheLabel() {
        let model = CardFaceModel(design: CardDesign(template: .terminal, density: .detailed, visibleFields: allVisible),
                                  content: content(extras: [work, home]))
        #expect(model.contacts.map(\.terminalKey) == ["tel", "tel.work", "tel.home", "mail"])
        let single = CardFaceModel(design: CardDesign(template: .terminal, visibleFields: allVisible),
                                   content: content(extras: []))
        #expect(single.contacts.first?.terminalKey == "tel")
    }

    @Test func voiceOverSaysWhichPhone() {
        let model = CardFaceModel(design: CardDesign(density: .detailed, visibleFields: [.phone]),
                                  content: content(extras: [work], email: false))
        #expect(model.accessibilityDescription ==
            "Kamola Rashidova. Mobile phone: +998 90 123 45 67. Work phone: +998 71 200 10 20")
    }

    @Test func oldCallersWithoutExtrasBehaveAsBefore() {
        let design = CardDesign(density: .balanced, visibleFields: allVisible)
        #expect(CardFaceModel.contacts(from: CardFaceContent.sample.fields, design: design).map(\.kind)
                == [.phone, .email, .telegram])
    }
}
