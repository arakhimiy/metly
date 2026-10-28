@preconcurrency import Contacts
import Foundation
import MetlyCore
import MetlyData

/// The values handed to iOS Contacts' "New Contact" screen.
public struct ContactDraft: Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var fullName: String
    public var jobTitle: String
    public var company: String
    /// Every number with its label, primary first. Saved as Mobile / Work / Home / Other in Contacts.
    public var phones: [LabeledPhone]
    public var email: String
    public var telegram: String
    public var website: String
    public var linkedin: String

    /// The primary number (first of `phones`).
    public var phone: String {
        get { phones.first?.value ?? "" }
        set {
            if phones.isEmpty {
                phones = [LabeledPhone(id: LabeledPhone.primaryID, label: .mobile, value: newValue)]
            } else {
                phones[0].value = newValue
            }
        }
    }

    /// - Parameters:
    ///   - phone: The primary number, labelled `phoneLabel`.
    ///   - additionalPhones: More numbers after it (work, home…).
    public init(fullName: String, jobTitle: String = "", company: String = "", phone: String = "",
                phoneLabel: PhoneLabel = .mobile, additionalPhones: [LabeledPhone] = [],
                email: String = "", telegram: String = "", website: String = "", linkedin: String = "") {
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        let primary = phone.trimmed.isEmpty ? [] : [LabeledPhone(id: LabeledPhone.primaryID, label: phoneLabel, value: phone)]
        self.phones = primary + additionalPhones.filter { !$0.isEmpty }
        self.email = email
        self.telegram = telegram
        self.website = website
        self.linkedin = linkedin
    }

    public init(connection: Connection) {
        self.init(fullName: connection.fullName, jobTitle: connection.jobTitle, company: connection.company,
                  email: connection.email, telegram: connection.telegram,
                  website: connection.website, linkedin: connection.linkedin)
        phones = connection.allPhones
    }

    /// The Contacts label for a phone label (`CNLabelPhoneNumberMobile`, `CNLabelWork`, `CNLabelHome`, `CNLabelOther`).
    static func contactsLabel(for label: PhoneLabel) -> String {
        switch label {
        case .mobile: CNLabelPhoneNumberMobile
        case .work: CNLabelWork
        case .home: CNLabelHome
        case .other: CNLabelOther
        }
    }

    /// Every non-empty phone once (same digits = same number), labelled for Contacts.
    var contactPhoneNumbers: [CNLabeledValue<CNPhoneNumber>] {
        var seen = Set<String>()
        return phones.compactMap { phone in
            let value = phone.value.trimmed
            guard !value.isEmpty, seen.insert(ContactLinks.dialable(value) ?? value).inserted else { return nil }
            return CNLabeledValue(label: Self.contactsLabel(for: phone.label), value: CNPhoneNumber(stringValue: value))
        }
    }

    /// Builds the `CNMutableContact` shown by `CNContactViewController(forNewContact:)`.
    /// The private note is never copied (it is "Only You" and would need the notes entitlement).
    func makeContact() -> CNMutableContact {
        let contact = CNMutableContact()
        let name = fullName.trimmed
        if let components = PersonNameComponentsFormatter().personNameComponents(from: name),
           components.givenName != nil || components.familyName != nil {
            contact.givenName = components.givenName ?? ""
            contact.middleName = components.middleName ?? ""
            contact.familyName = components.familyName ?? ""
        } else {
            contact.givenName = name
        }
        contact.jobTitle = jobTitle.trimmed
        contact.organizationName = company.trimmed

        contact.phoneNumbers = contactPhoneNumbers
        if !email.trimmed.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email.trimmed as NSString)]
        }
        if let url = ContactLinks.website(website) {
            contact.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: url.absoluteString as NSString)]
        }

        var profiles: [CNLabeledValue<CNSocialProfile>] = []
        if let handle = ContactLinks.telegramHandle(telegram) {
            let profile = CNSocialProfile(urlString: "https://t.me/\(handle)", username: handle,
                                          userIdentifier: nil, service: "Telegram")
            profiles.append(CNLabeledValue(label: "Telegram", value: profile))
        }
        if let url = ContactLinks.linkedIn(linkedin) {
            let profile = CNSocialProfile(urlString: url.absoluteString, username: nil,
                                          userIdentifier: nil, service: CNSocialProfileServiceLinkedIn)
            profiles.append(CNLabeledValue(label: CNSocialProfileServiceLinkedIn, value: profile))
        }
        contact.socialProfiles = profiles
        return contact
    }
}

public extension ContactDraft {
    /// Labels the primary phone and appends extra numbers (duplicates of an existing number are skipped).
    mutating func applyPhones(primaryLabel: PhoneLabel, additional: [LabeledPhone]) {
        if !phones.isEmpty { phones[0].label = primaryLabel }
        let digits = { (value: String) in value.filter(\.isNumber) }
        for phone in additional where !phone.isEmpty && !phones.contains(where: { digits($0.value) == digits(phone.value) }) {
            phones.append(phone)
        }
    }
}
