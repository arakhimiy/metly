import MetlyCardKit
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// INCOMING_REQUEST (SPEC §2.5.26): someone nearby wants to connect while CONNECT is open.
/// Their card, "{Name} wants to connect with you", Decline / Accept, "You'll share your {card} card."
/// Swiping it away leaves the request in People › Requests.
struct IncomingRequestSheet: View {
    let request: ConnectRequest
    let sharedCardName: String?
    let isAccepting: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 96

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                theirCard
                VStack(spacing: 4) {
                    Text(request.peerName)
                        .font(.title2.bold())
                    Text(ConnectCopy.wantsToConnect)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    if !details.isEmpty {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .bottomActionBar {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button(action: onDecline) {
                        Text("Decline")
                            .frame(maxWidth: .infinity)
                    }
                    .secondaryButtonStyle()

                    Button(action: onAccept) {
                        Text("Accept")
                            .opacity(isAccepting ? 0 : 1)
                            .overlay {
                                if isAccepting { ProgressView() }
                            }
                            .frame(maxWidth: .infinity)
                    }
                    .prominentButtonStyle()
                    .accessibilityLabel(isAccepting ? "Accepting" : "Accept")
                }
                .controlSize(.large)
                .disabled(isAccepting)

                if let sharedCardName {
                    Text(ConnectCopy.youllShare(sharedCardName))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isAccepting)
        .onAppear {
            AccessibilityNotification.Announcement("\(request.peerName) \(ConnectCopy.wantsToConnect)").post()
        }
    }

    @ViewBuilder
    private var theirCard: some View {
        if let card = request.peerCard {
            CardFaceView(design: card.design, content: card.faceContent)
                .cardFaceElevation()
                .frame(maxWidth: 300)
        } else {
            InitialsAvatar(name: request.peerName, size: avatarSize)
        }
    }

    private var details: String {
        let role = [request.peerTitle, request.peerCompany].filter { !$0.isEmpty }.joined(separator: " · ")
        return [role, request.eventName ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
