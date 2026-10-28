import Foundation
import MetlyCore
import Testing
@testable import FeatureScan

/// Every corpus card must read fully correctly with the heuristics alone (no model): name, title,
/// company, every phone with its label, email, Telegram and website.
@Suite("Paper card corpus (heuristics)")
struct PaperCorpusTests {
    static func lines(_ sample: PaperCardSample) -> [OCRLine] {
        sample.lines.map { OCRLine($0.text, height: $0.height, frame: $0.frame) }
    }

    private func value(_ draft: PaperCardDraft, _ kind: ContactFieldKind) -> String {
        draft.fields.first { $0.kind == kind }?.value ?? ""
    }

    @Test("Reads the card", arguments: PaperCardCorpus.samples)
    func reads(_ sample: PaperCardSample) {
        let draft = PaperCardParser.parse(Self.lines(sample))
        #expect(draft.fullName == sample.fullName)
        #expect(draft.jobTitle == sample.jobTitle)
        #expect(draft.company == sample.company)
        let phones = ([value(draft, .phone)].filter { !$0.isEmpty }.map { ($0, draft.phoneLabel) })
            + draft.additionalPhones.map { ($0.value, $0.label) }
        #expect(phones.map(\.0) == sample.phones.map(\.0))
        #expect(phones.map(\.1) == sample.phones.map(\.1))
        #expect(value(draft, .email) == sample.email)
        #expect(value(draft, .telegram) == sample.telegram)
        #expect(value(draft, .website) == sample.website)
    }

    @Test("Two-column cards are read column by column")
    func readingOrder() throws {
        let sample = try #require(PaperCardCorpus.samples.first { $0.name.hasPrefix("Two columns") })
        let ordered = PaperLayout.readingOrder(Self.lines(sample)).map(\.text)
        #expect(ordered == ["UZUM", "Kamila Yusupova", "Head of Partnerships",
                            "+998 90 555 12 34", "+998 71 203 00 00", "kamila@uzum.com", "uzum.com"])
    }

    @Test("Stacked lines without a gutter keep Vision's order")
    func stackedOrder() {
        let lines = [
            OCRLine("A", frame: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.05)),
            OCRLine("B", frame: CGRect(x: 0.1, y: 0.2, width: 0.6, height: 0.05)),
            OCRLine("C", frame: CGRect(x: 0.1, y: 0.3, width: 0.4, height: 0.05)),
            OCRLine("D", frame: CGRect(x: 0.1, y: 0.4, width: 0.7, height: 0.05)),
        ]
        #expect(PaperLayout.readingOrder(lines).map(\.text) == ["A", "B", "C", "D"])
    }

    @Test("Big brand at the top is the company; the name below it is the name")
    func brandOnTop() {
        let draft = PaperCardParser.parse([
            OCRLine("GRAND LUX", height: 0.11), OCRLine("Davron Rahim", height: 0.06), OCRLine("+998 95 145 67 89"),
        ])
        #expect(draft.fullName == "Davron Rahim")
        #expect(draft.company == "GRAND LUX")
    }

    @Test("A slogan is neither title nor company")
    func tagline() {
        let draft = PaperCardParser.parse(text: ["ARTEL", "Your trusted partner in every home", "Dilnoza Yusupova", "+998 93 555 12 34"])
        #expect(draft.fullName == "Dilnoza Yusupova")
        #expect(draft.jobTitle.isEmpty)
        #expect(draft.company == "ARTEL")
    }

    @Test("A line equal to the email domain is the company even when it looks like a name")
    func domainCompany() {
        let draft = PaperCardParser.parse(text: ["Grand Hotel", "Bekzod Toshev", "info@grandhotel.uz"])
        #expect(draft.company == "Grand Hotel")
        #expect(draft.fullName == "Bekzod Toshev")
    }

    @Test("Strong evidence makes a role confident (no “?” hint)")
    func confidence() {
        let scan = PaperCardParser.analyze([
            OCRLine("TEZKOR MCHJ", height: 0.08), OCRLine("Aziza Karimova", height: 0.06), OCRLine("Product Designer"),
        ]).scan
        #expect(scan.confidentFields == [.name, .title, .company])
        let hints = PaperFieldHint.assess(scan.draft, confident: scan.confidentFields)
        #expect(hints[.name] == .detected)

        let vague = PaperCardParser.analyze([OCRLine("Bobo Tosh"), OCRLine("+998 90 111 22 33")]).scan
        #expect(vague.draft.fullName == "Bobo Tosh")
        #expect(!vague.confidentFields.contains(.name))
    }
}
