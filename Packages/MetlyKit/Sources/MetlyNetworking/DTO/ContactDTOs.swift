import Foundation
import MetlyCore

// Contact lists on the wire (schema 3.0.0, docs/api/CONTACTS.md): `contacts: [{id, kind, label, value,
// privacy}]` on Profile, Connection and PublicCard, next to the legacy per-kind fields older apps read.
// Payloads without the key (older servers) decode to the list rebuilt from the legacy fields.

/// Lenient wire form of `ContactEntry`: an unknown kind (a newer server) drops the element, an unknown
/// label reads as `.other`, a missing privacy as the kind's default, a missing id gets a fresh one.
private struct WireContactEntry: Decodable {
    var entry: ContactEntry?

    private enum CodingKeys: String, CodingKey { case id, kind, label, value, privacy }

    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let rawKind = try? container.decode(String.self, forKey: .kind),
              let kind = ContactFieldKind(rawValue: rawKind),
              let value = try? container.decode(String.self, forKey: .value),
              !value.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let id = (try? container.decodeIfPresent(UUID.self, forKey: .id)).flatMap { $0 }
        let label = (try? container.decodeIfPresent(String.self, forKey: .label)).flatMap { $0 }
        let privacy = (try? container.decodeIfPresent(String.self, forKey: .privacy)).flatMap { $0 }
        entry = ContactEntry(id: id ?? UUID(), kind: kind, label: label.map { PhoneLabel(rawValue: $0) ?? .other },
                             value: value, privacy: privacy.flatMap(FieldPrivacy.init(rawValue:)))
    }
}

extension KeyedDecodingContainer {
    /// Missing or null → nil (the caller rebuilds the list from the legacy fields).
    func decodeContacts(forKey key: Key) throws -> [ContactEntry]? {
        guard let wire = try decodeIfPresent([WireContactEntry].self, forKey: key) else { return nil }
        var seen = Set<UUID>()
        return wire.compactMap(\.entry).filter { seen.insert($0.id).inserted }
    }
}

public extension ContactEntry {
    /// Why the server would reject this list, or nil when it is valid.
    static func validationProblem(_ entries: [ContactEntry]) -> String? {
        if entries.count > maxCount { return "At most \(maxCount) contacts." }
        if let long = entries.first(where: { $0.value.count > maxLength(for: $0.kind) }) {
            return "\(long.kind.title) is at most \(maxLength(for: long.kind)) characters."
        }
        return nil
    }
}

/// A card design as it goes over the wire: `CardDesign` plus `visibleContacts` (ids of the profile entries
/// the card shows; nil = a card from before 3.0.0). `CardDesign` itself stays as stored in SwiftData.
enum WireCardDesign {
    private enum Keys: String, CodingKey { case visibleContacts }

    static func decode<K: CodingKey>(from container: KeyedDecodingContainer<K>, forKey key: K) throws -> (CardDesign, [UUID]?) {
        let decoder = try container.superDecoder(forKey: key)
        let design = try CardDesign(from: decoder)
        let ids = try? decoder.container(keyedBy: Keys.self).decodeIfPresent([UUID].self, forKey: .visibleContacts)
        return (design, ids.flatMap { $0 })
    }

    static func encode<K: CodingKey>(_ design: CardDesign, visibleContacts: [UUID]?, to container: inout KeyedEncodingContainer<K>,
                                     forKey key: K) throws {
        let encoder = container.superEncoder(forKey: key)
        var legacy = design
        legacy.visibleFields = legacy.visibleFields.filter(\.isLegacy)
        try legacy.encode(to: encoder)
        var extra = encoder.container(keyedBy: Keys.self)
        try extra.encode(visibleContacts, forKey: .visibleContacts)
    }
}
