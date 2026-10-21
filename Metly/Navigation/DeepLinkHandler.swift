import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// Universal Links (`https://metly.link/c/{slug}`), custom scheme (`metly://…`) and widget/intent links.
enum DeepLinkHandler {
    /// A link that arrived before the app reached `.main` (cold launch from a widget, control or Siri).
    private static var pendingURL: URL?

    static func handle(_ url: URL, router: AppRouter, context: ModelContext) {
        guard router.phase == .main else {
            if router.phase == .launching { pendingURL = url }
            return
        }

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
            let card = parts.first.flatMap(UUID.init(uuidString:))
                .flatMap { context.record(Card.self, id: $0) }
                .flatMap { $0.isDeleted ? nil : $0 } ?? context.cardToShare()   // deleted card → card to share
            if let card {
                router.dismissAll()
                router.present(.qr(cardID: card.id))
            }
        case "followups":
            router.open(.followUps, in: .home)
        case "reminder":   // metly://reminder/{followUpID}
            if let id = parts.first.flatMap(UUID.init(uuidString:)),
               let followUp = context.record(FollowUp.self, id: id), !followUp.isDeleted {
                router.dismissAll()
                router.present(.reminderEdit(followUpID: id, connectionID: nil))
            } else {
                router.open(.followUps, in: .home)   // reminder gone (done elsewhere / deleted)
            }
        case "person":     // metly://person/{connectionID}
            if let id = parts.first.flatMap(UUID.init(uuidString:)),
               let person = context.record(Connection.self, id: id), !person.isDeleted, !person.isBlocked {
                router.open(.connectionDetail(id: id), in: .people)
            } else {
                router.select(.people)
            }
        case "people":
            router.select(.people)
        case "connect":
            router.dismissAll()
            router.present(.connect(cardID: nil))
        case "scan":
            router.select(.scan)
        case "event":    // metly://event/start — App Shortcut "Start Event"
            if parts.first == "start" {
                router.dismissAll()
                router.present(.startEvent(eventID: nil))
            }
        default:
            break
        }
    }

    static func handlePendingURL(router: AppRouter, context: ModelContext) {
        guard let url = pendingURL else { return }
        pendingURL = nil
        handle(url, router: router, context: context)
    }
}
