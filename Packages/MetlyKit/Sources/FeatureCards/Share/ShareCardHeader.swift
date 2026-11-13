import MetlyCardKit
import MetlyCore
import SwiftUI

/// Share sheet header: 62 pt card, "{name} · {card}", link (or publishing state).
struct ShareCardHeader: View {
    let design: CardDesign
    let content: CardFaceContent
    let title: String
    let status: CardLinkStatus
    let isPaused: Bool
    @ScaledMetric(relativeTo: .headline) private var thumbnailWidth: CGFloat = 62

    var body: some View {
        HStack(spacing: 14) {
            CardFaceView(design: design, content: content)
                .cardFaceElevation()
                .frame(width: thumbnailWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        isPaused && status.url != nil ? String(localized: "\(status.displayText) · Paused", bundle: .appStrings) : status.displayText
    }
}
