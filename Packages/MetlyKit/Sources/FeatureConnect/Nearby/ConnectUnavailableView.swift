import MetlyCore
import MetlyDesign
import SwiftUI

/// Why CONNECT can't look for people, with the way out (SPEC §3.22 permissions, §7 empty states).
struct ConnectUnavailableView: View {
    enum Reason: Equatable {
        case hiddenFromNearby
        case localNetworkDenied
        case offline
        case failed(String)
        case tapUnsupported
        case noOneNearby
    }

    let reason: Reason
    var onShowQR: (() -> Void)?
    var onTurnOnNearby: () -> Void = {}
    var onRetry: () -> Void = {}
    var onUseNearby: () -> Void = {}

    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch reason {
        case .hiddenFromNearby:
            Button("Turn On Show in Nearby", action: onTurnOnNearby)
                .prominentButtonStyle()
            showQRButton
        case .localNetworkDenied:
            Button("Open Settings", action: openSettings)
                .prominentButtonStyle()
            showQRButton
        case .offline, .failed:
            Button("Try Again", action: onRetry)
                .prominentButtonStyle()
            showQRButton
        case .tapUnsupported:
            Button("Use Nearby", action: onUseNearby)
                .prominentButtonStyle()
        case .noOneNearby:
            if let onShowQR {
                Button("Show My QR", systemImage: "qrcode", action: onShowQR)
                    .prominentButtonStyle()
            }
        }
    }

    @ViewBuilder
    private var showQRButton: some View {
        if let onShowQR {
            Button("Show My QR", systemImage: "qrcode", action: onShowQR)
                .secondaryButtonStyle()
        }
    }

    private var title: String {
        switch reason {
        case .hiddenFromNearby: "You’re Hidden from Nearby"
        case .localNetworkDenied: "Local Network Access Needed"
        case .offline: "You’re Offline"
        case .failed: "Couldn’t Start Connect"
        case .tapUnsupported: "Tap Phones Isn’t Available"
        case .noOneNearby: ConnectCopy.emptyTitle
        }
    }

    private var symbol: String {
        switch reason {
        case .hiddenFromNearby: "eye.slash"
        case .localNetworkDenied: "network.slash"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle"
        case .tapUnsupported: "iphone.slash"
        case .noOneNearby: "person.2.slash"
        }
    }

    private var message: String {
        switch reason {
        case .hiddenFromNearby:
            "“Show in Nearby” is off, so people around you can’t find you. Turn it on to swap cards, or show your QR code instead."
        case .localNetworkDenied:
            "Allow Local Network access in Settings › \(Brand.appName) to find people nearby. You can still show your QR code."
        case .offline:
            "Connect needs the internet to swap cards. Your QR code still works offline."
        case .failed(let message):
            message
        case .tapUnsupported:
            "This iPhone can’t tell when another phone is held close. Use Nearby to find the person instead."
        case .noOneNearby:
            ConnectCopy.emptyMessage
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}
