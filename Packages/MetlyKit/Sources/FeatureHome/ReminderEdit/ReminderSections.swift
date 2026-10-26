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

/// Quick picks (Tomorrow · In 3 Days · Next Week), Date (min today) and Time (default 10:00),
/// with the "Tanishly will remind you …" summary.
struct ReminderWhenSection: View {
    @Binding var form: ReminderForm
    let minimumDay: Date

    var body: some View {
        Section {
            FollowUpQuickPicker(selection: FollowUpQuickPick.matching(form.day),
                                picks: [.tomorrow, .inThreeDays, .nextWeek], onSelect: pick)
            DatePicker("Date", selection: $form.day, in: minimumDay..., displayedComponents: .date)
            DatePicker("Time", selection: $form.time, displayedComponents: .hourAndMinute)
        } header: {
            Text("When")
        } footer: {
            Text(form.summary())
        }
    }

    private func pick(_ pick: FollowUpQuickPick) {
        guard let offset = pick.dayOffset else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        form.day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }
}

/// Reply Via: segmented Telegram | Email | Call; channels without a value for the person are disabled.
struct ReminderChannelSection: View {
    @Binding var channel: FollowUpChannel
    let person: Connection?

    var body: some View {
        let available = ChannelLink.availableChannels(for: person)
        Section {
            Picker("Reply Via", selection: $channel) {
                ForEach(FollowUpChannel.allCases) { option in
                    Text(option.title)
                        .tag(option)
                        .disabled(!available.contains(option))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Reply Via")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let person, !ChannelLink.canOpen(channel, for: person) {
                    Text(ChannelLink.missingValueNote(channel, firstName: PersonText.firstName(person.fullName)))
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
                Button("Open Person", systemImage: "person.crop.circle", action: onOpenPerson)
            }
        }
        Section {
            Button("Delete Reminder", role: .destructive, action: onDelete)
                .frame(maxWidth: .infinity)
        }
    }
}
