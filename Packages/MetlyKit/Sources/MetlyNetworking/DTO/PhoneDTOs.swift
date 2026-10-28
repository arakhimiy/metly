import Foundation
import MetlyCore

// Labelled phones on the wire (schema 2.0.0): `phoneLabel` (label of the primary phone) and
// `additionalPhones: [{id, label, value, privacy}]` on Profile, Connection and PublicCard.
// Payloads from before the feature carry neither key: decoding falls back to `.mobile` / `[]`.

public extension LabeledPhone {
    // `maxAdditional` / `maxValueLength` live in MetlyCore (DomainValues) so every module sees them.

    /// Why the server would reject these extra phones, or nil when they are valid.
    static func validationProblem(_ phones: [LabeledPhone]) -> String? {
        if phones.count > maxAdditional { return "At most \(maxAdditional) additional phones." }
        if phones.contains(where: { $0.value.count > maxValueLength }) { return "A phone number is at most \(maxValueLength) characters." }
        return nil
    }
}

/// How phone numbers are compared and copied between people (accept, scan, mock server).
public enum PhoneMerge {
    /// Digits only: "+998 90 555-12-34" and "998905551234" are the same number.
    public static func digits(_ value: String) -> String { value.filter(\.isNumber) }

    /// Fills gaps with someone's labelled phones, never overwriting a number already there:
    /// - without a number in `phone`, their first number (primary, else the first extra) becomes it, label included;
    /// - with `adoptsLabel`, one of their numbers equal to `phone` (digits) lends it its label — its owner knows
    ///   whether it is Mobile or Work (off when merging two of your own records: the newer one's label stays);
    /// - every other number not present yet is appended to `additional` as Connections-level, up to
    ///   `LabeledPhone.maxAdditional`.
    /// - Returns: whether anything changed.
    @discardableResult
    public static func merge(phone: inout String, label: inout PhoneLabel, additional: inout [LabeledPhone],
                             incomingPhone: String, incomingLabel: PhoneLabel, incomingAdditional: [LabeledPhone],
                             adoptsLabel: Bool = true) -> Bool {
        var candidates = ([LabeledPhone(id: LabeledPhone.primaryID, label: incomingLabel, value: incomingPhone)] + incomingAdditional)
            .map { entry in
                var trimmed = entry
                trimmed.value = String(entry.value.trimmingCharacters(in: .whitespaces).prefix(LabeledPhone.maxValueLength))
                return trimmed
            }
            .filter { !digits($0.value).isEmpty }
        guard !candidates.isEmpty else { return false }
        var changed = false
        if digits(phone).isEmpty {
            let first = candidates.removeFirst()
            phone = first.value
            label = first.label
            changed = true
        }
        let primaryDigits = digits(phone)
        if adoptsLabel, let same = candidates.first(where: { digits($0.value) == primaryDigits }), same.label != label {
            label = same.label
            changed = true
        }
        var known = Set([primaryDigits] + additional.map { digits($0.value) })
        for candidate in candidates where additional.count < LabeledPhone.maxAdditional {
            guard known.insert(digits(candidate.value)).inserted else { continue }
            let id = candidate.isPrimary || additional.contains(where: { $0.id == candidate.id }) ? UUID() : candidate.id
            additional.append(LabeledPhone(id: id, label: candidate.label, value: candidate.value, privacy: .connections))
            changed = true
        }
        return changed
    }
}

/// Lenient wire form of `LabeledPhone`: an unknown label (a newer server) reads as `.other`, a
/// missing privacy as `.connections`, a missing id gets a fresh one. Elements without a value are dropped.
private struct WireLabeledPhone: Decodable {
    var phone: LabeledPhone?

    private enum CodingKeys: String, CodingKey { case id, label, value, privacy }

    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let value = try? container.decode(String.self, forKey: .value) else { return }
        let label = (try? container.decodeIfPresent(String.self, forKey: .label)).flatMap { $0 }
        let privacy = (try? container.decodeIfPresent(String.self, forKey: .privacy)).flatMap { $0 }
        let id = (try? container.decodeIfPresent(UUID.self, forKey: .id)).flatMap { $0 }
        phone = LabeledPhone(id: id ?? UUID(), label: label.map { PhoneLabel(rawValue: $0) ?? .other } ?? .other,
                             value: value, privacy: privacy.flatMap(FieldPrivacy.init(rawValue:)) ?? .connections)
    }
}

extension KeyedDecodingContainer {
    /// Missing or null → `.mobile`; an unknown value (a newer server) → `.other`.
    func decodePhoneLabel(forKey key: Key) throws -> PhoneLabel {
        guard let raw = try decodeIfPresent(String.self, forKey: key) else { return .mobile }
        return PhoneLabel(rawValue: raw) ?? .other
    }

    /// Missing or null → `[]`; see `WireLabeledPhone` for per-element tolerance.
    func decodeLabeledPhones(forKey key: Key) throws -> [LabeledPhone] {
        try decodeIfPresent([WireLabeledPhone].self, forKey: key)?.compactMap(\.phone) ?? []
    }
}
