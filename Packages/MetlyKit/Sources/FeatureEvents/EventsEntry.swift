import MetlyCore
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// the bodies host the real screens (StartEvent/, Detail/, Ended/, Export/).
// Auto-end: `EventLifecycle.endExpiredEvents(in:)` or `.endsExpiredEvents()` (Logic/).

/// START_EVENT (sheet, medium + large) — `eventID == nil` starts a new event, otherwise edits it.
public struct StartEventSheet: View {
    public let eventID: UUID?

    public init(eventID: UUID?) {
        self.eventID = eventID
    }

    public var body: some View {
        StartEventScreen(eventID: eventID)
    }
}

/// EVENT_DETAIL (push).
public struct EventDetailView: View {
    public let eventID: UUID

    public init(eventID: UUID) {
        self.eventID = eventID
    }

    public var body: some View {
        EventDetailScreen(eventID: eventID)
    }
}

/// EVENT_ENDED (full-screen cover).
public struct EventEndedView: View {
    public let eventID: UUID

    public init(eventID: UUID) {
        self.eventID = eventID
    }

    public var body: some View {
        EventEndedScreen(eventID: eventID)
    }
}

/// EVENT_EXPORT (large sheet, CSV).
public struct EventExportSheet: View {
    public let eventID: UUID

    public init(eventID: UUID) {
        self.eventID = eventID
    }

    public var body: some View {
        EventExportScreen(eventID: eventID)
    }
}
