import Foundation
import MetlyCore
import Testing
@testable import MetlyWidgetKit

@Suite("Snapshot JSON & store")
struct WidgetSnapshotStoreTests {
    @Test("JSON round-trip keeps every value (dates, sets, optionals, vCard payloads)")
    func jsonRoundTrip() throws {
        var snapshot = build(makeInput(
            followUps: [followUp(1, due: date(2026, 9, 25), context: "Tashkent Tech Week"), followUp(2, due: date(2026, 9, 30))],
            connectionDates: [date(2026, 9, 26, 9, 15)],
            photo: Data([0xFF, 0xD8]),
            eventName: "Tashkent Tech Week"
        ))
        snapshot.owner?.logoThumbnail = Data([7, 7, 7])
        let data = try WidgetSnapshotStore.encoder.encode(snapshot)
        let decoded = try WidgetSnapshotStore.decoder.decode(WidgetSnapshot.self, from: data)
        #expect(decoded == snapshot)
        #expect(decoded.card(id: personalCardID)?.qrPayload.hasPrefix("BEGIN:VCARD") == true)
    }

    @Test("Signed-out and sample snapshots round-trip too", arguments: [WidgetSnapshot.signedOut(at: testNow), .sample(now: testNow)])
    func roundTripVariants(_ snapshot: WidgetSnapshot) throws {
        let data = try WidgetSnapshotStore.encoder.encode(snapshot)
        #expect(WidgetSnapshotStore.decodeSnapshot(data) == snapshot)
    }

    @Test("Save then load returns the same snapshot")
    func saveAndLoad() throws {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        #expect(store.load() == nil)
        let snapshot = WidgetSnapshot.sample(now: testNow)
        try store.save(snapshot)
        #expect(store.load() == snapshot)
    }

    @Test("Unreadable or incompatible files are ignored")
    func corruptAndIncompatibleFiles() throws {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.snapshotURL)
        #expect(store.load() == nil)

        var future = WidgetSnapshot.sample(now: testNow)
        future.schemaVersion = WidgetSnapshot.currentSchemaVersion + 1
        try WidgetSnapshotStore.encoder.encode(future).write(to: store.snapshotURL)
        #expect(store.load() == nil)
    }

    @Test("Content comparison ignores the generation date")
    func sameContentIgnoresGeneratedAt() {
        let first = WidgetSnapshot.sample(now: testNow)
        var second = first
        second.generatedAt = testNow.addingTimeInterval(60)
        #expect(first.hasSameContent(as: second))
        second.activeEventName = "Other"
        #expect(!first.hasSameContent(as: second))
    }
}
