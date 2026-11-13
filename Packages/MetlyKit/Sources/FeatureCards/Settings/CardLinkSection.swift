import MetlyCore
import MetlyData
import SwiftUI
import UIKit

/// "Link": the card's public URL with Copy and Share. Disabled until the server assigned a slug.
struct CardLinkSection: View {
    let card: Card
    let isPaused: Bool
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var copyCount = 0

    var body: some View {
        let status = CardLinkStatus(url: card.url, isOnline: services.network.isOnline)
        Section {
            LabeledContent("Link") {
                HStack(spacing: 6) {
                    if status == .publishing { ProgressView() }
                    Text(status.displayText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Button("Copy Link", systemImage: "doc.on.doc") { copy(status.url) }
                .disabled(status.url == nil)
                .sensoryFeedback(.success, trigger: copyCount)

            if let url = status.url {
                ShareLink(item: url, message: Text(ShareCopy.message)) {
                    Label("Share Link…", systemImage: "square.and.arrow.up")
                }
            } else {
                Button("Share Link…", systemImage: "square.and.arrow.up") {}
                    .disabled(true)
            }
        } footer: {
            footer(for: status)
        }
    }

    @ViewBuilder
    private func footer(for status: CardLinkStatus) -> some View {
        if let explanation = status.explanation {
            Text(explanation)
        } else if isPaused {
            Text("Your links are paused, so this page is inactive until you resume them.")
        }
    }

    private func copy(_ url: URL?) {
        guard let url else { return }
        UIPasteboard.general.url = url
        copyCount += 1
        router.showToast(String(localized: "Link Copied", bundle: .appStrings), systemImage: "link")
    }
}

/// Copy shared by every place that shares a card link.
enum ShareCopy {
    static var message: String { String(localized: "Here’s my card", bundle: .appStrings) }
}
