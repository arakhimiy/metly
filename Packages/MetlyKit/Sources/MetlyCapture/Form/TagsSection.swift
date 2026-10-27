import SwiftUI

/// Preset tags (Investor, Client, Hiring, Partner, Friend) + custom tags as toggleable chips.
struct TagsSection: View {
    @Binding var tags: [String]

    @State private var isAddingTag = false
    @State private var newTag = ""

    var body: some View {
        Section("Tags") {
            TagFlowLayout {
                ForEach(allTags, id: \.self) { tag in
                    CaptureChip(tag, isSelected: isSelected(tag)) { toggle(tag) }
                }
                CaptureChip(String(localized: "Add Tag"), systemImage: "plus", isSelected: false, action: startAddingTag)
            }
            .padding(.vertical, 4)
            .sensoryFeedback(.selection, trigger: tags)
        }
        .alert("Add Tag", isPresented: $isAddingTag) {
            TextField("Tag", text: $newTag)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Add", action: addTag)
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("Tags help you find people later.")
        }
    }

    /// Presets first, then the custom tags already on this person.
    private var allTags: [String] {
        let custom = tags.filter { tag in !MetlyCapture.presetTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
        return MetlyCapture.presetTags + custom
    }

    private func isSelected(_ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    private func toggle(_ tag: String) {
        if let index = tags.firstIndex(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            tags.remove(at: index)
        } else {
            tags.append(tag)
        }
    }

    private func startAddingTag() {
        newTag = ""
        isAddingTag = true
    }

    private func addTag() {
        let tag = newTag.trimmed
        guard !tag.isEmpty, !isSelected(tag) else { return }
        tags.append(tag)
    }
}
