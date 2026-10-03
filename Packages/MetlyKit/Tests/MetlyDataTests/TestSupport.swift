import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData
@testable import MetlyData

/// In-memory store + instant mock server + a sync engine that only runs when asked.
@MainActor
struct SyncHarness {
    let container: ModelContainer
    let server: MockMetlyServer
    let engine: SyncEngine
    let state: SyncStateStore
    let network: NetworkMonitor

    var context: ModelContext { container.mainContext }

    init(local: PreviewSeed.Variant = .signedOut, server seed: MockMetlyServer.Seed = .demo, online: Bool = true) throws {
        container = try MetlyModelContainer.make(inMemory: true)
        PreviewSeed.insert(local, into: container.mainContext)
        server = MockMetlyServer(seed: seed, configuration: .instant)
        state = SyncStateStore(defaults: UserDefaults(suiteName: "metly.tests.\(UUID().uuidString)")!)
        network = NetworkMonitor(simulatedOnline: online)
        engine = SyncEngine(container: container, api: server, network: network, state: state, observeChanges: false)
    }

    func all<Model: PersistentModel>(_ type: Model.Type) -> [Model] {
        (try? context.fetch(FetchDescriptor<Model>())) ?? []
    }

    func count<Model: PersistentModel>(_ type: Model.Type) -> Int { all(type).count }

    func connection(_ id: UUID) -> Connection? { context.record(Connection.self, id: id) }
}

enum TestImage {
    /// Minimal JPEG-looking bytes (magic number is all the content-type sniffing needs).
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x02, 0x03])
}
