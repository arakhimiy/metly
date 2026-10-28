import Foundation
import MetlyCore
import SwiftData
import Testing
@testable import MetlyData

/// A store written by the shipped 1.0.0 schema must open with the current one, keep every record
/// and get the 2.0.0 defaults (labelled phones).
@Suite("Schema migration")
struct SchemaMigrationTests {
    @Test("A 1.0.0 store migrates to 2.0.0 without losing data")
    func v1StoreMigratesToV2() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "Metly.store")
        let profileID = UUID()
        let connectionID = UUID()

        // 1. Write with the frozen 1.0.0 schema only.
        do {
            let schema = Schema(versionedSchema: MetlySchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let context = ModelContext(container)
            let profile = MetlySchemaV1.Profile(id: profileID, fullName: "Aziza Karimova",
                                                contactFields: [ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .public)])
            context.insert(profile)
            let person = MetlySchemaV1.Connection(id: connectionID, fullName: "Kamila Yusupova", source: .paper)
            person.phone = "+998 71 200 00 00"
            context.insert(person)
            try context.save()
        }

        // 2. Open with the current schema + migration plan, like the app does.
        let schema = Schema(versionedSchema: MetlySchemaV2.self)
        let container = try ModelContainer(for: schema, migrationPlan: MetlyMigrationPlan.self,
                                           configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        let profile = try #require(try context.fetch(FetchDescriptor<Profile>()).first)
        #expect(profile.id == profileID)
        #expect(profile.fullName == "Aziza Karimova")
        #expect(profile.field(.phone).value == "+998 90 123 45 67")
        #expect(profile.phoneLabel == .mobile)
        #expect(profile.additionalPhones.isEmpty)

        let person = try #require(try context.fetch(FetchDescriptor<Connection>()).first)
        #expect(person.id == connectionID)
        #expect(person.phone == "+998 71 200 00 00")
        #expect(person.phoneLabel == .mobile)
        #expect(person.allPhones.map(\.value) == ["+998 71 200 00 00"])

        // 3. New fields round-trip.
        person.additionalPhones = [LabeledPhone(label: .work, value: "+998 71 202 02 02")]
        person.phoneLabel = .work
        try context.save()
        let reread = try #require(try ModelContext(container).fetch(FetchDescriptor<Connection>()).first)
        #expect(reread.allPhones.map(\.label) == [.work, .work])
        #expect(reread.mobilePhone == "+998 71 200 00 00")
    }

    @Test("Card face content carries public extra phones only")
    func faceContentFiltersExtraPhones() throws {
        let profile = Profile(fullName: "Aziza", contactFields: [ContactField(kind: .phone, value: "+998 90 1", privacy: .public)])
        profile.additionalPhones = [
            LabeledPhone(label: .work, value: "+998 71 1", privacy: .public),
            LabeledPhone(label: .home, value: "+998 71 2", privacy: .connections),
            LabeledPhone(label: .other, value: "+998 71 3", privacy: .private),
        ]
        let card = Card(name: "Work")
        #expect(card.faceContent(profile: profile, audience: .public).additionalPhones.map(\.value) == ["+998 71 1"])
        #expect(card.faceContent(profile: profile, audience: .connections).additionalPhones.map(\.value) == ["+998 71 1", "+998 71 2"])
        card.design.visibleFields.remove(.phone)
        #expect(card.faceContent(profile: profile, audience: .connections).additionalPhones.isEmpty)
    }
}
