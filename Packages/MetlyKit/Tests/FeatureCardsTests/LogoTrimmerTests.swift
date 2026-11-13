import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import FeatureCards

/// Logos are cropped to their content on import (card templates v2): transparent or uniform borders go.
struct LogoTrimmerTests {
    private func image(size: CGSize, background: UIColor?, mark: CGRect) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = background != nil
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            if let background {
                background.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
            UIColor.systemBlue.setFill()
            context.fill(mark)
        }.cgImage!
    }

    @Test func transparentMarginIsTrimmed() throws {
        let logo = image(size: CGSize(width: 400, height: 400), background: nil, mark: CGRect(x: 100, y: 150, width: 200, height: 100))
        let trimmed = try #require(LogoTrimmer.trimmed(logo))
        #expect(abs(trimmed.width - 200) <= 8 && abs(trimmed.height - 100) <= 8)
    }

    @Test func whiteBoxIsTrimmed() throws {
        let logo = image(size: CGSize(width: 300, height: 300), background: .white, mark: CGRect(x: 50, y: 50, width: 60, height: 200))
        let trimmed = try #require(LogoTrimmer.trimmed(logo))
        #expect(abs(trimmed.width - 60) <= 8 && abs(trimmed.height - 200) <= 8)
    }

    @Test func edgeToEdgeArtIsLeftAlone() {
        let logo = image(size: CGSize(width: 120, height: 120), background: nil, mark: CGRect(x: 0, y: 0, width: 120, height: 120))
        #expect(LogoTrimmer.trimmed(logo) == nil)
    }
}
