import Foundation
import MetlyCore
import Testing
@testable import MetlyCardKit

/// Several labelled phones in vCards: what the offline QR writes and what a scanned card gives back.
@Suite("vCard · labelled phones")
struct VCardPhonesTests {
    private func lines(_ vcard: String) -> [String] {
        VCardText.unfold(vcard).split(separator: "\n").map(String.init)
    }

    private var severalPhones: CardFaceContent {
        CardFaceContent(
            fullName: "Kamola Rashidova",
            fields: [
                ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .public),
                ContactField(kind: .email, value: "kamola@tezkor.uz", privacy: .public),
            ],
            additionalPhones: [
                LabeledPhone(label: .work, value: "+998 71 200 10 20", privacy: .public),
                LabeledPhone(label: .home, value: "+998 71 255 33 44", privacy: .public),
                LabeledPhone(label: .other, value: "+998 33 400 00 00", privacy: .public),
                LabeledPhone(label: .mobile, value: "+998 99 777 66 55", privacy: .public),
            ],
            phoneLabel: .mobile
        )
    }

    @Test func writesEveryNumberWithItsType() {
        let all = lines(VCardBuilder.make(content: severalPhones, url: nil))
        let tel = all.filter { $0.hasPrefix("TEL") }
        #expect(tel == [
            "TEL;TYPE=CELL:+998 90 123 45 67",
            "TEL;TYPE=WORK,VOICE:+998 71 200 10 20",
            "TEL;TYPE=HOME,VOICE:+998 71 255 33 44",
            "TEL;TYPE=VOICE:+998 33 400 00 00",
            "TEL;TYPE=CELL:+998 99 777 66 55",
        ])
        // Phones come first, before the email.
        #expect(all.firstIndex(of: "TEL;TYPE=CELL:+998 90 123 45 67")! < all.firstIndex(of: "EMAIL;TYPE=INTERNET:kamola@tezkor.uz")!)
    }

    @Test func primaryLabelDecidesTheFirstType() {
        var content = severalPhones
        content.phoneLabel = .work
        content.additionalPhones = []
        #expect(lines(VCardBuilder.make(content: content, url: nil)).contains("TEL;TYPE=WORK,VOICE:+998 90 123 45 67"))
    }

    @Test func neverWritesPrivateEmptyOrRepeatedNumbers() {
        var content = severalPhones
        content.additionalPhones = [
            LabeledPhone(label: .home, value: "+998 71 999 99 99", privacy: .private),
            LabeledPhone(label: .work, value: "  ", privacy: .public),
            LabeledPhone(label: .work, value: "+998901234567", privacy: .public),   // same digits as the primary
        ]
        let vcard = VCardBuilder.make(content: content, url: nil)
        #expect(!vcard.contains("999 99 99"))
        #expect(lines(vcard).filter { $0.hasPrefix("TEL") } == ["TEL;TYPE=CELL:+998 90 123 45 67"])
    }

    /// The card can hide its primary phone (Private) while a Public office number still goes out.
    @Test func writesExtrasWithoutAPrimary() {
        let content = CardFaceContent(fullName: "Aziza", fields: [], additionalPhones: [
            LabeledPhone(label: .work, value: "+998 71 200 10 20", privacy: .public),
        ])
        #expect(lines(VCardBuilder.make(content: content, url: nil)).contains("TEL;TYPE=WORK,VOICE:+998 71 200 10 20"))
    }

    @Test func roundTripsSeveralLabelledPhones() throws {
        let draft = try #require(VCardParser.parse(VCardBuilder.make(content: severalPhones, url: nil)))
        #expect(draft.fields.first { $0.kind == .phone }?.value == "+998 90 123 45 67")
        #expect(draft.phoneLabel == .mobile)
        #expect(draft.additionalPhones.map(\.label) == [.work, .home, .other, .mobile])
        #expect(draft.additionalPhones.map(\.value) == ["+998 71 200 10 20", "+998 71 255 33 44", "+998 33 400 00 00",
                                                        "+998 99 777 66 55"])
    }

    @Test func roundTripKeepsANonMobilePrimary() throws {
        var content = severalPhones
        content.phoneLabel = .work
        content.additionalPhones = [LabeledPhone(label: .home, value: "+998 71 255 33 44", privacy: .public)]
        let draft = try #require(VCardParser.parse(VCardBuilder.make(content: content, url: nil)))
        #expect(draft.phoneLabel == .work)
        #expect(draft.fields.first { $0.kind == .phone }?.value == "+998 90 123 45 67")
        #expect(draft.additionalPhones.map(\.label) == [.home])
    }

    @Test func firstMobileBecomesThePrimary() throws {
        let vcard = """
        BEGIN:VCARD
        VERSION:3.0
        FN:Jasur Aliev
        TEL;TYPE=WORK,VOICE:+998 71 200 00 00
        TEL;TYPE=HOME:+998 71 300 00 00
        TEL;TYPE=CELL:+998 90 555 44 33
        TEL;TYPE=CELL:+998 93 111 22 33
        END:VCARD
        """
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.fields.first { $0.kind == .phone }?.value == "+998 90 555 44 33")
        #expect(draft.phoneLabel == .mobile)
        #expect(draft.additionalPhones.map(\.value) == ["+998 71 200 00 00", "+998 71 300 00 00", "+998 93 111 22 33"])
        #expect(draft.additionalPhones.map(\.label) == [.work, .home, .mobile])
    }

    @Test func withoutAMobileThePreferredNumberLeads() throws {
        let vcard = """
        BEGIN:VCARD
        VERSION:3.0
        FN:Office
        TEL;TYPE=HOME:+998 71 300 00 00
        TEL;TYPE=WORK;TYPE=PREF:+998 71 200 00 00
        END:VCARD
        """
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.fields.first { $0.kind == .phone }?.value == "+998 71 200 00 00")
        #expect(draft.phoneLabel == .work)
        #expect(draft.additionalPhones.map(\.label) == [.home])
    }

    @Test func readsVCard21BareTypes() throws {
        let vcard = """
        BEGIN:VCARD
        VERSION:2.1
        N:Karimova;Dilnoza
        TEL;WORK;VOICE:+998712000000
        TEL;HOME;VOICE:+998713000000
        TEL;CELL:+998901112233
        TEL;WORK;FAX:+998712000001
        END:VCARD
        """
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.fields.first { $0.kind == .phone }?.value == "+998901112233")
        #expect(draft.additionalPhones.map(\.label) == [.work, .home])   // the fax is skipped
        #expect(draft.additionalPhones.map(\.value) == ["+998712000000", "+998713000000"])
    }

    @Test func readsAppleGroupedLabels() throws {
        let vcard = """
        BEGIN:VCARD
        VERSION:3.0
        FN:Bekzod Karimov
        item1.TEL;type=pref:+998 71 200 00 00
        item1.X-ABLabel:_$!<Work>!$_
        item2.X-ABLabel:моб.
        item2.TEL:+998 90 000 11 22
        item3.TEL:+998 71 300 00 00
        item3.X-ABLabel:Uy
        item4.TEL:+998 33 444 55 66
        item4.X-ABLabel:Beeline
        TEL;type=IPHONE;type=CELL;type=VOICE:+998 99 888 77 66
        item5.TEL:+998 71 200 00 09
        item5.X-ABLabel:_$!<WorkFAX>!$_
        END:VCARD
        """
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.fields.first { $0.kind == .phone }?.value == "+998 90 000 11 22")   // first mobile ("моб.")
        #expect(draft.phoneLabel == .mobile)
        #expect(draft.additionalPhones.map(\.value) == ["+998 71 200 00 00", "+998 71 300 00 00", "+998 33 444 55 66",
                                                        "+998 99 888 77 66"])
        #expect(draft.additionalPhones.map(\.label) == [.work, .home, .other, .mobile])
    }

    @Test func keepsAtMostFiveExtrasAndDropsDuplicates() throws {
        var vcard = "BEGIN:VCARD\nVERSION:3.0\nFN:Many\nTEL;TYPE=CELL:+998 90 000 00 00\nTEL:+998900000000\n"
        for index in 1...8 { vcard += "TEL;TYPE=WORK:+998 71 000 00 0\(index)\n" }
        vcard += "END:VCARD"
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.additionalPhones.count == VCardParser.maxAdditionalPhones)
        #expect(draft.additionalPhones.first?.value == "+998 71 000 00 01")
        #expect(!draft.additionalPhones.contains { $0.value == "+998900000000" })
    }

    static let labels: [(String, VCardPhoneLabel)] = [
        ("_$!<Mobile>!$_", .phone(.mobile)), ("Uyali telefon", .phone(.mobile)), ("Сотовый", .phone(.mobile)),
        ("Office", .phone(.work)), ("Ish", .phone(.work)), ("Рабочий", .phone(.work)), ("_$!<Main>!$_", .phone(.work)),
        ("_$!<Home>!$_", .phone(.home)), ("Домашний", .phone(.home)),
        ("_$!<Other>!$_", .phone(.other)), ("_$!<HomeFAX>!$_", .fax), ("_$!<WorkFAX>!$_", .fax), ("Факс", .fax),
    ]

    @Test(arguments: labels)
    func classifiesLabels(_ label: String, _ expected: VCardPhoneLabel) {
        #expect(VCardPhoneLabel.classify(label: label) == expected)
    }

    @Test func unknownCustomLabelsFallBackToTypes() {
        #expect(VCardPhoneLabel.classify(label: "Beeline") == nil)
        #expect(VCardPhoneLabel.classify(types: ["CELL"], customLabel: "Beeline") == .phone(.mobile))
        #expect(VCardPhoneLabel.classify(types: ["VOICE"], customLabel: nil) == .phone(.other))
        #expect(VCardPhoneLabel.classify(types: [], customLabel: nil) == .phone(.other))
        #expect(VCardPhoneLabel.classify(types: ["WORK", "FAX"], customLabel: nil) == .fax)
    }
}
