import AppIntents
import MetlyWidgetKit

/// One of the user's cards (or "Card to Share") for the Show My QR action in Shortcuts.
/// Backed by the widget snapshot the app publishes, so resolving it never waits on the store.
nonisolated struct ShareCardEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Card"
    static let defaultQuery = ShareCardEntityQuery()

    let id: String
    let title: String
    let subtitle: String

    init(_ choice: WidgetCardChoice) {
        id = choice.id
        title = choice.title
        subtitle = choice.subtitle
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(subtitle)")
    }

    /// nil for "Card to Share".
    var cardID: UUID? { UUID(uuidString: id) }
}

nonisolated struct ShareCardEntityQuery: EntityStringQuery {
    func entities(for identifiers: [ShareCardEntity.ID]) async throws -> [ShareCardEntity] {
        WidgetCardChoice.choices(for: identifiers, in: WidgetSnapshotStore.appGroup.load()).map(ShareCardEntity.init)
    }

    func entities(matching string: String) async throws -> [ShareCardEntity] {
        WidgetCardChoice.matching(string, in: WidgetSnapshotStore.appGroup.load()).map(ShareCardEntity.init)
    }

    func suggestedEntities() async throws -> [ShareCardEntity] {
        WidgetCardChoice.all(in: WidgetSnapshotStore.appGroup.load()).map(ShareCardEntity.init)
    }
}
