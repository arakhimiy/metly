import SwiftUI

/// Dismissable inline notice: "{first} didn't respond. Try again or show your QR." or a failure.
/// The requester never sees "declined" (PLAN Q9).
struct ConnectNoticeRow: View {
    let notice: ConnectMachine.Notice
    var onShowQR: (() -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                if let onShowQR {
                    Button("Show My QR", systemImage: "qrcode", action: onShowQR)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderless)
                }
            }
            Spacer(minLength: 0)
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.rect)
        }
        .onAppear {
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var message: String {
        switch notice {
        case .noResponse(let firstName): ConnectCopy.noResponse(firstName)
        case .failed(let message): message
        }
    }

    private var symbol: String {
        switch notice {
        case .noResponse: "clock.badge.exclamationmark"
        case .failed: "exclamationmark.triangle"
        }
    }
}
