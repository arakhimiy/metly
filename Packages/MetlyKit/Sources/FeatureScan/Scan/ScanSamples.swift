#if DEBUG
import MetlyCardKit
import MetlyCore
import SwiftUI

/// Sample scans for previews and the DEBUG demo menu (mock-server slugs, a vCard, a paper card).
enum ScanSamples {
    static let kamilaURL = "https://metly.link/c/kamila-x1y2"

    static let vCard = """
    BEGIN:VCARD
    VERSION:3.0
    N:Saidov;Olim;;;
    FN:Olim Saidov
    ORG:Humo Payments
    TITLE:Business Development Manager
    TEL;TYPE=CELL:+998 91 234 56 78
    EMAIL;TYPE=WORK:olim@humo.uz
    URL:https://t.me/olim_saidov
    URL:https://humo.uz
    END:VCARD
    """

    /// OCR lines of a typical card, as Vision returns them.
    static let paperLines = [
        "TEZKOR",
        "Dilshod Rakhimov",
        "Head of Sales",
        "+998 90 987 65 43",
        "dilshod@tezkor.uz",
        "t.me/dilshod_r",
        "tezkor.uz",
    ]

    static var paperDraft: PaperCardDraft {
        var draft = PaperCardParser.parse(text: paperLines)
        draft.imageData = sampleCardImage
        return draft
    }

    /// A rendered card face standing in for the captured photo.
    static var sampleCardImage: Data? {
        let content = CardFaceContent(
            fullName: "Dilshod Rakhimov", jobTitle: "Head of Sales", company: "Tezkor",
            fields: [ContactField(kind: .phone, value: "+998 90 987 65 43", privacy: .public),
                     ContactField(kind: .email, value: "dilshod@tezkor.uz", privacy: .public),
                     ContactField(kind: .telegram, value: "@dilshod_r", privacy: .public)])
        let face = CardFaceView(design: CardDesign(template: .professional, palette: .snow, appearance: .light, showQR: false),
                                content: content)
            .frame(width: 340)
        let renderer = ImageRenderer(content: face)
        renderer.scale = 2
        return renderer.uiImage?.jpegData(compressionQuality: 0.8)
    }
}
#endif
