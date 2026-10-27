import Foundation
import MetlyCore

/// Where a code came from — decides the alert wording.
enum ScanSource: Equatable {
    case camera
    case clipboard
}

/// ALERT_INVALID_QR: "No Business Card Found".
struct InvalidCodeAlert: Equatable {
    var source: ScanSource
    /// A web link that can be opened in Safari instead.
    var url: URL?
    var domain: String?

    static let title = String(localized: "No Business Card Found")

    var message: String {
        switch (source, domain) {
        case (.camera, let domain?):
            String(localized: "This QR code opens \(domain). It isn’t a \(Brand.appName) or vCard code.")
        case (.camera, nil):
            String(localized: "This QR code isn’t a \(Brand.appName) or vCard code.")
        case (.clipboard, let domain?):
            String(localized: "This link opens \(domain). It isn’t a \(Brand.appName) card link.")
        case (.clipboard, nil):
            String(localized: "The copied text isn’t a \(Brand.appName) card link. Copy a link like \(Brand.linkHost)/c/… and try again.")
        }
    }
}

/// ALERT_PAPER_NOT_READ: "Couldn't Read the Card" [Enter Manually · Retake].
struct PaperNotReadAlert: Equatable {
    /// The photo, kept for PAPER_REVIEW when the user types the details in.
    var imageData: Data?

    static let title = String(localized: "Couldn’t Read the Card")
    static let message = String(localized: "Hold the card flat in good light, or type the details yourself.")
}
