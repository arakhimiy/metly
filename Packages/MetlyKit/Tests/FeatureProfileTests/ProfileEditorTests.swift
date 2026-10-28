import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureProfile

@Suite("Profile editing marks changes for sync")
@MainActor
struct ProfileEditorTests {
    private func makeProfile() throws -> (ModelContainer, Profile) {
        let container = try MetlyModelContainer.make(inMemory: true)
        let profile = Profile(fullName: "Aziza Karimova", contactFields: ContactField.defaults)
        container.mainContext.insert(profile)
        profile.syncState = .synced
        return (container, profile)
    }

    @Test func unchangedValuesDoNotDirtyTheProfile() throws {
        let (container, profile) = try makeProfile()
        profile.editor.binding(\.fullName).wrappedValue = "Aziza Karimova"
        let phone = try #require(profile.addContact(.phone))
        profile.editor.privacyBinding(id: phone).wrappedValue = ContactFieldKind.phone.defaultPrivacy
        profile.editor.valueBinding(id: phone).wrappedValue = ""
        #expect(profile.syncState == .synced)
        withExtendedLifetime(container) {}
    }

    @Test func userEditsMarkTheProfileChanged() throws {
        let (container, profile) = try makeProfile()
        profile.editor.binding(\.jobTitle).wrappedValue = "Product Designer"
        #expect(profile.jobTitle == "Product Designer")
        #expect(profile.syncState == .pendingUpsert)
        withExtendedLifetime(container) {}
    }

    @Test func contactEditsAreCleanedUpWhenLeft() throws {
        let (container, profile) = try makeProfile()
        let editor = profile.editor
        let telegram = try #require(profile.addContact(.telegram))
        editor.valueBinding(id: telegram).wrappedValue = "t.me/aziza"
        editor.privacyBinding(id: telegram).wrappedValue = .private
        profile.normalizeContact(id: telegram)
        #expect(profile.field(.telegram) == ContactField(kind: .telegram, value: "@aziza", privacy: .private))
        #expect(profile.syncState == .pendingUpsert)

        // A row left empty goes away.
        let empty = try #require(profile.addContact(.instagram))
        profile.normalizeContact(id: empty)
        #expect(!profile.contacts.contains { $0.id == empty })
        withExtendedLifetime(container) {}
    }

    @Test func didEditRunsOnlyForRealChanges() throws {
        let (container, profile) = try makeProfile()
        let recorder = EditRecorder()
        let binding = profile.editor.binding(\.linksPaused) { recorder.values.append($0) }
        binding.wrappedValue = false
        binding.wrappedValue = true
        #expect(recorder.values == [true])
        withExtendedLifetime(container) {}
    }

    /// Regression: the API rejects a profile whose name / title / company is over 80 characters or a
    /// contact value over 200 (`openapi.yaml` Profile). A rejected profile stays unsynced until it
    /// changes again — so every later edit, including making a field Private, never reached the
    /// public page. Values are capped where they're typed.
    @Test func valuesAreCappedAtTheServerLimits() throws {
        let (container, profile) = try makeProfile()
        let editor = profile.editor
        editor.textBinding(\.fullName).wrappedValue = String(repeating: "A", count: 120)
        editor.textBinding(\.jobTitle).wrappedValue = String(repeating: "B", count: 81)
        editor.textBinding(\.company).wrappedValue = String(repeating: "C", count: 80)
        let website = try #require(profile.addContact(.website))
        editor.valueBinding(id: website).wrappedValue = "example.com/" + String(repeating: "x", count: 600)
        let phone = try #require(profile.addContact(.phone))
        editor.valueBinding(id: phone).wrappedValue = String(repeating: "9", count: 60)
        #expect(profile.fullName.count == 80)
        #expect(profile.jobTitle.count == 80)
        #expect(profile.company.count == 80)
        #expect(profile.field(.website).value.count == 500)
        #expect(profile.field(.website).value.hasPrefix("example.com/"))
        #expect(profile.field(.phone).value.filter(\.isNumber).count == 15)   // E.164, spaced as typed
        #expect(profile.field(.phone).value.count <= LabeledPhone.maxValueLength)
        withExtendedLifetime(container) {}
    }

    @Test func choosingTelegramBeforeLinkingAsksToLink() throws {
        let (container, profile) = try makeProfile()
        let recorder = EditRecorder()
        let delivery = profile.editor.deliveryBinding { recorder.values.append(true) }
        delivery.wrappedValue = .telegramBot
        #expect(recorder.values.count == 1)
        #expect(profile.notificationPrefs.delivery == .push)

        profile.editor.updateNotificationPrefs { $0.telegramLinked = true }
        delivery.wrappedValue = .telegramBot
        #expect(profile.notificationPrefs.delivery == .telegramBot)
        #expect(recorder.values.count == 1)
        withExtendedLifetime(container) {}
    }
}

/// Collects callback invocations (a MainActor class so `@Sendable` callbacks can capture it).
@MainActor
private final class EditRecorder {
    var values: [Bool] = []
}
