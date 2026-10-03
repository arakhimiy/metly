import Foundation
import MetlyCore
import MetlyData
import MetlyNetworking
import SwiftData
@testable import FeatureConnect

/// Keeps in-memory containers alive for the duration of a test.
@MainActor private var retainedContainers: [ModelContainer] = []

@MainActor
func makeContainer(_ seed: PreviewSeed.Variant? = nil) throws -> ModelContainer {
    let container = try MetlyModelContainer.make(inMemory: true)
    if let seed { PreviewSeed.insert(seed, into: container.mainContext) }
    retainedContainers.append(container)
    return container
}

/// A mock-backed client with instant timers (Kamila accepts after ~40 ms, Nodira expires after ~250 ms).
@MainActor
func makeClient(container: ModelContainer, online: Bool = true) -> MetlyClient {
    let server = MockMetlyServer(seed: .demo, configuration: .instant, isReachable: online)
    return MetlyClient(api: server, container: container, mockServer: server)
}

enum WaitError: Error { case timedOut(String) }

/// Polls `condition` on the main actor until it holds (or fails after `timeout`).
@MainActor
func waitUntil(_ description: String, timeout: Duration = .seconds(5),
               _ condition: @MainActor () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { throw WaitError.timedOut(description) }
        try await Task.sleep(for: .milliseconds(20))
    }
}
