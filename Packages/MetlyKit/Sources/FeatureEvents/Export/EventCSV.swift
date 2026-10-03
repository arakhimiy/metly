import Foundation

/// RFC 4180 CSV for the event export: CRLF line endings, quoted fields where needed,
/// UTF-8 with a byte-order mark so Excel detects the encoding (Cyrillic / Uzbek names).
enum EventCSV {
    static let byteOrderMark = "\u{FEFF}"
    static let lineEnding = "\r\n"

    /// Header + one line per row, no BOM.
    static func text(rows: [EventCSVRow], columns: [EventCSVColumn]) -> String {
        let columns = EventCSVColumn.ordered(columns)
        var lines = [columns.map { field($0.header) }.joined(separator: ",")]
        for row in rows {
            lines.append(columns.map { field(row[$0]) }.joined(separator: ","))
        }
        return lines.joined(separator: lineEnding) + lineEnding
    }

    /// File contents: BOM + UTF-8 text.
    static func data(rows: [EventCSVRow], columns: [EventCSVColumn]) -> Data {
        Data((byteOrderMark + text(rows: rows, columns: columns)).utf8)
    }

    /// One escaped cell.
    static func field(_ value: String) -> String {
        escape(neutralizingFormula(value))
    }

    /// Quotes a value containing a comma, quote, line break or edge whitespace; doubles inner quotes.
    static func escape(_ value: String) -> String {
        let needsQuotes = value.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
            || value.first?.isWhitespace == true || value.last?.isWhitespace == true
        guard needsQuotes else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// CSV injection guard (OWASP): a cell that a spreadsheet would run as a formula gets a leading
    /// apostrophe. Names and notes can come from web share-backs, i.e. from strangers.
    /// Phone-like values ("+998 90 123 45 67") are left alone — digits and punctuation can't call functions.
    static func neutralizingFormula(_ value: String) -> String {
        guard let first = value.unicodeScalars.first, formulaTriggers.contains(first) else { return value }
        if first == "+" || first == "-", value.unicodeScalars.allSatisfy(phoneCharacters.contains) {
            return value
        }
        return "'" + value
    }

    private static let formulaTriggers: Set<Unicode.Scalar> = ["=", "+", "-", "@", "\t", "\r"]
    private static let phoneCharacters: Set<Unicode.Scalar> = Set("0123456789 +-().".unicodeScalars)

    // MARK: File

    /// "Tashkent Tech Week.csv" — characters the file system or share targets dislike are removed.
    static func fileName(for eventName: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters).union(.newlines)
        let cleaned = eventName.unicodeScalars.filter { !forbidden.contains($0) }
        let base = String(String.UnicodeScalarView(cleaned)).trimmed
        return (base.isEmpty ? "Event" : String(base.prefix(80))) + ".csv"
    }

    /// Writes the export to a private temporary folder (complete file protection) and returns its URL.
    static func write(rows: [EventCSVRow], columns: [EventCSVColumn], eventName: String) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "EventExport", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName(for: eventName), directoryHint: .notDirectory)
        try data(rows: rows, columns: columns).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Removes exported files (they contain private notes) once the export sheet closes.
    static func removeExports() {
        let folder = URL.temporaryDirectory.appending(path: "EventExport", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
    }
}
