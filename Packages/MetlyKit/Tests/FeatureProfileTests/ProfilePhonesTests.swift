import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureProfile

/// PROFILE › Contact Details (3.0.0): a list the owner builds with "+ Add Contact".
@Suite("Profile contact list")
@MainActor
struct ProfilePhonesTests {
    private func makeProfile() throws -> (ModelContainer, Profile) {
        let container = try MetlyModelContainer.make(inMemory: true)
        let profile = Profile(fullName: "Aziza Karimova",
                              contactFields: [ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .public)])
        container.mainContext.insert(profile)
        profile.syncState = .synced
        return (container, profile)
    }

    @Test func addingAppendsAnEmptyEntryWithoutQueueingASync() throws {
        let (container, profile) = try makeProfile()
        let id = try #require(profile.addContact(.whatsapp))
        #expect(profile.contacts.map(\.kind) == [.phone, .whatsapp])
        #expect(profile.contacts.last?.id == id)
        #expect(profile.contacts.last?.isEmpty == true)
        #expect(profile.syncState == .synced)   // nothing to send until a value is typed
        profile.editor.valueBinding(id: id).wrappedValue = "+998 90 123 45 67"
        #expect(profile.syncState == .pendingUpsert)
        withExtendedLifetime(container) {}
    }

    /// Regression: tapping "Add Phone" twice before typing made the rows jump (the empty one vanished as
    /// another was added). The empty row is reused instead.
    @Test func tappingAddAgainReusesTheEmptyRow() throws {
        let (container, profile) = try makeProfile()
        let first = try #require(profile.addContact(.phone))
        #expect(profile.addContact(.phone) == first)
        #expect(profile.addContact(.instagram) == first)
        #expect(profile.contacts.count == 2)
        #expect(profile.contacts.last?.kind == .instagram)
        withExtendedLifetime(container) {}
    }

    @Test func newNumbersNeverShareMoreThanTheOwnersPhones() throws {
        let (container, profile) = try makeProfile()
        let shared = try #require(profile.addContact(.phone))
        #expect(profile.contacts.first { $0.id == shared }?.privacy == .connections)   // phones start at Connections
        profile.removeContacts(ids: [shared])

        profile.updateContact(id: profile.contacts[0].id) { $0.privacy = .private }
        let hidden = try #require(profile.addContact(.whatsapp))
        #expect(profile.contacts.first { $0.id == hidden }?.privacy == .private)
        let instagram = try #require(profile.addContact(.instagram))
        #expect(instagram == hidden)   // still empty: reused
        withExtendedLifetime(container) {}
    }

    @Test func theListStopsAtTheLimit() throws {
        let (container, profile) = try makeProfile()
        for index in 1..<ContactEntry.maxCount {
            let id = try #require(profile.addContact(.phone))
            profile.updateContact(id: id) { $0.value = "+998 71 200 10 \(index)" }
        }
        #expect(!profile.canAddContact)
        #expect(profile.addContact(.email) == nil)
        #expect(profile.contacts.count == ContactEntry.maxCount)
        withExtendedLifetime(container) {}
    }

    @Test func severalOfTheSameKind() throws {
        let (container, profile) = try makeProfile()
        for email in ["aziza@uzum.uz", "aziza@gmail.com"] {
            let id = try #require(profile.addContact(.email))
            profile.updateContact(id: id) { $0.value = email }
        }
        #expect(profile.contacts.entries(of: .email).map(\.value) == ["aziza@uzum.uz", "aziza@gmail.com"])
        #expect(profile.field(.email).value == "aziza@uzum.uz")   // the one-per-kind view takes the first
        withExtendedLifetime(container) {}
    }

    @Test func emptyRowsAreDroppedAndDeletesQueueASync() throws {
        let (container, profile) = try makeProfile()
        profile.addContact(.telegram)
        profile.removeEmptyContacts()
        #expect(profile.contacts.map(\.kind) == [.phone])
        #expect(profile.syncState == .synced)
        profile.removeContacts(ids: [profile.contacts[0].id])
        #expect(profile.contacts.isEmpty)
        #expect(profile.syncState == .pendingUpsert)
        withExtendedLifetime(container) {}
    }

    @Test func aNewNumberTakesTheNextFreeLabel() throws {
        let (container, profile) = try makeProfile()   // has a Mobile number
        let second = try #require(profile.addContact(.phone))
        #expect(profile.contacts.first { $0.id == second }?.label == .work)
        withExtendedLifetime(container) {}
    }

    @Test func labelsAreEditable() throws {
        let (container, profile) = try makeProfile()
        profile.editor.labelBinding(id: profile.contacts[0].id).wrappedValue = .work
        #expect(profile.phoneLabel == .work)
        #expect(profile.syncState == .pendingUpsert)
        withExtendedLifetime(container) {}
    }
}
