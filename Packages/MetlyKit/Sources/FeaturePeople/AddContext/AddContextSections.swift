import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// Person header: initials, name and how they reached you.
struct AddContextHeaderSection: View {
    let person: Connection

    var body: some View {
        Section {
            HStack(spacing: 12) {
                InitialsAvatar(name: person.fullName, imageData: person.avatarData, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.fullName)
                        .font(.headline)
                    kindLabel
                        .font(.subheadline)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var kindLabel: some View {
        switch person.source {
        case .webShareBack:
            Label("Shared via your web page", systemImage: "globe")
                .foregroundStyle(.tint)
        case .contactsCapture:
            Label("Added to Contacts", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        default:
            let role = [person.jobTitle, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
            if !role.isEmpty {
                Text(role).foregroundStyle(.secondary)
            }
        }
    }
}

/// "Is this who you met at 14:32?" — explicit confirmation before merging (PLAN Q18).
struct MergePromptSection: View {
    let candidate: Connection
    let onMerge: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Is this who you met at \(candidate.context.metAt.formatted(date: .omitted, time: .shortened))?")
                            .font(.headline)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } icon: {
                    Image(systemName: "arrow.triangle.merge")
                        .foregroundStyle(.tint)
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: 12) {
                    Button(action: onDismiss) {
                        Text("Not Them").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(action: onMerge) {
                        Text("Merge").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding(.vertical, 4)
        } footer: {
            Text("Merging keeps your note and adds the contact details they shared.")
        }
    }

    /// "Your note: “Talked about…”" or where you met.
    private var detail: String {
        let note = candidate.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return "Your note: “\(note)”" }
        let place = candidate.context.eventName ?? candidate.context.place
        return place.map { "\(candidate.fullName) · \($0)" } ?? candidate.fullName
    }
}
