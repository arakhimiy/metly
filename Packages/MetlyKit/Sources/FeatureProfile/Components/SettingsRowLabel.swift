import MetlyDesign
import SwiftUI

/// iOS Settings-style row label: colored rounded-square symbol + title in the primary color
/// (also inside `Button`s, which would otherwise tint the title).
struct SettingsRowLabel: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: Text
    let systemImage: String
    let color: Color

    /// Localizable title (String Catalog key).
    init(_ title: LocalizedStringKey, systemImage: String, color: Color) {
        self.title = Text(title)
        self.systemImage = systemImage
        self.color = color
    }

    /// Product names and other strings that must not be translated (e.g. `Brand.proName`).
    init(verbatim title: String, systemImage: String, color: Color) {
        self.title = Text(verbatim: title)
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            // `Color.primary`, not `.primary`: inside a Button the hierarchical style would resolve to the tint.
            title
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
        } icon: {
            SettingsIcon(systemImage, color: color)
        }
    }
}
