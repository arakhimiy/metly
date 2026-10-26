import Foundation
import MetlyCore
import MetlyData
import Testing
@testable import FeatureCards

/// SPEC §9 Q4: what may leave the device shows Public fields only; Private never appears.
@MainActor
struct PublicContentTests {
    private let allVisible = CardDesign(visibleFields: Set(ContactFieldKind.allCases))

    @Test func publicAudienceKeepsOnlyPublicFields() throws {
        let context = try makeContext()
        let profile = insertProfile(in: context)
        let content = CardContentFactory.content(profile: profile, design: allVisible, audience: .public, qrPayload: "")
        #expect(content.fields.map(\.kind) == [.telegram, .website])   // LinkedIn is public but empty
    }

    @Test func connectionsAudienceAddsConnectionsButNeverPrivate() throws {
        let context = try makeContext()
        let profile = insertProfile(in: context)
        let content = CardContentFactory.content(profile: profile, design: allVisible, audience: .connections, qrPayload: "")
        #expect(content.fields.map(\.kind) == [.email, .telegram, .website])
    }

    @Test func hiddenFieldsStayHidden() {
        let fields = [ContactField(kind: .website, value: "aziza.design", privacy: .public),
                      ContactField(kind: .telegram, value: "@aziza", privacy: .public)]
        let result = CardContentFactory.fields(fields, visible: [.website], audience: .public)
        #expect(result.map(\.kind) == [.website])
    }

    @Test func fieldsComeOutInDisplayOrder() {
        let fields = [ContactField(kind: .linkedin, value: "in/a", privacy: .public),
                      ContactField(kind: .phone, value: "1", privacy: .public)]
        let result = CardContentFactory.fields(fields, visible: Set(ContactFieldKind.allCases), audience: .public)
        #expect(result.map(\.kind) == [.phone, .linkedin])
    }

    @Test func draftMediaOverridesTheProfile() throws {
        let context = try makeContext()
        let profile = insertProfile(in: context)
        profile.photoData = Data([1])
        let content = CardContentFactory.content(profile: profile, design: allVisible, audience: .connections,
                                                 qrPayload: "", photo: .removed, logo: .replaced(Data([2])))
        #expect(content.photoData == nil)
        #expect(content.logoData == Data([2]))
    }

    @Test func shareableContentLinksPublishedCards() throws {
        let context = try makeContext()
        let profile = insertProfile(in: context)
        let card = insertCard("Work", sortOrder: 0, slug: "aziza-w7k2", design: allVisible, in: context)
        let content = CardContentFactory.shareable(card, profile: profile)
        #expect(content.qrPayload == "https://\(Brand.linkHost)/c/aziza-w7k2")
        #expect(!content.fields.contains { $0.privacy != .public })
    }

    @Test func unpublishedExportsCarryAPublicVCard() throws {
        let context = try makeContext()
        let profile = insertProfile(in: context)
        let card = insertCard("Work", sortOrder: 0, design: allVisible, in: context)
        let payload = CardContentFactory.shareable(card, profile: profile).qrPayload
        #expect(payload.hasPrefix("BEGIN:VCARD"))
        #expect(payload.contains("aziza.design"))
        #expect(!payload.contains("aziza@tezkor.uz"))       // Connections-only
        #expect(!payload.contains("123 45 67"))             // Private
    }

    @Test func offlineQRModes() throws {
        let context = try makeContext()
        let profile = insertProfile(in: context)
        let published = insertCard("Work", sortOrder: 0, slug: "aziza-w7k2", design: allVisible, in: context)
        let draft = insertCard("Draft", sortOrder: 1, design: allVisible, in: context)
        let publicContent = CardContentFactory.shareable(published, profile: profile)

        // Online + slug → the link.
        let online = QRCodeMode.resolve(url: published.url, isOnline: true, prefersOffline: nil, publicContent: publicContent)
        #expect(online == .link(Brand.cardURL(slug: "aziza-w7k2")))

        // Offline → automatic vCard (still carrying the link as a URL line).
        let offline = QRCodeMode.resolve(url: published.url, isOnline: false, prefersOffline: nil, publicContent: publicContent)
        #expect(offline.isOffline)
        #expect(offline.payload.contains("tanishly.app/c/aziza-w7k2"))
        #expect(!offline.payload.contains("aziza@tezkor.uz"))

        // The switch overrides the default either way.
        #expect(QRCodeMode.resolve(url: published.url, isOnline: false, prefersOffline: false, publicContent: publicContent).isOffline == false)
        #expect(QRCodeMode.resolve(url: published.url, isOnline: true, prefersOffline: true, publicContent: publicContent).isOffline)

        // No slug yet → only the vCard is possible.
        let unpublished = QRCodeMode.resolve(url: draft.url, isOnline: true, prefersOffline: false,
                                             publicContent: CardContentFactory.shareable(draft, profile: profile))
        #expect(unpublished.isOffline)
    }

    @Test func linkStatus() {
        let url = Brand.cardURL(slug: "aziza-w7k2")
        #expect(CardLinkStatus(url: url, isOnline: false) == .live(url))
        #expect(CardLinkStatus(url: nil, isOnline: true) == .publishing)
        #expect(CardLinkStatus(url: nil, isOnline: false) == .waitingForNetwork)
        #expect(CardLinkStatus(url: url, isOnline: true).displayText == "tanishly.app/c/aziza-w7k2")
        #expect(CardLinkStatus.publishing.url == nil)
    }
}
