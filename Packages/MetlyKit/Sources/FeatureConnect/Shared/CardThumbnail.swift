import MetlyCardKit
import MetlyCore
import MetlyData
import SwiftUI
import UIKit

/// Small card-face images for menu items (menus only show `Image`s, not live views).
@MainActor
enum CardThumbnail {
    static let width: CGFloat = 40

    static func image(for card: Card, profile: Profile?, scale: CGFloat) -> UIImage? {
        let content = card.faceContent(profile: profile, audience: .connections)
        let face = CardFaceView(design: card.design, content: content)
            .frame(width: width, height: width / CardFaceView.aspectRatio)
        let renderer = ImageRenderer(content: face)
        renderer.scale = scale
        return renderer.uiImage?.withRenderingMode(.alwaysOriginal)
    }
}
