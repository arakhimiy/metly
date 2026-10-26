import MetlyCardKit
import MetlyCore
import MetlyData
import SwiftUI

/// The selected card: a small live card face, its name and link.
struct CardChooserRow: View {
    let card: Card?
    let profile: Profile?
    var showsChevron: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let card {
                CardFaceView(design: card.design, content: card.faceContent(profile: profile, audience: .connections))
                    .frame(width: 64)
                    .cardFaceElevation()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(card.name) Card")
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let link = card.url.map(Self.displayLink) {
                        Text(link)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("No card yet")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }

    /// "tanishly.app/c/aziza-w7k2".
    private static func displayLink(_ url: URL) -> String {
        guard let host = url.host() else { return url.absoluteString }
        return host + url.path()
    }
}
