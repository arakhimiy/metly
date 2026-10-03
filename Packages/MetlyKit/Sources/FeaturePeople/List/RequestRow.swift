import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// "{first} wants to connect" with Accept / Decline.
struct RequestRow: View {
    let request: ConnectRequest
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                InitialsAvatar(name: request.peerName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(PersonName.first(request.peerName)) wants to connect")
                        .font(.headline)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                Button(action: onDecline) {
                    Text("Decline").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button(action: onAccept) {
                    Text("Accept").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        [request.peerCompany, request.eventName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
