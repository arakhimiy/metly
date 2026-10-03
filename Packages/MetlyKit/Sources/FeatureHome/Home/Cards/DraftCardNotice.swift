import MetlyCore
import SwiftUI

/// Publish failed: the card is a local draft until the sync engine publishes it (SPEC §3.21, ALERT_PUBLISH_FAILED copy).
struct DraftCardNotice: View {
    let cardName: String

    @Environment(AppServices.self) private var services

    var body: some View {
        let isSyncing = services.sync.status == .syncing
        VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Couldn’t Publish Card")
                        .font(.subheadline.weight(.semibold))
                    Text("Check your connection. Your card is saved as a draft and will publish when you’re back online.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(.orange)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                Button("Try Again", systemImage: "arrow.clockwise", action: retry)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .disabled(isSyncing)
                    .accessibilityHint(Text("Publishes your \(cardName) card"))
                if isSyncing {
                    ProgressView()
                        .accessibilityLabel("Publishing")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func retry() {
        services.sync.requestSync()
    }
}
