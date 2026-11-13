import SwiftUI
import UIKit

/// The app's colors beyond the AccentColor asset: what sits on top of the accent, and the
/// initials-avatar palette. Avatar hues are muted so a list of people doesn’t out-shout the brand blue
/// (the AccentColor asset is the HIG system Blue).
public enum BrandPalette {
    /// Text/icons drawn on an accent-filled control.
    public static let onAccent = Color(uiColor: UIColor { _ in .white })

    /// Avatar hues, picked to sit next to the system-blue accent (no neon pinks or purples).
    static let avatarHues: [UIColor] = [
        UIColor(hex: 0x2F6BC4), // blue (brand)
        UIColor(hex: 0x3D8B5E), // pine
        UIColor(hex: 0x5B6BBF), // slate indigo
        UIColor(hex: 0x8E5BA8), // plum
        UIColor(hex: 0xC2536B), // rose
        UIColor(hex: 0xC46A3D), // clay
        UIColor(hex: 0x6E8B3D), // olive
        UIColor(hex: 0x667085), // stone
    ]

    /// Solid fill with white initials, or a soft tint with colored initials.
    static let tonalAvatars = true
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
