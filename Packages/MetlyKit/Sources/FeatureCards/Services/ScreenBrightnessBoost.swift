import UIKit

/// Raises the screen to full brightness and keeps it awake while the QR is on screen
/// (SPEC §3.7, §9 Q42); restores both exactly once when the QR goes away or the app backgrounds.
///
/// Kept in `@State` as a plain reference (no observation needed).
@MainActor
final class ScreenBrightnessBoost {
    private var savedBrightness: CGFloat?
    private var savedIdleTimerDisabled: Bool?

    var isActive: Bool { savedBrightness != nil || savedIdleTimerDisabled != nil }

    func activate() {
        if savedIdleTimerDisabled == nil {
            savedIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        guard let screen = Self.currentScreen else { return }
        if savedBrightness == nil { savedBrightness = screen.brightness }
        screen.brightness = 1
    }

    func deactivate() {
        if let savedIdleTimerDisabled {
            UIApplication.shared.isIdleTimerDisabled = savedIdleTimerDisabled
            self.savedIdleTimerDisabled = nil
        }
        if let savedBrightness {
            Self.currentScreen?.brightness = savedBrightness
            self.savedBrightness = nil
        }
    }

    /// The foreground scene's screen (avoids the deprecated `UIScreen.main`).
    private static var currentScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.screen
    }
}
