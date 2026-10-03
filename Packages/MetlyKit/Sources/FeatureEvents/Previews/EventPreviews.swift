#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// Every SPEC state owned by FeatureEvents (Appendix A #7, #40, #41, #43, #44 + v1 variants).

// MARK: START_EVENT

#Preview("Start Event · new + calendar") {
    StartEventScreen(eventID: nil,
                     calendarProvider: CalendarSuggestionProvider(preview: .granted,
                                                                  suggestions: EventPreviewData.calendarSuggestions))
        .metlyPreview(.empty)
}

#Preview("Start Event · calendar not asked") {
    StartEventScreen(eventID: nil, calendarProvider: CalendarSuggestionProvider(preview: .notDetermined))
        .metlyPreview(.full, plan: .pro)
}

#Preview("Start Event · calendar denied") {
    StartEventScreen(eventID: nil, calendarProvider: CalendarSuggestionProvider(preview: .denied))
        .metlyPreview(.empty)
}

#Preview("Start Event · edit") {
    StartEventScreen(eventID: PreviewSeed.eventID)
        .metlyPreview(.full)
}

#Preview("Start Event · Free limit") {
    StartEventScreen(eventID: nil, calendarProvider: CalendarSuggestionProvider(preview: .granted,
                                                                                 suggestions: EventPreviewData.calendarSuggestions),
                     showsLimitAlert: true)
        .metlyPreview(.full)
}

// MARK: EVENT_DETAIL

#Preview("Event Detail · active") {
    EventPreviewPrepared(prepare: EventPreviewData.addEventPeople) {
        NavigationStack { EventDetailView(eventID: PreviewSeed.eventID) }
    }
    .metlyPreview(.full)
}

#Preview("Event Detail · ended") {
    EventPreviewPrepared(prepare: EventPreviewData.endSeedEvent) {
        NavigationStack { EventDetailView(eventID: PreviewSeed.eventID) }
    }
    .metlyPreview(.full, plan: .pro)
}

#Preview("Event Detail · empty") {
    EventPreviewPrepared(prepare: EventPreviewData.insertEmptyEvent) {
        NavigationStack { EventDetailView(eventID: EventPreviewData.emptyEventID) }
    }
    .metlyPreview(.full)
}

#Preview("Event Detail · dark, accessibility size") {
    EventPreviewPrepared(prepare: EventPreviewData.addEventPeople) {
        NavigationStack { EventDetailView(eventID: PreviewSeed.eventID) }
    }
    .metlyPreview(.full)
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}

#Preview("Event Detail · not found") {
    NavigationStack { EventDetailView(eventID: UUID()) }
        .metlyPreview(.empty)
}

// MARK: EVENT_ENDED

#Preview("Event Ended") {
    EventPreviewPrepared(prepare: { context in
        EventPreviewData.addEventPeople(in: context)
        EventPreviewData.endSeedEvent(in: context)
    }) {
        EventEndedView(eventID: PreviewSeed.eventID)
    }
    .metlyPreview(.full)
}

#Preview("Event Ended · nobody met, dark") {
    EventPreviewPrepared(prepare: { context in
        EventPreviewData.insertEmptyEvent(in: context)
        if let event = context.record(Event.self, id: EventPreviewData.emptyEventID) { EventLifecycle.end(event) }
    }) {
        EventEndedView(eventID: EventPreviewData.emptyEventID)
    }
    .metlyPreview(.full)
    .preferredColorScheme(.dark)
}

// MARK: EVENT_EXPORT

#Preview("Export · Free") {
    EventPreviewPrepared(prepare: EventPreviewData.addEventPeople) {
        EventExportSheet(eventID: PreviewSeed.eventID)
    }
    .metlyPreview(.full)
}

#Preview("Export · Pro") {
    EventPreviewPrepared(prepare: EventPreviewData.addEventPeople) {
        EventExportSheet(eventID: PreviewSeed.eventID)
    }
    .metlyPreview(.full, plan: .pro)
}
#endif
