import MetlyDesign
import SwiftUI

/// The prominent action under the card: **Connect** (with its request progress) or
/// **Open in People** when the person is already there.
struct ConnectActionSection: View {
    let firstName: String
    let phase: ScannedCardModel.ConnectPhase
    let isInPeople: Bool
    let showsConnectHint: Bool
    let onConnect: () -> Void
    let onCancel: () -> Void
    let onOpenInPeople: () -> Void

    var body: some View {
        Section {
            VStack(spacing: 10) {
                if isInPeople {
                    Button(action: onOpenInPeople) {
                        Label("Open in People", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .prominentButtonStyle()
                } else {
                    ConnectButton(firstName: firstName, phase: phase, action: onConnect)
                }
                if phase == .sending || phase == .waiting {
                    Button("Cancel Request", role: .cancel, action: onCancel)
                        .font(.subheadline)
                }
            }
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        } footer: {
            if let footer {
                Text(footer)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    private var footer: String? {
        switch phase {
        case .requestSent:
            "\(firstName) will see your request. You’re connected as soon as they accept."
        case .noResponse:
            "\(firstName) didn’t respond. Try again later, or add them to People now."
        case .savedOffline:
            "You’re offline, so \(firstName) was saved to People. Connect again when you’re back online."
        case .idle, .sending, .waiting, .accepted:
            if isInPeople {
                "\(firstName) is already in your People."
            } else if showsConnectHint {
                "Connect to see what \(firstName) shares with connections only."
            } else {
                nil
            }
        }
    }
}

/// Connect / Sending… / Waiting for {first}… / Request Sent / Try Again.
private struct ConnectButton: View {
    let firstName: String
    let phase: ScannedCardModel.ConnectPhase
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                    Text(title)
                } else {
                    Label(title, systemImage: symbol)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .prominentButtonStyle()
        .disabled(isBusy || phase == .requestSent || phase == .accepted)
        .accessibilityHint(phase == .idle ? "Sends \(firstName) a request to swap cards" : "")
    }

    private var isBusy: Bool { phase == .sending || phase == .waiting }

    private var title: String {
        switch phase {
        case .idle, .savedOffline: "Connect"
        case .sending: "Sending…"
        case .waiting: "Waiting for \(firstName)…"
        case .requestSent: "Request Sent"
        case .noResponse: "Try Again"
        case .accepted: "Connected"
        }
    }

    private var symbol: String {
        switch phase {
        case .requestSent, .accepted: "checkmark"
        case .noResponse: "arrow.clockwise"
        default: "person.badge.plus"
        }
    }
}
