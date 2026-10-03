import MetlyCore
import MetlyDesign
import SwiftUI

/// FROZEN PUBLIC API — renders a business card face (85:55) for any template/palette.
/// Wave 0 stub; the CardKit agent implements the 9 templates behind this exact signature.
public struct CardFaceView: View {
    public let design: CardDesign
    public let content: CardFaceContent

    public init(design: CardDesign, content: CardFaceContent) {
        self.design = design
        self.content = content
    }

    /// Business-card aspect ratio (85 × 55 mm).
    public static let aspectRatio: CGFloat = 85.0 / 55.0

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            VStack(alignment: .leading, spacing: width * 0.02) {
                Text(content.fullName).font(.system(size: width * 0.066, weight: .semibold))
                Text(content.role).font(.system(size: width * 0.033)).opacity(0.66)
                Spacer()
            }
            .padding(width * 0.07)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(design.appearance == .dark ? Color.white : Color.black)
            .background(design.appearance == .dark ? Color.black : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: width * 0.042, style: .continuous))
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(content.fullName), \(content.role)")
    }
}
