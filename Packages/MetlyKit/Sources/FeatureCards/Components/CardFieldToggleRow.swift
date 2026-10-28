import MetlyCore
import MetlyDesign
import SwiftUI

/// "Show on This Card" row: field icon, name + privacy badge, "{value} · {privacy}" and a switch.
/// Private fields are disabled with "Private — hidden from all cards".
///
/// A field that is still empty in the profile can be filled in right here (`onEditValue`): the value
/// goes to the profile, and typing one switches the field on — no detour through Profile.
struct CardFieldToggleRow: View {
    let field: ContactField
    @Binding var isOn: Bool
    var onEditValue: ((String) -> Void)?

    @State private var value = ""
    /// Decided once, so the text field doesn't vanish under the user's fingers after the first letter.
    @State private var asksForValue = false
    @FocusState private var isValueFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $isOn) {
                HStack(spacing: 12) {
                    SettingsIcon(field: field.kind)
                    VStack(alignment: .leading, spacing: 2) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 6) {
                                Text(field.kind.title)
                                PrivacyBadge(privacy: field.privacy)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.kind.title)
                                PrivacyBadge(privacy: field.privacy)
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
            .disabled(field.privacy == .private)
            .accessibilityValue(Text(accessibilityValue))

            if asksForValue {
                TextField(ContactFieldInput.placeholder(for: field.kind), text: $value)
                    .keyboardType(ContactFieldInput.keyboardType(for: field.kind))
                    .textContentType(ContactFieldInput.contentType(for: field.kind))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($isValueFocused)
                    .padding(.leading, 41)
                    .accessibilityLabel(Text("\(field.kind.title), not added in Profile yet"))
                    .onSubmit { commit(normalizing: true) }
            }
        }
        .onAppear {
            asksForValue = onEditValue != nil && field.isEmpty && field.privacy != .private
        }
        .onChange(of: value) { commit(normalizing: false) }
        .onChange(of: isValueFocused) { _, focused in
            if !focused { commit(normalizing: true) }
        }
        .onChange(of: isOn) { _, on in
            // Switching on a field that has no value yet: type it right away.
            if on, asksForValue, value.isEmpty { isValueFocused = true }
        }
    }

    /// Writes the value to the profile as it is typed; cleans it up ("@handle", no https://) on leave.
    private func commit(normalizing: Bool) {
        guard let onEditValue, asksForValue else { return }
        var text = String(value.prefix(Self.maxLength(for: field.kind)))
        if normalizing {
            text = ContactFieldInput.normalized(text, for: field.kind)
            if value != text { value = text }
        }
        guard text != field.value else { return }
        onEditValue(text)
        if !text.trimmingCharacters(in: .whitespaces).isEmpty, !isOn { isOn = true }
    }

    /// Server limits: every phone number 40 characters, other values 200.
    static func maxLength(for kind: ContactFieldKind) -> Int {
        kind == .phone ? 40 : ContactFieldInput.maxLength
    }

    private var subtitle: String {
        if field.privacy == .private { return String(localized: "Private — hidden from all cards") }
        let value = field.isEmpty ? String(localized: "Not added in Profile") : field.value
        return "\(value) · \(field.privacy.title)"
    }

    private var accessibilityValue: String {
        if field.privacy == .private { return String(localized: "Private, hidden from all cards") }
        return field.isEmpty ? String(localized: "Not added in Profile") : field.value
    }
}
