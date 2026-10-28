import Foundation
import MetlyCore

/// Reads the label of a vCard `TEL` line.
///
/// An Apple `itemN.X-ABLabel` wins when it is recognisable — built-in ones are written as
/// `_$!<Mobile>!$_`, custom ones are free text ("Office", "моб.", "Ish") — otherwise the `TYPE`
/// parameters decide (`CELL`/`IPHONE` → Mobile, `WORK` → Work, `HOME` → Home, anything else → Other).
/// Fax numbers are not phones you can call or message, so they are skipped.
enum VCardPhoneLabel: Equatable {
    case phone(PhoneLabel)
    case fax

    static func classify(types: Set<String>, customLabel: String?) -> VCardPhoneLabel {
        if let customLabel, let kind = classify(label: customLabel) { return kind }
        if types.contains("FAX") { return .fax }
        if !types.isDisjoint(with: ["CELL", "MOBILE", "IPHONE"]) { return .phone(.mobile) }
        if types.contains("WORK") { return .phone(.work) }
        if types.contains("HOME") { return .phone(.home) }
        return .phone(.other)
    }

    /// Free-text label → kind, nil when it says nothing we know ("Beeline", "Tashkent").
    static func classify(label: String) -> VCardPhoneLabel? {
        let text = label
            .replacing("_$!<", with: "")
            .replacing(">!$_", with: "")
            .lowercased()
        let words = text.split { !$0.isLetter }.map(String.init)
        func matches(prefixes: [String], words exact: [String] = []) -> Bool {
            words.contains { word in exact.contains(word) || prefixes.contains { word.hasPrefix($0) } }
        }
        if ["fax", "факс", "faks"].contains(where: { text.contains($0) }) { return .fax }   // also "WorkFAX", "HomeFAX"
        if matches(prefixes: ["mob", "cell", "iphone", "моб", "сот", "handy", "uyali"]) { return .phone(.mobile) }
        if matches(prefixes: ["work", "office", "busin", "раб", "офис", "служ"], words: ["ish", "main"]) {
            return .phone(.work)
        }
        if matches(prefixes: ["home", "дом"], words: ["uy"]) { return .phone(.home) }
        if matches(prefixes: ["other", "друг", "boshqa"]) { return .phone(.other) }
        return nil
    }
}
