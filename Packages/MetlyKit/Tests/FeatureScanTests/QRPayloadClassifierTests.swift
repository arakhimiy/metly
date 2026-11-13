import Foundation
import MetlyCardKit
import MetlyCore
import Testing
@testable import FeatureScan

@Suite("QR payload classification")
struct QRPayloadClassifierTests {
    private let kamila = QRPayload.metlyCard(url: URL(string: "https://tanishly.app/c/kamila-x1y2")!, slug: "kamila-x1y2")

    @Test("Nameshake card links in every spelling", arguments: [
        "https://tanishly.app/c/kamila-x1y2",
        "http://tanishly.app/c/kamila-x1y2",
        "tanishly.app/c/kamila-x1y2",
        "https://www.tanishly.app/c/kamila-x1y2",
        "HTTPS://TANISHLY.APP/C/KAMILA-X1Y2",
        "https://tanishly.app/c/kamila-x1y2/?src=qr",
        "  https://tanishly.app/c/kamila-x1y2\n",
        "tanishly://c/kamila-x1y2",
    ])
    func metlyLinks(raw: String) {
        #expect(QRPayloadClassifier.classify(raw) == kamila)
    }

    @Test("Only cards count as cards (a paper card's website QR is ignored while framing it)")
    func onlyCardsAreCards() {
        #expect(kamila.isCard)
        #expect(QRPayload.ownCard(slug: "me").isCard)
        #expect(QRPayload.vCard("BEGIN:VCARD").isCard)
        #expect(!QRPayload.webLink(URL(string: "https://example.com")!).isCard)
        #expect(!QRPayload.other.isCard)
    }

    @Test("The owner's own card is recognised")
    func ownCard() {
        let own: Set = ["aziza-w7k2", "aziza-p3x9"]
        #expect(QRPayloadClassifier.classify("https://tanishly.app/c/aziza-w7k2", ownSlugs: own) == .ownCard(slug: "aziza-w7k2"))
        #expect(QRPayloadClassifier.classify("TANISHLY.APP/C/AZIZA-P3X9", ownSlugs: own) == .ownCard(slug: "aziza-p3x9"))
        #expect(QRPayloadClassifier.classify("https://tanishly.app/c/kamila-x1y2", ownSlugs: own) == kamila)
    }

    @Test("vCards are passed through untouched")
    func vCard() {
        let card = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Jane Doe\r\nTEL;TYPE=CELL:+998901234567\r\nEND:VCARD"
        #expect(QRPayloadClassifier.classify(card) == .vCard(card))
        #expect(QRPayloadClassifier.classify("begin:vcard\nFN:Jane\nend:vcard") == .vCard("begin:vcard\nFN:Jane\nend:vcard"))
    }

    /// Regression: MECARD business-card QR codes were answered with "No Business Card Found".
    @Test("MECARD contact codes open as a contact card")
    func meCard() throws {
        let raw = "MECARD:N:Yusupova,Kamila;ORG:Uzum Market;TITLE:Head of Partnerships;TEL:+998901234567;"
            + "EMAIL:kamila@uzum.uz;URL:https\\://uzum.uz;NOTE:Met at TTW;;"
        guard case .vCard(let text) = QRPayloadClassifier.classify(raw) else {
            Issue.record("Expected a contact card, got \(QRPayloadClassifier.classify(raw))")
            return
        }
        let contact = try #require(VCardParser.parse(text))
        #expect(contact.fullName == "Kamila Yusupova")
        #expect(contact.company == "Uzum Market")
        #expect(contact.jobTitle == "Head of Partnerships")
        #expect(contact.fields.first { $0.kind == .phone }?.value == "+998901234567")
        #expect(contact.fields.first { $0.kind == .email }?.value == "kamila@uzum.uz")
        #expect(contact.fields.first { $0.kind == .website }?.value == "uzum.uz")
    }

    @Test("MECARD: lower-case prefix, a name without a comma, escaped separators")
    func meCardEscapes() throws {
        let raw = "mecard:N:Dilshod Rakhimov;ORG:Rakhimov\\; Sons;TEL:+998 90 987 65 43;;"
        guard case .vCard(let text) = QRPayloadClassifier.classify(raw) else {
            Issue.record("Expected a contact card")
            return
        }
        let contact = try #require(VCardParser.parse(text))
        #expect(contact.fullName == "Dilshod Rakhimov")
        #expect(contact.company == "Rakhimov; Sons")
        #expect(contact.fields.first { $0.kind == .phone }?.value == "+998 90 987 65 43")
    }

    @Test("Other web links offer Safari", arguments: [
        ("https://example.com/page?x=1", "example.com"),
        ("HTTP://WWW.UZUM.UZ", "uzum.uz"),
        ("www.payme.uz", "payme.uz"),
        ("example.org/menu", "example.org"),
        ("https://tanishly.app/pricing", "tanishly.app"),
    ])
    func webLinks(raw: String, domain: String) {
        let result = QRPayloadClassifier.classify(raw)
        guard case .webLink = result else {
            Issue.record("Expected a web link, got \(result)")
            return
        }
        #expect(result.displayDomain == domain)
    }

    @Test("Anything else is not a card", arguments: [
        "Hello there",
        "WIFI:S:Cafe;T:WPA;P:secret;;",
        "tel:+998901234567",
        "aziza@tezkor.uz",
        "ftp://files.example.com/card.vcf",
        "12345",
        "   ",
    ])
    func other(raw: String) {
        #expect(QRPayloadClassifier.classify(raw) == .other)
    }
}
