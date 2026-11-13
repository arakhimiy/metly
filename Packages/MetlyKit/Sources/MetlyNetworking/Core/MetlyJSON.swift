import Foundation

/// The one JSON dialect spoken with the Nameshake backend (see `docs/api/openapi.yaml`).
///
/// - Keys are lowerCamelCase. Swift's `…ID` / `…IDs` / `…URL` suffixes travel as `…Id` / `…Ids` / `…Url`
///   (`cardID` ⇄ `cardId`, `photoURL` ⇄ `photoUrl`), so Swift models keep Swift naming.
/// - Dates are ISO-8601 UTC strings with millisecond precision (`2026-09-26T10:00:00.000Z`);
///   decoding also accepts strings without fractional seconds.
public enum MetlyJSON {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(fractionalStyle))
        }
        encoder.keyEncodingStrategy = .custom { codingPath in
            WireKey(MetlyJSON.wireName(for: codingPath.last))
        }
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = MetlyJSON.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an ISO-8601 date, got \(string)")
        }
        decoder.keyDecodingStrategy = .custom { codingPath in
            WireKey(MetlyJSON.swiftName(for: codingPath.last))
        }
        return decoder
    }

    /// Parses ISO-8601 with or without fractional seconds.
    public static func date(from string: String) -> Date? {
        if let date = try? fractionalStyle.parse(string) { return date }
        return try? plainStyle.parse(string)
    }

    /// Formats a date exactly as it goes on the wire.
    public static func string(from date: Date) -> String { date.formatted(fractionalStyle) }

    // MARK: Key mapping

    private static let fractionalStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let plainStyle = Date.ISO8601FormatStyle()

    /// Swift `photoURL` → wire `photoUrl`, `cardIDs` → `cardIds`, `userID` → `userId`.
    static func wireName(for key: (any CodingKey)?) -> String {
        guard let key else { return "" }
        let name = key.stringValue
        for (swift, wire) in suffixes where name.count > swift.count && name.hasSuffix(swift) {
            return String(name.dropLast(swift.count)) + wire
        }
        return name
    }

    /// Wire `photoUrl` → Swift `photoURL`, `cardIds` → `cardIDs`, `userId` → `userID`.
    static func swiftName(for key: (any CodingKey)?) -> String {
        guard let key else { return "" }
        let name = key.stringValue
        for (swift, wire) in suffixes where name.count > wire.count && name.hasSuffix(wire) {
            let stem = name.dropLast(wire.count)
            // Only convert real suffixes ("cardId"), never words that merely end the same way ("void").
            guard let last = stem.last, last.isLowercase || last.isNumber else { continue }
            return String(stem) + swift
        }
        return name
    }

    private static let suffixes: [(swift: String, wire: String)] = [("IDs", "Ids"), ("ID", "Id"), ("URLs", "Urls"), ("URL", "Url")]
}

private struct WireKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
