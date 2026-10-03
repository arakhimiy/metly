import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// A Home reminder: avatar, what, "{name} · {due}" (tap → REMINDER_EDIT), then
/// channel action · Snooze ▾ · Done.
struct FollowUpTodayRow: View {
    struct Actions {
        var edit: () -> Void
        var openChannel: () -> Void
        var snooze: (SnoozeOption) -> Void
        var done: () -> Void
    }

    let followUp: FollowUp
    let now: Date
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: actions.edit) {
                FollowUpSummary(followUp: followUp, now: now)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the reminder")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .labelStyle(.titleAndIcon)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var buttons: some View {
        let channel = followUp.channel
        Button(action: actions.openChannel) {
            Label(ChannelLink.actionTitle(channel), systemImage: channel.symbolName)
        }
        .disabled(!ChannelLink.canOpen(channel, for: followUp.connection))
        .accessibilityLabel(Text("\(ChannelLink.actionTitle(channel)) \(PersonText.firstName(PersonText.displayName(followUp.connection)))"))

        Menu {
            SnoozeMenuItems(dueAt: followUp.dueAt, action: actions.snooze)
        } label: {
            Label("Snooze", systemImage: "clock.arrow.circlepath")
        }
        .accessibilityLabel(Text("Snooze \(followUp.title)"))

        Button(action: actions.done) {
            Label("Done", systemImage: "checkmark")
        }
        .accessibilityLabel(Text("Mark \(followUp.title) done"))
    }
}

/// Avatar + what + "{name} · {due}" — the tappable part of a Home reminder.
struct FollowUpSummary: View {
    let followUp: FollowUp
    let now: Date

    var body: some View {
        let calendar = Calendar.current
        let name = PersonText.displayName(followUp.connection)
        let due = FollowUpDates.dueLabel(followUp.dueAt, now: now, calendar: calendar)
        let emphasis = DueEmphasis.of(dueAt: followUp.dueAt, isDone: followUp.isDone, now: now, calendar: calendar)
        let dueText = Text(due).foregroundStyle(emphasis.style)

        HStack(spacing: 12) {
            InitialsAvatar(name: name, imageData: followUp.connection?.avatarData, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(followUp.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(name) · \(dueText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(followUp.title), \(name)"))
        .accessibilityValue(Text([due, emphasis.accessibilityNote].compactMap { $0 }.joined(separator: ", ")))
    }
}
