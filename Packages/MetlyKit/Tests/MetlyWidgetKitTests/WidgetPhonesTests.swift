import Foundation
import MetlyCore
import Testing
@testable import MetlyWidgetKit

/// Extra phone numbers on widgets (they can sit on the Lock Screen): Public only, and only when the
/// card shows phones.
@Suite("Widget phone numbers")
struct WidgetPhonesTests {
    private let office = LabeledPhone(label: .work, value: " +998 71 200 10 20 ", privacy: .public)
    private let home = LabeledPhone(label: .home, value: "+998 71 255 33 44", privacy: .connections)
    private let secret = LabeledPhone(label: .mobile, value: "+998 93 444 55 66", privacy: .private)

    private func input(design: CardDesign, slug: String = "") -> WidgetSnapshotInput {
        var owner = makeOwner()
        owner.phoneLabel = .work
        owner.additionalPhones = [office, home, secret, LabeledPhone(label: .other, value: "  ", privacy: .public)]
        return WidgetSnapshotInput(owner: owner, cards: [
            WidgetSnapshotInput.Card(id: workCardID, name: "Work", slug: slug, design: design),
        ], defaultCardID: workCardID)
    }

    @Test("Only Public, non-empty numbers reach the snapshot, trimmed")
    func publicExtrasOnly() throws {
        let card = try #require(build(input(design: designWithoutTelegram)).card(id: workCardID))
        let phones = (card.contacts ?? []).filter { $0.kind == .phone }
        #expect(phones.map(\.value) == ["+998 71 200 10 20"])   // the Connections primary stays out
        #expect(phones.allSatisfy { $0.privacy == .public })
        #expect(card.phoneLabel == .work)
        let face = card.faceContent(owner: WidgetSnapshot.sampleOwner)
        #expect(face.contacts == card.contacts)
        #expect(face.phoneLabel == .work)
    }

    @Test("Each card shows its own selection, WhatsApp and Instagram included")
    func selection() throws {
        var snapshotInput = input(design: designWithoutTelegram)
        let whatsapp = ContactEntry(kind: .whatsapp, value: "+998 90 123 45 67", privacy: .public)
        snapshotInput.owner.explicitContacts = snapshotInput.owner.contacts + [whatsapp]
        snapshotInput.cards = snapshotInput.cards.map { card in
            var copy = card
            copy.visibleContactIDs = [whatsapp.id]
            return copy
        }
        let card = try #require(build(snapshotInput).card(id: workCardID))
        #expect(card.contacts?.map(\.kind) == [.whatsapp])
    }

    @Test("A card that hides phones carries no extra numbers")
    func hiddenPhones() throws {
        let card = try #require(build(input(design: CardDesign(visibleFields: [.email]))).card(id: workCardID))
        #expect(card.additionalPhones.isEmpty)
    }

    @Test("The offline vCard of an unpublished card writes the Public office number only")
    func offlineVCard() throws {
        let card = try #require(build(input(design: designWithoutTelegram)).card(id: workCardID))
        #expect(card.qrPayload.contains("TEL;TYPE=WORK,VOICE:+998 71 200 10 20"))
        #expect(!card.qrPayload.contains("255 33 44"))   // Connections
        #expect(!card.qrPayload.contains("444 55 66"))   // Private
        #expect(!card.qrPayload.contains("123 45 67"))   // Connections primary
    }

    @Test("Snapshots written before labelled phones still decode")
    func decodesOlderSnapshots() throws {
        var snapshot = build(input(design: designWithoutTelegram, slug: "aziza-k7m2"))
        let data = try WidgetSnapshotStore.encoder.encode(snapshot)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var cards = try #require(json["cards"] as? [[String: Any]])
        for index in cards.indices {
            cards[index].removeValue(forKey: "additionalPhones")
            cards[index].removeValue(forKey: "phoneLabel")
        }
        json["cards"] = cards
        let old = try JSONSerialization.data(withJSONObject: json)

        let decoded = try #require(WidgetSnapshotStore.decodeSnapshot(old))
        snapshot.cards = snapshot.cards.map { card in
            var card = card
            card.additionalPhones = []
            card.phoneLabel = .mobile
            return card
        }
        #expect(decoded == snapshot)
    }

    @Test("New snapshots round-trip their extra numbers")
    func roundTrip() throws {
        let snapshot = build(input(design: designWithoutTelegram))
        let data = try WidgetSnapshotStore.encoder.encode(snapshot)
        #expect(WidgetSnapshotStore.decodeSnapshot(data) == snapshot)
    }
}
