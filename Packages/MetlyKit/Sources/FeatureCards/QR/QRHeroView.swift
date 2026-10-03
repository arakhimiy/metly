import MetlyCardKit
import MetlyCore
import SwiftUI

/// Owner name + role, the big black-on-white QR and the scan caption. Paused links dim the code.
struct QRHeroView: View {
    let fullName: String
    let role: String
    let mode: QRCodeMode
    let isPaused: Bool
    let onResume: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(fullName)
                    .font(.title2.bold())
                if !role.isEmpty {
                    Text(role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)

            QRCodeView(payload: mode.payload)
                .padding(8)
                .background(.white, in: .rect(cornerRadius: 24))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                .frame(maxWidth: 300)
                .opacity(showsPausedState ? 0.1 : 1)
                .overlay {
                    if showsPausedState {
                        PausedOverlay(onResume: onResume)
                    }
                }
                .accessibilityHidden(showsPausedState)

            VStack(spacing: 4) {
                Text("Scan with the camera — no app needed")
                    .font(.subheadline)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Pausing only affects the link — the offline vCard keeps working.
    private var showsPausedState: Bool {
        isPaused && !mode.isOffline
    }

    private var caption: String {
        switch mode {
        case .link(let url): CardLinkStatus.shortText(for: url)
        case .contact: "Contact only · works offline"
        }
    }
}

/// "Link Paused" over the dimmed code, with a way to resume.
private struct PausedOverlay: View {
    let onResume: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label("Link Paused", systemImage: "pause.circle.fill")
                .font(.headline)
            Text("People who scan it see an inactive page.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Resume Links", action: onResume)
                .buttonStyle(.bordered)
        }
        .padding()
    }
}
