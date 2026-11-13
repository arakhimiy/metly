import Foundation
import MetlyCore

/// Classifies the raw string of a QR code or the clipboard (SPEC §2.5.8 "Results").
nonisolated enum QRPayloadClassifier {
    /// - Parameter ownSlugs: slugs of the owner's live cards (scanning one shows "That's your card").
    static func classify(_ raw: String, ownSlugs: Set<String> = []) -> QRPayload {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .other }
        if isVCard(text) { return .vCard(text) }
        if let vCard = MECardConverter.vCard(fromMECard: text) { return .vCard(vCard) }
        if let slug = metlySlug(in: text) {
            if ownSlugs.contains(slug) { return .ownCard(slug: slug) }
            return .metlyCard(url: Brand.cardURL(slug: slug), slug: slug)
        }
        if let url = webURL(from: text) { return .webLink(url) }
        return .other
    }

    static func isVCard(_ text: String) -> Bool {
        text.range(of: "BEGIN:VCARD", options: [.caseInsensitive, .anchored]) != nil
    }

    /// Slug of `https://tanishly.app/c/{slug}`, also without scheme, with `www.`, upper-cased
    /// (QR alphanumeric mode upper-cases links) or as `nameshake://c/{slug}`.
    static func metlySlug(in text: String) -> String? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        // Slugs are lower-case `[a-z0-9-]`, so folding the whole link is safe.
        var candidate = text.lowercased()
        if !candidate.contains("://") { candidate = "https://" + candidate }
        guard var components = URLComponents(string: candidate) else { return nil }
        if let host = components.host, host.hasPrefix("www.") {
            components.host = String(host.dropFirst(4))
        }
        guard let url = components.url, let slug = Brand.slug(from: url), isValidSlug(slug) else { return nil }
        return slug
    }

    /// An `http(s)` link, a `www.` link or a bare domain ("example.com/page").
    static func webURL(from text: String) -> URL? {
        guard !text.contains(where: \.isWhitespace), !text.contains("@") || text.contains("://") else { return nil }
        let lower = text.lowercased()
        let string: String
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            string = text
        } else if lower.contains("://") {
            return nil   // other schemes (ftp://, custom apps) aren't web pages
        } else if lower.hasPrefix("www.") || lower.wholeMatch(of: /[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}(\/\S*)?/) != nil {
            string = "https://" + text
        } else {
            return nil
        }
        guard let url = URL(string: string), let host = url.host(), host.contains(".") else { return nil }
        return url
    }

    private static func isValidSlug(_ slug: String) -> Bool {
        !slug.isEmpty && slug.count <= 64
            && slug.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}
