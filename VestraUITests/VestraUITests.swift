import XCTest

final class VestraUITests: XCTestCase {
    private let screenshotDirectory = URL(fileURLWithPath: "/tmp/vestra_shots")

    override func setUp() {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(at: screenshotDirectory, withIntermediateDirectories: true)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        try? screenshot.pngRepresentation.write(to: screenshotDirectory.appendingPathComponent("ui-\(name).png"))
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func enter(_ text: String, into field: XCUIElement, clearing: Bool = false) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        if clearing, let current = field.value as? String {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        }
        field.typeText(text)
    }

    private func save(_ app: XCUIApplication) {
        app.navigationBars.buttons["Save"].tap()
    }

    private func assertLabel(_ element: XCUIElement, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        if XCTWaiter().wait(for: [expectation], timeout: 5) != .completed {
            XCTFail("Expected \"\(expected)\", found \"\(element.label)\"", file: file, line: line)
        }
    }

    private func openSettings(_ app: XCUIApplication) {
        if app.tabBars.buttons["Settings"].exists {
            app.tabBars.buttons["Settings"].tap()
        } else {
            XCTAssertTrue(app.tabBars.buttons["Ayarlar"].waitForExistence(timeout: 5))
            app.tabBars.buttons["Ayarlar"].tap()
        }
    }

    private func enableTurkish(_ app: XCUIApplication) {
        let toggle = app.switches["turkishEnabledToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" {
            toggle.tap()
        }
    }

    private func selectLanguage(_ app: XCUIApplication, _ name: String) {
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "Language", "Dil")).firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons[name].tap()
    }

    func testAddEditDeleteTransactionUpdatesBalances() {
        let app = launch(["-VestraInMemoryStore", "-appLanguage", "en"])
        let tlBalance = app.staticTexts["tlBalanceValue"]
        assertLabel(tlBalance, "₺0.00")

        app.buttons["Add Income"].tap()
        enter("1500,50", into: app.textFields["amountField"])
        save(app)
        assertLabel(tlBalance, "₺1,500.50")
        assertLabel(app.staticTexts["totalBalanceValue"], "₺1,500.50")

        button(app, containing: "Salary Income").tap()
        enter("2000", into: app.textFields["amountField"], clearing: true)
        button(app, containing: "Rental Income").tap()
        save(app)
        assertLabel(tlBalance, "₺2,000.00")
        XCTAssertTrue(button(app, containing: "Rental Income").exists)

        app.buttons["Add Expense"].tap()
        enter("250", into: app.textFields["amountField"])
        save(app)
        assertLabel(tlBalance, "₺1,750.00")

        button(app, containing: "Rental Income").tap()
        app.buttons["Delete Transaction"].tap()
        app.buttons["Delete"].firstMatch.tap()
        assertLabel(tlBalance, "-₺250.00")

        app.tabBars.buttons["Transactions"].tap()
        let expenseRow = button(app, containing: "Credit Card Expenses")
        XCTAssertTrue(expenseRow.waitForExistence(timeout: 5))
        expenseRow.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No Transactions"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Dashboard"].tap()
        assertLabel(tlBalance, "₺0.00")
    }

    func testHistoricalTransactionBelongsToItsMonth() {
        let app = launch(["-VestraInMemoryStore", "-appLanguage", "en"])
        app.tabBars.buttons["Transactions"].tap()
        app.buttons["Previous Period"].tap()
        app.navigationBars.buttons["Add Transaction"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Add Expense"].tap()
        enter("300", into: app.textFields["amountField"])
        save(app)

        XCTAssertTrue(button(app, containing: "Credit Card Expenses").waitForExistence(timeout: 5))
        capture("transactions-previous-month")

        app.buttons["Next Period"].tap()
        XCTAssertTrue(app.staticTexts["No Transactions"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Statistics"].tap()
        XCTAssertTrue(app.staticTexts["₺0.00"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Previous Period"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["-₺300.00"].firstMatch.waitForExistence(timeout: 5))

        app.tabBars.buttons["Dashboard"].tap()
        assertLabel(app.staticTexts["tlBalanceValue"], "-₺300.00")
    }

    func testGoldQuantityPriceAndTotal() {
        let app = launch(["-VestraInMemoryStore", "-appLanguage", "en"])
        app.buttons["Add Income"].tap()
        enter("20000", into: app.textFields["amountField"])
        save(app)

        app.buttons["Update Quantity"].tap()
        enter("25", into: app.textFields["gramsField"])
        save(app)
        assertLabel(app.staticTexts["goldGramsValue"], "25 g")

        app.buttons["Update Price"].tap()
        enter("6000", into: app.textFields["goldPriceField"])
        save(app)
        assertLabel(app.staticTexts["goldValue"], "₺150,000.00")
        assertLabel(app.staticTexts["totalBalanceValue"], "₺170,000.00")
        assertLabel(app.staticTexts["tlBalanceValue"], "₺20,000.00")

        app.buttons["Update Price"].tap()
        enter("6500", into: app.textFields["goldPriceField"], clearing: true)
        save(app)
        assertLabel(app.staticTexts["goldValue"], "₺162,500.00")
        assertLabel(app.staticTexts["totalBalanceValue"], "₺182,500.00")
        assertLabel(app.staticTexts["tlBalanceValue"], "₺20,000.00")

        app.buttons["Update Quantity"].tap()
        app.buttons["Remove"].tap()
        enter("30", into: app.textFields["gramsField"])
        XCTAssertTrue(app.staticTexts["Gold quantity cannot be negative."].waitForExistence(timeout: 3))
        XCTAssertFalse(app.navigationBars.buttons["Save"].isEnabled)
        app.navigationBars.buttons["Cancel"].tap()

        app.tabBars.buttons["Settings"].tap()
        app.buttons["Gold History"].tap()
        XCTAssertTrue(app.staticTexts["₺6,500.00 / g"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' / g'")).count, 1, "Same-day price updates replace each other")
    }

    func testDataPersistsAfterRelaunch() {
        var app = launch(["-VestraStoreFile", "uitest.store", "-VestraResetStore", "-appLanguage", "en"])
        app.buttons["Add Income"].tap()
        enter("4321", into: app.textFields["amountField"])
        save(app)
        assertLabel(app.staticTexts["tlBalanceValue"], "₺4,321.00")
        app.terminate()

        app = launch(["-VestraStoreFile", "uitest.store", "-appLanguage", "en"])
        assertLabel(app.staticTexts["tlBalanceValue"], "₺4,321.00")
        XCTAssertTrue(button(app, containing: "Salary Income").exists)
    }

    /// Switches language and appearance from Settings without relaunching.
    func testLanguageAndAppearanceSwitchLive() {
        let app = launch(["-VestraInMemoryStore", "-VestraDemoData"])
        openSettings(app)
        enableTurkish(app)
        selectLanguage(app, "Türkçe")
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5))
        capture("settings-tr")

        selectLanguage(app, "English")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Statistics"].exists)
        XCTAssertTrue(app.tabBars.buttons["Transactions"].exists)

        button(app, containing: "Appearance").tap()
        app.buttons["Dark"].tap()
        capture("settings-en-dark")
        app.tabBars.buttons["Statistics"].tap()
        capture("statistics-en-dark")

        app.tabBars.buttons["Settings"].tap()
        button(app, containing: "Appearance").tap()
        app.buttons["Light"].tap()
        capture("settings-en-light")

        selectLanguage(app, "Türkçe")
        XCTAssertTrue(app.navigationBars["Ayarlar"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["İstatistikler"].exists)
        button(app, containing: "Görünüm").tap()
        app.buttons["Sistem Varsayılanı"].tap()
    }

    func testTurkishStartsDisabledAndCategoryEnglishNameIsRequired() {
        let app = launch(["-VestraInMemoryStore", "-VestraResetLanguage"])
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.buttons["Özet"].exists)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["English"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Türkçe"].exists)

        app.buttons["Categories"].tap()
        app.buttons["New Category"].tap()
        XCTAssertTrue(app.textFields["categoryEnglishField"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["categoryTurkishField"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Save"].isEnabled)
        enter("Transit", into: app.textFields["categoryEnglishField"])
        save(app)
        XCTAssertTrue(app.staticTexts["Transit"].waitForExistence(timeout: 5))

        app.navigationBars.buttons["Settings"].tap()
        enableTurkish(app)
        XCTAssertFalse(app.buttons["Türkçe"].exists, "Enabling Turkish does not select it")
        app.buttons["Categories"].tap()
        app.buttons["Transit"].tap()
        XCTAssertTrue(app.textFields["categoryTurkishField"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.buttons["Save"].isEnabled, "The Turkish name is optional")
        save(app)

        app.navigationBars.buttons["Settings"].tap()
        selectLanguage(app, "Türkçe")
        XCTAssertTrue(app.tabBars.buttons["Özet"].waitForExistence(timeout: 5))
        app.buttons["Kategoriler"].tap()
        XCTAssertTrue(app.staticTexts["Transit"].waitForExistence(timeout: 5))

        app.switches["turkishEnabledToggle"].tap()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Türkçe"].exists)
        XCTAssertTrue(app.staticTexts["English"].waitForExistence(timeout: 5))
    }

    func testCustomCategoryArchiveAndLanguage() {
        let app = launch(["-VestraInMemoryStore"])
        openSettings(app)
        if app.navigationBars["Ayarlar"].exists {
            selectLanguage(app, "English")
        }
        enableTurkish(app)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Categories"].tap()
        XCTAssertTrue(app.staticTexts["Salary Income"].waitForExistence(timeout: 5))
        app.buttons["Expense"].tap()
        XCTAssertTrue(app.staticTexts["Credit Card Expenses"].waitForExistence(timeout: 5))
        app.buttons["Income"].tap()
        app.buttons["New Category"].tap()
        enter("Fon Geliri", into: app.textFields["categoryTurkishField"])
        enter("Fund Income", into: app.textFields["categoryEnglishField"])
        save(app)
        XCTAssertTrue(app.staticTexts["Fund Income"].waitForExistence(timeout: 5))

        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["Add Income"].tap()
        XCTAssertTrue(app.buttons["Fund Income"].waitForExistence(timeout: 5))
        app.buttons["Fund Income"].tap()
        enter("250", into: app.textFields["amountField"])
        save(app)
        XCTAssertTrue(button(app, containing: "Fund Income").waitForExistence(timeout: 5))
        assertLabel(app.staticTexts["tlBalanceValue"], "₺250.00")

        app.tabBars.buttons["Settings"].tap()
        if app.buttons["Categories"].waitForExistence(timeout: 2) {
            app.buttons["Categories"].tap()
        }
        button(app, containing: "Fund Income").tap()
        app.buttons["Archive Category"].tap()
        app.buttons["Archive"].tap()

        app.tabBars.buttons["Dashboard"].tap()
        app.buttons["Add Income"].tap()
        XCTAssertTrue(app.buttons["Salary Income"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Fund Income"].exists)
        app.buttons["Cancel"].tap()

        button(app, containing: "Fund Income").tap()
        XCTAssertTrue(app.buttons["Fund Income"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["This category is archived and stays available for this transaction."].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        assertLabel(app.staticTexts["tlBalanceValue"], "₺250.00")

        app.tabBars.buttons["Settings"].tap()
        if app.navigationBars.buttons["Settings"].waitForExistence(timeout: 2) {
            app.navigationBars.buttons["Settings"].tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        button(app, containing: "Language").tap()
        XCTAssertTrue(app.buttons["Türkçe"].waitForExistence(timeout: 5))
        app.buttons["Türkçe"].tap()
        XCTAssertTrue(app.tabBars.buttons["Özet"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Özet"].tap()
        XCTAssertTrue(button(app, containing: "Fon Geliri").waitForExistence(timeout: 5))
        assertLabel(app.staticTexts["tlBalanceValue"], "₺250,00")
    }

    func testCaptureScreens() {
        for appearance in ["light", "dark"] {
            let app = launch(["-VestraInMemoryStore", "-VestraDemoData", "-appLanguage", "tr", "-appearance", appearance])
            XCTAssertTrue(app.staticTexts["totalBalanceValue"].waitForExistence(timeout: 5))
            app.swipeUp()
            capture("dashboard-bottom-\(appearance)")

            app.tabBars.buttons["İşlemler"].tap()
            capture("transactions-\(appearance)")

            app.tabBars.buttons["İstatistikler"].tap()
            capture("statistics-month-\(appearance)-1")
            app.swipeUp()
            capture("statistics-month-\(appearance)-2")
            app.swipeUp()
            capture("statistics-month-\(appearance)-3")
            app.swipeUp()
            app.swipeUp()
            capture("statistics-month-\(appearance)-4")

            app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown()
            app.buttons["Yıllık"].tap()
            capture("statistics-year-\(appearance)-1")
            app.swipeUp()
            capture("statistics-year-\(appearance)-2")

            app.tabBars.buttons["Özet"].tap()
            app.buttons["Gelir Ekle"].tap()
            capture("editor-\(appearance)")
            app.navigationBars.buttons["Vazgeç"].tap()

            app.tabBars.buttons["Ayarlar"].tap()
            app.buttons["Kategoriler"].tap()
            XCTAssertTrue(app.navigationBars["Kategoriler"].waitForExistence(timeout: 5))
            capture("categories-\(appearance)")
            app.buttons["Yeni Kategori"].tap()
            XCTAssertTrue(app.navigationBars["Yeni Kategori"].waitForExistence(timeout: 5))
            capture("category-editor-\(appearance)")
            app.buttons["Vazgeç"].tap()
            app.navigationBars.buttons["Ayarlar"].tap()
            app.buttons["Altın Geçmişi"].tap()
            XCTAssertTrue(app.navigationBars["Altın Geçmişi"].waitForExistence(timeout: 5))
            sleep(1)
            capture("gold-history-\(appearance)")
            app.terminate()
        }
    }
}
