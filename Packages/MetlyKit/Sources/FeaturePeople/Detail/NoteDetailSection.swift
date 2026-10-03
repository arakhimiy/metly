import MetlyCapture
import MetlyData
import SwiftUI

/// Private note + tags ("Only You").
struct NoteDetailSection: View {
    let person: Connection
    let onEdit: () -> Void

    var body: some View {
        Section {
            if person.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Add Note…", systemImage: "square.and.pencil", action: onEdit)
            } else {
                Text(person.note)
                    .textSelection(.enabled)
            }
            if !person.tags.isEmpty {
                TagFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(person.tags, id: \.self) { tag in
                        TagCapsule(title: tag)
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Tags: \(person.tags.joined(separator: ", "))")
            }
        } header: {
            HStack {
                Text("Private Note")
                Spacer()
                if !person.note.isEmpty {
                    Button("Edit", action: onEdit)
                        .font(.subheadline)
                        .textCase(nil)
                }
            }
        } footer: {
            Label("Only You", systemImage: "lock.fill")
        }
    }
}

/// Read-only tag capsule.
struct TagCapsule: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.fill.tertiary, in: .capsule)
    }
}
