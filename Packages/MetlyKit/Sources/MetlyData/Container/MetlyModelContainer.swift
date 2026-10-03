import Foundation
import MetlyCore
import SwiftData

public enum MetlyModelContainer {
    /// On-disk store in the App Group container (shared with widgets, read-only there).
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MetlySchemaV1.self)
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

    /// Removes every record (sign-out / account deletion).
    public static func wipe(_ context: ModelContext) throws {
        try context.delete(model: FollowUp.self)
        try context.delete(model: Connection.self)
        try context.delete(model: Event.self)
        try context.delete(model: ConnectRequest.self)
        try context.delete(model: Card.self)
        try context.delete(model: Profile.self)
        try context.save()
    }
}
