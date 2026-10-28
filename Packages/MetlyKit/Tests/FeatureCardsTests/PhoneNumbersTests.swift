import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureCards

/// Several numbers and the new kinds on cards (3.0.0): audience filtering (exports stay Public-only),
/// per-card selection, defaults for a new card.
@MainActor
struct PhoneNumbersTests {
    private let office = ContactEntry(kind: .phone, label: .work, value: "+998 71 200 10 20", privacy: .public)
    private let home = ContactEntry(kind: .phone, label: .home, value: "+998 71 255 33 44", privacy: .connections)
    private let secondMobile = ContactEntry(kind: .phone, label: .mobile, value: "+998 93 444 55 66", privacy: .private)
    private let whatsapp = ContactEntry(kind: .whatsapp, value: "+998 90 123 45 67", privacy: .public)

    /// Aziza's profile (first phone Private) with a Public, a Connections and a Private extra number and
    /// a Public WhatsApp.
    private func profileWithPhones(in context: ModelContext) -> Profile {
        let profile = insertProfile(in: context)
        profile.phoneLabel = .work
        profile.contacts.insert(contentsOf: [office, home, secondMobile], at: 1)
        profile.contacts.append(whatsapp)
        return profile
    }

    private func all(_ profile: Profile) -> [UUID] { profile.contacts.map(\.id) }

    // MARK: Audience

    @Test func publicContentCarriesOnlyPublicEntries() throws {
        let profile = profileWithPhones(in: try makeContext())
        let content = CardContentFactory.content(profile: profile, design: CardDesign(), selection: all(profile),
                                                 audience: .public, qrPayload: "")
        #expect(content.contacts.map(\.value) == ["+998 71 200 10 20", "@aziza.k", "aziza.design", "+998 90 123 45 67"])
        #expect(content.additionalPhones.isEmpty)   // the office number is the first visible phone
        #expect(content.fields.first { $0.kind == .phone }?.value == "+998 71 200 10 20")
    }

    @Test func inAppPreviewAddsConnectionsButNeverPrivate() throws {
        let profile = profileWithPhones(in: try makeContext())
        let content = CardContentFactory.content(profile: profile, design: CardDesign(), selection: all(profile),
                                                 audience: .connections, qrPayload: "")
        #expect(content.contacts.filter { $0.kind == .phone }.map(\.value) == ["+998 71 200 10 20", "+998 71 255 33 44"])
        #expect(!content.contacts.contains { $0.privacy == .private })
    }

    @Test func eachCardShowsItsOwnSelection() throws {
        let profile = profileWithPhones(in: try makeContext())
        let content = CardContentFactory.content(profile: profile, design: CardDesign(), selection: [whatsapp.id],
                                                 audience: .connections, qrPayload: "")
        #expect(content.contacts.map(\.kind) == [.whatsapp])
    }

    @Test func aNewCardShowsEveryEntryThatIsNotPrivate() throws {
        let profile = profileWithPhones(in: try makeContext())
        let selection = profile.defaultCardSelection
        #expect(!selection.contains(secondMobile.id))
        #expect(!selection.contains { id in profile.contacts.first { $0.id == id }?.privacy == .private })
        #expect(selection.contains(whatsapp.id))
    }

    @Test func theSelectionKeepsVisibleFieldsInStepForOlderApps() throws {
        let profile = profileWithPhones(in: try makeContext())
        var design = CardDesign(visibleFields: [])
        design.syncVisibleFields(with: [whatsapp.id, office.id], in: profile.contacts)
        #expect(design.visibleFields == [.phone])   // WhatsApp isn't a legacy kind
    }

    @Test func exportsAndUnpublishedQRStayPublic() throws {
        let context = try makeContext()
        let profile = profileWithPhones(in: context)
        let card = insertCard("Work", sortOrder: 0, design: CardDesign(), in: context)
        card.visibleContactIDs = all(profile)
        let content = CardContentFactory.shareable(card, profile: profile)
        #expect(content.contacts.allSatisfy { $0.privacy == .public })
        #expect(content.qrPayload.contains("TEL;TYPE=WORK,VOICE:+998 71 200 10 20"))
        #expect(content.qrPayload.contains("X-SOCIALPROFILE;TYPE=whatsapp:https://wa.me/998901234567"))
        #expect(!content.qrPayload.contains("255 33 44"))   // Connections
        #expect(!content.qrPayload.contains("444 55 66"))   // Private
    }

    @Test func offlineQRCarriesThePublicOfficeNumber() throws {
        let context = try makeContext()
        let profile = profileWithPhones(in: context)
        let card = insertCard("Work", sortOrder: 0, slug: "aziza-w7k2", design: CardDesign(), in: context)
        card.visibleContactIDs = all(profile)
        let mode = QRCodeMode.resolve(url: card.url, isOnline: false, prefersOffline: true,
                                      publicContent: CardContentFactory.shareable(card, profile: profile))
        #expect(mode.payload.contains("+998 71 200 10 20"))
        #expect(!mode.payload.contains("255 33 44"))
    }
}
