import Foundation
import MetlyCore

/// Editable values of SETUP_PROFILE ("About You") plus validation. Pure value type, unit-tested.
nonisolated struct SetupProfileForm: Equatable, Sendable {
    var fullName = ""
    var jobTitle = ""
    var company = ""
    var phone = ""
    var email = ""
    var telegram = ""
    var photoData: Data?

    init(fullName: String = "", jobTitle: String = "", company: String = "", phone: String = "",
         email: String = "", telegram: String = "", photoData: Data? = nil) {
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.phone = phone
        self.email = email
        self.telegram = telegram
        self.photoData = photoData
    }

    /// Starts from what the identity provider suggested.
    init(prefill: SetupPrefill?) {
        self.init(fullName: prefill?.fullName ?? "", email: prefill?.email ?? "")
    }

    // MARK: Merging

    /// Overlays values already saved on the profile (e.g. returning to setup after a relaunch).
    /// Empty values never overwrite a suggestion.
    mutating func overlay(fullName: String, jobTitle: String, company: String, phone: String,
                          email: String, telegram: String, photoData: Data?) {
        func pick(_ saved: String, _ current: String) -> String {
            saved.trimmed.isEmpty ? current : saved
        }
        self.fullName = pick(fullName, self.fullName)
        self.jobTitle = pick(jobTitle, self.jobTitle)
        self.company = pick(company, self.company)
        self.phone = pick(phone, self.phone)
        self.email = pick(email, self.email)
        self.telegram = pick(telegram, self.telegram)
        self.photoData = photoData ?? self.photoData
    }

    // MARK: Validation

    var isNameValid: Bool { !fullName.trimmed.isEmpty }

    /// Email is optional, but when present it must look complete (SPEC §2.5.2 regex).
    var isEmailValid: Bool {
        let value = email.trimmed
        return value.isEmpty || Self.looksLikeEmail(value)
    }

    var canContinue: Bool { isNameValid && isEmailValid }

    /// Inline footer copy for an incomplete email, nil when fine.
    var emailError: String? {
        isEmailValid ? nil : String(localized: "Check your email — it looks incomplete.")
    }

    static func looksLikeEmail(_ value: String) -> Bool {
        value.wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]{2,}/) != nil
    }

    // MARK: Normalised output

    /// Server limits for the synced profile (`docs/api/openapi.yaml` → Profile, ContactField): a
    /// longer value gets the whole profile rejected, and a rejected profile doesn't sync again
    /// until it changes.
    static let maxTextLength = 80
    static let maxContactLength = 200
    /// Phone numbers (schema 2.0.0: every number, primary and extra, is capped at 40).
    static let maxPhoneLength = 40

    /// Values written to the profile: trimmed and capped at the server limits.
    var profileFullName: String { fullName.trimmed.capped(at: Self.maxTextLength) }
    var profileJobTitle: String { jobTitle.trimmed.capped(at: Self.maxTextLength) }
    var profileCompany: String { company.trimmed.capped(at: Self.maxTextLength) }

    /// Telegram handles are stored with a leading "@" (links like t.me/… are kept as typed).
    var normalizedTelegram: String {
        let value = telegram.trimmed.replacing(" ", with: "")
        guard !value.isEmpty, !value.hasPrefix("@"), !value.contains("/") else { return value }
        return "@" + value
    }

    /// Contact values written to the profile, in display order.
    var contactValues: [(kind: ContactFieldKind, value: String)] {
        let values: [(kind: ContactFieldKind, value: String)] = [
            (.phone, phone.trimmed), (.email, email.trimmed), (.telegram, normalizedTelegram),
        ]
        return values.map { ($0.kind, $0.value.capped(at: $0.kind == .phone ? Self.maxPhoneLength : Self.maxContactLength)) }
    }
}

private extension String {
    nonisolated var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    nonisolated func capped(at limit: Int) -> String {
        count > limit ? String(prefix(limit)) : self
    }
}
