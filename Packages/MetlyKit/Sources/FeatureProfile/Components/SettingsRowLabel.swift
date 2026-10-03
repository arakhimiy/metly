import MetlyDesign
import SwiftUI

/// iOS Settings-style row label: colored rounded-square symbol + title in the primary color
/// (also inside `Button`s, which would otherwise tint the title).
struct SettingsRowLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let systemImage: String
    let color: Color

    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            // `Color.primary`, not `.primary`: inside a Button the hierarchical style would resolve to the tint.
            Text(title)
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        } icon: {
            SettingsIcon(systemImage, color: color)
        }
    }
}
