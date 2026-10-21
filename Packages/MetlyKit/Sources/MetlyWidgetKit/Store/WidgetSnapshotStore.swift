import Foundation
import MetlyCore

/// Reads and writes the widget snapshot and the pending-action queue in the App Group container.
///
/// Both processes touch these files (the app publishes snapshots and drains the queue; the widget
/// extension appends to the queue and updates the snapshot optimistically), so every read and
/// read-modify-write goes through `NSFileCoordinator`, and writes are atomic. Operations are tiny
/// and synchronous — nothing holds a coordination lock across a suspension point.
nonisolated public struct WidgetSnapshotStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The shared store: `<App Group>/Widgets`. Falls back to Application Support when the App Group
    /// is unavailable (unsigned builds) so nothing crashes — widgets then simply show their empty state.
    public static var appGroup: WidgetSnapshotStore {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Brand.appGroup)
            ?? URL.applicationSupportDirectory
        return WidgetSnapshotStore(directory: base.appending(path: "Widgets", directoryHint: .isDirectory))
    }

    var snapshotURL: URL { directory.appending(path: "snapshot.json") }
    var queueURL: URL { directory.appending(path: "pending-actions.json") }

    // MARK: Snapshot

    /// The last published snapshot, or nil (none yet, unreadable, or written by an incompatible version).
    public func load() -> WidgetSnapshot? {
        guard let data = coordinatedRead(snapshotURL) else { return nil }
        return Self.decodeSnapshot(data)
    }

    public func save(_ snapshot: WidgetSnapshot) throws {
        let data = try Self.encoder.encode(snapshot)
        try coordinatedUpdate(snapshotURL) { _ in data }
    }

    /// Read-modify-write of the snapshot (no-op when there is none).
    public func updateSnapshot(_ transform: (inout WidgetSnapshot) -> Void) throws {
        try coordinatedUpdate(snapshotURL) { data in
            guard let data, var snapshot = Self.decodeSnapshot(data) else { return nil }
            transform(&snapshot)
            return try Self.encoder.encode(snapshot)
        }
    }

    // MARK: Pending actions

    public func pendingActions() -> [WidgetPendingAction] {
        guard let data = coordinatedRead(queueURL) else { return [] }
        return (try? Self.decoder.decode([WidgetPendingAction].self, from: data)) ?? []
    }

    public func enqueue(_ action: WidgetPendingAction) throws {
        try coordinatedUpdate(queueURL) { data in
            var actions = data.flatMap { try? Self.decoder.decode([WidgetPendingAction].self, from: $0) } ?? []
            actions.append(action)
            return try Self.encoder.encode(actions)
        }
    }

    /// Removes only the given entries, so actions appended meanwhile by the widget survive.
    public func removePendingActions(withIDs ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        try coordinatedUpdate(queueURL) { data in
            guard let data else { return nil }
            var actions = (try? Self.decoder.decode([WidgetPendingAction].self, from: data)) ?? []
            actions.removeAll { ids.contains($0.id) }
            return try Self.encoder.encode(actions)
        }
    }

    /// Widget "Done" tap: queue the completion for the app, withdraw the reminder's local notification
    /// and hide the row right away. The app applies the queue only when it next runs, so without the
    /// withdrawal the reminder could still fire after it was marked done.
    public func enqueueFollowUpCompletion(_ followUpID: UUID, at date: Date = .now,
                                          notifications: any WidgetNotificationCenter = SystemWidgetNotificationCenter()) throws {
        let action = WidgetPendingAction.completeFollowUp(followUpID, at: date)
        try enqueue(action)
        notifications.removeNotifications(withIdentifiers: [WidgetFollowUpNotification.identifier(for: followUpID)])
        try updateSnapshot { snapshot in snapshot = snapshot.applying([action]) }
    }

    /// Follow-ups marked done on the widget that the app hasn't applied to its store yet. The app's
    /// notification scheduler skips them, so it never re-adds a notification the widget withdrew.
    public func pendingFollowUpCompletionIDs() -> Set<UUID> {
        Set(pendingActions().filter { $0.kind == .completeFollowUp }.map(\.targetID))
    }

    /// Deletes snapshot and queue (tests, sign-out clean-up).
    public func removeAll() {
        for url in [snapshotURL, queueURL] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Coding

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder { JSONDecoder() }

    static func decodeSnapshot(_ data: Data) -> WidgetSnapshot? {
        guard let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }

    // MARK: File coordination

    private func coordinatedRead(_ url: URL) -> Data? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        var result: Data?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = try? Data(contentsOf: readURL)
        }
        return result
    }

    /// Coordinated read-modify-write. `transform` gets the current bytes (nil when missing) and returns
    /// the new bytes, or nil to leave the file untouched.
    private func coordinatedUpdate(_ url: URL, transform: (Data?) throws -> Data?) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var coordinationError: NSError?
        var thrown: (any Error)?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) { writeURL in
            do {
                let current = try? Data(contentsOf: writeURL)
                guard let updated = try transform(current) else { return }
                try updated.write(to: writeURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                thrown = error
            }
        }
        if let thrown { throw thrown }
        if let coordinationError { throw coordinationError }
    }
}
