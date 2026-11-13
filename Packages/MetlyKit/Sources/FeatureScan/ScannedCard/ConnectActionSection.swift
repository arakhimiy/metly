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
            String(localized: "\(firstName) will see your request. You’re connected as soon as they accept.", bundle: .appStrings)
        case .noResponse:
            String(localized: "\(firstName) didn’t respond. Try again later, or add them to People now.", bundle: .appStrings)
        case .savedOffline:
            String(localized: "You’re offline, so \(firstName) was saved to People. Connect again when you’re back online.", bundle: .appStrings)
        case .idle, .sending, .waiting, .accepted:
            if isInPeople {
                String(localized: "\(firstName) is already in your People.", bundle: .appStrings)
            } else if showsConnectHint {
                String(localized: "Connect to see what \(firstName) shares with connections only.", bundle: .appStrings)
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
        case .idle, .savedOffline: String(localized: "Connect", bundle: .appStrings)
        case .sending: String(localized: "Sending…", bundle: .appStrings)
        case .waiting: String(localized: "Waiting for \(firstName)…", bundle: .appStrings)
        case .requestSent: String(localized: "Request Sent", bundle: .appStrings)
        case .noResponse: String(localized: "Try Again", bundle: .appStrings)
        case .accepted: String(localized: "Connected", bundle: .appStrings)
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
