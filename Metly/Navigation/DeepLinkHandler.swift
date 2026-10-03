import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// Universal Links (`https://metly.link/c/{slug}`), custom scheme (`metly://…`) and widget/intent links.
enum DeepLinkHandler {
    static func handle(_ url: URL, router: AppRouter, context: ModelContext) {
        guard router.phase == .main else { return }

        // Someone else's card link → Scanned Card.
        if let slug = Brand.slug(from: url) {
            if let own = (try? context.fetch(Card.live))?.first(where: { $0.slug == slug }) {
                router.dismissAll()
                router.present(.qr(cardID: own.id))
            } else {
                router.open(.scannedCard(ScannedCardPayload(url: url, slug: slug)), in: .scan)
            }
            return
        }

        guard url.scheme == Brand.urlScheme else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host() {
        case "qr":   // metly://qr[/cardID]  — widgets, App Shortcut, Control
            let card = parts.first.flatMap(UUID.init(uuidString:)).flatMap { context.record(Card.self, id: $0) } ?? context.cardToShare()
            if let card {
                router.dismissAll()
                router.present(.qr(cardID: card.id))
            }
        case "followups":
            router.open(.followUps, in: .home)
        case "reminder":   // metly://reminder/{followUpID}
            if let id = parts.first.flatMap(UUID.init(uuidString:)) {
                router.dismissAll()
                router.present(.reminderEdit(followUpID: id, connectionID: nil))
            }
        case "person":     // metly://person/{connectionID}
            if let id = parts.first.flatMap(UUID.init(uuidString:)) { router.open(.connectionDetail(id: id), in: .people) }
        case "people":
            router.select(.people)
        case "connect":
            router.dismissAll()
            router.present(.connect(cardID: nil))
        case "scan":
            router.select(.scan)
        default:
            break
        }
    }
}
