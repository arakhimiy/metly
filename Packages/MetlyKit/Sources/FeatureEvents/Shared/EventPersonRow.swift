import MetlyData
import MetlyDesign
import SwiftUI

/// "People You Met" row: avatar, name, note (or "No note yet") and the follow-up status pill.
struct EventPersonRow: View {
    let person: Connection

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: person.fullName, imageData: person.avatarData, size: 40)
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.fullName)
                        .font(.body.weight(.semibold))
                        .lineLimit(2)
                    Text(hasNote ? person.note.trimmed : String(localized: "No note yet", bundle: .appStrings))
                        .font(.subheadline)
                        .foregroundStyle(hasNote ? .secondary : .tertiary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                FollowUpStatusPill(status: FollowUpStatus(person: person))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var hasNote: Bool { !person.note.trimmed.isEmpty }
}
