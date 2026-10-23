import MetlyCore
import SwiftUI

/// "Show on This Card" — one switch per contact field (CARD_CREATE details, CARD_EDITOR Fields).
/// Changes go through `CardDesignRules`, so Private fields can never be switched on.
struct CardFieldsSection: View {
    /// The profile's fields (values + privacy).
    let fields: [ContactField]
    @Binding var design: CardDesign
    let footer: String
    /// Saves a value typed into a field that is still empty in the profile (nil: read-only rows).
    var onEditValue: ((ContactFieldKind, String) -> Void)?

    var body: some View {
        Section {
            ForEach(ContactFieldKind.allCases) { kind in
                CardFieldToggleRow(field: field(kind), isOn: isShown(kind),
                                   onEditValue: onEditValue.map { save in { save(kind, $0) } })
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

    private func isShown(_ kind: ContactFieldKind) -> Binding<Bool> {
        let privacy = field(kind).privacy
        return Binding {
            CardDesignRules.isFieldShown(kind, privacy: privacy, in: design)
        } set: { visible in
            if case .updated(let updated) = CardDesignRules.settingField(kind, visible: visible, privacy: privacy, in: design) {
                design = updated
            }
        }
    }

    /// Adds a density note when more fields are on than the card can show.
    private var footerText: Text {
        let hidden = CardDesignRules.fieldsHiddenByDensity(fields: fields, design: design)
        guard hidden > 0 else { return Text(footer) }
        let density = design.density
        return Text("\(footer) \(density.title) density shows up to \(density.maxContacts) contact lines, so ^[\(hidden) field](inflect: true) won’t fit.")
    }
}
