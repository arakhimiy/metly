import MetlyCore
import MetlyData
import SwiftUI

/// The shared Context Capture block (SPEC §3.14) as Form sections:
/// **Where You Met** (auto event / location + time) · **Private Note** (voice dictation) · **Tags** · **Follow Up**.
///
/// Place it inside a `Form`/`List`; it emits `Section`s only:
/// ```swift
/// Form {
///     ContextCaptureForm(draft: $draft)
/// }
/// ```
/// Requires `AppServices`, `AppRouter` and a `modelContext` in the environment.
public struct ContextCaptureForm: View {
    @Binding var draft: CaptureDraft
    let sections: CaptureSections

    @State private var location = LocationContextProvider()
    @State private var voice = VoiceNoteRecognizer()

    public init(draft: Binding<CaptureDraft>, sections: CaptureSections = .all) {
        _draft = draft
        self.sections = sections
    }

    public var body: some View {
        if sections.contains(.whereYouMet) {
            WhereYouMetSection(draft: $draft, location: location)
        }
        if sections.contains(.note) {
            PrivateNoteSection(note: $draft.note, voice: voice)
        }
        if sections.contains(.tags) {
            TagsSection(tags: $draft.tags)
        }
        if sections.contains(.followUp) {
            FollowUpSection(draft: $draft)
        }
    }
}

#Preview("Capture · event active") {
    @Previewable @State var draft = CaptureDraft(
        context: MeetingContext(eventName: "Tashkent Tech Week", place: "Hyatt Regency", city: "Tashkent"))
    NavigationStack {
        Form { ContextCaptureForm(draft: $draft) }
            .navigationTitle("Add Context")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { draft.markAutoFilled() }
    }
    .metlyPreview()
}

#Preview("Capture · reminder picked") {
    @Previewable @State var draft: CaptureDraft = {
        var draft = CaptureDraft(note: "Talked about the Payline SDK.", tags: ["Client"])
        draft.followUp = FollowUpDraft(pick: .inThreeDays, channel: .telegram, title: "Send the deck")
        return draft
    }()
    NavigationStack {
        Form { ContextCaptureForm(draft: $draft) }
    }
    .metlyPreview()
}

#Preview("Capture · Just Met subset") {
    @Previewable @State var draft = CaptureDraft()
    NavigationStack {
        Form { ContextCaptureForm(draft: $draft, sections: [.whereYouMet, .note, .followUp]) }
    }
    .metlyPreview()
}
