import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// A Home reminder: avatar, name, "{task} · {event or company} · {due}" (tap → REMINDER_EDIT), then
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

            // Always one row, the same shape for every reminder: when the titles don't fit (a long
            // channel name, Russian words) Snooze and Done drop to their icons. A column only at
            // accessibility text sizes, where even icons don't fit.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons(compact: false) }
                HStack(spacing: 8) { buttons(compact: true) }
                VStack(alignment: .leading, spacing: 8) { buttons(compact: false) }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private func buttons(compact: Bool) -> some View {
        let channel = followUp.channel
        let target = ChannelLink.target(channel, for: followUp.connection)
        Button(action: actions.openChannel) {
            ActionLabel(verbatim: ChannelLink.actionTitle(channel), systemImage: channel.symbolName)
        }
        .disabled(target == nil)
        .accessibilityLabel(Text("\(ChannelLink.actionTitle(channel)) \(PersonText.firstName(PersonText.displayName(followUp.connection)))"))
        .accessibilityHint(target?.isTelegramByPhone == true ? Text("Opens Telegram by phone number") : Text(""))

        Menu {
            SnoozeMenuItems(dueAt: followUp.dueAt, action: actions.snooze)
        } label: {
            ActionLabel("Snooze", systemImage: "clock.arrow.circlepath", iconOnly: compact)
        }
        .accessibilityLabel(Text("Snooze \(followUp.title)"))

        Button(action: actions.done) {
            ActionLabel("Done", systemImage: "checkmark", iconOnly: compact)
        }
        .accessibilityLabel(Text("Mark \(followUp.title) done"))
    }
}

/// Icon and title close together (the system label style leaves a wide gap in small bordered buttons).
private struct ActionLabel: View {
    let title: Text
    let systemImage: String
    var iconOnly = false

    init(_ title: LocalizedStringKey, systemImage: String, iconOnly: Bool = false) {
        self.title = Text(title); self.systemImage = systemImage; self.iconOnly = iconOnly
    }

    /// An already-localized title (the channel name).
    init(verbatim title: String, systemImage: String, iconOnly: Bool = false) {
        self.title = Text(verbatim: title); self.systemImage = systemImage; self.iconOnly = iconOnly
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            if !iconOnly {
                title.lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// Avatar + name + "{task} · {event or company} · {due}" — the tappable part of a Home reminder.
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
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Group {
                    if let detail = PersonText.reminderDetail(of: followUp) {
                        Text("\(detail) · \(dueText)")
                    } else {
                        dueText
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text([name, PersonText.reminderDetail(of: followUp)].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityValue(Text([due, emphasis.accessibilityNote].compactMap { $0 }.joined(separator: ", ")))
    }
}
