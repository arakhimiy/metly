import MetlyCapture
import MetlyCore
import MetlyData
import SwiftUI

/// Event · Place · Met for the current meeting.
struct WhereYouMetDetailSection: View {
    let person: Connection

    @Environment(AppRouter.self) private var router

    var body: some View {
        let context = person.context
        Section("Where You Met") {
            if let eventName = context.eventName, !eventName.isEmpty {
                if let eventID = person.event?.id ?? context.eventID {
                    Button {
                        router.push(.eventDetail(id: eventID))
                    } label: {
                        LabeledContent("Event", value: eventName)
                            .contentShape(.rect)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityHint("Opens the event")
                } else {
                    LabeledContent("Event", value: eventName)
                }
            }
            if let place = MeetingFormatting.place(context) {
                LabeledContent("Place", value: place)
            }
            LabeledContent("Met") {
                Text(context.metAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            }
        }
    }
}

/// History of earlier meetings (moved here when the person was met again elsewhere).
struct EarlierMeetingsSection: View {
    let meetings: [MeetingContext]

    var body: some View {
        if !meetings.isEmpty {
            Section("Earlier Meetings") {
                ForEach(meetings, id: \.self) { meeting in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meeting.eventName ?? MeetingFormatting.place(meeting) ?? String(localized: "Meeting", bundle: .appStrings))
                            .font(.body)
                        Text(MeetingFormatting.placeAndDate(meeting))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

enum MeetingFormatting {
    /// "Hyatt Regency, Tashkent" — the city once, even when the place already ends in it.
    static func place(_ context: MeetingContext) -> String? {
        PlaceText.joined(context)
    }

    /// "Hyatt Regency · Sep 24" (the city when there's no place).
    static func placeAndDate(_ context: MeetingContext) -> String {
        let date = context.metAt.formatted(.dateTime.month(.abbreviated).day().year())
        guard let place = PlaceText.normalizedPlace(context.place, city: context.city) ?? context.city, !place.isEmpty
        else { return date }
        return "\(place) · \(date)"
    }
}
