import SwiftUI

/// Circular avatar: profile photo (when shown and present) or initials.
struct CardAvatar: View {
    let photoData: Data?
    let initials: String
    let style: CardFaceStyle
    /// Diameter, % of card width.
    let size: CGFloat
    /// Initials size, % of card width.
    let initialsSize: CGFloat
    let fill: Color
    let textColor: Color

    var body: some View {
        let diameter = style.u(size)
        ZStack {
            Circle().fill(fill)
            if let photoData, let image = CardImageDecoder.image(from: photoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter, height: diameter)
            } else {
                Text(verbatim: initials)
                    .font(style.font(initialsSize, weight: .semibold))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(.circle)
    }
}

/// Professional's logo square (object-fit: contain) or the monogram tile fallback.
struct CardLogoTile: View {
    let logoData: Data?
    let monogram: String
    let style: CardFaceStyle

    var body: some View {
        let side = style.u(9)
        Group {
            if let logoData, let image = CardImageDecoder.image(from: logoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: side, height: side)
                    .clipShape(.rect(cornerRadius: style.u(1.6)))
            } else {
                Text(verbatim: monogram)
                    .font(style.font(4.4, weight: .bold))
                    .foregroundStyle(style.bg)
                    .frame(width: side, height: side)
                    .background(style.accent, in: .rect(cornerRadius: style.u(1.8)))
            }
        }
    }
}
