import MetlyData
import SwiftUI

/// One bucket with its count; Overdue has a red header, Done can be shown or hidden.
struct FollowUpGroupSection: View {
    let group: FollowUpGroup<FollowUp>
    let now: Date
    @Binding var showsDone: Bool
    let showsSwipeHint: Bool
    let actions: (FollowUp) -> FollowUpRow.Actions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isDone = group.bucket == .done
        Section {
            if !isDone || showsDone {
                ForEach(group.items) { followUp in
                    FollowUpRow(followUp: followUp, now: now, actions: actions(followUp))
                }
            }
        } header: {
            HomeSectionHeader(title) {
                HStack(spacing: 12) {
                    Text(group.items.count, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    if isDone {
                        Button(showsDone ? "Hide" : "Show", action: toggleDone)
                            .accessibilityLabel(showsDone ? Text("Hide Done") : Text("Show Done"))
                    }
                }
            }
            .accessibilityElement(children: .contain)
        } footer: {
            if showsSwipeHint {
                Text("Swipe right on a reminder to mark it done, or left to snooze it.")
            }
        }
    }

    private var title: Text {
        let base = Text(group.bucket.title)
        let count = Text("^[\(group.items.count) reminder](inflect: true)")
        return (group.bucket == .overdue ? base.foregroundStyle(.red) : base)
            .accessibilityLabel(Text("\(group.bucket.title), \(count)"))
    }

    private func toggleDone() {
        withAnimation(reduceMotion ? nil : .default) {
            showsDone.toggle()
        }
    }
}
