import Foundation
import ImageIO
import MetlyCore
import UniformTypeIdentifiers

/// Builds a vCard 3.0 for the offline QR (QR_FULLSCREEN "Offline QR") and `.vcf` sharing.
///
/// - Text values are escaped, lines folded at 75 octets, CRLF line breaks (RFC 2426).
/// - Entries in `content.contacts` order. Phones → one `TEL` per number, typed by label: Mobile `TYPE=CELL`, Work `TYPE=WORK,VOICE`,
///   Home `TYPE=HOME,VOICE`, Other `TYPE=VOICE`. Email → `EMAIL;TYPE=INTERNET`, website → `URL`,
///   Telegram / WhatsApp / Instagram → `X-SOCIALPROFILE;TYPE=…` + labelled `URL`, LinkedIn → labelled `URL`,
///   the card link → labelled `URL`. Labels use Apple's `itemN.X-ABLabel` grouping, ignored elsewhere.
/// - Private fields are never written. `content` should already be filtered for `CardAudience.public`.
/// - `PHOTO` (base64 JPEG, ≤ 256 px) only when `includePhoto` is set — keep it off for QR codes.
public enum VCardBuilder {
    public static func make(content: CardFaceContent, url: URL?, includePhoto: Bool = false) -> String {
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        var itemIndex = 0
        func labelledURL(_ value: String, label: String) {
            itemIndex += 1
            lines.append("item\(itemIndex).URL:\(uri(value))")
            lines.append("item\(itemIndex).X-ABLabel:\(VCardText.escape(label))")
        }

        let name = content.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        let given = words.first ?? ""
        let family = words.dropFirst().joined(separator: " ")
        lines.append("N:\(VCardText.escape(family));\(VCardText.escape(given));;;")
        lines.append("FN:\(VCardText.escape(name))")

        let company = content.company.trimmingCharacters(in: .whitespacesAndNewlines)
        if !company.isEmpty { lines.append("ORG:\(VCardText.escape(company))") }
        let title = content.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { lines.append("TITLE:\(VCardText.escape(title))") }

        for phone in phones(of: content) {
            lines.append("TEL;\(phone.label.vCardType):\(VCardText.escape(phone.value))")
        }

        for entry in content.contacts where entry.privacy != .private && !entry.isEmpty {
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch entry.kind {
            case .phone:
                continue   // written above, deduplicated
            case .email:
                lines.append("EMAIL;TYPE=INTERNET:\(VCardText.escape(value))")
            case .website:
                if let url = ContactValueFormat.websiteURL(from: value) { lines.append("URL:\(uri(url.absoluteString))") }
            case .telegram:
                guard let username = ContactValueFormat.telegramUsername(from: value),
                      let url = ContactValueFormat.telegramURL(username: username) else { continue }
                lines.append("X-SOCIALPROFILE;TYPE=telegram;X-USER=\(username):\(uri(url.absoluteString))")
                labelledURL(url.absoluteString, label: "Telegram")
            case .whatsapp:
                guard let url = ContactValueFormat.whatsAppURL(from: value) else { continue }
                lines.append("X-SOCIALPROFILE;TYPE=whatsapp:\(uri(url.absoluteString))")
                labelledURL(url.absoluteString, label: "WhatsApp")
            case .instagram:
                guard let username = ContactValueFormat.instagramUsername(from: value),
                      let url = ContactValueFormat.instagramURL(username: username) else { continue }
                lines.append("X-SOCIALPROFILE;TYPE=instagram;X-USER=\(username):\(uri(url.absoluteString))")
                labelledURL(url.absoluteString, label: "Instagram")
            case .linkedin:
                if let url = ContactValueFormat.linkedInURL(from: value) { labelledURL(url.absoluteString, label: "LinkedIn") }
            }
        }

        if let url { labelledURL(url.absoluteString, label: Brand.appName) }

        if includePhoto, let photo = content.photoData, let jpeg = thumbnailJPEG(from: photo) {
            lines.append("PHOTO;ENCODING=b;TYPE=JPEG:\(jpeg.base64EncodedString())")
        }

        lines.append("END:VCARD")
        return lines.map(VCardText.fold).joined(separator: VCardText.lineBreak) + VCardText.lineBreak
    }

    /// One non-empty, non-private field per kind, in display order.
    static func orderedFields(_ fields: [ContactField]) -> [ContactField] {
        ContactFieldKind.allCases.compactMap { kind in
            fields.first { $0.kind == kind && $0.privacy != .private && !$0.isEmpty }
        }
    }

    /// Every number to write, in the card's order. Private and empty numbers are skipped, and so is a number
    /// already written (same digits).
    static func phones(of content: CardFaceContent) -> [(label: PhoneLabel, value: String)] {
        var result: [(label: PhoneLabel, value: String)] = []
        var seen = Set<String>()
        for entry in content.contacts where entry.kind == .phone && entry.privacy != .private {
            let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            let digits = value.filter(\.isNumber)
            if !digits.isEmpty {
                guard seen.insert(digits).inserted else { continue }
            }
            result.append((entry.label ?? .mobile, value))
        }
        return result
    }

    /// URI values are not TEXT-escaped in vCard 3.0; only line breaks are removed.
    private static func uri(_ value: String) -> String {
        value.filter { $0 != "\r" && $0 != "\n" }
    }

    /// Small JPEG so the vCard stays shareable (≤ 256 px, quality 0.7).
    static func thumbnailJPEG(from data: Data, maxPixelSize: Int = 256) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary)
        else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
