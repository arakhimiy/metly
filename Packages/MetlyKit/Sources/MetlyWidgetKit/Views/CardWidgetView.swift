import MetlyCardKit
import MetlyCore
import SwiftUI
import WidgetKit

/// WIDGET_CARD_M (systemMedium): the card face (with its QR) + "{Card} Card",
/// "{N} new connections this week" and a "Show QR" affordance (the whole widget opens QR_FULLSCREEN).
///
/// On a tinted / clear Home Screen (accented rendering) a full-colour card face would be flattened into
/// one tint, so the widget switches to a text layout with a scannable QR.
public struct CardWidgetView: View {
    let content: CardWidgetContent
    @Environment(\.widgetRenderingMode) private var renderingMode

    public init(content: CardWidgetContent) {
        self.content = content
    }

    public var body: some View {
        switch content {
        case .card(let display):
            if renderingMode == .fullColor {
                faceLayout(display)
            } else {
                textLayout(display)
            }
        case .noCard:
            WidgetMessageView.noCard
        case .signedOut:
            WidgetMessageView(systemImage: "person.text.rectangle", title: "\(Brand.appName)",
                              message: "Sign in to show your card here.")
        }
    }

    private func faceLayout(_ display: CardWidgetDisplay) -> some View {
        HStack(spacing: 14) {
            CardFaceView(design: display.card.widgetDesign, content: display.card.faceContent(owner: display.owner))
                .cardFaceElevation()
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            CardWidgetDetails(display: display)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows your QR code full screen"))
    }

    private func textLayout(_ display: CardWidgetDisplay) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.owner.displayName)
                    .font(.headline)
                    .widgetAccentable()
                if !display.owner.role.isEmpty {
                    Text(display.owner.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(display.card.displayName)
                    .font(.caption.weight(.semibold))
                Text(display.isPaused ? String(localized: "Link Paused", bundle: .appStrings) : display.newConnectionsText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            WidgetQRCode(payload: display.card.qrPayload, isDimmed: display.isPaused)
                .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows your QR code full screen"))
    }
}

/// Right-hand column of the card widget.
struct CardWidgetDetails: View {
    let display: CardWidgetDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(display.card.displayName)
                .font(.headline)
                .lineLimit(2)
            Text(display.isPaused ? String(localized: "Link paused. Your QR shows an inactive page.", bundle: .appStrings) : display.newConnectionsText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Spacer(minLength: 4)
            Label("Show QR", systemImage: "qrcode")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(.tint)
                .background(.tint.opacity(0.14), in: .capsule)
                .widgetAccentable()
                .accessibilityHidden(true)
        }
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
