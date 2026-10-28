import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureProfile

/// PROFILE › Contact Details: the primary phone's label and the extra labelled numbers.
@Suite("Profile phone numbers")
@MainActor
struct ProfilePhonesTests {
    private func makeProfile() throws -> (ModelContainer, Profile) {
        let container = try MetlyModelContainer.make(inMemory: true)
        let profile = Profile(fullName: "Aziza Karimova", contactFields: ContactField.defaults)
        profile.setField(ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .public))
        container.mainContext.insert(profile)
        profile.syncState = .synced
        return (container, profile)
    }

    @Test func addingSuggestsTheNextUnusedLabel() throws {
        let (container, profile) = try makeProfile()
        let first = try #require(profile.addPhone())
        #expect(profile.syncState == .pendingUpsert)
        #expect(profile.additionalPhone(id: first)?.label == .work)
        #expect(profile.additionalPhone(id: first)?.value == "")
        profile.addPhone()
        profile.addPhone()
        #expect(profile.additionalPhones.map(\.label) == [.work, .home, .other])
        withExtendedLifetime(container) {}
    }

    @Test func newNumbersAreNeverMoreOpenThanThePrimary() throws {
        let (container, profile) = try makeProfile()
        let shared = try #require(profile.addPhone())
        #expect(profile.additionalPhone(id: shared)?.privacy == .connections)   // phones start at Connections

        profile.update(.phone) { $0.privacy = .private }
        let hidden = try #require(profile.addPhone())
        #expect(profile.additionalPhone(id: hidden)?.privacy == .private)
        withExtendedLifetime(container) {}
    }

    @Test func atMostFiveExtraNumbers() throws {
        let (container, profile) = try makeProfile()
        for _ in 0..<ProfileFieldLimits.maxAdditionalPhones { #expect(profile.addPhone() != nil) }
        #expect(!profile.canAddPhone)
        #expect(profile.addPhone() == nil)
        #expect(profile.additionalPhones.count == 5)
        withExtendedLifetime(container) {}
    }

    @Test func labelPrivacyAndValueEditsMarkTheProfileChanged() throws {
        let (container, profile) = try makeProfile()
        let id = try #require(profile.addPhone())
        profile.syncState = .synced
        let editor = profile.editor

        editor.extraPhoneLabelBinding(id: id).wrappedValue = .work   // unchanged
        editor.extraPhonePrivacyBinding(id: id).wrappedValue = .connections   // unchanged
        #expect(profile.syncState == .synced)

        editor.extraPhoneLabelBinding(id: id).wrappedValue = .home
        #expect(profile.additionalPhone(id: id)?.label == .home)
        #expect(profile.syncState == .pendingUpsert)

        profile.syncState = .synced
        editor.extraPhonePrivacyBinding(id: id).wrappedValue = .public
        #expect(profile.additionalPhone(id: id)?.privacy == .public)
        #expect(profile.syncState == .pendingUpsert)

        profile.syncState = .synced
        editor.extraPhoneValueBinding(id: id).wrappedValue = "+998 71 200 10 20"
        #expect(profile.additionalPhone(id: id)?.value == "+998 71 200 10 20")
        #expect(profile.syncState == .pendingUpsert)
        withExtendedLifetime(container) {}
    }

    @Test func primaryLabelEdits() throws {
        let (container, profile) = try makeProfile()
        let label = profile.editor.phoneLabelBinding()
        label.wrappedValue = .mobile
        #expect(profile.syncState == .synced)
        label.wrappedValue = .work
        #expect(profile.phoneLabel == .work)
        #expect(profile.syncState == .pendingUpsert)
        withExtendedLifetime(container) {}
    }

    /// The API caps every phone number at 40 characters (a longer one gets the whole profile rejected).
    @Test func numbersAreCappedAtFortyCharacters() throws {
        let (container, profile) = try makeProfile()
        let id = try #require(profile.addPhone())
        let long = "+998 " + String(repeating: "9", count: 60)
        profile.editor.extraPhoneValueBinding(id: id).wrappedValue = long
        profile.editor.valueBinding(for: .phone).wrappedValue = long
        #expect(profile.additionalPhone(id: id)?.value.count == 40)
        #expect(profile.field(.phone).value.count == 40)
        #expect(profile.field(.phone).value.hasPrefix("+998 9"))
        withExtendedLifetime(container) {}
    }

    @Test func leavingANumberCleansItUpOrRemovesItWhenEmpty() throws {
        let (container, profile) = try makeProfile()
        let typed = try #require(profile.addPhone())
        let blank = try #require(profile.addPhone())
        profile.editor.extraPhoneValueBinding(id: typed).wrappedValue = "  +998 71   200 10 20 "
        profile.editor.extraPhoneValueBinding(id: blank).wrappedValue = "   "

        profile.normalizePhone(id: typed)
        profile.normalizePhone(id: blank)
        #expect(profile.additionalPhones.map(\.value) == ["+998 71 200 10 20"])
        withExtendedLifetime(container) {}
    }

    @Test func removingNumbers() throws {
        let (container, profile) = try makeProfile()
        let work = try #require(profile.addPhone())
        let home = try #require(profile.addPhone())
        let other = try #require(profile.addPhone())
        profile.syncState = .synced

        profile.removePhone(id: UUID())   // unknown: nothing to do
        #expect(profile.syncState == .synced)

        profile.removePhone(id: home)
        #expect(profile.additionalPhones.map(\.id) == [work, other])
        #expect(profile.syncState == .pendingUpsert)

        profile.syncState = .synced
        profile.removePhones(atOffsets: IndexSet([0, 7]))
        #expect(profile.additionalPhones.map(\.id) == [other])
        #expect(profile.syncState == .pendingUpsert)
        withExtendedLifetime(container) {}
    }

    @Test func allPhonesListsThePrimaryFirst() throws {
        let (container, profile) = try makeProfile()
        let id = try #require(profile.addPhone())
        profile.editor.extraPhoneValueBinding(id: id).wrappedValue = "+998 71 200 10 20"
        profile.addPhone()   // still empty: skipped
        #expect(profile.allPhones.map(\.value) == ["+998 90 123 45 67", "+998 71 200 10 20"])
        #expect(profile.allPhones.first?.isPrimary == true)
        withExtendedLifetime(container) {}
    }

    @Test func returnKeyWalksThroughExtraNumbersBeforeEmail() {
        let first = UUID(), second = UUID()
        let ids = [first, second]
        #expect(ProfileFocusField.contact(.phone).next(extraPhoneIDs: ids) == .extraPhone(first))
        #expect(ProfileFocusField.extraPhone(first).next(extraPhoneIDs: ids) == .extraPhone(second))
        #expect(ProfileFocusField.extraPhone(second).next(extraPhoneIDs: ids) == .contact(.email))
        #expect(ProfileFocusField.extraPhone(UUID()).next(extraPhoneIDs: ids) == .contact(.email))
        #expect(ProfileFocusField.contact(.phone).next(extraPhoneIDs: []) == .contact(.email))
        #expect(ProfileFocusField.contact(.linkedin).next(extraPhoneIDs: ids) == nil)
    }

    @Test func suggestedLabelsAndPrivacy() {
        #expect(PhoneListRules.suggestedLabel(primary: .work, extras: []) == .mobile)
        #expect(PhoneListRules.suggestedLabel(primary: .mobile, extras: [LabeledPhone(label: .work)]) == .home)
        #expect(PhoneListRules.suggestedLabel(primary: .mobile, extras: [LabeledPhone(label: .work), LabeledPhone(label: .home)])
                == .other)
        #expect(PhoneListRules.suggestedPrivacy(primary: .public) == .connections)
        #expect(PhoneListRules.suggestedPrivacy(primary: .connections) == .connections)
        #expect(PhoneListRules.suggestedPrivacy(primary: .private) == .private)
    }
}
