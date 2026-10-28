#if DEBUG
import MetlyCardKit
import MetlyCore
import SwiftUI

/// Sample scans for previews and the DEBUG demo menu (mock-server slugs, a vCard, a paper card).
enum ScanSamples {
    static let kamilaURL = "https://tanishly.app/c/kamila-x1y2"

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

    /// OCR lines of a typical card, as Vision returns them (logo on top, office and mobile numbers).
    static let paperLines = [
        OCRLine("TEZKOR", height: 0.11),
        OCRLine("Dilshod Rakhimov", height: 0.06),
        OCRLine("Head of Sales", height: 0.035),
        OCRLine("Ish: +998 71 200 10 20", height: 0.03),
        OCRLine("Mob: +998 90 987 65 43", height: 0.03),
        OCRLine("dilshod@tezkor.uz", height: 0.03),
        OCRLine("t.me/dilshod_r", height: 0.03),
        OCRLine("tezkor.uz", height: 0.03),
    ]

    /// The reader's full result, with the photo stand-in.
    static var paperScan: PaperScan {
        var scan = PaperCardParser.analyze(paperLines).scan
        scan.draft.imageData = sampleCardImage
        return scan
    }

    static var paperDraft: PaperCardDraft { paperScan.draft }

    /// The user's failure mode: a two-word brand above a name no dictionary knows.
    static var brandFirstScan: PaperScan {
        PaperCardParser.analyze([
            OCRLine("GRAND LUX", height: 0.11), OCRLine("Bobur Tosh", height: 0.06), OCRLine("Bosh menejer", height: 0.035),
            OCRLine("+998 95 145 67 89"), OCRLine("+998 71 233 00 11"), OCRLine("grandlux.hotel@gmail.com"),
        ]).scan
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
