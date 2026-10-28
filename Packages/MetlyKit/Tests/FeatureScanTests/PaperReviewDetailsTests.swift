import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureScan

/// PAPER_REVIEW editing: Recognized Text "Use As", Swap Name and Company, phone rows, saving.
@MainActor
@Suite("Paper review details")
struct PaperReviewDetailsTests {
    /// The user's failure mode: the name read into Company.
    private var misread: PaperCardDetails {
        PaperCardDetails(draft: PaperCardDraft(fullName: "", jobTitle: "Bosh menejer", company: "Davron Rahim",
                                               fields: [ContactField(kind: .phone, value: "+998 95 145 67 89"),
                                                        ContactField(kind: .email, value: "d.rahim@gmail.com")]))
    }

    @Test("Which fields use a line")
    func uses() {
        var details = misread
        #expect(details.uses(of: "Davron Rahim") == [.company])
        #expect(details.uses(of: "Bosh menejer") == [.title])
        #expect(details.uses(of: "+998 95 145 67 89") == [.phone])
        #expect(details.uses(of: "E-mail: d.rahim@gmail.com") == [.email])
        #expect(details.uses(of: "GRAND LUX").isEmpty)
        details.fullName = "Aziza Karimova"
        details.jobTitle = "Product Designer"
        #expect(details.uses(of: "Aziza Karimova, Product Designer") == [.name, .title])
    }

    @Test("Use As moves a line: Company → Name, then the logo line as Company")
    func useAsMoves() {
        var details = misread
        details.use("Davron Rahim", as: .name)
        #expect(details.fullName == "Davron Rahim")
        #expect(details.company.isEmpty)
        details.use("GRAND LUX", as: .company)
        #expect(details.company == "GRAND LUX")
        #expect(details.fullName == "Davron Rahim")
    }

    @Test("Use As takes the right part of the line")
    func useAsParts() {
        var details = PaperCardDetails(draft: PaperCardDraft())
        details.use("Aziza Karimova, Product Designer", as: .name)
        details.use("Aziza Karimova, Product Designer", as: .title)
        #expect(details.fullName == "Aziza Karimova")
        #expect(details.jobTitle == "Product Designer")

        details.use("SARDOR TOSHMATOV", as: .name)
        #expect(details.fullName == "Sardor Toshmatov")
        details.use("E-mail: S.Ivanov@uzum.uz", as: .email)
        #expect(details.email == "s.ivanov@uzum.uz")
        details.use("https://t.me/kamila_y", as: .telegram)
        #expect(details.telegram == "@kamila_y")
        details.use("www.uzum.uz", as: .website)
        #expect(details.website == "uzum.uz")
    }

    @Test("Use As Phone adds a row with the printed label; a number already there isn't added twice")
    func useAsPhone() {
        var details = misread
        details.use("Ish: +998 71 233 00 11", as: .phone)
        #expect(details.phones.map(\.value) == ["+998 95 145 67 89", "+998 71 233 00 11"])
        #expect(details.phones.last?.label == .work)
        details.use("+998 71 233 00 11", as: .phone)
        #expect(details.phones.count == 2)
    }

    @Test("Ignore lets go of the line")
    func ignore() {
        var details = misread
        details.use("d.rahim@gmail.com", as: .ignore)
        #expect(details.email.isEmpty)
        details.use("+998 95 145 67 89", as: .ignore)
        #expect(details.phones.isEmpty)
        details.use("Davron Rahim", as: .ignore)
        #expect(details.company.isEmpty)
        #expect(details.jobTitle == "Bosh menejer")
    }

    @Test("Swap Name and Company")
    func swap() {
        var details = PaperCardDetails(draft: PaperCardDraft(fullName: "Grand Lux", company: "Davron Rahim"))
        #expect(details.canSwapNameAndCompany)
        details.swapNameAndCompany()
        #expect(details.fullName == "Davron Rahim")
        #expect(details.company == "Grand Lux")
        #expect(!misread.canSwapNameAndCompany)
    }

    @Test("Phone rows round-trip; the first mobile is saved as the phone, the rest as additional phones")
    func phonesRoundTrip() {
        let draft = PaperCardDraft(fullName: "Rustam Nazarov",
                                   fields: [ContactField(kind: .phone, value: "+998 90 123 45 67")], phoneLabel: .mobile,
                                   additionalPhones: [LabeledPhone(label: .work, value: "+998 71 234 56 78")])
        var details = PaperCardDetails(draft: draft)
        #expect(details.phones.map(\.label) == [.mobile, .work])

        // The user relabels the first one Work and adds a mobile.
        details.phones[0].label = .work
        let added = details.addPhone()
        #expect(details.phones.last?.label == .mobile)
        details.phones[details.phones.firstIndex { $0.id == added }!].value = " +998 99 000 11 22 "
        let saved = details.draft
        #expect(saved.fields.first { $0.kind == .phone }?.value == "+998 99 000 11 22")
        #expect(saved.phoneLabel == .mobile)
        #expect(saved.additionalPhones.map(\.value) == ["+998 90 123 45 67", "+998 71 234 56 78"])
        #expect(saved.additionalPhones.map(\.label) == [.work, .work])

        details.removePhones(at: [0, 1])
        #expect(details.draft.additionalPhones.isEmpty)
        #expect(details.draft.phoneLabel == .mobile)
        #expect(details.addPhone() != added)
        #expect(details.phones.last?.label == .work)
    }

    @Test("Saving writes phone, phoneLabel and additionalPhones on the connection")
    func saveWritesPhones() throws {
        let container = try MetlyModelContainer.make(inMemory: true)
        let context = container.mainContext
        let draft = PaperCardParser.parse(text: ["Michael Brown", "Office: +1 212 555 0100", "Mobile: +1 917 555 0199",
                                                 "Home: +1 917 555 0100"])
        let person = ScanConnectionFactory.insertConnection(from: PaperCardDetails(draft: draft).draft, source: .paper, in: context)
        #expect(person.phone == "+1 917 555 0199")
        #expect(person.phoneLabel == .mobile)
        #expect(person.additionalPhones.map(\.value) == ["+1 212 555 0100", "+1 917 555 0100"])
        #expect(person.additionalPhones.map(\.label) == [.work, .home])

        // Matching an existing person works through any of their numbers.
        #expect(ScanConnectionFactory.existing(matching: [], phones: ["212-555-0100"], among: [person]) === person)
    }
}
