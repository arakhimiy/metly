import MetlyCapture
import MetlyCore

extension ContactDraft {
    /// iOS Contacts "New Contact" prefilled from scanned values.
    init(fullName: String, jobTitle: String, company: String, fields: [ContactField]) {
        func value(_ kind: ContactFieldKind) -> String { fields.first { $0.kind == kind }?.value ?? "" }
        self.init(fullName: fullName, jobTitle: jobTitle, company: company,
                  phone: value(.phone), email: value(.email), telegram: value(.telegram),
                  website: value(.website), linkedin: value(.linkedin))
    }
}
