import Foundation
import MetlyCardKit
import MetlyCore

/// Pure transformation `WidgetSnapshotInput` → `WidgetSnapshot` (unit-tested).
///
/// • Card faces use `CardAudience.public` semantics: Public, design-visible, non-empty fields in display
///   order — never Connections or Private (widgets can be on the Lock Screen, SPEC §9 Q4). The same goes
///   for extra phone numbers (they follow the card's phone switch).
/// • The QR encodes the card link, or a public-only vCard while the card is unpublished.
/// • Follow-ups are sorted by due date; the snapshot keeps the first `maxFollowUps` rows plus every due date.
/// • Connections older than 8 days are dropped (they can never count as "this week").
nonisolated public enum WidgetSnapshotBuilder {
    /// - Parameter thumbnail: downscales profile media before it is embedded (identity in tests).
    public static func build(from input: WidgetSnapshotInput?, now: Date = .now,
                             thumbnail: (Data) -> Data? = { WidgetImageThumbnail.make(from: $0) }) -> WidgetSnapshot {
        guard let input else { return .signedOut(at: now) }

        let orderedCards = input.cards.enumerated()
            .sorted { ($0.element.sortOrder, $0.offset) < ($1.element.sortOrder, $1.offset) }
            .map(\.element)
        let defaultID = input.defaultCardID.flatMap { id in orderedCards.first { $0.id == id }?.id } ?? orderedCards.first?.id
        let cards = orderedCards.map { card(from: $0, owner: input.owner, isDefault: $0.id == defaultID) }
        let shareCardID = input.shareCardID.flatMap { id in cards.first { $0.id == id }?.id } ?? defaultID

        let showsPhoto = orderedCards.contains { $0.design.showPhoto && $0.design.templateShowsPhoto }
        let showsLogo = orderedCards.contains { $0.design.showLogo && $0.design.templateShowsLogo }
        let owner = WidgetOwner(
            fullName: input.owner.fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            jobTitle: input.owner.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            company: input.owner.company.trimmingCharacters(in: .whitespacesAndNewlines),
            photoThumbnail: showsPhoto ? input.owner.photoData.flatMap(thumbnail) : nil,
            logoThumbnail: showsLogo ? input.owner.logoData.flatMap(thumbnail) : nil,
            linksPaused: input.owner.linksPaused
        )

        let sortedFollowUps = input.openFollowUps.sorted { ($0.dueAt, $0.id.uuidString) < ($1.dueAt, $1.id.uuidString) }
        let cutoff = now.addingTimeInterval(-WidgetSnapshot.recentConnectionWindow)

        return WidgetSnapshot(
            generatedAt: now,
            owner: owner,
            cards: cards,
            shareCardID: shareCardID,
            followUps: sortedFollowUps.prefix(WidgetSnapshot.maxFollowUps).map(followUp(from:)),
            openFollowUpDueDates: sortedFollowUps.map(\.dueAt),
            recentConnectionDates: input.connectionDates.filter { $0 >= cutoff }.sorted(by: >),
            activeEventName: input.activeEventName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
    }

    /// Public, design-visible, non-empty fields in display order (one per kind).
    public static func publicFields(_ fields: [ContactField], design: CardDesign) -> [ContactField] {
        ContactFieldKind.allCases.compactMap { kind in
            guard design.visibleFields.contains(kind),
                  let field = fields.first(where: { $0.kind == kind && !$0.isEmpty && CardAudience.public.allows($0.privacy) })
            else { return nil }
            return ContactField(kind: kind, value: field.value.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)
        }
    }

    /// Public, non-empty extra numbers when the card shows phones (none otherwise).
    public static func publicPhones(_ phones: [LabeledPhone], design: CardDesign) -> [LabeledPhone] {
        guard design.visibleFields.contains(.phone) else { return [] }
        return phones.compactMap { phone in
            guard !phone.isEmpty, CardAudience.public.allows(phone.privacy) else { return nil }
            return LabeledPhone(id: phone.id, label: phone.label,
                                value: phone.value.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)
        }
    }

    /// Public, non-empty entries the card shows, in the owner's order.
    public static func publicContacts(_ contacts: [ContactEntry], selection: [UUID]?, design: CardDesign) -> [ContactEntry] {
        let chosen = selection.map(Set.init)
        return contacts.compactMap { entry in
            guard !entry.isEmpty, CardAudience.public.allows(entry.privacy),
                  chosen?.contains(entry.id) ?? design.visibleFields.contains(entry.kind) else { return nil }
            var copy = entry
            copy.value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            return copy
        }
    }

    static func card(from card: WidgetSnapshotInput.Card, owner: WidgetSnapshotInput.Owner, isDefault: Bool) -> WidgetCard {
        let contacts = publicContacts(owner.contacts, selection: card.visibleContactIDs, design: card.design)
        let fields = ContactFieldKind.allCases.compactMap { contacts.first(of: $0)?.field }
        let phones = Array(contacts.entries(of: .phone).dropFirst().map(\.labeledPhone))
        let slug = card.slug.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = slug.isEmpty ? nil : Brand.cardURL(slug: slug)
        let payload: String
        if let url {
            payload = url.absoluteString
        } else {
            let content = CardFaceContent(fullName: owner.fullName, jobTitle: owner.jobTitle, company: owner.company,
                                          contacts: contacts)
            payload = VCardBuilder.make(content: content, url: nil)
        }
        return WidgetCard(id: card.id, name: card.name, design: card.design, url: url, fields: fields,
                          qrPayload: payload, isDefault: isDefault, additionalPhones: phones,
                          phoneLabel: contacts.legacyPhoneLabel, contacts: contacts)
    }

    static func followUp(from followUp: WidgetSnapshotInput.FollowUp) -> WidgetFollowUp {
        let title = followUp.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return WidgetFollowUp(
            id: followUp.id,
            title: title.isEmpty ? String(localized: "Follow up") : title,
            personName: followUp.personName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? String(localized: "Someone"),
            connectionID: followUp.connectionID,
            context: followUp.personContext?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            dueAt: followUp.dueAt,
            channel: followUp.channel
        )
    }
}

private extension String {
    nonisolated var nilIfEmpty: String? { isEmpty ? nil : self }
}
