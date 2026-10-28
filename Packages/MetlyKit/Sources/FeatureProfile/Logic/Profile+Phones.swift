import Foundation
import MetlyCore
import MetlyData

/// Editing the owner's extra phone numbers (PROFILE › Contact Details). Every real change calls
/// `markChanged()` so the sync engine republishes the profile; no-op edits never dirty it.
extension Profile {
    func additionalPhone(id: UUID) -> LabeledPhone? {
        additionalPhones.first { $0.id == id }
    }

    var canAddPhone: Bool { PhoneListRules.canAdd(to: additionalPhones) }

    /// Appends an empty number with a suggested label and privacy; nil at the limit.
    /// Returns its id so the new row can take focus.
    @discardableResult
    func addPhone() -> UUID? {
        guard canAddPhone else { return nil }
        let phone = PhoneListRules.newPhone(primaryLabel: phoneLabel, primaryPrivacy: field(.phone).privacy,
                                            extras: additionalPhones)
        additionalPhones.append(phone)
        markChanged()
        return phone.id
    }

    func removePhone(id: UUID) {
        guard let index = additionalPhones.firstIndex(where: { $0.id == id }) else { return }
        additionalPhones.remove(at: index)
        markChanged()
    }

    /// Swipe to delete in Contact Details.
    func removePhones(atOffsets offsets: IndexSet) {
        let valid = offsets.filter { additionalPhones.indices.contains($0) }
        guard !valid.isEmpty else { return }
        for index in valid.sorted(by: >) { additionalPhones.remove(at: index) }
        markChanged()
    }

    /// Mutates one extra number and marks the profile changed when something actually changed.
    func updatePhone(id: UUID, _ change: (inout LabeledPhone) -> Void) {
        guard let index = additionalPhones.firstIndex(where: { $0.id == id }) else { return }
        var phone = additionalPhones[index]
        let original = phone
        change(&phone)
        guard phone != original else { return }
        additionalPhones[index] = phone
        markChanged()
    }

    func setPhoneLabel(_ label: PhoneLabel) {
        guard phoneLabel != label else { return }
        phoneLabel = label
        markChanged()
    }

    /// Cleans a number up when the user leaves it; a number left empty is removed (like Contacts).
    func normalizePhone(id: UUID) {
        guard let phone = additionalPhone(id: id) else { return }
        let value = PhoneListRules.normalized(phone.value)
        if value.isEmpty {
            removePhone(id: id)
        } else {
            updatePhone(id: id) { $0.value = value }
        }
    }
}
