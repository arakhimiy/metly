import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// Large avatar, name, "{title} · {company}" and how they were added.
struct DetailHeaderSection: View {
    let person: Connection

    var body: some View {
        Section {
            VStack(spacing: 8) {
                InitialsAvatar(name: person.fullName, imageData: person.avatarData, size: 96)
                Text(person.fullName)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if !role.isEmpty {
                    Text(role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if person.source == .webShareBack {
                    ViaWebBadge()
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.clear)
    }

    private var role: String {
        [person.jobTitle, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// "Merged · Your QR note + their web share-back".
struct MergedBannerSection: View {
    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Merged")
                        .font(.headline)
                    Text("Your QR note + their web share-back")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "arrow.triangle.merge")
                    .foregroundStyle(.tint)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
