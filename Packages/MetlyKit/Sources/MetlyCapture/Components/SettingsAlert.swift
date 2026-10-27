import MetlyCore
import SwiftUI

/// A denied-permission alert with Cancel · Open Settings (SPEC §7.1 ALERT_MIC_OFF / ALERT_PERM_SETTINGS).
public struct SettingsAlert: Identifiable, Equatable, Sendable {
    public var title: String
    public var message: String

    public var id: String { title }

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    public static let microphoneOff = SettingsAlert(
        title: String(localized: "Microphone Is Off"),
        message: String(localized: "Allow microphone access in Settings › \(Brand.appName) to add notes by voice."))

    public static let speechOff = SettingsAlert(
        title: String(localized: "Speech Recognition Is Off"),
        message: String(localized: "Allow speech recognition in Settings › \(Brand.appName) to add notes by voice."))

    public static let locationOff = SettingsAlert(
        title: String(localized: "Turn On in Settings"),
        message: String(localized: "Open iOS Settings › \(Brand.appName) to allow location access."))

    public static func permission(_ name: String) -> SettingsAlert {
        SettingsAlert(title: String(localized: "Turn On in Settings"), message: String(localized: "Open iOS Settings › \(Brand.appName) to allow \(name)."))
    }
}

private struct SettingsAlertModifier: ViewModifier {
    @Binding var alert: SettingsAlert?
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert(alert?.title ?? "", isPresented: isPresented, presenting: alert) { _ in
            Button("Cancel", role: .cancel) {}
            Button("Open Settings", action: openSettings)
                .keyboardShortcut(.defaultAction)
        } message: { alert in
            Text(alert.message)
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }
}

public extension View {
    /// Shows `alert` with Cancel · Open Settings while it is non-nil.
    func settingsAlert(_ alert: Binding<SettingsAlert?>) -> some View {
        modifier(SettingsAlertModifier(alert: alert))
    }
}
