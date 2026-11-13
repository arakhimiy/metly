import MetlyCardKit
import MetlyCore
import SwiftUI

/// Owner name + "{title} · {company}" above the code.
struct QROwnerHeader: View {
    let fullName: String
    let role: String

    var body: some View {
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
        .accessibilityElement(children: .combine)
    }
}

/// The big black-on-white QR on its plate. Paused links dim the code and offer Resume.
struct QRCodePlate: View {
    enum Sizing {
        /// Takes the height left on screen, between `minimumSide` and `maximumSide`.
        case fillsRemainingHeight
        /// Full size (inside a scroll view).
        case full
    }

    static let minimumSide: CGFloat = 150
    static let maximumSide: CGFloat = 300

    let mode: QRCodeMode
    let isPaused: Bool
    let sizing: Sizing
    let onResume: () -> Void

    var body: some View {
        switch sizing {
        case .fillsRemainingHeight:
            // The ideal height is the minimum, so `ViewThatFits` keeps the one-screen layout whenever
            // the rest fits; the VStack then hands the plate the leftover height.
            plate.frame(minHeight: Self.minimumSide, idealHeight: Self.minimumSide, maxHeight: Self.maximumSide)
        case .full:
            plate
        }
    }

    private var plate: some View {
        QRCodeView(payload: mode.payload)
            .padding(8)
            .background(.white, in: .rect(cornerRadius: 24))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
            .opacity(showsPausedState ? 0.1 : 1)
            // On the square itself (not the wider frame), so the notice wraps inside the dimmed code.
            .overlay {
                if showsPausedState {
                    PausedOverlay(onResume: onResume)
                }
            }
            .accessibilityHidden(showsPausedState)
            .frame(maxWidth: Self.maximumSide, maxHeight: Self.maximumSide)
    }

    /// Pausing only affects the link — the offline vCard keeps working.
    private var showsPausedState: Bool {
        isPaused && !mode.isOffline
    }
}

/// "Scan with the camera — no app needed" + the link (or "Contact only · works offline").
struct QRScanCaption: View {
    let mode: QRCodeMode

    var body: some View {
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
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        switch mode {
        case .link(let url): CardLinkStatus.shortText(for: url)
        case .contact: String(localized: "Contact only · works offline", bundle: .appStrings)
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
