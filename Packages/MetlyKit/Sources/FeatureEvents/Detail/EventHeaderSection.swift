import MetlyData
import SwiftUI

/// Day stepper (which day of the event it is), place and status ("In Progress · new connections are added automatically" / "Ended …").
struct EventHeaderSection: View {
    let event: Event

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    // The steps show weekday + day; the range above gives the month.
                    Text(EventCopy.dateRange(of: event))
                        .font(.subheadline.weight(.semibold))
                    EventDayStepper(event: event)
                }
                VStack(alignment: .leading, spacing: 10) {
                    let place = EventCopy.place(of: event)
                    if !place.isEmpty {
                        Label(place, systemImage: "mappin.and.ellipse")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                EventStatusLine(event: event)
            }
            .padding(.vertical, 8)
        }
    }
}

private struct EventStatusLine: View {
    let event: Event

    var body: some View {
        if event.isActive {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                let status = Text("In Progress").fontWeight(.semibold).foregroundStyle(.green)
                Text("\(status) · new connections are added automatically")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        } else {
            Label(endedText, systemImage: "flag.checkered")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var endedText: String {
        guard let endedAt = event.endedAt else { return String(localized: "Ended", bundle: .appStrings) }
        return String(localized: "Ended \(endedAt.formatted(.dateTime.month(.abbreviated).day()))", bundle: .appStrings)
    }
}

/// The event's days as steps: done (filled), today (accent ring), still to come (grey).
/// One step per day up to a week; longer events show the first day, today and the last day.
private struct EventDayStepper: View {
    let event: Event

    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .subheadline) private var labelHeight: CGFloat = 40

    var body: some View {
        let days = steps
        // Full width: the first day sits on the leading edge, the last on the trailing edge, and the
        // lines between them stretch. Each day's label hangs under its marker.
        HStack(spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                if index > 0 {
                    connector(done: day.state != .upcoming)
                }
                marker(day.state)
                    .overlay(alignment: labelAlignment(index, of: days.count)) {
                        dayLabel(day)
                            .fixedSize()
                            .alignmentGuide(.top) { _ in -30 }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide).month(.wide).day()))
                    .accessibilityValue(day.state == .today ? Text("Today") : Text(""))
            }
        }
        .padding(.bottom, labelHeight)
        .accessibilityElement(children: .contain)
    }

    private func labelAlignment(_ index: Int, of count: Int) -> Alignment {
        if count > 1 && index == 0 { return .topLeading }
        if count > 1 && index == count - 1 { return .topTrailing }
        return .top
    }

    private func dayLabel(_ day: Step) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(day.date, format: .dateTime.day())
                .font(.subheadline.weight(day.state == .today ? .bold : .regular))
                .foregroundStyle(day.state == .today ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
    }

    private enum StepState { case done, today, upcoming }
    private struct Step { let date: Date; let state: StepState }

    private var steps: [Step] {
        let start = calendar.startOfDay(for: event.startDate)
        let end = max(start, calendar.startOfDay(for: event.endDate))
        let today = calendar.startOfDay(for: .now)
        let count = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        var dates: [Date]
        if count <= 7 {
            dates = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        } else {
            dates = [start, end]
            if today > start && today < end { dates.insert(today, at: 1) }
        }
        return dates.map { date in
            let state: StepState
            if !event.isActive { state = .done }
            else if date < today { state = .done }
            else if date == today { state = .today }
            else { state = .upcoming }
            return Step(date: date, state: state)
        }
    }

    private func marker(_ state: StepState) -> some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(.tint)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            case .today:
                Circle().strokeBorder(.tint, lineWidth: 2.5)
                Circle().fill(.tint).padding(6)
            case .upcoming:
                Circle().strokeBorder(Color(.tertiaryLabel), lineWidth: 2)
            }
        }
        .frame(width: 22, height: 22)
    }

    private func connector(done: Bool) -> some View {
        Rectangle()
            .fill(done ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiaryLabel)))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }
}
