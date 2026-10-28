import Foundation
import MetlyCore
import Testing
@testable import FeatureProfile

@Suite("Contact field & privacy helpers")
struct ContactFieldRulesTests {
    @Test(arguments: [
        ("  @aziza.k ", "@aziza.k"),
        ("aziza.k", "@aziza.k"),
        ("https://t.me/aziza_k/", "@aziza_k"),
        ("t.me/aziza", "@aziza"),
        ("", ""),
        ("   ", ""),
    ])
    func telegramIsNormalisedToHandle(input: String, expected: String) {
        #expect(ContactFieldRules.normalized(input, for: .telegram) == expected)
    }

    @Test func websiteDropsSchemeAndTrailingSlash() {
        #expect(ContactFieldRules.normalized("https://aziza.design/", for: .website) == "aziza.design")
        #expect(ContactFieldRules.normalized("HTTP://www.aziza.design", for: .website) == "www.aziza.design")
    }

    @Test func linkedInKeepsOnlyThePath() {
        #expect(ContactFieldRules.normalized("https://www.linkedin.com/in/azizakarimova/", for: .linkedin) == "in/azizakarimova")
        #expect(ContactFieldRules.normalized("in/azizakarimova", for: .linkedin) == "in/azizakarimova")
    }

    @Test func emailIsTrimmedAndLowercased() {
        #expect(ContactFieldRules.normalized(" Aziza@Tezkor.UZ ", for: .email) == "aziza@tezkor.uz")
    }

    @Test func phoneCollapsesWhitespace() {
        #expect(ContactFieldRules.normalized(" +998  90 123   45 67 ", for: .phone) == "+998 90 123 45 67")
    }

    @Test func everyKindHasAKeyboardAndPlaceholder() {
        for kind in ContactFieldKind.allCases {
            #expect(!ContactFieldRules.placeholder(for: kind).isEmpty)
        }
        #expect(ContactFieldRules.keyboardType(for: .phone) == .phonePad)
        #expect(ContactFieldRules.keyboardType(for: .email) == .emailAddress)
        #expect(ContactFieldRules.contentType(for: .email) == .emailAddress)
        #expect(ContactFieldRules.contentType(for: .telegram) == nil)
    }

    private var fields: [ContactField] {
        [
            ContactField(kind: .linkedin, value: "in/aziza", privacy: .connections),
            ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .private),
            ContactField(kind: .email, value: "aziza@tezkor.uz", privacy: .public),
            ContactField(kind: .telegram, value: "", privacy: .public),
            ContactField(kind: .website, value: "aziza.design", privacy: .public),
        ]
    }

    @Test func publicAudienceSeesOnlyFilledPublicFieldsInOrder() {
        let visible = ContactFieldRules.visibleFields(fields, to: .public).map(\.kind)
        #expect(visible == [.email, .website])
    }

    @Test func connectionsAudienceNeverSeesPrivateFields() {
        let visible = ContactFieldRules.visibleFields(fields, to: .connections).map(\.kind)
        #expect(visible == [.email, .website, .linkedin])
        #expect(!visible.contains(.phone))
    }

    @Test func privacyCountsIgnoreEmptyFields() {
        let counts = ContactFieldRules.privacyCounts(fields)
        #expect(counts[.public] == 2)
        #expect(counts[.connections] == 1)
        #expect(counts[.private] == 1)
    }

    @Test func everyPrivacyLevelHasASymbol() {
        #expect(Set(FieldPrivacy.allCases.map(\.symbolName)).count == FieldPrivacy.allCases.count)
    }

    @Test @MainActor func returnKeyWalksThroughEveryField() {
        let ids = [UUID(), UUID(), UUID()]
        var field: ProfileFocusField? = .name
        var visited: [ProfileFocusField] = []
        while let current = field {
            visited.append(current)
            field = current.next(contactIDs: ids)
        }
        #expect(visited == [.name, .jobTitle, .company] + ids.map { .contact($0) })
        #expect(ProfileFocusField.company.next(contactIDs: []) == nil)
    }
}
