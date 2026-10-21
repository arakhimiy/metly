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
        profile.editor.privacyBinding(for: .phone).wrappedValue = ContactFieldKind.phone.defaultPrivacy
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

    @Test func contactFieldEditsKeepOneEntryPerKind() throws {
        let (container, profile) = try makeProfile()
        let editor = profile.editor
        editor.valueBinding(for: .telegram).wrappedValue = "t.me/aziza"
        editor.privacyBinding(for: .telegram).wrappedValue = .private
        profile.normalizeField(.telegram)
        #expect(profile.field(.telegram) == ContactField(kind: .telegram, value: "@aziza", privacy: .private))
        #expect(profile.contactFields.count == ContactFieldKind.allCases.count)
        #expect(profile.syncState == .pendingUpsert)
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
        editor.valueBinding(for: .website).wrappedValue = "example.com/" + String(repeating: "x", count: 300)
        #expect(profile.fullName.count == 80)
        #expect(profile.jobTitle.count == 80)
        #expect(profile.company.count == 80)
        #expect(profile.field(.website).value.count == 200)
        #expect(profile.field(.website).value.hasPrefix("example.com/"))
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
