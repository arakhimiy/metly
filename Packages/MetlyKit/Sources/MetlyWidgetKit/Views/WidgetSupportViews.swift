import MetlyCardKit
import MetlyCore
import SwiftUI
import WidgetKit

/// Container backgrounds shared by the widget extension (`containerBackground`) and the gallery previews.
public enum WidgetBackgrounds {
    /// The card's palette — solid, or its gradient for gradient designs (SPEC Appendix B colours).
    public static func card(_ design: CardDesign) -> LinearGradient {
        let colors = design.colors
        let end = design.usesGradientFill ? colors.gradientEnd : colors.background
        return LinearGradient(colors: [colors.background.color, end.color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Neutral background for the Card and Follow-ups widgets.
    public static var standard: Color { Color(.systemBackground) }
}

/// Icon + title + message, for signed-out / no-card / empty states in system families.
public struct WidgetMessageView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    public init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .widgetAccentable()
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// "Open Nameshake to make your first card."
    public static var noCard: WidgetMessageView {
        WidgetMessageView(systemImage: "rectangle.stack.badge.plus", title: "Create Your Card",
                          message: "Open \(Brand.appName) to make your first card.")
    }

    public static var signedOutQR: WidgetMessageView {
        WidgetMessageView(systemImage: "qrcode", title: "\(Brand.appName)",
                          message: "Sign in to show your QR code here.")
    }
}

/// The "mark done" circle used by Follow-ups rows (wrapped in `Button(intent:)` by the extension).
public struct FollowUpDoneGlyph: View {
    public init() {}

    public var body: some View {
        Image(systemName: "circle")
            .font(.title3)
            .foregroundStyle(.secondary)
            .widgetAccentable()
            .frame(width: 28, height: 28)
            .contentShape(.circle)
    }
}
