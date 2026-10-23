import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// PROFILE tab root (SPEC §2.5.13) — an iOS Settings-style inset grouped form.
struct ProfileScreen: View {
    var body: some View {
        ProfileReader { profile in
            ProfileForm(profile: profile)
        }
        .navigationTitle("Profile")
        .toolbarTitleDisplayMode(.inlineLarge)
    }
}

/// The form itself, once a profile exists.
struct ProfileForm: View {
    let profile: Profile
    @Environment(AppServices.self) private var services
    @Query(Card.live) private var cards: [Card]
    @FocusState private var focusedField: ProfileFocusField?

    var body: some View {
        Form {
            ProfileHeaderSection(profile: profile, focusedField: $focusedField)
            ContactDetailsSection(profile: profile, focusedField: $focusedField)
            CardsSection(profile: profile, cards: cards)
            SharingSection(profile: profile, cards: cards)
            ProPlanSection()
            SettingsLinksSection()
            SignOutSection()
        }
        .contentMargins(.top, 8, for: .scrollContent)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done", action: endEditing)
            }
        }
        .onChange(of: focusedField) { previous, _ in
            if let previous { finishEditing(previous) }
        }
    }

    private func endEditing() {
        focusedField = nil
    }

    /// Cleans up the field the user just left and nudges sync.
    private func finishEditing(_ field: ProfileFocusField) {
        let editor = profile.editor
        switch field {
        case .name:
            editor.textBinding(\.fullName).wrappedValue = profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        case .jobTitle:
            editor.textBinding(\.jobTitle).wrappedValue = profile.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        case .company:
            editor.textBinding(\.company).wrappedValue = profile.company.trimmingCharacters(in: .whitespacesAndNewlines)
        case .contact(let kind):
            profile.normalizeField(kind)
        }
        services.sync.requestSync()
    }
}

#Preview("Profile · Free") {
    NavigationStack { ProfileView() }
        .metlyPreview(.full)
}

#Preview("Profile · Pro") {
    NavigationStack { ProfileView() }
        .profilePreview(plan: .pro, entitlements: { $0.simulateYearly() })
}

#Preview("Profile · Empty fields") {
    NavigationStack { ProfileView() }
        .profilePreview { profile in
            profile.jobTitle = ""
            profile.company = ""
            profile.photoData = nil
            profile.contactFields = ContactField.defaults
        }
}

#Preview("Profile · Links paused, dark") {
    NavigationStack { ProfileView() }
        .profilePreview { $0.linksPaused = true }
        .preferredColorScheme(.dark)
}

#Preview("Profile · Accessibility size") {
    NavigationStack { ProfileView() }
        .metlyPreview(.full)
        .dynamicTypeSize(.accessibility2)
}
