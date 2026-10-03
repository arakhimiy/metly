import SwiftUI

extension DueEmphasis {
    /// Red when overdue, tint when due today, secondary otherwise (never the only cue — the label says it too).
    var style: AnyShapeStyle {
        switch self {
        case .overdue: AnyShapeStyle(.red)
        case .today: AnyShapeStyle(.tint)
        case .upcoming, .done: AnyShapeStyle(.secondary)
        }
    }

    /// Spoken after the due label so VoiceOver users get the same cue as the color.
    var accessibilityNote: String? {
        switch self {
        case .overdue: String(localized: "Overdue")
        case .today, .upcoming, .done: nil
        }
    }
}
