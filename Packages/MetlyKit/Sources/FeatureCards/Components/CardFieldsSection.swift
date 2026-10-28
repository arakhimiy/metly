import MetlyCardKit
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// "Show on This Card" — one switch per entry of the profile's contact list, in its order
/// (CARD_CREATE details, CARD_EDITOR Fields). Private entries can never be switched on.
///
/// "+ Add Contact" adds an entry to the profile right here (no detour through Profile): the new row asks for
/// its value, is switched on, and goes away again if left empty.
struct CardFieldsSection: View {
    /// The live profile (its entries are edited in place when adding one).
    let profile: Profile?
    /// The card's chosen entries; nil = a card from before 3.0.0, shown by `design.visibleFields` until changed.
    @Binding var selection: [UUID]?
    @Binding var design: CardDesign
    let footer: String
    /// Whether "+ Add Contact" and typing values are offered.
    var allowsAdding = true

    @FocusState private var focusedEntry: UUID?

    var body: some View {
        let entries = profile?.contacts ?? []
        let phoneCount = entries.filter { $0.kind == .phone && !$0.isEmpty }.count
        Section {
            if entries.isEmpty, !allowsAdding {
                Text("No contact details yet. Add them in Profile.")
                    .foregroundStyle(.secondary)
            }
            ForEach(entries) { entry in
                CardContactToggleRow(entry: entry, showsPhoneLabel: phoneCount > 1, isOn: isShown(entry),
                                     value: allowsAdding ? value(of: entry) : nil, focus: $focusedEntry,
                                     onLeave: { leave(entry.id) })
            }
            if allowsAdding, let profile {
                AddContactMenu(isEnabled: profile.canAddContact, action: add)
            }
        } header: {
            Text("Show on This Card")
        } footer: {
            footerText
        }
    }

    /// The selection the switches show: the chosen ids, or for an old card the kinds it showed.
    private var effectiveSelection: [UUID] {
        selection ?? profile?.contacts(selectedBy: nil, design: design).map(\.id) ?? []
    }

    private func isShown(_ entry: ContactEntry) -> Binding<Bool> {
        Binding {
            entry.privacy != .private && effectiveSelection.contains(entry.id)
        } set: { visible in
            guard case .updated(let ids) = CardDesignRules.settingContact(entry, visible: visible, in: effectiveSelection) else { return }
            select(ids)
        }
    }

    private func select(_ ids: [UUID]) {
        selection = ids
        design.syncVisibleFields(with: ids, in: profile?.contacts ?? [])
    }

    /// The value as typed, written straight into the profile; typing one switches the entry on.
    private func value(of entry: ContactEntry) -> Binding<String> {
        Binding {
            profile?.contacts.first { $0.id == entry.id }?.value ?? ""
        } set: { text in
            profile?.updateContact(id: entry.id) { $0.value = ContactFieldInput.typing(text, for: $0.kind) }
            if !text.trimmingCharacters(in: .whitespaces).isEmpty, !effectiveSelection.contains(entry.id), entry.privacy != .private {
                select(effectiveSelection + [entry.id])
            }
        }
    }

    private func add(_ kind: ContactFieldKind) {
        guard let id = profile?.addContact(kind) else { return }
        // Next run loop: the new row has to exist before it can take focus.
        Task { focusedEntry = id }
    }

    /// Leaving a row: clean the value up ("@handle", no https://), drop it when still empty.
    private func leave(_ id: UUID) {
        guard let profile, let entry = profile.contacts.first(where: { $0.id == id }) else { return }
        let cleaned = ContactFieldInput.normalized(entry.value, for: entry.kind)
        if cleaned.isEmpty {
            profile.removeContacts(ids: [id])
            if effectiveSelection.contains(id) { select(effectiveSelection.filter { $0 != id }) }
        } else if cleaned != entry.value {
            profile.updateContact(id: id) { $0.value = cleaned }
        }
    }

    /// Adds a density note when more entries are on than the card can show.
    private var footerText: some View {
        let selected = profile?.contacts(selectedBy: effectiveSelection, design: design) ?? []
        let hidden = CardDesignRules.hiddenByDensity(selected, design: design)
        let total = hidden.fields + hidden.phones
        let density = design.density
        return VStack(alignment: .leading, spacing: 6) {
            if total > 0 {
                Text("\(footer) \(density.title) density shows up to \(density.maxContacts) contact lines, so ^[\(total) contact](inflect: true) won’t fit.")
            } else {
                Text(footer)
            }
            if let profile, !profile.canAddContact {
                Text("You can add up to \(ContactEntry.maxCount) contacts.")
            }
        }
    }
}

/// One entry: icon, title + privacy badge, "{value} · {privacy}" and a switch. Private entries are disabled
/// with "Private — hidden from all cards". A row added with "+ Add Contact" asks for its value instead.
struct CardContactToggleRow: View {
    let entry: ContactEntry
    /// Phones say which one they are (Mobile, Work…) when there are several.
    let showsPhoneLabel: Bool
    @Binding var isOn: Bool
    /// Editable value (nil: read-only rows).
    var value: Binding<String>?
    var focus: FocusState<UUID?>.Binding
    let onLeave: () -> Void

    /// Decided once, so the text field doesn't vanish under the user's fingers after the first letter.
    @State private var asksForValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 12) {
                    SettingsIcon(field: entry.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                Text(title)
                                PrivacyBadge(privacy: entry.privacy)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                PrivacyBadge(privacy: entry.privacy)
                            }
                        }
                        if !asksForValue {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .disabled(entry.privacy == .private)
            .accessibilityValue(Text(accessibilityValue))

            if asksForValue, let value {
                TextField(ContactFieldInput.placeholder(for: entry.kind), text: value)
                    .keyboardType(ContactFieldInput.keyboardType(for: entry.kind))
                    .textContentType(ContactFieldInput.contentType(for: entry.kind))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused(focus, equals: entry.id)
                    .padding(.leading, 41)
                    .accessibilityLabel(Text(title))
                    .onSubmit { focus.wrappedValue = nil }
                if focus.wrappedValue != entry.id, let problem = ContactFieldInput.problem(value.wrappedValue, for: entry.kind) {
                    ContactProblemNote(problem).padding(.leading, 41)
                }
            }
        }
        .onAppear {
            asksForValue = value != nil && entry.isEmpty
        }
        .onChange(of: focus.wrappedValue) { old, new in
            if old == entry.id, new != entry.id { onLeave() }
        }
    }

    private var title: String {
        if entry.kind == .phone, showsPhoneLabel, let label = entry.label { return label.phoneNumberTitle }
        return entry.kind.title
    }

    private var subtitle: String {
        if entry.privacy == .private { return String(localized: "Private — hidden from all cards") }
        return "\(entry.value) · \(entry.privacy.title)"
    }

    private var accessibilityValue: String {
        if entry.privacy == .private { return String(localized: "Private, hidden from all cards") }
        return entry.value
    }
}
