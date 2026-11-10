import FeatureCards
import FeatureConnect
import FeatureEvents
import FeatureHome
import FeaturePeople
import FeatureProfile
import FeatureScan
import MetlyCore
import MetlyWidgetKit
import SwiftUI

/// The only place that knows every feature. Maps routes from MetlyCore to feature views.
enum RouteResolver {
    @ViewBuilder
    static func view(for destination: PushDestination) -> some View {
        switch destination {
        case .connectionDetail(let id): ConnectionDetailView(connectionID: id)
        case .followUps: FollowUpsView()
        case .eventDetail(let id): EventDetailView(eventID: id)
        case .scannedCard(let payload): ScannedCardView(payload: payload)
        case .paperReview(let draft): PaperReviewView(draft: draft)
        case .widgetsGallery: WidgetsGalleryView()
        case .cardSettings(let id): CardSettingsView(cardID: id)
        case .settings: SettingsView()
        case .settingsNotifications: NotificationSettingsView()
        case .settingsPrivacy: PrivacySettingsView()
        case .settingsSubscription: SubscriptionSettingsView()
        case .settingsHelp: HelpSupportView()
        case .settingsDeleteAccount: DeleteAccountView()
        case .settingsBlockedPeople: BlockedPeopleView()
        }
    }

    @ViewBuilder
    static func view(for presentation: Presentation) -> some View {
        switch presentation {
        case .sheet(let sheet): view(for: sheet)
        case .cover(let cover): view(for: cover)
        }
    }

    @ViewBuilder
    static func view(for sheet: SheetDestination) -> some View {
        switch sheet {
        case .share(let cardID): ShareCardSheet(cardID: cardID)
        case .startEvent(let eventID): StartEventSheet(eventID: eventID)
        case .addContext(let connectionID): AddContextSheet(connectionID: connectionID)
        case .justMet(let cardID): JustMetSheet(cardID: cardID)
        case .reminderEdit(let followUpID, let connectionID): ReminderEditSheet(followUpID: followUpID, connectionID: connectionID)
        case .eventExport(let eventID): EventExportSheet(eventID: eventID)
        }
    }

    @ViewBuilder
    static func view(for cover: CoverDestination) -> some View {
        switch cover {
        case .cardCreate(let origin): CardCreateView(origin: origin)
        case .cardEditor(let cardID): CardEditorView(cardID: cardID)
        case .cardExport(let cardID, let tab): CardExportView(cardID: cardID, tab: tab)
        case .connect(let cardID): ConnectView(cardID: cardID)
        case .connected(let connectionID): ConnectedView(connectionID: connectionID)
        case .qr(let cardID): QRFullscreenView(cardID: cardID)
        case .paywall(let trigger): PaywallView(trigger: trigger)
        case .eventEnded(let eventID): EventEndedView(eventID: eventID)
        }
    }
}
