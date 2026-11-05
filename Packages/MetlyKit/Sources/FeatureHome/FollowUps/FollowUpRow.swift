import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// FOLLOWUPS row: tap → REMINDER_EDIT; swipe right Done / Undo; swipe left Snooze (+1 day);
/// touch and hold → MENU_REMINDER_ROW (Edit… · Open Person · Snooze · Done/Undo · Delete).
struct FollowUpRow: View {
    struct Actions {
        var edit: () -> Void
        var openPerson: () -> Void
        var snooze: (SnoozeOption) -> Void
        var toggleDone: () -> Void
        var delete: () -> Void
    }

    let followUp: FollowUp
    let now: Date
    let actions: Actions

    var body: some View {
        Button(action: actions.edit) {
            FollowUpRowContent(followUp: followUp, now: now)
                .contentShape(.rect)
        }
        .foregroundStyle(.primary)
        .accessibilityHint("Edits the reminder")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if followUp.isDone {
                Button("Undo", systemImage: "arrow.uturn.backward", action: actions.toggleDone)
                    .tint(.blue)
                    .accessibilityLabel("Mark as Not Done")
            } else {
                Button("Done", systemImage: "checkmark", action: actions.toggleDone)
                    .tint(.green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !followUp.isDone {
                Button("Snooze", systemImage: "clock.arrow.circlepath") { actions.snooze(.tomorrow) }
                    .tint(.orange)
                    .accessibilityLabel("Snooze 1 Day")
            }
        }
        .contextMenu {
            Section {
                Button("Edit…", systemImage: "pencil", action: actions.edit)
                if followUp.connection != nil {
                    Button("Open Person", systemImage: "person.crop.circle", action: actions.openPerson)
                }
            }
            Section {
                if !followUp.isDone {
                    Menu("Snooze", systemImage: "clock.arrow.circlepath") {
                        SnoozeMenuItems(dueAt: followUp.dueAt, action: actions.snooze)
                    }
                    Button("Done", systemImage: "checkmark.circle", action: actions.toggleDone)
                } else {
                    Button("Mark as Not Done", systemImage: "arrow.uturn.backward.circle", action: actions.toggleDone)
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive, action: actions.delete)
        }
    }
}

/// Avatar · name (struck through when done) · "{task} · {event or company}" · due label + channel icon.
struct FollowUpRowContent: View {
    let followUp: FollowUp
    let now: Date

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let calendar = Calendar.current
        let person = followUp.connection
        let name = PersonText.displayName(person)
        let detail = PersonText.reminderDetail(of: followUp)
        let due = FollowUpDates.dueLabel(followUp.dueAt, now: now, calendar: calendar)
        let emphasis = DueEmphasis.of(dueAt: followUp.dueAt, isDone: followUp.isDone, now: now, calendar: calendar)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        layout {
            InitialsAvatar(name: name, imageData: person?.avatarData, size: 40)
                .opacity(followUp.isDone ? 0.6 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .strikethrough(followUp.isDone)
                    .foregroundStyle(followUp.isDone ? .secondary : .primary)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Text(due)
                    .font(.subheadline)
                    .foregroundStyle(emphasis.style)
                Image(systemName: followUp.channel.symbolName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([name, detail].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityValue(Text(accessibilityValue(due: due, emphasis: emphasis)))
    }

    private func accessibilityValue(due: String, emphasis: DueEmphasis) -> String {
        var parts = [due]
        if let note = emphasis.accessibilityNote { parts.append(note) }
        parts.append(String(localized: "via \(followUp.channel.title)"))
        if followUp.isDone { parts.append(String(localized: "Done")) }
        return parts.joined(separator: ", ")
    }
}
