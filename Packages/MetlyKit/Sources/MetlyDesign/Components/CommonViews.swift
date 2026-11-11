import MetlyCore
import SwiftUI

/// Circular avatar: photo when available, otherwise initials on a tinted fill.
public struct InitialsAvatar: View {
    let name: String
    let imageData: Data?
    let size: CGFloat

    public init(name: String, imageData: Data? = nil, size: CGFloat = 40) {
        self.name = name
        self.imageData = imageData
        self.size = size
    }

    public var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(BrandPalette.tonalAvatars ? Color.avatarInk(for: name) : .white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if BrandPalette.tonalAvatars {
                            Color.avatarColor(for: name).opacity(0.2)
                        } else {
                            Rectangle().fill(Color.avatarColor(for: name).gradient)
                        }
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// Settings-style rounded-square icon (like iOS Settings rows).
public struct SettingsIcon: View {
    let systemName: String
    let color: Color

    public init(_ systemName: String, color: Color) {
        self.systemName = systemName
        self.color = color
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .accessibilityHidden(true)
    }
}

public extension SettingsIcon {
    init(field: ContactFieldKind) {
        self.init(field.symbolName, color: field.tint)
    }
}

/// Small "PRO" capsule for gated rows.
public struct ProBadge: View {
    public init() {}
    public var body: some View {
        Text("PRO")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.white)
            .background(Color.accentColor, in: Capsule())
            .accessibilityLabel(Brand.proName)
    }
}

public extension ContactFieldKind {
    var tint: Color {
        switch self {
        case .phone: .green
        case .email: .blue
        case .telegram: .cyan
        case .website: .indigo
        case .linkedin: Color(red: 0.04, green: 0.4, blue: 0.76)
        case .whatsapp: Color(red: 0.15, green: 0.68, blue: 0.38)
        case .instagram: Color(red: 0.86, green: 0.18, blue: 0.47)
        case .address: .red
        }
    }
}

public extension Color {
    /// Stable color per name for initials avatars.
    static func avatarColor(for name: String) -> Color {
        Color(uiColor: avatarHue(for: name))
    }

    /// Initials color for the soft-tint avatar: the hue itself, lifted in dark mode so it reads on black.
    static func avatarInk(for name: String) -> Color {
        let hue = avatarHue(for: name)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? hue.lifted(by: 0.25) : hue })
    }

    private static func avatarHue(for name: String) -> UIColor {
        let palette = BrandPalette.avatarHues
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return palette[hash % palette.count]
    }
}
