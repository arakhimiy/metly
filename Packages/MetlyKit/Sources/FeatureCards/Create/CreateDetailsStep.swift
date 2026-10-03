import MetlyCapture
import MetlyCore
import MetlyDesign
import SwiftUI

/// Step 4 — "Details": live preview, card name (Work / Personal / Conference) and
/// "Show on This Card". Publish creates the card; the sync engine publishes it.
struct CreateDetailsStep: View {
    @Binding var design: CardDesign
    @Binding var name: String
    let content: CardFaceContent
    /// The profile's fields (values + privacy).
    let fields: [ContactField]
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

            CardFieldsSection(fields: fields, design: $design,
                              footer: "Values come from your profile. Change privacy there.")
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
