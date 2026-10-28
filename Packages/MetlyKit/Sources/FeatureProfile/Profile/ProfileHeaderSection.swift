import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// Avatar (photo picker) + inline-editable name, job title and company.
struct ProfileHeaderSection: View {
    let profile: Profile

    private var contactIDs: [UUID] { profile.contacts.map(\.id) }
    var focusedField: FocusState<ProfileFocusField?>.Binding
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let editor = profile.editor
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 16))

        Section {
            layout {
                AvatarPickerButton(profile: profile)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("Full Name", text: editor.textBinding(\.fullName))
                        .font(.title3.bold())
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused(focusedField, equals: .name)
                        .onSubmit { focusedField.wrappedValue = ProfileFocusField.name.next(contactIDs: contactIDs) }

                    Divider()

                    TextField("Job Title", text: editor.textBinding(\.jobTitle))
                        .textContentType(.jobTitle)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused(focusedField, equals: .jobTitle)
                        .onSubmit { focusedField.wrappedValue = ProfileFocusField.jobTitle.next(contactIDs: contactIDs) }
                }
            }
            .padding(.vertical, 4)

            LabeledFieldRow(title: String(localized: "Company")) {
                SettingsIcon("building.2.fill", color: .gray)
            } field: {
                TextField("Company", text: editor.textBinding(\.company))
                    .textContentType(.organizationName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused(focusedField, equals: .company)
                    .onSubmit { focusedField.wrappedValue = ProfileFocusField.company.next(contactIDs: contactIDs) }
            } accessory: {
                EmptyView()
            }
        } footer: {
            Text("Your name, title and company appear on every card.")
        }
    }
}
