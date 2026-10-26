import Foundation
import MetlyCore
import Testing
@testable import MetlyCardKit

@Suite("VCardParser")
struct VCardParserTests {
    private func value(_ draft: PaperCardDraft, _ kind: ContactFieldKind) -> String? {
        draft.fields.first { $0.kind == kind }?.value
    }

    @Test func roundTripsBuiltVCard() throws {
        let vcard = VCardBuilder.make(content: .sample, url: URL(string: "https://tanishly.app/c/kamola-7f3k"))
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.fullName == "Kamola Rashidova")
        #expect(draft.jobTitle == "Product Designer")
        #expect(draft.company == "Tezkor")
        #expect(draft.fields.map(\.kind) == ContactFieldKind.allCases)
        #expect(value(draft, .phone) == "+998 90 123 45 67")
        #expect(value(draft, .email) == "kamola@tezkor.uz")
        #expect(value(draft, .telegram) == "@kamola.r")
        #expect(value(draft, .website) == "kamola.design")   // the tanishly.app card URL is not a website
        #expect(value(draft, .linkedin) == "in/kamolarashidova")
    }

    @Test func roundTripsEscapedAndFoldedValues() throws {
        let content = CardFaceContent(fullName: "Ann\\Marie O'Neil, Jr.",
                                      jobTitle: "Head of R&D; Platform, Payments and Long Titles That Need Folding",
                                      company: "Acme, Inc; Labs — Ўзбекистон 😀")
        let draft = try #require(VCardParser.parse(VCardBuilder.make(content: content, url: nil)))
        #expect(draft.fullName == content.fullName)
        #expect(draft.jobTitle == content.jobTitle)
        #expect(draft.company == content.company)
    }

    @Test func unfoldsFoldedLines() throws {
        let vcard = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Dilnoza\r\n  Yusupova\r\nEMAIL:dilnoza@exa\r\n\tmple.com\r\nEND:VCARD\r\n"
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.fullName == "Dilnoza Yusupova")
        #expect(value(draft, .email) == "dilnoza@example.com")
    }

    @Test func buildsNameFromNWhenFNIsMissing() throws {
        let vcard = "BEGIN:VCARD\nVERSION:3.0\nN:Karimov;Bekzod;;Dr.;\nORG:Uzcard;Payments\nEND:VCARD"
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.fullName == "Dr. Bekzod Karimov")
        #expect(draft.company == "Uzcard")
    }

    @Test func readsGroupsSocialProfilesAndLowercaseNames() throws {
        let vcard = """
        begin:vcard
        version:3.0
        fn:Jasur Aliev
        title:CTO
        tel;type=work:+998 71 200 00 00
        tel;type=cell,voice:+998 90 555 44 33
        email;type=internet;type=pref:jasur@startup.uz
        item1.URL:https://t.me/jasur_dev
        item1.X-ABLabel:Telegram
        X-SOCIALPROFILE;type=linkedin:https://www.linkedin.com/in/jasuraliev/
        URL;type=WORK:https://www.startup.uz/
        end:vcard
        """
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.fullName == "Jasur Aliev")
        #expect(draft.jobTitle == "CTO")
        #expect(value(draft, .phone) == "+998 90 555 44 33")   // mobile preferred over work
        #expect(value(draft, .email) == "jasur@startup.uz")
        #expect(value(draft, .telegram) == "@jasur_dev")
        #expect(value(draft, .linkedin) == "in/jasuraliev")
        #expect(value(draft, .website) == "startup.uz")
    }

    @Test func readsVCard21QuotedPrintable() throws {
        let vcard = """
        BEGIN:VCARD
        VERSION:2.1
        FN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:=D0=90=D0=B7=D0=B8=D0=B7=D0=B0 =D0=9A=D0=B0=
        =D1=80=D0=B8=D0=BC=D0=BE=D0=B2=D0=B0
        TEL;CELL:+998901112233
        END:VCARD
        """
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.fullName == "Азиза Каримова")
        #expect(value(draft, .phone) == "+998901112233")
    }

    @Test func readsVCard4URIsAndTelegramVariants() throws {
        let vcard = """
        BEGIN:VCARD
        VERSION:4.0
        FN:Malika
        TEL;VALUE=uri;TYPE=cell:tel:+998-93-000-11-22
        EMAIL:mailto:malika@mail.uz
        IMPP:telegram:malika_m
        END:VCARD
        """
        let draft = try #require(VCardParser.parse(vcard))
        #expect(value(draft, .phone) == "+998-93-000-11-22")
        #expect(value(draft, .email) == "malika@mail.uz")
        #expect(value(draft, .telegram) == "@malika_m")
    }

    @Test(arguments: ["https://example.com", "", "BEGIN:VCARD\nVERSION:3.0\nEND:VCARD", "FN:No envelope"])
    func rejectsNonVCardsAndEmptyCards(_ text: String) {
        #expect(VCardParser.parse(text) == nil)
    }

    @Test func readsOnlyTheFirstCard() throws {
        let vcard = "BEGIN:VCARD\nFN:First\nEND:VCARD\nBEGIN:VCARD\nFN:Second\nEND:VCARD"
        let draft = try #require(VCardParser.parse(vcard))
        #expect(draft.fullName == "First")
    }

    @Test func splitsPropertyLine() throws {
        let property = try #require(VCardProperty(line: "item2.X-SOCIALPROFILE;TYPE=telegram;X-USER=a_b:https://t.me/a_b"))
        #expect(property.group == "item2")
        #expect(property.name == "X-SOCIALPROFILE")
        #expect(property.types == ["TELEGRAM"])
        #expect(property.parameters["X-USER"] == ["a_b"])
        #expect(property.value == "https://t.me/a_b")
    }
}
