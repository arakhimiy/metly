import MetlyCore
import SwiftUI

/// Circular avatar: photo when available, otherwise white initials on a vertical colour gradient.
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
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.avatarGradient(for: name))
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

/// Settings-style rounded-square icon (like iOS Settings rows): an SF Symbol, or for contact fields
/// with a brand (Telegram, WhatsApp, Instagram, LinkedIn) the brand's own mark.
public struct SettingsIcon: View {
    private enum Glyph {
        case symbol(String)
        case brand(Image)
    }

    private let glyph: Glyph
    private let color: Color

    public init(_ systemName: String, color: Color) {
        glyph = .symbol(systemName)
        self.color = color
    }

    public init(field: ContactFieldKind) {
        glyph = field.brandImage.map(Glyph.brand) ?? .symbol(field.symbolName)
        color = field.tint
    }

    public var body: some View {
        Group {
            switch glyph {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: 15, weight: .semibold))
            case .brand(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 29, height: 29)
        .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
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
    /// Brand colour for brands (official values), system colours for the rest.
    var tint: Color {
        switch self {
        case .phone: .green
        case .email: .blue
        case .telegram: Color(red: 0.149, green: 0.647, blue: 0.894)    // #26A5E4
        case .website: .indigo
        case .linkedin: Color(red: 0.039, green: 0.4, blue: 0.761)      // #0A66C2
        case .whatsapp: Color(red: 0.145, green: 0.827, blue: 0.4)      // #25D366
        case .instagram: Color(red: 0.894, green: 0.251, blue: 0.373)   // #E4405F
        case .address: .red
        }
    }

    /// The brand's own mark (template image, 20 pt) for Telegram, WhatsApp, Instagram and LinkedIn;
    /// nil for the rest, which use `symbolName`. Sources and licences: Resources/BRAND_ICONS.md.
    var brandImage: Image? {
        switch self {
        case .telegram: Image("brand.telegram", bundle: .module)
        case .whatsapp: Image("brand.whatsapp", bundle: .module)
        case .instagram: Image("brand.instagram", bundle: .module)
        case .linkedin: Image("brand.linkedin", bundle: .module)
        case .phone, .email, .website, .address: nil
        }
    }

    /// Brand mark or SF Symbol. Size it with `.resizable().scaledToFit().frame(…)`, not `.font`.
    var icon: Image { brandImage ?? Image(systemName: symbolName) }
}

public extension FollowUpChannel {
    /// The contact field the channel uses: its icon and colour.
    var fieldKind: ContactFieldKind {
        switch self {
        case .telegram: .telegram
        case .email: .email
        case .call: .phone
        }
    }

    /// Brand mark for Telegram, SF Symbol for Email and Call.
    var icon: Image { fieldKind.brandImage ?? Image(systemName: symbolName) }
}

public extension Color {
    /// Stable color per name for initials avatars.
    /// Light-to-deep vertical gradient for initials avatars, stable per name.
    static func avatarGradient(for name: String) -> LinearGradient {
        let palette = BrandPalette.avatarGradients
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        let pair = palette[hash % palette.count]
        return LinearGradient(colors: [Color(uiColor: pair.top), Color(uiColor: pair.bottom)],
                              startPoint: .top, endPoint: .bottom)
    }
}
