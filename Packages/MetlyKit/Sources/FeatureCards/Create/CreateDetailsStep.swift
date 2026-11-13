import MetlyCapture
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// Step 3 — "Details": live preview, card name (Work / Personal / Conference) and "Show on This Card"
/// (title, company, logo, photo, contacts, QR). Publish creates the card; the sync engine publishes it.
struct CreateDetailsStep: View {
    @Binding var design: CardDesign
    /// Profile entries the card shows.
    @Binding var selection: [UUID]?
    @Binding var options: CardFaceOptions
    @Binding var photo: MediaEdit
    @Binding var logo: MediaEdit
    @Binding var name: String
    let content: CardFaceContent
    /// The live profile ("+ Add Contact" writes to it).
    let profile: Profile?
    let onPublish: () -> Void

    @FocusState private var isNameFocused: Bool

    var body: some View {
        Form {
            Section {
                CardPreviewRow(design: design, content: content)
            }

            Section {
                TextField("Card Name", text: $name, prompt: Text("e.g. Work"))
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($isNameFocused)
                TagFlowLayout {
                    ForEach(CardNaming.suggestions, id: \.self) { suggestion in
                        CaptureChip(suggestion, isSelected: trimmedName == suggestion) {
                            name = suggestion
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Card Name")
            }

            CardIdentitySection(profile: profile, design: $design, options: $options, photo: $photo, logo: $logo)
            CardFieldsSection(profile: profile, selection: $selection, design: $design,
                              footer: String(localized: "Values come from your profile. Change privacy there.", bundle: .appStrings))
            CardQRSection(showQR: $design.showQR)
        }
        .onAppear {
            // A new card shows every entry that isn't Private.
            if selection == nil, let profile {
                selection = profile.defaultCardSelection
                design.syncVisibleFields(with: profile.defaultCardSelection, in: profile.contacts)
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .createProgress(CreateStep.details.progress)
        .bottomActionBar {
            Button(action: publish) {
                Text("Publish Card").frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .controlSize(.large)
            .disabled(trimmedName.isEmpty)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func publish() {
        isNameFocused = false
        onPublish()
    }
}
