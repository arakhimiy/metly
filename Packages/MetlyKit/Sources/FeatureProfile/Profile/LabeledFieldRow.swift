import SwiftUI

/// Settings-style editable row: icon · small title above an inline text field · trailing accessory.
/// Stacks vertically at accessibility text sizes so nothing truncates.
struct LabeledFieldRow<Icon: View, Field: View, Accessory: View>: View {
    let title: String
    @ViewBuilder let icon: Icon
    @ViewBuilder let field: Field
    @ViewBuilder let accessory: Accessory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                field
                    .accessibilityLabel(Text(title))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
    }
}
