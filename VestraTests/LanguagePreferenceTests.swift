import XCTest
@testable import Vestra

final class LanguagePreferenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "vestra-language-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testFreshInstallationDefaultsToEnglishWithTurkishDisabled() {
        LanguagePreferences.prepare(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppPreferences.languageKey), AppLanguage.english.rawValue)
        XCTAssertFalse(defaults.bool(forKey: AppPreferences.turkishEnabledKey))
    }

    func testExplicitTurkishSelectionStaysSelectedAndEnablesTurkish() {
        defaults.set(AppLanguage.turkish.rawValue, forKey: AppPreferences.languageKey)
        LanguagePreferences.prepare(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppPreferences.languageKey), AppLanguage.turkish.rawValue)
        XCTAssertTrue(defaults.bool(forKey: AppPreferences.turkishEnabledKey))
    }

    func testExplicitEnglishSelectionIsNotOverwritten() {
        defaults.set(AppLanguage.english.rawValue, forKey: AppPreferences.languageKey)
        LanguagePreferences.prepare(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppPreferences.languageKey), AppLanguage.english.rawValue)
        XCTAssertFalse(defaults.bool(forKey: AppPreferences.turkishEnabledKey))

        LanguagePreferences.setTurkishEnabled(true, defaults: defaults)
        defaults.set(AppLanguage.turkish.rawValue, forKey: AppPreferences.languageKey)
        LanguagePreferences.prepare(defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppPreferences.languageKey), AppLanguage.turkish.rawValue)
        XCTAssertTrue(defaults.bool(forKey: AppPreferences.turkishEnabledKey))
    }

    func testDisablingTurkishReturnsToEnglish() {
        defaults.set(AppLanguage.turkish.rawValue, forKey: AppPreferences.languageKey)
        LanguagePreferences.setTurkishEnabled(true, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppPreferences.languageKey), AppLanguage.turkish.rawValue)

        LanguagePreferences.setTurkishEnabled(false, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: AppPreferences.languageKey), AppLanguage.english.rawValue)
        XCTAssertFalse(defaults.bool(forKey: AppPreferences.turkishEnabledKey))
    }

    func testCategoryNamesFollowTheSelectedLanguage() {
        let grocery = CategoryInfo(
            id: "grocery", type: .expense, nameTurkish: "", nameEnglish: "Grocery",
            localizationKey: "", symbol: "cart.fill", palette: .olive, isBuiltIn: false,
            isArchived: false, sortOrder: 0, createdAt: .now
        )
        XCTAssertEqual(grocery.displayName(in: AppLanguage.english.locale), "Grocery")
        XCTAssertEqual(grocery.displayName(in: AppLanguage.turkish.locale), "Grocery")

        let translated = CategoryInfo(
            id: "grocery", type: .expense, nameTurkish: "Market", nameEnglish: "Grocery",
            localizationKey: "", symbol: "cart.fill", palette: .olive, isBuiltIn: false,
            isArchived: true, sortOrder: 0, createdAt: .now
        )
        XCTAssertEqual(translated.displayName(in: AppLanguage.english.locale), "Grocery")
        XCTAssertEqual(translated.displayName(in: AppLanguage.turkish.locale), "Market")

        let salary = CategoryInfo(
            id: "salary", type: .income, nameTurkish: "", nameEnglish: "",
            localizationKey: BuiltInCategory.salary.localizationKey, symbol: BuiltInCategory.salary.symbol,
            palette: .green, isBuiltIn: true, isArchived: false, sortOrder: 0, createdAt: .now
        )
        XCTAssertEqual(salary.displayName(in: AppLanguage.english.locale), "Salary Income")
        XCTAssertEqual(salary.displayName(in: AppLanguage.turkish.locale), "Maaş Geliri")
    }
}
