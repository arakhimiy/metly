import SwiftUI

/// Chips for Tomorrow · In 3 Days · Next Week · Pick a Date… (single select).
public struct FollowUpQuickPicker: View {
    let selection: FollowUpQuickPick?
    let picks: [FollowUpQuickPick]
    let onSelect: (FollowUpQuickPick) -> Void

    public init(selection: FollowUpQuickPick?, picks: [FollowUpQuickPick] = FollowUpQuickPick.allCases,
                onSelect: @escaping (FollowUpQuickPick) -> Void) {
        self.selection = selection
        self.picks = picks
        self.onSelect = onSelect
    }

    public var body: some View {
        TagFlowLayout {
            ForEach(picks) { pick in
                CaptureChip(pick.title, isSelected: selection == pick) { onSelect(pick) }
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
