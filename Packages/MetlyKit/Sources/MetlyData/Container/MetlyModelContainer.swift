import Foundation
import MetlyCore
import SwiftData

public enum MetlyModelContainer {
    /// On-disk store in the App Group container (shared with widgets, read-only there).
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MetlySchemaV2.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Brand.appGroup) {
            configuration = ModelConfiguration(schema: schema, url: groupURL.appending(path: "Metly.store"))
        } else {
            configuration = ModelConfiguration(schema: schema)
        }
        return try ModelContainer(for: schema, migrationPlan: MetlyMigrationPlan.self, configurations: configuration)
    }

    /// In-memory container filled with `PreviewSeed` (Aziza Karimova demo account).
    @MainActor public static func preview(_ seed: PreviewSeed.Variant = .full) -> ModelContainer {
        do {
            let container = try make(inMemory: true)
            PreviewSeed.insert(seed, into: container.mainContext)
            return container
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }

    /// Removes every record (sign-out / account deletion). Idempotent: wiping an empty store is a
    /// no-op, so the UI and `AuthService` may both call it.
    public static func wipe(_ context: ModelContext) throws {
        wipeAll(FollowUp.self, in: context)
        wipeAll(Connection.self, in: context)
        wipeAll(Event.self, in: context)
        wipeAll(ConnectRequest.self, in: context)
        wipeAll(Card.self, in: context)
        wipeAll(Profile.self, in: context)
        try context.save()
    }

    /// Per-object deletes: SwiftData's batch `delete(model:)` traps on this relationship graph
    /// (Event ⇄ Connection ⇄ FollowUp). Stores are small, so this stays fast.
    private static func wipeAll<Model: PersistentModel>(_ type: Model.Type, in context: ModelContext) {
        for model in (try? context.fetch(FetchDescriptor<Model>())) ?? [] {
            context.delete(model)
        }
    }
}
