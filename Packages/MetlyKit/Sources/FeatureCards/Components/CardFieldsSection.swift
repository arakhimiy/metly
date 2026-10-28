import MetlyCore
import SwiftUI

/// "Show on This Card" — one switch per contact field (CARD_CREATE details, CARD_EDITOR Fields).
/// Changes go through `CardDesignRules`, so Private fields can never be switched on.
///
/// With extra numbers in the profile, the phone row becomes "Phone Numbers": one switch for every
/// number, listing each one with its label and privacy, and noting the ones that never appear.
struct CardFieldsSection: View {
    /// The profile's fields (values + privacy).
    let fields: [ContactField]
    /// The profile's extra numbers (after the primary phone).
    var additionalPhones: [LabeledPhone] = []
    /// Label of the primary phone.
    var phoneLabel: PhoneLabel = .mobile
    @Binding var design: CardDesign
    let footer: String
    /// Saves a value typed into a field that is still empty in the profile (nil: read-only rows).
    var onEditValue: ((ContactFieldKind, String) -> Void)?

    var body: some View {
        Section {
            ForEach(ContactFieldKind.allCases) { kind in
                if kind == .phone, !filledExtraPhones.isEmpty {
                    CardPhonesToggleRow(phones: listedPhones, isOn: isShown(.phone, privacy: phoneGroupPrivacy),
                                        privateCount: privatePhoneCount)
                } else {
                    CardFieldToggleRow(field: field(kind), isOn: isShown(kind, privacy: privacy(of: kind)),
                                       onEditValue: onEditValue.map { save in { save(kind, $0) } })
                }
            }
        } header: {
            Text("Show on This Card")
        } footer: {
            footerText
        }
    }

    private func field(_ kind: ContactFieldKind) -> ContactField {
        fields.first { $0.kind == kind } ?? ContactField(kind: kind)
    }

    private var filledExtraPhones: [LabeledPhone] { additionalPhones.filter { !$0.isEmpty } }

    /// Every filled number, primary first.
    private var listedPhones: [LabeledPhone] {
        let primary = field(.phone)
        let first = primary.isEmpty ? [] : [LabeledPhone(id: LabeledPhone.primaryID, label: phoneLabel,
                                                         value: primary.value, privacy: primary.privacy)]
        return first + filledExtraPhones
    }

    private var phoneGroupPrivacy: FieldPrivacy {
        CardDesignRules.phoneGroupPrivacy(primary: field(.phone), additionalPhones: additionalPhones)
    }

    private var privatePhoneCount: Int {
        CardDesignRules.privatePhoneCount(primary: field(.phone), additionalPhones: additionalPhones)
    }

    private func privacy(of kind: ContactFieldKind) -> FieldPrivacy {
        kind == .phone ? phoneGroupPrivacy : field(kind).privacy
    }

    private func isShown(_ kind: ContactFieldKind, privacy: FieldPrivacy) -> Binding<Bool> {
        Binding {
            CardDesignRules.isFieldShown(kind, privacy: privacy, in: design)
        } set: { visible in
            if case .updated(let updated) = CardDesignRules.settingField(kind, visible: visible, privacy: privacy, in: design) {
                design = updated
            }
        }
    }

    /// Adds a density note when more fields (or extra numbers) are on than the card can show.
    private var footerText: some View {
        let hidden = CardDesignRules.fieldsHiddenByDensity(fields: fields, additionalPhones: additionalPhones, design: design)
        let hiddenPhones = CardDesignRules.phonesHiddenByDensity(fields: fields, additionalPhones: additionalPhones,
                                                                 design: design)
        let density = design.density
        return VStack(alignment: .leading, spacing: 6) {
            if hidden > 0 {
                Text("\(footer) \(density.title) density shows up to \(density.maxContacts) contact lines, so ^[\(hidden) field](inflect: true) won’t fit.")
            } else {
                Text(footer)
            }
            if hiddenPhones > 0 {
                Text("Extra phone numbers use only the lines left free, so ^[\(hiddenPhones) number](inflect: true) won’t fit.")
            }
        }
    }
}
