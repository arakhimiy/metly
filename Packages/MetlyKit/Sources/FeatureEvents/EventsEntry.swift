import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

public struct StartEventSheet: View {
    public let eventID: UUID?

    public init(eventID: UUID?) {
        self.eventID = eventID
    }

    public var body: some View {
        FeaturePlaceholder("Start Event", specID: "START_EVENT")
    }
}
public struct EventDetailView: View {
    public let eventID: UUID

    public init(eventID: UUID) {
        self.eventID = eventID
    }

    public var body: some View {
        FeaturePlaceholder("Event", specID: "EVENT_DETAIL")
    }
}
public struct EventEndedView: View {
    public let eventID: UUID

    public init(eventID: UUID) {
        self.eventID = eventID
    }

    public var body: some View {
        FeaturePlaceholder("Event Ended", specID: "EVENT_ENDED")
    }
}
public struct EventExportSheet: View {
    public let eventID: UUID

    public init(eventID: UUID) {
        self.eventID = eventID
    }

    public var body: some View {
        FeaturePlaceholder("Export", specID: "EVENT_EXPORT")
    }
}
