import MetlyCore
import SwiftUI
import WidgetKit

/// WIDGET_FOLLOWUPS_M (systemMedium): "Follow Up Today" + count of open reminders due today or overdue,
/// then up to 3 rows (what, "{name} · {due}"). Each row links to REMINDER_EDIT; the leading circle marks it
/// done (the extension wraps it in `Button(intent:)`, the gallery shows it inert).
public struct FollowUpsWidgetView<DoneButton: View>: View {
    let content: FollowUpsWidgetContent
    let now: Date
    let doneButton: (WidgetFollowUp) -> DoneButton
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(content: FollowUpsWidgetContent, now: Date, @ViewBuilder doneButton: @escaping (WidgetFollowUp) -> DoneButton) {
        self.content = content
        self.now = now
        self.doneButton = doneButton
    }

    public var body: some View {
        switch content {
        case .signedOut:
            WidgetMessageView(systemImage: "bell", title: "Follow-ups",
                              message: "Sign in to \(Brand.appName) to see your follow-ups.")
        case .reminders(let summary):
            VStack(alignment: .leading, spacing: 6) {
                FollowUpsHeader(count: summary.dueCount)
                if summary.due.isEmpty {
                    FollowUpsEmptyState(summary: summary, now: now)
                } else {
                    ForEach(summary.due.prefix(maxRows)) { followUp in
                        FollowUpsWidgetRow(followUp: followUp, now: now, doneButton: doneButton(followUp))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Fewer, wrapping rows at large text sizes.
    private var maxRows: Int {
        if dynamicTypeSize.isAccessibilitySize { return 1 }
        return dynamicTypeSize >= .xLarge ? 2 : 3
    }
}

struct FollowUpsHeader: View {
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Follow Up Today")
                .font(.headline)
                .widgetAccentable()
            Spacer(minLength: 4)
            if count > 0 {
                Text(count, format: .number)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.tint)
                    .widgetAccentable()
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Follow Up Today"))
        .accessibilityValue(Text(count == 1 ? String(localized: "1 reminder", bundle: .appStrings) : String(localized: "\(count) reminders", bundle: .appStrings)))
    }
}

struct FollowUpsWidgetRow<DoneButton: View>: View {
    let followUp: WidgetFollowUp
    let now: Date
    let doneButton: DoneButton

    var body: some View {
        let due = WidgetDueLabel(due: followUp.dueAt, now: now)
        HStack(spacing: 8) {
            doneButton
            Link(destination: WidgetDeepLink.reminder(followUp.id)) {
                // Explicit colours: a Link would otherwise tint its label with the accent colour.
                VStack(alignment: .leading, spacing: 0) {
                    Text(followUp.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                    Text("\(followUp.personName) · \(Text(due.text).foregroundStyle(due.style))")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(followUp.title), \(followUp.personName)"))
            .accessibilityValue(Text([due.text, due.accessibilityNote].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityHint(Text("Opens the reminder"))
        }
        .privacySensitive()
    }
}

/// Nothing due today: "All Caught Up" (+ the next reminder), or "No Follow-ups Yet" when there are none.
struct FollowUpsEmptyState: View {
    let summary: FollowUpsWidgetSummary
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: summary.isEmpty ? "bell" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(summary.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
                .widgetAccentable()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.isEmpty ? "No Follow-ups Yet" : "All Caught Up")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var message: String {
        if summary.isEmpty { return String(localized: "Add one right after you connect.", bundle: .appStrings) }
        guard let next = summary.next else { return String(localized: "Nothing due today.", bundle: .appStrings) }
        let due = WidgetDueLabel(due: next.dueAt, now: now)
        return String(localized: "Next: \(next.personName) · \(due.text)", bundle: .appStrings)
    }
}

extension WidgetDueLabel {
    /// Red when overdue, tinted today (SPEC §2.5.14).
    var style: AnyShapeStyle {
        switch emphasis {
        case .overdue: AnyShapeStyle(.red)
        case .today: AnyShapeStyle(.tint)
        case .upcoming: AnyShapeStyle(Color.secondary)
        }
    }
}
