import SwiftUI
import UIKit

/// The app's colors beyond the AccentColor asset: what sits on top of the accent, and the
/// initials-avatar gradients (the AccentColor asset is the HIG system Blue).
public enum BrandPalette {
    /// Text/icons drawn on an accent-filled control.
    public static let onAccent = Color(uiColor: UIColor { _ in .white })

    /// Initials-avatar gradients, light at the top to deep at the bottom, with white initials (the
    /// Telegram look the owner asked for, 2026-11-13). One pair per name, picked by a stable hash.
    static let avatarGradients: [(top: UIColor, bottom: UIColor)] = [
        (UIColor(hex: 0x72D5FD), UIColor(hex: 0x2A9EF1)), // blue
        (UIColor(hex: 0xA0DE7E), UIColor(hex: 0x54CB68)), // green
        (UIColor(hex: 0xFFCD6A), UIColor(hex: 0xFFA85C)), // orange
        (UIColor(hex: 0xFF885E), UIColor(hex: 0xFF516A)), // red
        (UIColor(hex: 0x82B1FF), UIColor(hex: 0x665FFF)), // violet
        (UIColor(hex: 0x53EDD6), UIColor(hex: 0x28C9B7)), // cyan
        (UIColor(hex: 0xE0A2F3), UIColor(hex: 0xD669ED)), // pink
    ]
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Same hue, lifted for dark backgrounds.
    func lifted(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: max(0, s - amount * 0.4), brightness: min(1, b + amount), alpha: a)
    }
}
