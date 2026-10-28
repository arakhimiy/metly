import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureCards

/// Several labelled phones on cards: audience filtering (exports stay Public-only), the
/// "Phone Numbers" switch and the density notes in CARD_EDITOR › Fields.
@MainActor
struct PhoneNumbersTests {
    private let allVisible = CardDesign(density: .detailed, visibleFields: Set(ContactFieldKind.allCases))

    private let office = LabeledPhone(label: .work, value: "+998 71 200 10 20", privacy: .public)
    private let home = LabeledPhone(label: .home, value: "+998 71 255 33 44", privacy: .connections)
    private let secondMobile = LabeledPhone(label: .mobile, value: "+998 93 444 55 66", privacy: .private)

    /// Aziza's profile (primary phone Private) with a Public, a Connections and a Private extra number.
    private func profileWithPhones(in context: ModelContext) -> Profile {
        let profile = insertProfile(in: context)
        profile.phoneLabel = .work
        profile.additionalPhones = [office, home, secondMobile, LabeledPhone(label: .other, value: " ", privacy: .public)]
        return profile
    }

    // MARK: Audience

    @Test func publicContentCarriesOnlyPublicExtras() throws {
        let profile = profileWithPhones(in: try makeContext())
        let content = CardContentFactory.content(profile: profile, design: allVisible, audience: .public, qrPayload: "")
        #expect(content.additionalPhones == [office])
        #expect(content.phoneLabel == .work)
        #expect(!content.fields.contains { $0.kind == .phone })   // the primary is Private
    }

    @Test func inAppPreviewAddsConnectionsExtrasButNeverPrivate() throws {
        let profile = profileWithPhones(in: try makeContext())
        let content = CardContentFactory.content(profile: profile, design: allVisible, audience: .connections, qrPayload: "")
        #expect(content.additionalPhones == [office, home])
    }

    @Test func hidingPhonesHidesEveryNumber() throws {
        let profile = profileWithPhones(in: try makeContext())
        let design = CardDesign(visibleFields: [.email, .telegram])
        #expect(CardContentFactory.content(profile: profile, design: design, audience: .connections, qrPayload: "")
            .additionalPhones.isEmpty)
    }

    @Test func exportsAndUnpublishedQRStayPublic() throws {
        let context = try makeContext()
        let profile = profileWithPhones(in: context)
        let card = insertCard("Work", sortOrder: 0, design: allVisible, in: context)
        let content = CardContentFactory.shareable(card, profile: profile)
        #expect(content.additionalPhones.allSatisfy { $0.privacy == .public })
        #expect(content.qrPayload.contains("TEL;TYPE=WORK,VOICE:+998 71 200 10 20"))
        #expect(!content.qrPayload.contains("255 33 44"))   // Connections
        #expect(!content.qrPayload.contains("444 55 66"))   // Private
        #expect(!content.qrPayload.contains("123 45 67"))   // Private primary
    }

    @Test func offlineQRCarriesThePublicOfficeNumber() throws {
        let context = try makeContext()
        let profile = profileWithPhones(in: context)
        let card = insertCard("Work", sortOrder: 0, slug: "aziza-w7k2", design: allVisible, in: context)
        let mode = QRCodeMode.resolve(url: card.url, isOnline: false, prefersOffline: true,
                                      publicContent: CardContentFactory.shareable(card, profile: profile))
        #expect(mode.payload.contains("+998 71 200 10 20"))
        #expect(!mode.payload.contains("255 33 44"))
    }

    // MARK: "Phone Numbers" switch

    @Test func aPublicExtraKeepsTheSwitchUsableWhenThePrimaryIsPrivate() {
        let primary = ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .private)
        let privacy = CardDesignRules.phoneGroupPrivacy(primary: primary, additionalPhones: [secondMobile, office])
        #expect(privacy == .public)
        #expect(CardDesignRules.settingField(.phone, visible: true, privacy: privacy, in: CardDesign(visibleFields: []))
                == .updated(CardDesign(visibleFields: [.phone])))
    }

    @Test func everyNumberPrivateDisablesTheSwitch() {
        let primary = ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .private)
        let privacy = CardDesignRules.phoneGroupPrivacy(primary: primary, additionalPhones: [secondMobile])
        #expect(privacy == .private)
        #expect(CardDesignRules.settingField(.phone, visible: true, privacy: privacy, in: CardDesign(visibleFields: []))
                == .blocked(.privateField))
        #expect(CardDesignRules.privatePhoneCount(primary: primary, additionalPhones: [secondMobile, office]) == 2)
    }

    @Test func withoutNumbersThePrimaryPrivacyApplies() {
        let empty = ContactField(kind: .phone, value: "", privacy: .connections)
        #expect(CardDesignRules.phoneGroupPrivacy(primary: empty, additionalPhones: [LabeledPhone(value: "")]) == .connections)
        #expect(CardDesignRules.privatePhoneCount(primary: empty, additionalPhones: []) == 0)
    }

    // MARK: Density notes

    @Test func extraNumbersOnlyUseFreeLines() {
        let fields = [
            ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .public),
            ContactField(kind: .email, value: "a@b.uz", privacy: .public),
            ContactField(kind: .telegram, value: "@a", privacy: .connections),
        ]
        let extras = [office, home, secondMobile]
        func design(_ density: CardDensity) -> CardDesign {
            CardDesign(density: density, visibleFields: Set(ContactFieldKind.allCases))
        }
        // Balanced: phone, email, Telegram fill the 3 lines → both visible extras (office, home) are left out.
        #expect(CardDesignRules.fieldsHiddenByDensity(fields: fields, additionalPhones: extras, design: design(.balanced)) == 0)
        #expect(CardDesignRules.phonesHiddenByDensity(fields: fields, additionalPhones: extras, design: design(.balanced)) == 2)
        // Minimal: Telegram doesn't fit either.
        #expect(CardDesignRules.fieldsHiddenByDensity(fields: fields, additionalPhones: extras, design: design(.minimal)) == 1)
        // Detailed: 2 free lines → both extras fit; the Private one never counts.
        #expect(CardDesignRules.phonesHiddenByDensity(fields: fields, additionalPhones: extras, design: design(.detailed)) == 0)
        // Phones hidden on this card: nothing to note.
        #expect(CardDesignRules.phonesHiddenByDensity(fields: fields, additionalPhones: extras,
                                                      design: CardDesign(density: .minimal, visibleFields: [.email])) == 0)
    }
}
