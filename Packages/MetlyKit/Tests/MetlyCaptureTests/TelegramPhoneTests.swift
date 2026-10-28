import Foundation
import MetlyCore
import MetlyData
import Testing
@testable import MetlyCapture

@MainActor
struct TelegramPhoneTests {
    // MARK: Number formats

    @Test func uzbekNumbersWithACountryCode() {
        #expect(TelegramPhone.digits(from: "+998 90 123 45 67") == "998901234567")
        #expect(TelegramPhone.digits(from: "+998 (90) 123-45-67") == "998901234567")
        #expect(TelegramPhone.digits(from: "(+998) 90 123 45 67") == "998901234567")
        #expect(TelegramPhone.digits(from: "00998 90 123 45 67") == "998901234567")
        #expect(TelegramPhone.digits(from: "998901234567") == "998901234567")
        #expect(TelegramPhone.digits(from: "+998 33 700 00 00") == "998337000000")
    }

    @Test func uzbekNumbersWithoutACountryCodeGetPlus998() {
        #expect(TelegramPhone.digits(from: "90 123-45-67") == "998901234567")
        #expect(TelegramPhone.digits(from: "901234567") == "998901234567")
        #expect(TelegramPhone.digits(from: "(93) 555 12 34") == "998935551234")
        // The old domestic trunk prefix.
        #expect(TelegramPhone.digits(from: "8 (90) 123-45-67") == "998901234567")
        #expect(TelegramPhone.digits(from: "8 90 123 45 67") == "998901234567")
    }

    @Test func russianAndKazakhMobiles() {
        #expect(TelegramPhone.digits(from: "+7 912 345-67-89") == "79123456789")
        #expect(TelegramPhone.digits(from: "+7 (999) 000 11 22") == "79990001122")
        #expect(TelegramPhone.digits(from: "+7 701 123 45 67") == "77011234567")
        #expect(TelegramPhone.digits(from: "+7 777 123 45 67") == "77771234567")
    }

    @Test func otherCountriesAreUsedAsWritten() {
        #expect(TelegramPhone.digits(from: "+44 7700 900123") == "447700900123")
        #expect(TelegramPhone.digits(from: "+1 (415) 555-0100") == "14155550100")
        #expect(TelegramPhone.digits(from: "+90 532 123 45 67") == "905321234567")
    }

    @Test func landlinesAreNotOffered() {
        #expect(TelegramPhone.digits(from: "+998 71 200-00-00") == nil)   // Tashkent
        #expect(TelegramPhone.digits(from: "+998 78 150 00 00") == nil)   // Tashkent
        #expect(TelegramPhone.digits(from: "66 233 00 00") == nil)        // Samarkand, no country code
        #expect(TelegramPhone.digits(from: "8 (71) 200-00-00") == nil)
        #expect(TelegramPhone.digits(from: "+7 495 123-45-67") == nil)    // Moscow
        #expect(TelegramPhone.digits(from: "+7 (812) 123-45-67") == nil)  // St Petersburg
        #expect(TelegramPhone.digits(from: "+7 727 250 00 00") == nil)    // Almaty
    }

    @Test func numbersWithoutACountryCodeAreNotGuessedOtherwise() {
        #expect(TelegramPhone.digits(from: "8 (912) 345-67-89") == nil)   // Russian domestic format
        #expect(TelegramPhone.digits(from: "912 345 67 89") == nil)
        #expect(TelegramPhone.digits(from: "12 345 67 89") == nil)        // not an Uzbek operator code
        #expect(TelegramPhone.digits(from: "1234567") == nil)
    }

    @Test func malformedValues() {
        #expect(TelegramPhone.digits(from: "") == nil)
        #expect(TelegramPhone.digits(from: "   ") == nil)
        #expect(TelegramPhone.digits(from: "+998 90 123") == nil)
        #expect(TelegramPhone.digits(from: "+998 90 123 45 67 89") == nil)
        #expect(TelegramPhone.digits(from: "+12345") == nil)
        #expect(TelegramPhone.digits(from: "call me") == nil)
        // An extension after the number is ignored.
        #expect(TelegramPhone.digits(from: "+998 90 123 45 67 доб. 12") == "998901234567")
        #expect(TelegramPhone.digits(from: "+998 90 123 45 67 ext 3") == "998901234567")
    }

    // MARK: Links

    @Test func byPhoneLinks() {
        #expect(ContactLinks.telegramApp(phone: "+998 90 123 45 67")?.absoluteString == "tg://resolve?phone=998901234567")
        #expect(ContactLinks.telegramWeb(phone: "+998 90 123 45 67")?.absoluteString == "https://t.me/+998901234567")
        #expect(ContactLinks.telegramApp(phone: "90 123-45-67")?.absoluteString == "tg://resolve?phone=998901234567")
        #expect(ContactLinks.telegramApp(phone: "+7 912 345-67-89")?.absoluteString == "tg://resolve?phone=79123456789")
        #expect(ContactLinks.telegramWeb(phone: "+7 912 345-67-89")?.absoluteString == "https://t.me/+79123456789")
        #expect(ContactLinks.telegramApp(phone: "+998 71 200 00 00") == nil)
        #expect(ContactLinks.telegramWeb(phone: "") == nil)
    }

    @Test func theUsernameWinsOverThePhone() throws {
        let byName = try #require(TelegramTarget(username: "@aziza.k", phones: ["+998 90 123 45 67"]))
        #expect(byName == .username("aziza.k"))
        #expect(!byName.isByPhone)
        #expect(byName.appURL?.absoluteString == "tg://resolve?domain=aziza.k")
        #expect(byName.webURL?.absoluteString == "https://t.me/aziza.k")

        let byPhone = try #require(TelegramTarget(username: "  ", phones: ["", "+998 71 200 00 00", "90 123 45 67"]))
        #expect(byPhone == .phone("998901234567"))
        #expect(byPhone.isByPhone)

        #expect(TelegramTarget(username: "", phones: ["+998 71 200 00 00"]) == nil)
        #expect(TelegramTarget(username: "", phones: []) == nil)
    }

    @Test func aConnectionPrefersItsMobileNumber() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, phone: "+998 93 111 11 11")
        person.phoneLabel = .work
        person.additionalPhones = [LabeledPhone(label: .mobile, value: "+998 90 123 45 67")]
        #expect(person.phonesForMessaging.map(\.value) == ["+998 90 123 45 67", "+998 93 111 11 11"])
        #expect(person.telegramTarget == .phone("998901234567"))

        person.telegram = "@kamila.y"
        #expect(person.telegramTarget == .username("kamila.y"))

        let landline = insertPerson("Office", in: context, phone: "+998 71 200 00 00")
        #expect(landline.telegramTarget == nil)
    }

    // MARK: Follow-up channel

    @Test func aUsablePhoneMakesTelegramAvailable() throws {
        #expect(FollowUpPolicy.preferredChannel(phone: "+998 90 123 45 67", email: "", telegram: "") == .telegram)
        #expect(FollowUpPolicy.preferredChannel(phone: "+998 90 123 45 67", email: "a@b.c", telegram: "") == .telegram)
        #expect(FollowUpPolicy.preferredChannel(phone: "+998 71 200 00 00", email: "a@b.c", telegram: "") == .email)
        #expect(FollowUpPolicy.preferredChannel(phone: "+998 71 200 00 00", email: "", telegram: "") == .call)
        #expect(FollowUpPolicy.preferredChannel(phones: ["+998 71 200 00 00", "90 123 45 67"], email: "", telegram: "")
                == .telegram)

        let context = try makeContext()
        let person = insertPerson("Office", in: context, phone: "+998 71 200 00 00")
        #expect(FollowUpPolicy.preferredChannel(for: person) == .call)
        person.additionalPhones = [LabeledPhone(label: .mobile, value: "+998 99 000 00 00")]
        #expect(FollowUpPolicy.preferredChannel(for: person) == .telegram)
    }
}
