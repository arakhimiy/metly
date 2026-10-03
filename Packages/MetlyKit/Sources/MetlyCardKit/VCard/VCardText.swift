import Foundation

/// vCard 3.0 (RFC 2426) text rules: escaping, line folding and unfolding.
enum VCardText {
    static let lineBreak = "\r\n"
    /// Maximum octets per physical line, excluding the line break (RFC 2425 §5.8.1).
    static let maxLineOctets = 75

    /// Escapes a TEXT value: backslash, comma, semicolon and newlines.
    static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)
        var previousWasCR = false
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case ",": result += "\\,"
            case ";": result += "\\;"
            case "\r": result += "\\n"
            case "\n": if !previousWasCR { result += "\\n" }
            default: result.unicodeScalars.append(scalar)
            }
            previousWasCR = scalar == "\r"
        }
        return result
    }

    /// Reverses `escape` (also accepts `\N` and `\:` written by other generators).
    static func unescape(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else {
                result.append(character)
                continue
            }
            switch next {
            case "n", "N": result.append("\n")
            default: result.append(next)   // \\  \,  \;  \:
            }
        }
        return result
    }

    /// Splits a structured value (N, ORG, ADR) on unescaped semicolons, then unescapes each part.
    static func components(of value: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaping = false
        for character in value {
            if escaping {
                current.append("\\")
                current.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == ";" {
                parts.append(unescape(current))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaping { current.append("\\") }
        parts.append(unescape(current))
        return parts
    }

    /// Folds a content line to ≤ 75 octets per physical line; continuation lines start with one space.
    /// Never splits a UTF-8 sequence.
    static func fold(_ line: String) -> String {
        guard line.utf8.count > maxLineOctets else { return line }
        var result = ""
        var lineOctets = 0
        var limit = maxLineOctets
        for scalar in line.unicodeScalars {
            let octets = String(scalar).utf8.count
            if lineOctets + octets > limit {
                result += lineBreak + " "
                lineOctets = 1   // the leading space counts toward the 75 octets
                limit = maxLineOctets
            }
            result.unicodeScalars.append(scalar)
            lineOctets += octets
        }
        return result
    }

    /// Normalises line breaks to `\n` and joins folded lines (line break followed by a space or tab).
    static func unfold(_ text: String) -> String {
        text.replacing("\r\n", with: "\n")
            .replacing("\r", with: "\n")
            .replacing("\n ", with: "")
            .replacing("\n\t", with: "")
    }

    /// Decodes quoted-printable (vCard 2.1) as UTF-8.
    static func decodeQuotedPrintable(_ value: String) -> String {
        var bytes: [UInt8] = []
        var utf8 = Array(value.utf8)[...]
        while let byte = utf8.popFirst() {
            if byte == UInt8(ascii: "="), utf8.count >= 2,
               let high = hexValue(utf8[utf8.startIndex]), let low = hexValue(utf8[utf8.startIndex + 1]) {
                bytes.append(high << 4 | low)
                utf8 = utf8.dropFirst(2)
            } else {
                bytes.append(byte)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a")...UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        default: nil
        }
    }
}
