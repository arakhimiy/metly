import Foundation
import MetlyCore
import Testing
import UIKit
@testable import MetlyCardKit

@Suite("VCardBuilder")
struct VCardBuilderTests {
    private let cardURL = URL(string: "https://tanishly.app/c/kamola-7f3k")!

    private func lines(_ vcard: String) -> [String] {
        VCardText.unfold(vcard).split(separator: "\n").map(String.init)
    }

    @Test func writesVCard30WithCRLF() {
        let vcard = VCardBuilder.make(content: .sample, url: cardURL)
        #expect(vcard.hasPrefix("BEGIN:VCARD\r\nVERSION:3.0\r\n"))
        #expect(vcard.hasSuffix("END:VCARD\r\n"))
        #expect(!vcard.replacing("\r\n", with: "").contains("\n"))
    }

    @Test func writesNameOrganisationAndContacts() {
        let all = lines(VCardBuilder.make(content: .sample, url: cardURL))
        #expect(all.contains("N:Rashidova;Kamola;;;"))
        #expect(all.contains("FN:Kamola Rashidova"))
        #expect(all.contains("ORG:Tezkor"))
        #expect(all.contains("TITLE:Product Designer"))
        #expect(all.contains("TEL;TYPE=CELL:+998 90 123 45 67"))
        #expect(all.contains("EMAIL;TYPE=INTERNET:kamola@tezkor.uz"))
        #expect(all.contains("URL:https://kamola.design"))
    }

    @Test func writesTelegramAsSocialProfileAndURL() {
        let all = lines(VCardBuilder.make(content: .sample, url: nil))
        #expect(all.contains("X-SOCIALPROFILE;TYPE=telegram;X-USER=kamola.r:https://t.me/kamola.r"))
        #expect(all.contains("item1.URL:https://t.me/kamola.r"))
        #expect(all.contains("item1.X-ABLabel:Telegram"))
    }

    @Test func writesLinkedInAndCardLinkAsLabelledURLs() {
        let all = lines(VCardBuilder.make(content: .sample, url: cardURL))
        #expect(all.contains("item2.URL:https://www.linkedin.com/in/kamolarashidova"))
        #expect(all.contains("item2.X-ABLabel:LinkedIn"))
        #expect(all.contains("item3.URL:https://tanishly.app/c/kamola-7f3k"))
        #expect(all.contains("item3.X-ABLabel:\(Brand.appName)"))
    }

    @Test func escapesTextValues() {
        let content = CardFaceContent(fullName: "Ann\\Marie Smith, Jr.", jobTitle: "R&D; Lead\nPlatform",
                                      company: "Acme, Inc; Labs")
        let all = lines(VCardBuilder.make(content: content, url: nil))
        #expect(all.contains("FN:Ann\\\\Marie Smith\\, Jr."))
        #expect(all.contains("N:Smith\\, Jr.;Ann\\\\Marie;;;"))
        #expect(all.contains("TITLE:R&D\\; Lead\\nPlatform"))
        #expect(all.contains("ORG:Acme\\, Inc\\; Labs"))
    }

    @Test func escapeAndUnescapeAreInverse() {
        let samples = ["plain", "a,b;c\\d", "line1\nline2", "crlf\r\nend", "trailing\\"]
        for sample in samples {
            #expect(VCardText.unescape(VCardText.escape(sample)) == sample.replacing("\r\n", with: "\n"))
        }
    }

    @Test func neverWritesPrivateFields() {
        let content = CardFaceContent(fullName: "Ali Valiyev", fields: [
            ContactField(kind: .phone, value: "+998 99 000 00 00", privacy: .private),
            ContactField(kind: .email, value: "ali@example.com", privacy: .public),
        ])
        let vcard = VCardBuilder.make(content: content, url: nil)
        #expect(!vcard.contains("TEL"))
        #expect(vcard.contains("EMAIL;TYPE=INTERNET:ali@example.com"))
    }

    @Test func foldsLongLinesAt75Octets() {
        let longName = String(repeating: "Ўзбекистон ", count: 12) + "😀 end"
        let content = CardFaceContent(fullName: longName, company: String(repeating: "Company ", count: 20))
        let vcard = VCardBuilder.make(content: content, url: nil)
        let physical = vcard.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        #expect(physical.allSatisfy { $0.utf8.count <= 75 })
        #expect(physical.contains { $0.hasPrefix(" ") })
        // Unfolding restores the logical line exactly (no broken multi-byte characters).
        #expect(lines(vcard).contains("FN:\(longName.trimmingCharacters(in: .whitespaces))"))
    }

    @Test func foldKeepsShortLinesUntouched() {
        #expect(VCardText.fold("FN:Short") == "FN:Short")
        let exact = String(repeating: "a", count: 75)
        #expect(VCardText.fold(exact) == exact)
        #expect(VCardText.fold(exact + "b") == exact + "\r\n b")
    }

    @Test func omitsPhotoByDefault() throws {
        var content = CardFaceContent.sample
        content.photoData = Self.samplePNG()
        #expect(!VCardBuilder.make(content: content, url: nil).contains("PHOTO"))
    }

    @Test func includesSmallJPEGPhotoWhenRequested() throws {
        var content = CardFaceContent.sample
        content.photoData = Self.samplePNG()
        let photoLine = try #require(lines(VCardBuilder.make(content: content, url: nil, includePhoto: true))
            .first { $0.hasPrefix("PHOTO;ENCODING=b;TYPE=JPEG:") })
        let base64 = String(photoLine.dropFirst("PHOTO;ENCODING=b;TYPE=JPEG:".count))
        let jpeg = try #require(Data(base64Encoded: base64))
        let image = try #require(UIImage(data: jpeg))
        #expect(max(image.size.width, image.size.height) <= 256)
    }

    @Test func normalisesHandles() {
        #expect(ContactValueFormat.telegramUsername(from: "@kamola_r") == "kamola_r")
        #expect(ContactValueFormat.telegramUsername(from: "https://t.me/kamola_r?start=1") == "kamola_r")
        #expect(ContactValueFormat.telegramUsername(from: "t.me/kamola_r") == "kamola_r")
        #expect(ContactValueFormat.telegramUsername(from: "not a handle") == nil)
        #expect(ContactValueFormat.linkedInURL(from: "in/aziza")?.absoluteString == "https://www.linkedin.com/in/aziza")
        #expect(ContactValueFormat.linkedInURL(from: "aziza")?.absoluteString == "https://www.linkedin.com/in/aziza")
        #expect(ContactValueFormat.linkedInURL(from: "linkedin.com/in/aziza")?.absoluteString == "https://linkedin.com/in/aziza")
        #expect(ContactValueFormat.websiteURL(from: "aziza.design")?.absoluteString == "https://aziza.design")
        #expect(ContactValueFormat.websiteDisplay(from: "https://www.aziza.design/") == "aziza.design")
    }

    static func samplePNG() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 400))
        return renderer.pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
        }
    }
}
