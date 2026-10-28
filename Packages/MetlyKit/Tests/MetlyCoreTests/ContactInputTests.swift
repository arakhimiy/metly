import Foundation
import Testing
@testable import MetlyCore

@Suite("Phone numbers are spaced for their country while typed")
struct PhoneNumberFormatTests {
    @Test(arguments: [
        ("+998901234567", "+998 90 123 45 67"),
        ("+998 (90) 123-45-67", "+998 90 123 45 67"),
        ("998901234567", "+998 90 123 45 67"),
        ("00998901234567", "+998 90 123 45 67"),
        ("+9989", "+998 9"),
        ("+99890123", "+998 90 123"),
        ("+79123456789", "+7 912 345 67 89"),
        ("+12025550123", "+1 202 555 0123"),
        ("+", "+"),
        ("", ""),
    ])
    func international(_ typed: String, _ shown: String) {
        #expect(PhoneNumberFormat.asYouType(typed, region: "US") == shown)
    }

    @Test func localUzbekNumbersGetTheirCodeOnLeave() {
        #expect(PhoneNumberFormat.asYouType("901234567", region: "UZ") == "90 123 45 67")
        #expect(PhoneNumberFormat.normalized("901234567", region: "UZ") == "+998 90 123 45 67")
        // An Uzbek operator code is enough, whatever the phone's region.
        #expect(PhoneNumberFormat.normalized("99 123 12 12", region: "DE") == "+998 99 123 12 12")
        // A short number stays as typed (spaced).
        #expect(PhoneNumberFormat.normalized("1234567", region: "DE") == "123 456 7")
    }

    @Test func lettersAndExtraDigitsAreDropped() {
        #expect(PhoneNumberFormat.asYouType("+998 90 abc 123 45 67", region: "UZ") == "+998 90 123 45 67")
        #expect(PhoneNumberFormat.asYouType("+9989012345678901234", region: "UZ").filter(\.isNumber).count == 15)
    }
}

@Suite("Contact values are checked for their kind")
struct ContactValidationTests {
    @Test func emails() {
        #expect(ContactValidation.isValid("test@test.test", for: .email))
        #expect(ContactValidation.isValid("aziza.k+cards@tezkor.uz", for: .email))
        #expect(!ContactValidation.isValid("hello", for: .email))
        #expect(!ContactValidation.isValid("a@b", for: .email))
        #expect(!ContactValidation.isValid("a b@c.uz", for: .email))
        #expect(ContactValidation.problem("", for: .email) == nil)   // empty isn't an error
    }

    @Test func phonesAndUsernames() {
        #expect(ContactValidation.isValid("+998 90 123 45 67", for: .phone))
        #expect(!ContactValidation.isValid("12345", for: .phone))
        #expect(!ContactValidation.isValid("call me", for: .whatsapp))
        #expect(ContactValidation.isValid("@aziza_k", for: .telegram))
        #expect(ContactValidation.isValid("t.me/aziza_k", for: .telegram))
        #expect(!ContactValidation.isValid("@a", for: .telegram))
        #expect(ContactValidation.isValid("@kamila.design", for: .instagram))
        #expect(!ContactValidation.isValid("@kamila design", for: .instagram))
    }

    @Test func linksAndAddresses() {
        #expect(ContactValidation.isValid("tezkor.uz", for: .website))
        #expect(ContactValidation.isValid("https://tezkor.uz/team", for: .website))
        #expect(!ContactValidation.isValid("tezkor", for: .website))
        #expect(ContactValidation.isValid("in/azizakarimova", for: .linkedin))
        #expect(ContactValidation.isValid("Amir Temur 108, Toshkent", for: .address))
        #expect(!ContactValidation.isValid("ab", for: .address))
    }
}
