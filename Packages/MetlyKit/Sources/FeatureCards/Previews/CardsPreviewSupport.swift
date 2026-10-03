#if DEBUG
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// Runs `prepare` once against the preview store, then shows `content`.
struct PreviewPrepared<Content: View>: View {
    var prepare: (ModelContext) -> Void
    @ViewBuilder var content: Content

    @Environment(\.modelContext) private var modelContext
    @State private var isReady = false

    var body: some View {
        Group {
            if isReady {
                content
            } else {
                ProgressView()
            }
        }
        .task {
            prepare(modelContext)
            try? modelContext.save()
            isReady = true
        }
    }
}

/// Resolves a seeded card + profile for previews of views that take models directly.
struct PreviewCard<Content: View>: View {
    let cardID: UUID
    let content: (Card, Profile?) -> Content

    @Query(Card.live) private var cards: [Card]
    @Query(ProfileQuery.current) private var profiles: [Profile]

    var body: some View {
        if let card = cards.first(where: { $0.id == cardID }) {
            content(card, profiles.first)
        } else {
            ProgressView()
        }
    }
}

/// Store tweaks for the SPEC states the seed doesn't cover.
enum PreviewStore {
    static let workCardID = PreviewSeed.workCardID
    static let personalCardID = PreviewSeed.personalCardID

    /// No slug yet: "Publishing…", link actions disabled, offline QR only.
    static func unpublish(_ cardID: UUID, in context: ModelContext) {
        guard let card = context.record(Card.self, id: cardID) else { return }
        card.slug = ""
        card.publishState = .draft
    }

    static func pauseLinks(in context: ModelContext) {
        context.currentProfile()?.linksPaused = true
    }

    /// Setup → first card: a profile without cards.
    static func removeAllCards(in context: ModelContext) {
        for card in (try? context.fetch(Card.live)) ?? [] { card.markDeleted() }
        context.currentProfile()?.defaultCardID = nil
    }

    static func useDesign(_ design: CardDesign, for cardID: UUID, in context: ModelContext) {
        context.record(Card.self, id: cardID)?.design = design
    }

    /// A profile photo so Modern / Split / Stack show it.
    static func addPhoto(in context: ModelContext) {
        let renderer = ImageRenderer(content: Image(systemName: "person.crop.circle.fill")
            .resizable().foregroundStyle(.teal).frame(width: 120, height: 120).background(.white))
        context.currentProfile()?.photoData = renderer.uiImage?.pngData()
    }
}
#endif
