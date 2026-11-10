import MetlyCardKit
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// Final step — "Your Card Is Live" with the link (or publishing state), the card, Share Now / Done.
/// Created offline → ALERT_PUBLISH_FAILED: the card stays a draft and publishes when back online.
struct CreateSuccessView: View {
    let card: Card
    let profile: Profile?
    let onShare: () -> Void
    let onDone: () -> Void

    @Environment(AppServices.self) private var services
    @State private var isShowingPublishFailed: Bool
    @State private var hasAppeared = false

    init(card: Card, profile: Profile?, createdOffline: Bool, onShare: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.card = card
        self.profile = profile
        self.onShare = onShare
        self.onDone = onDone
        _isShowingPublishFailed = State(initialValue: createdOffline)
    }

    var body: some View {
        let status = CardLinkStatus(url: card.url, isOnline: services.network.isOnline)
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .imageScale(.large)
                            .foregroundStyle(.green)
                            .symbolEffect(.bounce, value: hasAppeared)
                            .accessibilityHidden(true)
                        Text(status.url == nil ? "Your Card Is Ready" : "Your Card Is Live")
                            .font(.title.bold())
                            .accessibilityAddTraits(.isHeader)
                        LinkStatusLabel(status: status)
                    }
                    .multilineTextAlignment(.center)

                    CardFaceView(design: card.design, content: CardContentFactory.preview(of: card, profile: profile))
                        .cardFaceElevation()
                        .frame(maxWidth: 380)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(card.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .bottomActionBar {
                ActionButtonStack {
                    Button(action: onShare) {
                        Label("Share Now", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .prominentButtonStyle()
                } secondary: {
                    Button(action: onDone) {
                        Text("Done").frame(maxWidth: .infinity)
                    }
                    .secondaryButtonStyle()
                }
            }
        }
        .sensoryFeedback(.success, trigger: hasAppeared)
        .onAppear { hasAppeared = true }
        .task {
            // Let the "Your Card Is Live" moment land before the system prompt.
            try? await Task.sleep(for: .seconds(1.2))
            await NotificationPrompt.askIfNeeded()
        }
        .alert("Couldn’t Publish Card", isPresented: $isShowingPublishFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection. Your card is saved as a draft and will publish when you’re back online.")
        }
    }
}

/// The card link, a spinner while publishing, or the offline-draft note.
private struct LinkStatusLabel: View {
    let status: CardLinkStatus

    var body: some View {
        switch status {
        case .live(let url):
            Text(CardLinkStatus.shortText(for: url))
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        case .publishing:
            HStack(spacing: 8) {
                ProgressView()
                Text("Publishing…")
            }
            .foregroundStyle(.secondary)
        case .waitingForNetwork:
            Label("Publishes when you’re back online", systemImage: "wifi.slash")
                .foregroundStyle(.secondary)
        }
    }
}
