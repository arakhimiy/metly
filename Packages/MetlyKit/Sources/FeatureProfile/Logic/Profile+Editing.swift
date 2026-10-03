import MetlyCore
import MetlyData
import SwiftUI

/// Bindings into the synced `Profile` that call `markChanged()` only for real user edits
/// (values arriving from sync are never re-marked as dirty).
///
/// A MainActor class (hence Sendable) wraps the model so the `@Sendable` Binding closures
/// don't capture the non-Sendable `@Model` directly.
@MainActor
final class ProfileEditor {
    let profile: Profile

    init(_ profile: Profile) {
        self.profile = profile
    }

    /// - Parameter didEdit: runs after a user edit was applied (e.g. to show a toast).
    func binding<Value: Equatable & Sendable>(
        _ keyPath: ReferenceWritableKeyPath<Profile, Value> & Sendable,
        didEdit: (@MainActor @Sendable (Value) -> Void)? = nil
    ) -> Binding<Value> {
        Binding {
            self.profile[keyPath: keyPath]
        } set: { newValue in
            guard self.profile[keyPath: keyPath] != newValue else { return }
            self.profile[keyPath: keyPath] = newValue
            self.profile.markChanged()
            didEdit?(newValue)
        }
    }

    func valueBinding(for kind: ContactFieldKind) -> Binding<String> {
        Binding {
            self.profile.field(kind).value
        } set: { newValue in
            self.profile.update(kind) { $0.value = newValue }
        }
    }

    func privacyBinding(for kind: ContactFieldKind) -> Binding<FieldPrivacy> {
        Binding {
            self.profile.field(kind).privacy
        } set: { newValue in
            self.profile.update(kind) { $0.privacy = newValue }
        }
    }

    /// Reminder delivery; picking Telegram before the bot is linked asks to link it instead.
    func deliveryBinding(requestTelegramLink: @escaping @MainActor @Sendable () -> Void) -> Binding<ReminderDelivery> {
        Binding {
            self.profile.notificationPrefs.delivery
        } set: { newValue in
            if newValue == .telegramBot, !self.profile.notificationPrefs.telegramLinked {
                requestTelegramLink()
                return
            }
            self.updateNotificationPrefs { $0.delivery = newValue }
        }
    }

    func updateNotificationPrefs(_ change: (inout NotificationPrefs) -> Void) {
        var prefs = profile.notificationPrefs
        change(&prefs)
        guard prefs != profile.notificationPrefs else { return }
        profile.notificationPrefs = prefs
        profile.markChanged()
    }
}

extension Profile {
    @MainActor var editor: ProfileEditor { ProfileEditor(self) }

    /// Applies `ContactFieldRules.normalized` to a field (called when the user leaves it).
    func normalizeField(_ kind: ContactFieldKind) {
        update(kind) { $0.value = ContactFieldRules.normalized($0.value, for: kind) }
    }

    /// Mutates one contact field and marks the profile changed when something actually changed.
    func update(_ kind: ContactFieldKind, _ change: (inout ContactField) -> Void) {
        var field = field(kind)
        let original = field
        change(&field)
        guard field != original else { return }
        setField(field)
        markChanged()
    }
}
