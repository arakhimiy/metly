import Foundation
import MetlyCore
import Testing
@testable import MetlyCardKit

@Suite("CardFaceModel")
struct CardFaceModelTests {
    private let allVisible = Set(ContactFieldKind.allCases)

    @Test(arguments: CardDensity.allCases)
    func truncatesContactsToDensity(_ density: CardDensity) {
        let design = CardDesign(density: density, visibleFields: allVisible)
        let model = CardFaceModel(design: design, content: .sample)
        #expect(model.contacts.count == density.maxContacts)
        #expect(model.contacts.map(\.kind) == Array(ContactFieldKind.allCases.prefix(density.maxContacts)))
    }

    @Test func densityLimitsAreTwoThreeFive() {
        #expect(CardDensity.minimal.maxContacts == 2)
        #expect(CardDensity.balanced.maxContacts == 3)
        #expect(CardDensity.detailed.maxContacts == 5)
    }

    @Test func excludesPrivateHiddenAndEmptyFields() {
        let content = CardFaceContent(fullName: "Aziza Karimova", fields: [
            ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .private),
            ContactField(kind: .email, value: "   ", privacy: .public),
            ContactField(kind: .telegram, value: "@aziza.k", privacy: .connections),
            ContactField(kind: .website, value: "aziza.design", privacy: .public),
            ContactField(kind: .linkedin, value: "in/aziza", privacy: .public),
        ])
        let design = CardDesign(density: .detailed, visibleFields: [.phone, .email, .telegram, .linkedin])
        let model = CardFaceModel(design: design, content: content)
        #expect(model.contacts.map(\.kind) == [.telegram, .linkedin])
    }

    @Test func keepsDisplayOrderAndFirstValuePerKind() {
        let content = CardFaceContent(fullName: "A B", fields: [
            ContactField(kind: .linkedin, value: "in/ab"),
            ContactField(kind: .email, value: "first@ab.uz"),
            ContactField(kind: .email, value: "second@ab.uz"),
            ContactField(kind: .phone, value: "+1"),
        ])
        let model = CardFaceModel(design: CardDesign(density: .detailed, visibleFields: allVisible), content: content)
        #expect(model.contacts.map(\.kind) == [.phone, .email, .linkedin])
        #expect(model.contacts[1].value == "first@ab.uz")
    }

    @Test func boldShowsAtMostTwoContacts() {
        let model = CardFaceModel(design: CardDesign(template: .bold, density: .detailed, visibleFields: allVisible),
                                  content: .sample)
        #expect(model.boldContacts.count == 2)
    }

    @Test func derivesNamesRoleInitialsAndMonogram() {
        let model = CardFaceModel(design: CardDesign(), content: CardFaceContent(
            fullName: "  Kamola  Rashidova Bekovna ", jobTitle: "Designer", company: "tezkor"))
        #expect(model.fullName == "Kamola  Rashidova Bekovna")
        #expect(model.firstName == "Kamola")
        #expect(model.lastName == "Rashidova Bekovna")
        #expect(model.role == "Designer · tezkor")
        #expect(model.initials == "KR")
        #expect(model.monogram == "T")
    }

    @Test func fallsBackWhenValuesAreMissing() {
        let model = CardFaceModel(design: CardDesign(), content: CardFaceContent(fullName: "Timur"))
        #expect(model.role.isEmpty)
        #expect(model.lastName.isEmpty)
        #expect(model.initials == "T")
        #expect(model.monogram == "T")
        #expect(model.qrPayload == "https://\(Brand.linkHost)")
    }

    @Test func honoursPhotoLogoAndQRToggles() {
        var content = CardFaceContent.sample
        content.photoData = Data([1, 2, 3])
        content.logoData = Data([4, 5, 6])
        let shown = CardFaceModel(design: CardDesign(), content: content)
        #expect(shown.photoData != nil && shown.logoData != nil && shown.showsQR)
        let hidden = CardFaceModel(design: CardDesign(showQR: false, showPhoto: false, showLogo: false), content: content)
        #expect(hidden.photoData == nil && hidden.logoData == nil && !hidden.showsQR)
    }

    @Test func accessibilityDescriptionListsNameRoleAndVisibleContacts() {
        let model = CardFaceModel(design: CardDesign(density: .minimal, visibleFields: allVisible), content: .sample)
        #expect(model.accessibilityDescription ==
            "Kamola Rashidova. Product Designer, Tezkor. Phone: +998 90 123 45 67. Email: kamola@tezkor.uz")
    }

    @Test func templatesForceFontsAndAlignment() {
        #expect(CardDesign(template: .terminal, font: .serif).effectiveFont == .mono)
        #expect(CardDesign(template: .editorial, font: .rounded).effectiveFont == .serif)
        #expect(CardDesign(template: .stack, font: .rounded).effectiveFont == .rounded)
        // v2: only Wordmark (`bold`) is composed for both alignments.
        #expect(CardDesign(template: .minimal, alignment: .center).effectiveAlignment == .leading)
        #expect(CardDesign(template: .gradient, alignment: .center).effectiveAlignment == .leading)
        #expect(CardDesign(template: .bold, alignment: .center).effectiveAlignment == .center)
        #expect(CardDesign(template: .split, alignment: .center).effectiveAlignment == .leading)
        // Aurora draws its own fill, so the palette gradient is off for it.
        #expect(!CardDesign(template: .gradient, background: .gradient).usesGradientFill)
        #expect(CardDesign(template: .minimal, background: .gradient).usesGradientFill)
        #expect(!CardDesign(template: .minimal, background: .solid).usesGradientFill)
    }

    // MARK: Templates v2

    @Test func logoAndPhotoSlotsFollowTheTemplates() {
        let logo = CardTemplate.allCases.filter { CardDesign(template: $0).templateShowsLogo }
        #expect(Set(logo) == [.minimal, .professional, .modern, .bold, .split, .stack, .editorial])
        let photo = CardTemplate.allCases.filter { CardDesign(template: $0).templateShowsPhoto }
        #expect(Set(photo) == [.split, .stack])
    }

    @Test func proTemplatesAreTheFinishTemplates() {
        #expect(Set(CardTemplate.allCases.filter(\.isPro)) == [.modern, .gradient, .editorial])
        #expect(Set(CardTemplate.pickerOrder) == Set(CardTemplate.allCases))
        #expect(CardTemplate.pickerOrder.suffix(3).allSatisfy { $0.isPro })
    }

    @Test func faceOptionsHideTitleAndCompany() {
        let content = CardFaceContent.sample.applying(CardFaceOptions(showJobTitle: false, showCompany: false, logoStyle: .mono))
        let model = CardFaceModel(design: CardDesign(), content: content)
        #expect(model.jobTitle.isEmpty && model.company.isEmpty && model.role.isEmpty)
        #expect(model.logoStyle == .mono)
        #expect(model.wordmark == "Kamola")
        let shown = CardFaceModel(design: CardDesign(), content: .sample.applying(CardFaceOptions()))
        #expect(shown.wordmark == "Tezkor" && shown.jobTitle == "Product Designer")
    }

    @Test func faceOptionsDecodeMissingKeysAsShown() throws {
        let options = try JSONDecoder().decode(CardFaceOptions.self, from: Data(#"{"template":"minimal"}"#.utf8))
        #expect(options == CardFaceOptions())
        let hidden = try JSONDecoder().decode(CardFaceOptions.self, from: Data(#"{"showCompany":false,"logoStyle":"mono"}"#.utf8))
        #expect(hidden == CardFaceOptions(showJobTitle: true, showCompany: false, logoStyle: .mono))
    }
}
