import Foundation
import MetlyCore
import Testing
@testable import FeatureScan

/// Realistic OCR output (line order as Vision returns it) from Uzbek, Russian and English cards.
@Suite("Paper card line classification")
struct PaperCardParserTests {
    private func value(_ draft: PaperCardDraft, _ kind: ContactFieldKind) -> String? {
        draft.fields.first { $0.kind == kind }?.value
    }

    @Test("Modern card: name, title, company, every contact kind")
    func modernCard() {
        let draft = PaperCardParser.parse(text: [
            "Aziza Karimova",
            "Product Designer",
            "Tezkor",
            "+998 90 123 45 67",
            "aziza@tezkor.uz",
            "@aziza.k",
            "tezkor.uz",
            "linkedin.com/in/azizakarimova",
        ])
        #expect(draft.fullName == "Aziza Karimova")
        #expect(draft.jobTitle == "Product Designer")
        #expect(draft.company == "Tezkor")
        #expect(value(draft, .phone) == "+998 90 123 45 67")
        #expect(value(draft, .email) == "aziza@tezkor.uz")
        #expect(value(draft, .telegram) == "@aziza.k")
        #expect(value(draft, .website) == "tezkor.uz")
        #expect(value(draft, .linkedin) == "in/azizakarimova")
        #expect(draft.fields.map(\.kind) == [.phone, .email, .telegram, .website, .linkedin])
    }

    @Test("Russian card: patronymic, ООО company, labelled numbers, mobile preferred, address ignored")
    func russianCard() {
        let draft = PaperCardParser.parse(text: [
            "ООО «Узум Маркет»",
            "Иванов Сергей Петрович",
            "Генеральный директор",
            "Тел.: +998 (71) 200-00-00",
            "Моб.: +998 93 555 12 34",
            "E-mail: S.Ivanov@uzum.uz",
            "www.uzum.uz",
            "г. Ташкент, ул. Амира Темура, 108",
        ])
        #expect(draft.fullName == "Иванов Сергей Петрович")
        #expect(draft.jobTitle == "Генеральный директор")
        #expect(draft.company == "ООО «Узум Маркет»")
        #expect(value(draft, .phone) == "+998 93 555 12 34")
        #expect(value(draft, .email) == "s.ivanov@uzum.uz")
        #expect(value(draft, .website) == "uzum.uz")
    }

    @Test("Uzbek card in capitals: apostrophe surname, Uzbek title, t.me link, logo company")
    func uzbekCapsCard() {
        let draft = PaperCardParser.parse(text: [
            "PAYME",
            "SHOXRUH ABDUG'ANIYEV",
            "Bosh dasturchi",
            "Tel: +998901112233",
            "t.me/shoxruh_dev",
            "shoxruh@payme.uz",
        ])
        #expect(draft.fullName == "Shoxruh Abdug'aniyev")
        #expect(draft.jobTitle == "Bosh dasturchi")
        #expect(draft.company == "PAYME")
        #expect(value(draft, .phone) == "+998 90 111 22 33")
        #expect(value(draft, .telegram) == "@shoxruh_dev")
        #expect(value(draft, .email) == "shoxruh@payme.uz")
    }

    @Test("\"CTO at Payme\" splits into title and company; Telegram label; Gmail isn't a company")
    func combinedRoleLine() {
        let draft = PaperCardParser.parse(text: [
            "Sardor Rashidov",
            "CTO at Payme",
            "Telegram: sardor_r",
            "sardor.rashidov@gmail.com",
            "+998 (97) 765-43-21",
        ])
        #expect(draft.fullName == "Sardor Rashidov")
        #expect(draft.jobTitle == "CTO")
        #expect(draft.company == "Payme")
        #expect(value(draft, .telegram) == "@sardor_r")
        #expect(value(draft, .email) == "sardor.rashidov@gmail.com")
        #expect(value(draft, .phone) == "+998 97 765 43 21")
    }

    @Test("English card: T:/E:/W: labels, legal form, Instagram skipped, international number")
    func englishLabelledCard() {
        let draft = PaperCardParser.parse(text: [
            "JOHN SMITH",
            "Head of Partnerships",
            "Silk Road Ventures LLC",
            "T: +1 (415) 555-0123",
            "E: john@silkroad.vc",
            "W: silkroad.vc",
            "Instagram: @silkroad",
        ])
        #expect(draft.fullName == "John Smith")
        #expect(draft.jobTitle == "Head of Partnerships")
        #expect(draft.company == "Silk Road Ventures LLC")
        #expect(value(draft, .phone) == "+1 (415) 555-0123")
        #expect(value(draft, .email) == "john@silkroad.vc")
        #expect(value(draft, .website) == "silkroad.vc")
        #expect(value(draft, .telegram) == nil)
    }

    @Test("Type size picks the name; the big logo word is the company")
    func heightRanking() {
        let draft = PaperCardParser.parse([
            OCRLine("UZUM", height: 0.12),
            OCRLine("Kamila Yusupova", height: 0.08),
            OCRLine("Head of Partnerships", height: 0.04),
            OCRLine("kamila@uzum.uz", height: 0.03),
            OCRLine("https://t.me/kamila_y", height: 0.03),
        ])
        #expect(draft.fullName == "Kamila Yusupova")
        #expect(draft.jobTitle == "Head of Partnerships")
        #expect(draft.company == "UZUM")
        #expect(value(draft, .telegram) == "@kamila_y")
    }

    @Test("Separators on one line, city line ignored, fallback company")
    func separatorsAndAddress() {
        let draft = PaperCardParser.parse(text: [
            "Madina Alieva",
            "Product Manager",
            "Click",
            "+998 90 000 11 22 | madina@click.uz",
            "Tashkent, Uzbekistan",
        ])
        #expect(draft.fullName == "Madina Alieva")
        #expect(draft.jobTitle == "Product Manager")
        #expect(draft.company == "Click")
        #expect(value(draft, .phone) == "+998 90 000 11 22")
        #expect(value(draft, .email) == "madina@click.uz")
    }

    @Test("Uzbek patronymic and a fax number that must not become the phone")
    func patronymicAndFax() {
        let draft = PaperCardParser.parse(text: [
            "Karimov Akmal Rustam o'g'li",
            "Bo'lim boshlig'i",
            "Faks: +998 71 140 00 01",
            "Mob +998 99 812 34 56",
        ])
        #expect(draft.fullName == "Karimov Akmal Rustam o'g'li")
        #expect(value(draft, .phone) == "+998 99 812 34 56")
    }

    @Test("Low-confidence lines are ignored")
    func lowConfidence() {
        let draft = PaperCardParser.parse([
            OCRLine("Jasur Akhmedov", confidence: 1),
            OCRLine("Xqzt Lmnop", confidence: 0.1),
            OCRLine("jasur@workly.uz", confidence: 0.9),
        ])
        #expect(draft.fullName == "Jasur Akhmedov")
        #expect(draft.company.isEmpty)
    }

    @Test("Noise yields an unreadable draft (ALERT_PAPER_NOT_READ)")
    func unreadable() {
        let draft = PaperCardParser.parse(text: ["", "©", "~~~", "12", "Tashkent"])
        #expect(!draft.isReadable)
        #expect(draft.fields.isEmpty)
        #expect(draft.detectedFieldCount == 0)
    }

    @Test("Detected field count and hints")
    func hints() {
        let draft = PaperCardParser.parse(text: ["Aziza Karimova", "Product Designer", "+998 90 123 45 67", "aziza@tezkor.uz"])
        #expect(draft.isReadable)
        #expect(draft.detectedFieldCount == 4)
        let hints = PaperFieldHint.assess(draft)
        #expect(hints[.name] == .guessed)
        #expect(hints[.title] == .guessed)
        #expect(hints[.phone] == .detected)
        #expect(hints[.email] == .detected)
        #expect(hints[.company] == nil)
    }

    @Test("Phone formatting", arguments: [
        ("+998901234567", "+998 90 123 45 67"),
        ("+998 (71) 200-00-00", "+998 71 200 00 00"),
        ("998 93 555 12 34", "+998 93 555 12 34"),
        ("(90) 123-45-67", "(90) 123-45-67"),
        ("+1  (415)  555-0123", "+1 (415) 555-0123"),
    ])
    func phoneFormat(raw: String, expected: String) {
        #expect(PhoneFormat.display(raw) == expected)
    }

    @Test("Uzbek mobile detection")
    func uzbekMobile() {
        #expect(PhoneFormat.isUzbekMobile("+998 93 555 12 34"))
        #expect(PhoneFormat.isUzbekMobile("90 123 45 67"))
        #expect(!PhoneFormat.isUzbekMobile("+998 71 200 00 00"))
        #expect(!PhoneFormat.isUzbekMobile("+1 415 555 0123"))
    }

    @Test func readsTheCompanyAddress() {
        let draft = PaperCardParser.parse(text: [
            "Aziza Karimova", "Product Designer", "Tezkor", "+998 90 123 45 67",
            "Amir Temur ko‘chasi 108", "Toshkent",
        ])
        #expect(draft.fullName == "Aziza Karimova")
        #expect(draft.fields.first { $0.kind == .address }?.value == "Amir Temur ko‘chasi 108, Toshkent")
    }

    @Test func aLoneCityIsNotAnAddress() {
        let draft = PaperCardParser.parse(text: ["Aziza Karimova", "Tezkor", "+998 90 123 45 67", "Toshkent"])
        #expect(!draft.fields.contains { $0.kind == .address })
    }

}
