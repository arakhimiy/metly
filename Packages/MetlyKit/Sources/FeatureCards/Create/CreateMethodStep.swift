import SwiftUI

/// Step 1 — "How do you want to start?": Start from a Template / Blank Card.
struct CreateMethodStep: View {
    /// False for the very first card after setup, which can't be skipped.
    let canCancel: Bool
    let onCancel: () -> Void
    let onChoose: (CreateMethod) -> Void

    var body: some View {
        List {
            Section {
                CreateMethodRow(title: "Start from a Template", subtitle: "Nine layouts, ready for your details",
                                systemImage: "square.grid.2x2.fill", color: .accentColor) {
                    onChoose(.template)
                }
                CreateMethodRow(title: "Blank Card", subtitle: "A minimal layout to build on",
                                systemImage: "rectangle.fill", color: .gray) {
                    onChoose(.blank)
                }
            } header: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How do you want to start?")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Text("You can change everything later in the editor.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
        }
        .navigationTitle("New Card")
        .navigationBarTitleDisplayMode(.inline)
        .createProgress(0.2)
        .toolbar {
            if canCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

/// A large tappable option row with icon, title, subtitle and a disclosure chevron.
struct CreateMethodRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
    let action: () -> Void
    @ScaledMetric(relativeTo: .title3) private var iconSide: CGFloat = 44

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: iconSide, height: iconSide)
                    .background(color.gradient, in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .accessibilityElement(children: .combine)
    }
}
