import MetlyCore
import MetlyData
import MetlyDesign
import PhotosUI
import SwiftData
import SwiftUI

/// SETUP_PROFILE — "About You". Creates/updates the `Profile`, then pushes SETUP_PERMISSIONS.
struct SetupProfileView: View {
    let store: OnboardingStore
    let onContinue: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var form: SetupProfileForm
    @State private var prefill: SetupPrefill?
    @State private var hasLoaded: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var isShowingSaveError = false
    @FocusState private var focusedField: SetupProfileField?

    /// `initialForm` bypasses loading (previews).
    init(store: OnboardingStore = OnboardingStore(), initialForm: SetupProfileForm? = nil,
         onContinue: @escaping () -> Void) {
        self.store = store
        self.onContinue = onContinue
        _form = State(initialValue: initialForm ?? SetupProfileForm())
        _hasLoaded = State(initialValue: initialForm != nil)
    }

    var body: some View {
        Form {
            Section {
                ProfilePhotoHeader(name: form.fullName, photoData: form.photoData, selection: $photoItem,
                                   isProcessing: isProcessingPhoto, onRemove: removePhoto)
            }
            .listRowBackground(Color.clear)

            Section {
                SetupTextField(field: .fullName, text: $form.fullName, focus: $focusedField)
                    .accessibilityHint("Required")
                SetupTextField(field: .jobTitle, text: $form.jobTitle, focus: $focusedField)
                SetupTextField(field: .company, text: $form.company, focus: $focusedField)
            } footer: {
                if !form.isNameValid {
                    Text("Your name is required. It appears on every card.")
                }
            }

            Section {
                SetupTextField(field: .phone, text: typed($form.phone, as: .phone), focus: $focusedField)
                SetupTextField(field: .email, text: typed($form.email, as: .email), focus: $focusedField)
                SetupTextField(field: .telegram, text: typed($form.telegram, as: .telegram), focus: $focusedField)
            } footer: {
                SetupContactFooter(emailError: focusedField == .email ? nil : form.emailError, prefill: prefill)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("About You")
        .bottomActionBar {
            Button(action: save) {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .controlSize(.large)
            .disabled(!form.canContinue || isProcessingPhoto)
        }
        .onSubmit(focusNextField)
        .task { load() }
        .task(id: photoItem) { await loadPhoto() }
        .alert("Couldn’t Save Your Profile", isPresented: $isShowingSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try again in a moment.")
        }
    }

    // MARK: Actions

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        let prefill = store.setupPrefill
        var form = SetupProfileForm(prefill: prefill)
        if let profile = modelContext.currentProfile() {
            form.overlay(fullName: profile.fullName, jobTitle: profile.jobTitle, company: profile.company,
                         phone: profile.field(.phone).value, email: profile.field(.email).value,
                         telegram: profile.field(.telegram).value, photoData: profile.photoData)
        }
        self.prefill = prefill
        self.form = form
    }

    private func loadPhoto() async {
        guard let photoItem else { return }
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        guard let data = try? await photoItem.loadTransferable(type: Data.self),
              let jpeg = await ImageDownscaler.jpegData(from: data) else { return }
        form.photoData = jpeg
    }

    private func removePhoto() {
        photoItem = nil
        form.photoData = nil
    }

    private func focusNextField() {
        focusedField = focusedField?.next
    }

    private func save() {
        guard form.canContinue else { return }
        let profile = modelContext.currentProfile() ?? {
            let profile = Profile()
            modelContext.insert(profile)
            return profile
        }()
        profile.fullName = form.profileFullName
        profile.jobTitle = form.profileJobTitle
        profile.company = form.profileCompany
        profile.photoData = form.photoData
        for (kind, value) in form.contactValues {
            // Keeps any privacy the user already chose; new fields get the SPEC §3.3 defaults.
            var field = profile.field(kind)
            field.value = value
            profile.setField(field)
        }
        profile.markChanged()
        do {
            try modelContext.save()
            focusedField = nil
            onContinue()
        } catch {
            isShowingSaveError = true
        }
    }
}

/// "Name and email came from your Apple ID…" or the inline email error.
private struct SetupContactFooter: View {
    let emailError: String?
    let prefill: SetupPrefill?

    var body: some View {
        if let emailError {
            Label(emailError, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        } else if let prefill, prefill.hasValues {
            switch prefill.provider {
            case .apple: Text("Name and email came from your Apple ID. Each card decides what it shows.")
            case .google: Text("Name and email came from your Google account. Each card decides what it shows.")
            case .telegram: Text("Your name came from Telegram. Each card decides what it shows.")
            }
        } else {
            Text("Each card decides what it shows.")
        }
    }
}

#Preview("Setup profile · prefilled") {
    NavigationStack {
        SetupProfileView(store: .preview(prefill: SetupPrefill(fullName: "Aziza Karimova", email: "aziza@tezkor.uz", provider: .apple))) {}
    }
    .metlyPreview(.signedOut)
}

#Preview("Setup profile · empty") {
    NavigationStack { SetupProfileView(store: .preview()) {} }
        .metlyPreview(.signedOut)
}

#Preview("Setup profile · invalid") {
    NavigationStack {
        SetupProfileView(store: .preview(), initialForm: SetupProfileForm(fullName: "", email: "aziza@tezkor")) {}
    }
    .metlyPreview(.signedOut)
}

#Preview("Setup profile · dark, large text") {
    NavigationStack {
        SetupProfileView(store: .preview(prefill: SetupPrefill(fullName: "Debug Google User", email: "debug.google@example.com", provider: .google))) {}
    }
    .metlyPreview(.signedOut)
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility1)
}

/// Phone numbers spaced for their country, no spaces in an email, only username characters in a handle.
@MainActor
private func typed(_ value: Binding<String>, as kind: ContactFieldKind) -> Binding<String> {
    Binding { value.wrappedValue } set: { value.wrappedValue = ContactFieldInput.typing($0, for: kind) }
}
