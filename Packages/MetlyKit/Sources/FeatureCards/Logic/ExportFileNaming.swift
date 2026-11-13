import Foundation
import MetlyCore

/// File names for exported cards, e.g. "Aziza Karimova - Work Card@2x.png".
/// Safe for Files, AirDrop, Mail and Windows (no path separators or reserved characters).
nonisolated enum ExportFileNaming {
    static let maximumBaseLength = 80

    /// "{Full Name} - {Card} Card", falling back to whichever part exists, then "Nameshake Card".
    static func baseName(fullName: String, cardName: String) -> String {
        let person = sanitize(fullName)
        var card = sanitize(cardName)
        if !card.isEmpty, !card.lowercased().hasSuffix("card") { card += " Card" }
        let base = switch (person.isEmpty, card.isEmpty) {
        case (false, false): "\(person) - \(card)"
        case (false, true): "\(person) Card"
        case (true, false): card
        case (true, true): "\(Brand.appName) Card"
        }
        return String(base.prefix(maximumBaseLength)).trimmingCharacters(in: .whitespaces)
    }

    static func fileName(for output: ExportOutput, fullName: String, cardName: String) -> String {
        let base = baseName(fullName: fullName, cardName: cardName)
        return switch output {
        case .png(let scale, .rounded): "\(base)@\(scale.rawValue)x.png"
        case .png(let scale, .square): "\(base) Square@\(scale.rawValue)x.png"
        case .pdf(.single): "\(base) (Print).pdf"
        case .pdf(.sheetA4): "\(base) (A4 Sheet).pdf"
        case .lockScreen(let device): "\(base) Lock Screen (\(device.title)).png"
        }
    }

    /// Removes characters that are invalid in file names on common systems, control characters
    /// and leading dots; collapses whitespace.
    static func sanitize(_ text: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let cleaned = String(String.UnicodeScalarView(text.unicodeScalars.map { forbidden.contains($0) ? " " : $0 }))
        let collapsed = cleaned.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(collapsed.drop(while: { $0 == "." || $0 == " " }))
    }
}
