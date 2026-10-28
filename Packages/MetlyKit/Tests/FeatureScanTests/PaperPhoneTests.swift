import Foundation
import MetlyCore
import Testing
@testable import FeatureScan

/// Every number on the card, with its label (printed in English / Russian / Uzbek, or guessed
/// from the prefix), extensions and fax numbers dropped, the first mobile as the primary.
@Suite("Paper card phone numbers")
struct PaperPhoneTests {
    private func phones(_ lines: [String]) -> [(String, PhoneLabel)] {
        var contacts = PaperContacts()
        let extractor = PaperContactExtractor()
        for line in lines {
            _ = extractor.extract(from: line, into: &contacts)
        }
        return contacts.phones.map { ($0.value, $0.label) }
    }

    @Test("Printed labels", arguments: [
        ("Mob: +998 93 555 12 34", PhoneLabel.mobile),
        ("Mobile +1 917 555 0199", .mobile),
        ("Cell: +1 917 555 0199", .mobile),
        ("Моб.: +998 (90) 350-12-34", .mobile),
        ("Сот.: +998 97 444 55 66", .mobile),
        ("Uyali: +998 99 100 20 30", .mobile),
        ("Ish: +998 71 200 00 00", .work),
        ("Office: +1 212 555 0100", .work),
        ("Work: +998 90 111 22 33", .work),
        ("Раб.: +7 (495) 123-45-67", .work),
        ("Офис: +998 71 120 00 00", .work),
        ("Uy: +998 71 255 33 44", .home),
        ("Home: +1 415 555 0101", .home),
        ("Дом.: +998 71 255 33 44", .home),
        ("Tel/Fax: +998 71 140 00 01", .work),
    ])
    func printedLabel(line: String, label: PhoneLabel) {
        #expect(phones([line]).map(\.1) == [label])
    }

    @Test("Generic or no label: the prefix decides", arguments: [
        ("Tel: +998 90 123 45 67", PhoneLabel.mobile),
        ("Tel: +998 71 200 00 00", .work),
        ("Тел.: +998 (55) 501-00-00", .work),
        ("T: +1 (415) 555-0123", .work),
        ("+998 88 200 30 40", .mobile),
        ("+998 33 123 45 67", .mobile),
        ("+998 20 123 45 67", .mobile),
        ("+998 77 123 45 67", .mobile),
        ("+998 71 233 33 33", .work),
        ("+998 55 501 00 00", .work),
        ("(94) 600-70-80", .mobile),
        ("+7 916 765 43 21", .mobile),
        ("+7 (727) 250-00-00", .work),
        ("+7 777 123 45 67", .mobile),
        ("+1 415 555 0123", .mobile),
    ])
    func inferredLabel(line: String, label: PhoneLabel) {
        #expect(phones([line]).map(\.1) == [label])
    }

    @Test("Labels written after the number; fax skipped")
    func postfixLabels() {
        let found = phones(["+998 90 123 45 67 (mob.)", "+998 71 234 56 78 (ish)", "+998 71 234 56 79 (faks)",
                            "+998 71 234 56 70 моб"])
        #expect(found.map(\.0) == ["+998 90 123 45 67", "+998 71 234 56 78", "+998 71 234 56 70"])
        #expect(found.map(\.1) == [.mobile, .work, .mobile])
    }

    @Test("Two labelled numbers on one line")
    func twoOnOneLine() {
        let found = phones(["Tel: +998 71 207 00 00, Mob: +998 90 909 09 09"])
        #expect(found.map(\.0) == ["+998 71 207 00 00", "+998 90 909 09 09"])
        #expect(found.map(\.1) == [.work, .mobile])

        let sameLabel = phones(["Tel: +998 71 200 00 00, +998 71 200 00 01"])
        #expect(sameLabel.map(\.1) == [.work, .work])
    }

    @Test("Extensions are dropped, never glued to the number or read as another one", arguments: [
        ("Тел.: +998 (71) 120-45-00 доб. 210", "+998 71 120 45 00"),
        ("Tel: +998 71 120 45 00, доб. 210", "+998 71 120 45 00"),
        ("Office: +1 212 555 0100 ext. 12", "+1 212 555 0100"),
        ("+998 71 120 45 00 вн. 3", "+998 71 120 45 00"),
    ])
    func extensions(line: String, number: String) {
        #expect(phones([line]).map(\.0) == [number])
    }

    @Test("Fax numbers are skipped")
    func fax() {
        #expect(phones(["Факс: +998 71 200 00 01", "Fax +1 212 555 0101", "F: +998 71 140 00 01"]).isEmpty)
    }

    @Test("The same number twice is kept once; a printed label beats a guess")
    func duplicates() {
        let found = phones(["+998 71 200 00 00", "Mob: +998 71 200 00 00"])
        #expect(found.count == 1)
        #expect(found.first?.1 == .mobile)
    }

    @Test("Draft: the first mobile is the phone, the rest are additional phones in card order")
    func draftPhones() {
        let draft = PaperCardParser.parse(text: ["Rustam Nazarov", "Office: +998 71 234 56 78", "Home: +998 71 255 33 44",
                                                 "Mob: +998 90 123 45 67", "Mob: +998 91 765 43 21"])
        #expect(draft.fields.first { $0.kind == .phone }?.value == "+998 90 123 45 67")
        #expect(draft.phoneLabel == .mobile)
        #expect(draft.additionalPhones.map(\.value) == ["+998 71 234 56 78", "+998 71 255 33 44", "+998 91 765 43 21"])
        #expect(draft.additionalPhones.map(\.label) == [.work, .home, .mobile])
        #expect(draft.detectedFieldCount == 5)
    }

    @Test("Without a mobile the first number is the phone, with its label")
    func noMobile() {
        let draft = PaperCardParser.parse(text: ["Rustam Nazarov", "Ish: +998 71 234 56 78", "Uy: +998 71 255 33 44"])
        #expect(draft.fields.first { $0.kind == .phone }?.value == "+998 71 234 56 78")
        #expect(draft.phoneLabel == .work)
        #expect(draft.additionalPhones.map(\.label) == [.home])
    }
}
