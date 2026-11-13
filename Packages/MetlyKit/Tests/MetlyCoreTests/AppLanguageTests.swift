import Foundation
import Testing
@testable import MetlyCore

@Suite struct AppLanguageTests {
    @Test(arguments: [
        (["uz-Latn-UZ", "en-US"], AppLanguage.uz),
        (["ru-RU"], .ru),
        (["en-GB", "ru-RU"], .en),
        (["de-DE", "ru-RU"], .ru),     // first language the app ships wins
        (["de-DE", "fr-FR"], .uz),     // none shipped: the home market
        ([], .uz),
    ])
    func matchesTheDeviceLanguages(preferred: [String], expected: AppLanguage) {
        #expect(AppLanguage.matching(preferred) == expected)
    }

    @Test func namesAreWrittenInTheirOwnLanguage() {
        #expect(AppLanguage.allCases.map(\.nativeName) == ["O‘zbekcha", "Русский", "English"])
    }

    @Test func withoutAChoiceStringsComeFromTheMainBundle() {
        AppLanguage.resetChoice()
        #expect(AppLanguage.chosen == nil)
        #expect(Bundle.appStrings === Bundle.main)
    }

    @Test func aMissingLocalizationFallsBackToTheKey() {
        // The test bundle ships no `.lproj`: the language screen still shows readable English.
        #expect(AppLanguage.ru.localized("Choose Your Language") == "Choose Your Language")
    }
}
