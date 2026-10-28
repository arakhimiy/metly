import Foundation
import MetlyCore
import SwiftData
import Testing
@testable import MetlyData

/// A store written by a shipped schema (1.0.0, 2.0.0) must open with the current one (3.0.0), keep every
/// record and turn the per-kind values into contact lists.
/// Serialized and in a test target of its own: stores of different versions opened side by side make
/// SwiftData mix up the same-named models of the frozen schemas.
@Suite("Schema migration", .serialized)
struct SchemaMigrationTests {
    private func storeURL() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory, directory.appending(path: "Metly.store"))
    }

    /// Opens with the current schema + migration plan, like the app does.
    private func openCurrent(at url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MetlySchemaV3.self)
        return try ModelContainer(for: schema, migrationPlan: MetlyMigrationPlan.self,
                                  configurations: ModelConfiguration(schema: schema, url: url))
    }

    @Test("A 1.0.0 store migrates to 3.0.0 without losing data")
    func v1StoreMigratesToV3() throws {
        let (directory, url) = try storeURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profileID = UUID()

        do {
            let schema = Schema(versionedSchema: MetlySchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let profile = MetlySchemaV1.Profile(id: profileID, fullName: "Aziza Karimova",
                                                contactFields: [ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .public),
                                                                ContactField(kind: .email, value: "", privacy: .public),
                                                                ContactField(kind: .telegram, value: "@aziza", privacy: .connections)])
            context.insert(profile)
            let person = MetlySchemaV1.Connection(fullName: "Kamila Yusupova", source: .paper)
            person.phone = "+998 71 200 00 00"
            person.email = "kamila@uzum.uz"
            context.insert(person)
            try context.save()
        }

        let context = ModelContext(try openCurrent(at: url))
        let profile = try #require(try context.fetch(FetchDescriptor<Profile>()).first)
        #expect(profile.id == profileID)
        #expect(profile.fullName == "Aziza Karimova")
        #expect(profile.contacts.map(\.kind) == [.phone, .telegram])
        #expect(profile.contacts.first?.id == ContactEntry.primaryID(for: .phone))
        #expect(profile.contacts.first?.label == .mobile)
        #expect(profile.field(.telegram).privacy == .connections)

        let person = try #require(try context.fetch(FetchDescriptor<Connection>()).first)
        #expect(person.contacts.map(\.value) == ["+998 71 200 00 00", "kamila@uzum.uz"])
        #expect(person.phone == "+998 71 200 00 00")
    }

    @Test("A 2.0.0 store keeps every labelled phone in its list")
    func v2StoreMigratesToV3() throws {
        let (directory, url) = try storeURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workID = UUID()

        do {
            let schema = Schema(versionedSchema: MetlySchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let profile = MetlySchemaV2.Profile(fullName: "Aziza",
                                                contactFields: [ContactField(kind: .phone, value: "+998 90 1", privacy: .public),
                                                                ContactField(kind: .website, value: "aziza.design", privacy: .public)])
            profile.phoneLabelRaw = PhoneLabel.work.rawValue
            profile.additionalPhones = [LabeledPhone(id: workID, label: .home, value: "+998 71 2", privacy: .private)]
            context.insert(profile)
            let person = MetlySchemaV2.Connection(fullName: "Kamila", source: .paper)
            person.phone = "+998 71 200 00 00"
            person.additionalPhones = [LabeledPhone(label: .mobile, value: "+998 93 1")]
            context.insert(person)
            try context.save()
        }

        let container = try openCurrent(at: url)
        let context = ModelContext(container)
        let profile = try #require(try context.fetch(FetchDescriptor<Profile>()).first)
        #expect(profile.contacts.map(\.kind) == [.phone, .phone, .website])
        #expect(profile.contacts.compactMap(\.label) == [.work, .home])
        #expect(profile.contacts[1].id == workID)
        #expect(profile.contacts[1].privacy == .private)

        let person = try #require(try context.fetch(FetchDescriptor<Connection>()).first)
        #expect(person.allPhones.map(\.value) == ["+998 71 200 00 00", "+998 93 1"])

        // New entries round-trip.
        person.contacts.append(ContactEntry(kind: .instagram, value: "@kamila"))
        try context.save()
        let reread = try #require(try ModelContext(container).fetch(FetchDescriptor<Connection>()).first)
        #expect(reread.contacts.last?.kind == .instagram)
    }
}
