import CoreImage
import Foundation
import MetlyCore
import Testing
@testable import MetlyCardKit

@Suite("QR code")
struct QRCodeTests {
    private let url = "https://metly.link/c/kamola-7f3k"

    @Test func producesUprightMatrix() throws {
        let matrix = try #require(QRCodeGenerator.matrix(for: url))
        #expect((matrix.size - 17) % 4 == 0)
        #expect(matrix.isUpright)
        #expect(!matrix.hasFinderPattern(atX: matrix.size - 7, y: matrix.size - 7))
    }

    @Test func imageHasFourModuleQuietZone() throws {
        let matrix = try #require(QRCodeGenerator.matrix(for: url))
        let image = try #require(QRCodeGenerator.cgImage(for: url, scale: 10))
        #expect(image.width == (matrix.size + 8) * 10)
        #expect(image.height == image.width)
    }

    @Test(arguments: ["https://metly.link/c/kamola-7f3k", "Hello, Ўзбекистон 😀"])
    func imageDecodesBackToPayload(_ payload: String) throws {
        let image = try #require(QRCodeGenerator.cgImage(for: payload, scale: 8))
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let features = detector.features(in: CIImage(cgImage: image)).compactMap { $0 as? CIQRCodeFeature }
        #expect(features.first?.messageString == payload)
    }

    @Test func offlineVCardFitsInAQRCode() throws {
        var content = CardFaceContent.sampleLong
        content.photoData = nil
        let vcard = VCardBuilder.make(content: content, url: URL(string: url))
        let matrix = try #require(QRCodeGenerator.matrix(for: vcard))
        #expect(matrix.version <= 25)
    }

    @Test func rejectsEmptyAndOversizedPayloads() {
        #expect(QRCodeGenerator.matrix(for: "") == nil)
        #expect(QRCodeGenerator.matrix(for: String(repeating: "x", count: 4000)) == nil)
    }

    @Test func describesPayloadForVoiceOver() {
        #expect(QRPayloadDescription(payload: url).spoken == "Link to metly.link/c/kamola-7f3k")
        let vcard = VCardBuilder.make(content: .sample, url: nil)
        #expect(QRPayloadDescription(payload: vcard).spoken == "Contact card for Kamola Rashidova")
    }
}
