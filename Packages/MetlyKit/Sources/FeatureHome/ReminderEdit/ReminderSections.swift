import MetlyCapture
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// Person row: fixed (editing, or opened from a person) or a link to the searchable picker.
struct ReminderPersonSection: View {
    let person: Connection?
    let isFixed: Bool
    @Binding var selection: UUID?

    var body: some View {
        Section {
            if isFixed, let person {
                ReminderPersonLabel(person: person)
            } else {
                NavigationLink {
                    ReminderPersonPicker(selection: $selection)
                } label: {
                    if let person {
                        ReminderPersonLabel(person: person)
                            .accessibilityHint("Changes the person")
                    } else {
                        Label("Choose a Person", systemImage: "person.crop.circle.badge.plus")
                            .foregroundStyle(.tint)
                    }
                }
            }
        } header: {
            Text("Person")
        } footer: {
            if !isFixed, person == nil {
                Text("Choose who you want to follow up with.")
            }
        }
    }
}

struct ReminderPersonLabel: View {
    let person: Connection

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: person.fullName, imageData: person.avatarData, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.fullName)
                    .foregroundStyle(.primary)
                if let context = PersonText.context(of: person) {
                    Text(context)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Date (min today) and Time (default 10:00), with the "Nameshake will remind you …" summary.
/// No quick-pick chips here (owner, 2026-11-13): editing a reminder sets an exact date.
struct ReminderWhenSection: View {
    @Binding var form: ReminderForm
    let minimumDay: Date

    var body: some View {
        Section {
            DatePicker("Date", selection: $form.day, in: minimumDay..., displayedComponents: .date)
            DatePicker("Time", selection: $form.time, displayedComponents: .hourAndMinute)
        } header: {
            Text("When")
        } footer: {
            Text(form.summary())
        }
    }
}

/// "How to Contact": Telegram / Email / Call as a list with a checkmark on the chosen one; channels
/// without a value for the person are disabled.
struct ReminderChannelSection: View {
    @Binding var channel: FollowUpChannel
    let person: Connection?

    var body: some View {
        let available = ChannelLink.availableChannels(for: person)
        Section {
            Picker("How to Contact", selection: $channel) {
                ForEach(FollowUpChannel.allCases) { option in
                    Label {
                        Text(option.title)
                    } icon: {
                        ChannelIcon(channel: option)
                    }
                    .tag(option)
                        .disabled(!available.contains(option))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("How to Contact")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let person {
                    if let target = ChannelLink.target(channel, for: person) {
                        if target.isTelegramByPhone {
                            Text(TelegramTarget.byPhoneNote)
                        }
                    } else {
                        Text(ChannelLink.missingValueNote(channel, firstName: PersonText.firstName(person.fullName)))
                    }
                }
                Text("Only you see your reminders. The other person is never notified.")
            }
        }
        .sensoryFeedback(.selection, trigger: channel)
    }
}

/// Edit-mode extras: Open Person and Delete Reminder.
struct ReminderEditExtras: View {
    let person: Connection?
    let onOpenPerson: () -> Void
    let onDelete: () -> Void

    var body: some View {
        if person != nil {
            Section {
                // Centred like Delete Reminder below: two stand-alone actions, not list rows.
                Button("Open Person", systemImage: "person.crop.circle", action: onOpenPerson)
                    .frame(maxWidth: .infinity)
            }
        }
        Section {
            Button("Delete Reminder", role: .destructive, action: onDelete)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Settings-style tile, in the same colour as the field on Profile. Every glyph is fitted into the
/// same box, so the wide envelope and the narrow phone read as one set.
private struct ChannelIcon: View {
    let channel: FollowUpChannel

    var body: some View {
        channel.icon
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .frame(width: 14, height: 14)
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(channel.fieldKind.tint.gradient, in: .rect(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }
}
