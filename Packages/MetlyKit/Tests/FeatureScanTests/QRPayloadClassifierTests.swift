import Foundation
import Testing
@testable import FeatureScan

@Suite("QR payload classification")
struct QRPayloadClassifierTests {
    private let kamila = QRPayload.metlyCard(url: URL(string: "https://metly.link/c/kamila-x1y2")!, slug: "kamila-x1y2")

    @Test("Metly card links in every spelling", arguments: [
        "https://metly.link/c/kamila-x1y2",
        "http://metly.link/c/kamila-x1y2",
        "metly.link/c/kamila-x1y2",
        "https://www.metly.link/c/kamila-x1y2",
        "HTTPS://METLY.LINK/C/KAMILA-X1Y2",
        "https://metly.link/c/kamila-x1y2/?src=qr",
        "  https://metly.link/c/kamila-x1y2\n",
        "metly://c/kamila-x1y2",
    ])
    func metlyLinks(raw: String) {
        #expect(QRPayloadClassifier.classify(raw) == kamila)
    }

    @Test("The owner's own card is recognised")
    func ownCard() {
        let own: Set = ["aziza-w7k2", "aziza-p3x9"]
        #expect(QRPayloadClassifier.classify("https://metly.link/c/aziza-w7k2", ownSlugs: own) == .ownCard(slug: "aziza-w7k2"))
        #expect(QRPayloadClassifier.classify("METLY.LINK/C/AZIZA-P3X9", ownSlugs: own) == .ownCard(slug: "aziza-p3x9"))
        #expect(QRPayloadClassifier.classify("https://metly.link/c/kamila-x1y2", ownSlugs: own) == kamila)
    }

    @Test("vCards are passed through untouched")
    func vCard() {
        let card = "BEGIN:VCARD\r\nVERSION:3.0\r\nFN:Jane Doe\r\nTEL;TYPE=CELL:+998901234567\r\nEND:VCARD"
        #expect(QRPayloadClassifier.classify(card) == .vCard(card))
        #expect(QRPayloadClassifier.classify("begin:vcard\nFN:Jane\nend:vcard") == .vCard("begin:vcard\nFN:Jane\nend:vcard"))
    }

    @Test("Other web links offer Safari", arguments: [
        ("https://example.com/page?x=1", "example.com"),
        ("HTTP://WWW.UZUM.UZ", "uzum.uz"),
        ("www.payme.uz", "payme.uz"),
        ("example.org/menu", "example.org"),
        ("https://metly.link/pricing", "metly.link"),
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
        "MECARD:N:Doe,John;TEL:123;;",
        "ftp://files.example.com/card.vcf",
        "12345",
        "   ",
    ])
    func other(raw: String) {
        #expect(QRPayloadClassifier.classify(raw) == .other)
    }
}
