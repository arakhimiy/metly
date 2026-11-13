import Foundation
import Testing
@testable import FeatureOnboarding

@Suite("Setup profile validation")
struct SetupProfileFormTests {
    @Test func emptyFormCannotContinue() {
        let form = SetupProfileForm()
        #expect(!form.isNameValid)
        #expect(!form.canContinue)
        #expect(form.emailError == nil)
    }

    @Test func nameAloneIsEnough() {
        let form = SetupProfileForm(fullName: "Aziza Karimova")
        #expect(form.canContinue)
    }

    @Test func whitespaceNameIsInvalid() {
        #expect(!SetupProfileForm(fullName: "  \n ").canContinue)
    }

    @Test(arguments: ["aziza@tezkor.uz", "a.b+c@sub.domain.co", "  aziza@tezkor.uz  "])
    func acceptsCompleteEmails(_ email: String) {
        let form = SetupProfileForm(fullName: "Aziza", email: email)
        #expect(form.isEmailValid)
        #expect(form.canContinue)
    }

    @Test(arguments: ["aziza", "aziza@", "aziza@tezkor", "aziza@tezkor.u", "@tezkor.uz", "a ziza@tezkor.uz", "a@@b.uz"])
    func rejectsIncompleteEmails(_ email: String) {
        let form = SetupProfileForm(fullName: "Aziza", email: email)
        #expect(!form.isEmailValid)
        #expect(!form.canContinue)
        #expect(form.emailError == "This email address looks incomplete.")
    }

    @Test func prefillsFromProvider() {
        let form = SetupProfileForm(prefill: SetupPrefill(fullName: "Aziza Karimova", email: "aziza@icloud.com", provider: .apple))
        #expect(form.fullName == "Aziza Karimova")
        #expect(form.email == "aziza@icloud.com")
        #expect(form.canContinue)
        #expect(SetupProfileForm(prefill: nil) == SetupProfileForm())
    }

    @Test func savedProfileValuesWinOverSuggestionButEmptyOnesDont() {
        var form = SetupProfileForm(prefill: SetupPrefill(fullName: "Apple Name", email: "apple@icloud.com", provider: .apple))
        form.overlay(fullName: "Saved Name", jobTitle: "Designer", company: "", phone: " ",
                     email: "", telegram: "@saved", photoData: nil)
        #expect(form.fullName == "Saved Name")
        #expect(form.jobTitle == "Designer")
        #expect(form.phone == "")
        #expect(form.email == "apple@icloud.com")
        #expect(form.telegram == "@saved")
    }

    @Test(arguments: [("aziza", "@aziza"), ("@aziza", "@aziza"), (" az iza ", "@aziza"), ("t.me/aziza", "t.me/aziza"), ("", "")])
    func normalizesTelegram(_ input: String, _ expected: String) {
        #expect(SetupProfileForm(telegram: input).normalizedTelegram == expected)
    }

    /// Regression: the API rejects a profile with a contact value over 200 characters (or a name,
    /// title or company over 80); the rejected profile then never synced, so setup's values never
    /// reached the server.
    @Test func contactValuesAreCappedAtTheServerLimit() {
        let form = SetupProfileForm(fullName: "A", email: String(repeating: "a", count: 250) + "@b.uz")
        #expect(form.contactValues.first { $0.kind == .email }?.value.count == 200)
    }

    /// Phone numbers are capped at 40 characters, like every number in Profile.
    @Test func phoneKeepsAtMostFifteenDigitsSpacedForItsCountry() {
        let form = SetupProfileForm(fullName: "A", phone: "+998 " + String(repeating: "9", count: 60))
        let phone = form.contactValues.first { $0.kind == .phone }?.value ?? ""
        #expect(phone.filter(\.isNumber).count == 15)
        #expect(phone.hasPrefix("+998 99 999 99 99"))
        #expect(phone.count <= 40)
        #expect(SetupProfileForm(fullName: "A", phone: "901234567").contactValues.first?.value == "+998 90 123 45 67")
    }

    @Test func nameTitleAndCompanyAreTrimmedAndCapped() {
        let long = String(repeating: "x", count: 95)
        let form = SetupProfileForm(fullName: "  Aziza Karimova ", jobTitle: long, company: " Tezkor ")
        #expect(form.profileFullName == "Aziza Karimova")
        #expect(form.profileJobTitle.count == 80)
        #expect(form.profileCompany == "Tezkor")
    }

    @Test func contactValuesAreTrimmedInDisplayOrder() {
        let form = SetupProfileForm(fullName: "A", phone: " +998 90 123 45 67 ", email: " a@b.uz ", telegram: "aziza")
        let values = form.contactValues
        #expect(values.map(\.kind) == [.phone, .email, .telegram])
        #expect(values.map(\.value) == ["+998 90 123 45 67", "a@b.uz", "@aziza"])
    }
}
