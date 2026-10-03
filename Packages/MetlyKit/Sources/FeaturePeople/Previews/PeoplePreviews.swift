#if DEBUG
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

// SPEC Appendix A states owned by People & Context.
// Swipe actions (state 45) and the long-press menu need interaction: use Live Preview on "People · full".

#Preview("People · full + requests") {
    NavigationStack { PeopleView() }
        .metlyPreview(.full)
}

#Preview("People · empty") {
    NavigationStack { PeopleView() }
        .metlyPreview(.empty)
}

#Preview("People · loading") {
    let services = AppServices.preview()
    services.sync = SyncingPreviewStub()
    return NavigationStack { PeopleView() }
        .environment(services)
        .metlyPreview(.empty)
}

#Preview("People · requests only") {
    NavigationStack {
        PreviewPrepared(prepare: { context in
            for person in (try? context.fetch(FetchDescriptor<Connection>())) ?? [] { person.markDeleted() }
        }) {
            PeopleView()
        }
    }
    .metlyPreview(.full)
}

#Preview("People · Events") {
    NavigationStack { PeopleScreen(filter: .events) }
        .metlyPreview(.full)
}

#Preview("People · Places") {
    NavigationStack { PeopleScreen(filter: .places) }
        .metlyPreview(.full)
}

#Preview("People · Tags") {
    NavigationStack { PeopleScreen(filter: .tags) }
        .metlyPreview(.full)
}

#Preview("People · search") {
    NavigationStack { PeopleScreen(query: "Payme") }
        .metlyPreview(.full)
}

#Preview("People · no results") {
    NavigationStack { PeopleScreen(query: "Zebra") }
        .metlyPreview(.full)
}

#Preview("People · via web + merged") {
    NavigationStack {
        PreviewPerson(name: "Timur Nazarov", prepare: { person, _ in person.isMerged = true }) { _ in
            PeopleView()
        }
    }
    .metlyPreview(.full)
}

#Preview("People · dark, accessibility text") {
    NavigationStack { PeopleView() }
        .metlyPreview(.full)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
#endif
