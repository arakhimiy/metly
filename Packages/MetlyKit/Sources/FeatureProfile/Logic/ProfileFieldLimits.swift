import Foundation
import MetlyCore
import MetlyNetworking

/// Server limits for the synced profile (`docs/api/openapi.yaml` → Profile, ContactField, LabeledPhone).
/// A longer value gets the whole profile rejected by sync push, and a rejected profile isn't sent
/// again until it changes — so later edits (e.g. making a field Private) would never reach the
/// public page. Values are capped where they're typed.
nonisolated enum ProfileFieldLimits {
    /// Full name, job title, company.
    static let text = 80
    /// Email, Telegram, website, LinkedIn.
    static let contactValue = 200
    /// Every phone number: the extras' server limit, applied to the primary one too.
    static let phone = LabeledPhone.maxValueLength
    /// Extra numbers after the primary phone.
    static let maxAdditionalPhones = LabeledPhone.maxAdditional

    static func limit(for kind: ContactFieldKind) -> Int {
        kind == .phone ? phone : contactValue
    }

    static func capped(_ value: String, at limit: Int) -> String {
        value.count > limit ? String(value.prefix(limit)) : value
    }
}
