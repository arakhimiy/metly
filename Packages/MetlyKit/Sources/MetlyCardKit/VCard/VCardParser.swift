import Foundation
import MetlyCore

/// Parses a foreign vCard (2.1 / 3.0 / 4.0, e.g. from a scanned QR) into a `PaperCardDraft`.
///
/// Handles folded lines, CRLF/LF/CR, groups (`item1.URL`), case-insensitive names and parameters,
/// escaped text, quoted-printable (2.1), `tel:`/`mailto:` URIs, `FN`/`N`, `ORG`, `TITLE`, `TEL`,
/// `EMAIL`, `URL`, `X-SOCIALPROFILE`, `IMPP` and `X-TELEGRAM`. Returns nil when the text is not a
/// vCard or carries nothing usable. Only the first card of a multi-card file is read.
///
/// Phones: every `TEL` is read with its label — from `TYPE` (`CELL`, `WORK`, `HOME`, v2.1 bare
/// `TEL;WORK;VOICE:`) or Apple's grouped `itemN.X-ABLabel` (`_$!<Work>!$_`, or a custom "Office" / "моб.").
/// The first Mobile number becomes the primary phone (else the `PREF` one, else the first); the rest
/// become `additionalPhones` in file order (at most `maxAdditionalPhones`, duplicates and faxes skipped).
public enum VCardParser {
    /// Extra numbers kept beyond the primary one (the profile allows the same).
    public static let maxAdditionalPhones = 5

    public static func parse(_ string: String) -> PaperCardDraft? {
        let properties = properties(in: string)
        guard !properties.isEmpty else { return nil }
        var accumulator = Accumulator(groupLabels: groupLabels(in: properties))
        for property in properties { accumulator.add(property) }
        return accumulator.draft
    }

    /// `itemN.X-ABLabel` values by upper-cased group (the label line may come before or after its property).
    static func groupLabels(in properties: [VCardProperty]) -> [String: String] {
        var labels: [String: String] = [:]
        for property in properties where property.name == "X-ABLABEL" {
            guard let group = property.group?.uppercased(), labels[group] == nil else { continue }
            labels[group] = property.text
        }
        return labels
    }

    /// Content lines between the first `BEGIN:VCARD` and its `END:VCARD`, unfolded and split.
    static func properties(in string: String) -> [VCardProperty] {
        let lines = VCardText.unfold(string).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var properties: [VCardProperty] = []
        var insideCard = false
        var index = 0
        while index < lines.count {
            var line = lines[index]
            index += 1
            // vCard 2.1 quoted-printable soft line breaks: "=" at the end continues on the next line.
            if line.uppercased().contains("QUOTED-PRINTABLE") {
                while line.hasSuffix("="), index < lines.count {
                    line.removeLast()
                    line += lines[index]
                    index += 1
                }
            }
            guard let property = VCardProperty(line: line) else { continue }
            if property.name == "BEGIN", property.value.uppercased() == "VCARD" {
                insideCard = true
            } else if property.name == "END", property.value.uppercased() == "VCARD" {
                if insideCard { break }
            } else if insideCard {
                properties.append(property)
            }
        }
        return insideCard ? properties : []
    }
}

/// One `[group.]NAME[;PARAM=VALUE…]:value` content line.
struct VCardProperty: Equatable {
    var group: String?
    /// Upper-cased property name.
    var name: String
    /// Upper-cased parameter names → values (bare 2.1 parameters are filed under `TYPE`).
    var parameters: [String: [String]]
    /// Raw value (still escaped; QP already decoded).
    var value: String

    init?(line: String) {
        guard let colon = Self.valueSeparator(in: line) else { return nil }
        let head = line[..<colon]
        var rawValue = String(line[line.index(after: colon)...])

        var segments = head.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard !segments.isEmpty else { return nil }
        var fullName = segments.removeFirst()
        if let dot = fullName.lastIndex(of: ".") {
            group = String(fullName[..<dot])
            fullName = String(fullName[fullName.index(after: dot)...])
        }
        name = fullName.trimmingCharacters(in: .whitespaces).uppercased()
        guard !name.isEmpty else { return nil }

        var parameters: [String: [String]] = [:]
        for segment in segments where !segment.isEmpty {
            let pair = segment.split(separator: "=", maxSplits: 1).map(String.init)
            let key = pair.count == 2 ? pair[0].trimmingCharacters(in: .whitespaces).uppercased() : "TYPE"
            let values = (pair.count == 2 ? pair[1] : pair[0])
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) }
            parameters[key, default: []] += values
        }
        self.parameters = parameters

        if parameters["ENCODING"]?.contains(where: { $0.uppercased() == "QUOTED-PRINTABLE" }) == true {
            rawValue = VCardText.decodeQuotedPrintable(rawValue)
        }
        value = rawValue
    }

    /// Upper-cased TYPE values (`TYPE=CELL,VOICE` / `TYPE=cell;TYPE=pref` / bare `CELL`).
    var types: Set<String> { Set((parameters["TYPE"] ?? []).map { $0.uppercased() }) }

    var text: String { VCardText.unescape(value).trimmingCharacters(in: .whitespacesAndNewlines) }

    /// First colon outside a double-quoted parameter value.
    private static func valueSeparator(in line: String) -> String.Index? {
        var quoted = false
        for index in line.indices {
            switch line[index] {
            case "\"": quoted.toggle()
            case ":" where !quoted: return index
            default: continue
            }
        }
        return nil
    }
}

/// Collects the best value per field while walking the properties.
private struct Accumulator {
    struct Phone {
        var value: String
        var label: PhoneLabel
        var preferred: Bool
    }

    let groupLabels: [String: String]
    var formattedName = ""
    var structuredName = ""
    var company = ""
    var title = ""
    var role = ""
    var phones: [Phone] = []
    var email: (value: String, preferred: Bool)?
    var telegram: String?
    var linkedIn: String?
    var website: String?

    mutating func add(_ property: VCardProperty) {
        switch property.name {
        case "FN":
            if formattedName.isEmpty { formattedName = property.text }
        case "N":
            if structuredName.isEmpty { structuredName = Self.name(fromStructured: property.value) }
        case "ORG":
            if company.isEmpty { company = VCardText.components(of: property.value).first?.trimmed ?? "" }
        case "TITLE":
            if title.isEmpty { title = property.text }
        case "ROLE":
            if role.isEmpty { role = property.text }
        case "TEL":
            addPhone(property)
        case "EMAIL":
            let value = property.text.removingPrefix("mailto:")
            let preferred = property.types.contains("PREF")
            if !value.isEmpty, email == nil || (preferred && email?.preferred == false) { email = (value, preferred) }
        case "URL":
            addURL(property.text)
        case "X-SOCIALPROFILE":
            addSocialProfile(property)
        case "IMPP":
            let value = property.text
            if value.lowercased().hasPrefix("telegram:") {
                setTelegram(String(value.dropFirst("telegram:".count)))
            }
        case "X-TELEGRAM":
            setTelegram(property.text)
        default:
            break
        }
    }

    private mutating func addPhone(_ property: VCardProperty) {
        let value = property.text.removingPrefix("tel:")
        guard !value.isEmpty else { return }
        let customLabel = property.group.flatMap { groupLabels[$0.uppercased()] }
        guard case .phone(let label) = VCardPhoneLabel.classify(types: property.types, customLabel: customLabel)
        else { return }
        let digits = value.filter(\.isNumber)
        if !digits.isEmpty, phones.contains(where: { $0.value.filter(\.isNumber) == digits }) { return }
        phones.append(Phone(value: value, label: label, preferred: property.types.contains("PREF")))
    }

    private mutating func addURL(_ value: String) {
        switch ContactValueFormat.classify(value) {
        case .telegram(let username): if telegram == nil { telegram = username }
        case .linkedIn(let url): if linkedIn == nil { linkedIn = ContactValueFormat.linkedInDisplay(from: url) }
        case .website(let url): if website == nil { website = ContactValueFormat.websiteDisplay(from: url.absoluteString) }
        case .metlyCard, nil: break
        }
    }

    private mutating func addSocialProfile(_ property: VCardProperty) {
        let user = property.parameters["X-USER"]?.first ?? ""
        let value = property.text
        if property.types.contains("TELEGRAM") || value.lowercased().contains("t.me/") {
            setTelegram(user.isEmpty ? value : user)
        } else if property.types.contains("LINKEDIN") || value.lowercased().contains("linkedin.com") {
            guard linkedIn == nil else { return }
            if let url = ContactValueFormat.linkedInURL(from: value.isEmpty ? user : value) {
                linkedIn = ContactValueFormat.linkedInDisplay(from: url)
            }
        }
    }

    private mutating func setTelegram(_ value: String) {
        guard telegram == nil, let username = ContactValueFormat.telegramUsername(from: value) else { return }
        telegram = username
    }

    var draft: PaperCardDraft? {
        let name = formattedName.isEmpty ? structuredName : formattedName
        var fields: [ContactField] = []
        var orderedPhones = phones
        let primaryIndex = phones.firstIndex { $0.label == .mobile } ?? phones.firstIndex(where: \.preferred)
            ?? phones.indices.first
        let primary = primaryIndex.map { orderedPhones.remove(at: $0) }
        if let primary { fields.append(ContactField(kind: .phone, value: primary.value)) }
        if let email { fields.append(ContactField(kind: .email, value: email.value)) }
        if let telegram { fields.append(ContactField(kind: .telegram, value: ContactValueFormat.telegramDisplay(username: telegram))) }
        if let website { fields.append(ContactField(kind: .website, value: website)) }
        if let linkedIn { fields.append(ContactField(kind: .linkedin, value: linkedIn)) }
        let jobTitle = title.isEmpty ? role : title
        guard !name.isEmpty || !company.isEmpty || !fields.isEmpty else { return nil }
        let extras = orderedPhones.prefix(VCardParser.maxAdditionalPhones).map {
            LabeledPhone(label: $0.label, value: $0.value)
        }
        return PaperCardDraft(fullName: name, jobTitle: jobTitle, company: company, fields: fields,
                              phoneLabel: primary?.label ?? .mobile, additionalPhones: Array(extras))
    }

    /// "Family;Given;Additional;Prefix;Suffix" → "Prefix Given Additional Family Suffix".
    private static func name(fromStructured value: String) -> String {
        let parts = VCardText.components(of: value).map(\.trimmed)
        func part(_ index: Int) -> String { index < parts.count ? parts[index] : "" }
        return [part(3), part(1), part(2), part(0), part(4)].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    func removingPrefix(_ prefix: String) -> String {
        lowercased().hasPrefix(prefix) ? String(dropFirst(prefix.count)).trimmed : self
    }
}
