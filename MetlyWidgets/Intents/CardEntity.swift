import AppIntents
import MetlyWidgetKit

/// A card the widget can show ("Card to Share" or one of the user's cards), read from the snapshot
/// the app publishes — the extension never opens the SwiftData store.
nonisolated struct CardEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Card"
    static let defaultQuery = CardEntityQuery()

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

nonisolated struct CardEntityQuery: EntityStringQuery {
    func entities(for identifiers: [CardEntity.ID]) async throws -> [CardEntity] {
        WidgetCardChoice.choices(for: identifiers, in: WidgetSnapshotStore.appGroup.load()).map(CardEntity.init)
    }

    func entities(matching string: String) async throws -> [CardEntity] {
        WidgetCardChoice.matching(string, in: WidgetSnapshotStore.appGroup.load()).map(CardEntity.init)
    }

    func suggestedEntities() async throws -> [CardEntity] {
        WidgetCardChoice.all(in: WidgetSnapshotStore.appGroup.load()).map(CardEntity.init)
    }

    func defaultResult() async -> CardEntity? {
        CardEntity(.automatic)
    }
}
