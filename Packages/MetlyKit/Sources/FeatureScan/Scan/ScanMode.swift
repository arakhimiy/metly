import CoreGraphics

/// SCAN's segmented control: **QR Code | Paper Card**.
enum ScanMode: String, CaseIterable, Identifiable, Hashable {
    case qr, paper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qr: "QR Code"
        case .paper: "Paper Card"
        }
    }

    var hint: String {
        switch self {
        case .qr: "Point at a Tanishly or vCard QR code"
        case .paper: "Fit the business card inside the frame"
        }
    }

    /// Viewfinder shape: square for QR, 85 : 55 business card for paper.
    var aspectRatio: CGFloat {
        switch self {
        case .qr: 1
        case .paper: 85.0 / 55.0
        }
    }

    var maxGuideWidth: CGFloat {
        switch self {
        case .qr: 250
        case .paper: 320
        }
    }
}
