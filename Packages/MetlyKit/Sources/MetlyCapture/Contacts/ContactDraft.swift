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
    public var phone: String
    public var email: String
    public var telegram: String
    public var website: String
    public var linkedin: String

    public init(fullName: String, jobTitle: String = "", company: String = "", phone: String = "",
                email: String = "", telegram: String = "", website: String = "", linkedin: String = "") {
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.phone = phone
        self.email = email
        self.telegram = telegram
        self.website = website
        self.linkedin = linkedin
    }

    public init(connection: Connection) {
        self.init(fullName: connection.fullName, jobTitle: connection.jobTitle, company: connection.company,
                  phone: connection.phone, email: connection.email, telegram: connection.telegram,
                  website: connection.website, linkedin: connection.linkedin)
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

        if !phone.trimmed.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                                   value: CNPhoneNumber(stringValue: phone.trimmed))]
        }
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
