import SwiftUI

/// Every "nothing here yet" in the app: an isometric illustration, a title, one short line of
/// description and the action that fills the screen (prominent first, an optional secondary one).
///
/// - `.screen`: centred in an empty screen or list background (replaces `ContentUnavailableView`).
/// - `.inline`: inside a `List` section row (Home sections, event people), smaller art.
///
/// The illustration is dropped at accessibility text sizes so the words and the button stay on screen.
public struct EmptyStateView<Actions: View>: View {
    public enum Style: Sendable { case screen, inline }

    let art: EmptyStateArt
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let style: Style
    let actions: Actions

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(_ art: EmptyStateArt, title: LocalizedStringKey, message: LocalizedStringKey,
                style: Style = .screen, @ViewBuilder actions: () -> Actions) {
        self.art = art
        self.title = title
        self.message = message
        self.style = style
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: style == .screen ? 20 : 14) {
            if !dynamicTypeSize.isAccessibilitySize {
                IsometricArtView(art)
                    .frame(maxWidth: style == .screen ? 300 : 180, maxHeight: style == .screen ? 210 : 120)
            }
            VStack(spacing: 6) {
                Text(title)
                    .font(style == .screen ? .title3.weight(.semibold) : .headline)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(style == .screen ? .body : .subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Group {
                if style == .screen {
                    VStack(spacing: 10) { actions }
                } else {
                    // In a card: hugging buttons side by side, stacked when they don't fit.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { actions }
                        VStack(spacing: 10) { actions }
                    }
                }
            }
            // Full screen: every CTA spans the column. Inside a card the buttons hug their label
            // (use `subtleButtonStyle()` there).
            .labelStyle(EmptyStateButtonLabelStyle(fillsWidth: style == .screen))
            .controlSize(style == .screen ? .large : .regular)
            .font(.body.weight(.semibold))
        }
        .frame(maxWidth: style == .screen ? 360 : .infinity)
        .padding(.horizontal, style == .screen ? 32 : 4)
        .padding(.vertical, style == .screen ? 24 : 12)
        .frame(maxWidth: .infinity, maxHeight: style == .screen ? .infinity : nil)
    }
}

/// Icon + title; across the full width when `fillsWidth`, so the CTA buttons fill the column.
/// Long titles (ru) shrink a little instead of wrapping inside the capsule.
private struct EmptyStateButtonLabelStyle: LabelStyle {
    let fillsWidth: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            configuration.title
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil)
    }
}

#Preview("Empty state · screen") {
    EmptyStateView(.connections, title: "No Connections Yet",
                   message: "Scan someone’s card or open Connect. Your notes about them stay private.") {
        Button("Open Connect", systemImage: "dot.radiowaves.left.and.right") {}
            .prominentButtonStyle()
        Button("Show My QR", systemImage: "qrcode") {}
            .secondaryButtonStyle()
    }
}

#Preview("Empty state · inline") {
    List {
        Section("Follow Up Today") {
            EmptyStateView(.followUps, title: "No Follow-ups Yet",
                           message: "Add one right after you connect.", style: .inline) {
                Button("New Reminder", systemImage: "plus") {}
                    .subtleButtonStyle()
            }
        }
    }
}
