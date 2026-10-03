import MetlyCardKit
import MetlyCore
import SwiftUI
import WidgetKit

/// WIDGET_QR_S (systemSmall): the card's QR + first name and "{Card} Card" — "Your QR, one tap away."
/// Background: the card palette (applied by the caller with `WidgetBackgrounds.card`).
public struct MyQRWidgetView: View {
    let content: CardWidgetContent
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    public init(content: CardWidgetContent) {
        self.content = content
    }

    public var body: some View {
        switch content {
        case .card(let display):
            ready(display)
        case .noCard:
            WidgetMessageView.noCard
        case .signedOut:
            WidgetMessageView.signedOutQR
        }
    }

    private func ready(_ display: CardWidgetDisplay) -> some View {
        let usesPalette = renderingMode == .fullColor && showsBackground
        let colors = display.card.design.colors
        return VStack(spacing: 6) {
            WidgetQRCode(payload: display.card.qrPayload, isDimmed: display.isPaused)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if display.isPaused { PausedBadge() }
                }
                .layoutPriority(1)
            VStack(spacing: 0) {
                Text(display.owner.firstName)
                    .font(.headline)
                    .widgetAccentable()
                Text(display.isPaused ? String(localized: "Link Paused") : display.card.displayName)
                    .font(.caption2)
                    .foregroundStyle(usesPalette ? AnyShapeStyle(colors.muted.color) : AnyShapeStyle(.secondary))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .foregroundStyle(usesPalette ? AnyShapeStyle(colors.foreground.color) : AnyShapeStyle(.primary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(display.card.displayName) QR code"))
        .accessibilityValue(display.isPaused ? Text("Link Paused") : Text(display.owner.displayName))
        .accessibilityHint(Text("Shows your QR code full screen"))
    }
}

/// "Link Paused" label over a dimmed QR (SPEC QR_FULLSCREEN paused state).
struct PausedBadge: View {
    var body: some View {
        Label("Link Paused", systemImage: "pause.fill")
            .labelStyle(.iconOnly)
            .font(.title3.weight(.semibold))
            .accessibilityHidden(true)
    }
}
