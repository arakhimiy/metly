import Foundation
import MetlyData
import SwiftUI

/// Status pill of a person in "People You Met": due label (tinted), red Overdue, Done or None.
enum FollowUpStatus: Equatable {
    case none
    case done
    case due(Date)
    case overdue(Date)

    init(person: Connection, now: Date = .now) {
        if let open = person.openFollowUp {
            self = open.dueAt < now ? .overdue(open.dueAt) : .due(open.dueAt)
        } else if person.followUps.contains(where: { $0.isDone && !$0.isDeleted }) {
            self = .done
        } else {
            self = .none
        }
    }

    func title(now: Date = .now, calendar: Calendar = .current) -> String {
        switch self {
        case .none: "None"
        case .done: "Done"
        case .overdue: "Overdue"
        case .due(let date):
            if calendar.isDate(date, inSameDayAs: now) {
                "Today"
            } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
                "Tomorrow"
            } else {
                date.formatted(.dateTime.month(.abbreviated).day())
            }
        }
    }

    var systemImage: String {
        switch self {
        case .none: "bell.slash"
        case .done: "checkmark"
        case .due: "bell"
        case .overdue: "exclamationmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .none: .secondary
        case .done: .green
        case .due: .accentColor
        case .overdue: .red
        }
    }

    func accessibilityLabel(now: Date = .now) -> String {
        switch self {
        case .none: "No follow-up"
        case .done: "Follow-up done"
        case .overdue: "Follow-up overdue"
        case .due: "Follow-up \(title(now: now))"
        }
    }
}

/// Capsule showing a `FollowUpStatus`; icon + text so it never relies on color alone.
struct FollowUpStatusPill: View {
    let status: FollowUpStatus

    var body: some View {
        Label(status.title(), systemImage: status.systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(status.tint.opacity(0.12), in: .capsule)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(status.accessibilityLabel())
    }
}
