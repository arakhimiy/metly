import MetlyCardKit
import MetlyCore
import MetlyDesign
import SwiftUI

/// Their card face (their design, fields visible to you) with name and "{title} · {company}".
struct ScannedCardHeader: View {
    let snapshot: CardSnapshot

    var body: some View {
        Section {
            VStack(spacing: 16) {
                CardFaceView(design: snapshot.design, content: snapshot.faceContent)
                    .cardFaceElevation()
                    .frame(maxWidth: 420)
                PersonTitle(name: snapshot.fullName, role: snapshot.faceContent.role)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4))
    }
}

/// A foreign vCard has no card design: initials, name, role and where it came from.
struct ContactCardHeader: View {
    let contact: PaperCardDraft

    var body: some View {
        Section {
            VStack(spacing: 12) {
                InitialsAvatar(name: ScanConnectionFactory.displayName(for: contact), size: 80)
                PersonTitle(name: ScanConnectionFactory.displayName(for: contact),
                            role: [contact.jobTitle, contact.company].filter { !$0.isEmpty }.joined(separator: " · "))
                Label("Contact Card", systemImage: "person.text.rectangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }
}

/// Name (title2) over a secondary role line, read as one element.
struct PersonTitle: View {
    let name: String
    let role: String

    var body: some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.title2.bold())
            if !role.isEmpty {
                Text(role)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
