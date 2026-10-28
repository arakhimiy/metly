import Foundation

/// Instructions and prompt for reading a card with the on-device model.
///
/// The instructions are fixed (trusted); the card's text only ever goes into the prompt. Each
/// line is framed in English with its relative size and position ("Line 1 (largest text, top left):
/// …") — the model sees the layout, and the English frame keeps Russian / Uzbek cards from being
/// rejected as an unsupported language.
nonisolated enum PaperModelPrompt {
    static let maximumLines = 30
    static let maximumLineLength = 100

    static let instructions = """
        You read the text lines of a scanned business card and fill in the person's contact details.
        Copy every value exactly as it is written in the lines, letter for letter. DO NOT invent, translate, \
        transliterate, correct or complete anything. Leave a field empty when the card doesn't show it.
        fullName: the person's own name: a first name and surname (sometimes with a patronymic such as \
        "o'g'li", "qizi" or "Petrovich"), Uzbek, Russian, Korean or English, in Latin or Cyrillic letters. \
        Never a brand.
        company: usually the logo or brand text, often big and at the top, or a name with a legal form \
        (LLC, Inc, MChJ, AJ, XK, OOO, ООО, АО). A line that matches the email or website domain is the \
        company. The biggest text is not always the person's name.
        jobTitle: the person's position, for example Director, Bosh menejer or Генеральный директор.
        Slogans, addresses, cities and field labels are never the name, title or company.
        phones: every phone number except fax numbers, without its label. label is mobile for mob, mobile, \
        cell, моб, сот, uyali; work for office, work, tel, раб, офис, ish; home for home, дом, uy.
        """

    static func text(for lines: [OCRLine]) -> String {
        let maxHeight = lines.map(\.height).max() ?? 0
        let described = lines.prefix(maximumLines).enumerated().map { offset, line in
            let notes = [PaperLayout.size(of: line, maxHeight: maxHeight)?.rawValue, PaperLayout.position(of: line)]
                .compactMap(\.self)
            let text = String(PaperText.collapseWhitespace(line.text).prefix(maximumLineLength))
            return notes.isEmpty ? "Line \(offset + 1): \(text)" : "Line \(offset + 1) (\(notes.joined(separator: ", "))): \(text)"
        }
        return "Business card text lines in reading order:\n" + described.joined(separator: "\n")
            + "\nFill in the contact details from these lines."
    }
}
