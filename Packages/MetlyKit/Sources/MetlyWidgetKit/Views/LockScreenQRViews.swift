import MetlyCore
import SwiftUI
import WidgetKit

/// WIDGET_LOCK_QR_RECT (accessoryRectangular): QR + "Scan to connect" + owner name.
/// The QR is rendered by the widget itself, so anyone can scan it without the phone being unlocked (Q23).
///
/// `backdrop` sits behind the QR: `AccessoryWidgetBackground()` in the extension, a translucent fill in
/// the gallery. In vibrant mode it gives the cut-out modules a consistent dark base.
public struct LockQRRectangularView<Backdrop: View>: View {
    let content: CardWidgetContent
    let backdrop: Backdrop

    public init(content: CardWidgetContent, @ViewBuilder backdrop: () -> Backdrop) {
        self.content = content
        self.backdrop = backdrop()
    }

    public var body: some View {
        switch content {
        case .card(let display):
            HStack(spacing: 8) {
                WidgetQRCode(payload: display.card.qrPayload, quietZone: 2, isDimmed: display.isPaused)
                    .padding(2)
                    .background { backdrop }
                    .clipShape(.rect(cornerRadius: 6, style: .continuous))
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 0) {
                    Text(display.isPaused ? String(localized: "Link Paused") : String(localized: "Scan to connect"))
                        .font(.headline)
                        .lineLimit(2)
                        .widgetAccentable()
                    Text(display.owner.displayName)
                        .font(.caption)
                        .lineLimit(1)
                }
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("QR code for \(display.owner.displayName)"))
            .accessibilityValue(display.isPaused ? Text("Link Paused") : Text("Scan to connect"))
        case .noCard, .signedOut:
            HStack(spacing: 8) {
                Image(systemName: "qrcode")
                    .font(.title)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Brand.appName).font(.headline)
                    Text(content == .noCard ? String(localized: "Create a card to show its QR.")
                                            : String(localized: "Sign in to show your QR."))
                        .font(.caption)
                }
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// WIDGET_LOCK_QR_CIRC (accessoryCircular): the QR inside the circle.
public struct LockQRCircularView<Backdrop: View>: View {
    let content: CardWidgetContent
    let backdrop: Backdrop

    public init(content: CardWidgetContent, @ViewBuilder backdrop: () -> Backdrop) {
        self.content = content
        self.backdrop = backdrop()
    }

    /// Side of the square inscribed in the circle (1/√2), minus a hair of breathing room.
    static var inscribedFraction: CGFloat { 0.69 }

    public var body: some View {
        ZStack {
            backdrop
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height) * Self.inscribedFraction
                Group {
                    if let display = content.display {
                        WidgetQRCode(payload: display.card.qrPayload, quietZone: 2, isDimmed: display.isPaused)
                    } else {
                        Image(systemName: "qrcode")
                            .resizable()
                            .scaledToFit()
                            .widgetAccentable()
                    }
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(content.display.map { String(localized: "QR code for \($0.owner.displayName)") }
                                 ?? String(localized: "\(Brand.appName) QR code")))
    }
}
