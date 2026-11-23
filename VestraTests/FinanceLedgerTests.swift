import XCTest
@testable import Vestra

final class FinanceLedgerTests: XCTestCase {
    private let calendar = Calendar.app

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testTLBalanceIsOpeningPlusIncomeMinusExpenses() {
        let ledger = FinanceLedger(
            openingBalance: 10_000,
            entries: [
                LedgerEntry(amount: 50_000, category: .salary, date: date(2026, 1, 1)),
                LedgerEntry(amount: Decimal(string: "1250.75")!, category: .creditCard, date: date(2026, 1, 5)),
                LedgerEntry(amount: Decimal(string: "0.10")!, category: .cash, date: date(2026, 1, 6)),
                LedgerEntry(amount: Decimal(string: "0.20")!, category: .cash, date: date(2026, 1, 7)),
            ]
        )
        XCTAssertEqual(ledger.current.tlBalance, Decimal(string: "58748.95")!)
    }

    func testGoldValueAndTotalBalance() {
        let ledger = FinanceLedger(
            openingBalance: 20_000,
            goldPrices: [GoldPoint(date: date(2026, 1, 1), value: 6_000)],
            goldMovements: [GoldPoint(date: date(2026, 1, 1), value: 25)]
        )
        let current = ledger.current
        XCTAssertEqual(current.goldGrams, 25)
        XCTAssertEqual(current.goldValue, 150_000)
        XCTAssertEqual(current.total, 170_000)
        XCTAssertEqual(current.tlBalance, 20_000, "Gold must not change the TL balance")
    }

    func testGoldValueRoundsToKurus() {
        let snapshot = WealthSnapshot(tlBalance: 0, goldGrams: Decimal(string: "1.333")!, goldPrice: Decimal(string: "3000.01")!)
        XCTAssertEqual(snapshot.goldValue, Decimal(string: "3999.01")!)
    }

    func testGoldWithoutPriceHasNoValue() {
        let ledger = FinanceLedger(goldMovements: [GoldPoint(date: date(2026, 1, 1), value: 10)])
        XCTAssertEqual(ledger.current.goldValue, 0)
        XCTAssertNil(ledger.current.goldPrice)
    }

    func testHistoricalReportsUseHistoricalGoldPriceAndQuantity() {
        let ledger = FinanceLedger(
            openingBalance: 0,
            goldPrices: [
                GoldPoint(date: date(2026, 1, 10), value: 5_000),
                GoldPoint(date: date(2026, 3, 5), value: 6_000),
            ],
            goldMovements: [
                GoldPoint(date: date(2026, 1, 2), value: 10),
                GoldPoint(date: date(2026, 3, 20), value: 5),
            ]
        )

        let january = ledger.summary(for: ReportPeriod(kind: .month, year: 2026, month: 1)).closing
        XCTAssertEqual(january.goldPrice, 5_000)
        XCTAssertEqual(january.goldGrams, 10)
        XCTAssertEqual(january.goldValue, 50_000)

        let february = ledger.summary(for: ReportPeriod(kind: .month, year: 2026, month: 2)).closing
        XCTAssertEqual(february.goldPrice, 5_000, "Latest price on or before the period end")
        XCTAssertEqual(february.goldValue, 50_000)

        let march = ledger.summary(for: ReportPeriod(kind: .month, year: 2026, month: 3)).closing
        XCTAssertEqual(march.goldPrice, 6_000)
        XCTAssertEqual(march.goldGrams, 15)
        XCTAssertEqual(march.goldValue, 90_000)

        let december2025 = ledger.summary(for: ReportPeriod(kind: .month, year: 2025, month: 12)).closing
        XCTAssertNil(december2025.goldPrice)
        XCTAssertEqual(december2025.goldValue, 0)
    }

    func testPriceOnLastDayOfMonthBelongsToThatMonth() {
        let ledger = FinanceLedger(
            goldPrices: [
                GoldPoint(date: date(2026, 1, 31, hour: 23), value: 5_500),
                GoldPoint(date: date(2026, 2, 1, hour: 0), value: 9_999),
            ],
            goldMovements: [GoldPoint(date: date(2026, 1, 1), value: 1)]
        )
        XCTAssertEqual(ledger.summary(for: ReportPeriod(kind: .month, year: 2026, month: 1)).closing.goldPrice, 5_500)
    }

    func testTransactionDateNotCreationDateDecidesPeriod() {
        let ledger = FinanceLedger(entries: [
            LedgerEntry(amount: 1_000, category: .salary, date: date(2026, 1, 15)),
            LedgerEntry(amount: 300, category: .home, date: date(2026, 1, 20)),
            LedgerEntry(amount: 999, category: .cash, date: date(2026, 2, 1, hour: 0)),
        ])
        let january = ledger.summary(for: ReportPeriod(kind: .month, year: 2026, month: 1))
        XCTAssertEqual(january.income, 1_000)
        XCTAssertEqual(january.expense, 300)
        XCTAssertEqual(january.net, 700)
        XCTAssertEqual(january.transactionCount, 2)
        XCTAssertEqual(january.closing.tlBalance, 700)
    }

    func testCategoryBreakdown() {
        let ledger = FinanceLedger(entries: [
            LedgerEntry(amount: 300, category: .creditCard, date: date(2026, 5, 1)),
            LedgerEntry(amount: 100, category: .cash, date: date(2026, 5, 2)),
            LedgerEntry(amount: 600, category: .creditCard, date: date(2026, 5, 3)),
            LedgerEntry(amount: 2_000, category: .rental, date: date(2026, 5, 3)),
        ])
        let summary = ledger.summary(for: ReportPeriod(kind: .month, year: 2026, month: 5))
        XCTAssertEqual(summary.expenseByCategory.map(\.categoryID), ["creditCard", "cash"])
        XCTAssertEqual(summary.expenseByCategory.first?.amount, 900)
        XCTAssertEqual(summary.expenseByCategory.first?.share ?? 0, 0.9, accuracy: 0.0001)
        XCTAssertEqual(summary.incomeByCategory.map(\.categoryID), ["rental"])
    }

    func testDynamicCategoriesAppearInMonthlyAndYearlyReports() {
        let ledger = FinanceLedger(entries: [
            LedgerEntry(amount: 30, categoryID: "grocery", type: .expense, date: date(2026, 3, 2)),
            LedgerEntry(amount: 80, categoryID: "fund", type: .income, date: date(2026, 3, 4)),
            LedgerEntry(amount: 20, category: .salary, date: date(2026, 8, 1)),
            LedgerEntry(amount: 10, categoryID: "grocery", type: .expense, date: date(2026, 8, 2)),
        ])

        let march = ledger.summary(for: ReportPeriod(kind: .month, year: 2026, month: 3))
        XCTAssertEqual(march.expenseByCategory.map(\.categoryID), ["grocery"])
        XCTAssertEqual(march.incomeByCategory.map(\.categoryID), ["fund"])
        XCTAssertEqual(march.expense, 30)
        XCTAssertEqual(march.income, 80)

        let year = ledger.summary(for: ReportPeriod(kind: .year, year: 2026))
        XCTAssertEqual(year.income, 100)
        XCTAssertEqual(year.expense, 40)
        XCTAssertEqual(Set(year.incomeByCategory.map(\.categoryID)), ["fund", "salary"])
        XCTAssertEqual(year.expenseByCategory.map(\.categoryID), ["grocery"])
        XCTAssertEqual(year.expenseByCategory.first?.amount, 40)
        XCTAssertEqual(ledger.current.tlBalance, 60)
    }

    func testYearlySummaryAndMonthlyPoints() {
        let ledger = FinanceLedger(entries: [
            LedgerEntry(amount: 1_000, category: .salary, date: date(2025, 12, 31)),
            LedgerEntry(amount: 5_000, category: .salary, date: date(2026, 1, 1)),
            LedgerEntry(amount: 2_000, category: .home, date: date(2026, 1, 9)),
            LedgerEntry(amount: 4_000, category: .cash, date: date(2026, 6, 9)),
        ])
        let year = ledger.summary(for: ReportPeriod(kind: .year, year: 2026))
        XCTAssertEqual(year.income, 5_000)
        XCTAssertEqual(year.expense, 6_000)
        XCTAssertEqual(year.net, -1_000)

        let previousYear = ledger.summary(for: ReportPeriod(kind: .year, year: 2026).previous)
        XCTAssertEqual(previousYear.income, 1_000)

        let months = ledger.monthlyPoints(year: 2026)
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months[0].net, 3_000)
        XCTAssertEqual(months[5].net, -4_000)
        XCTAssertEqual(months[11].net, 0)
    }

    func testMonthlyPointsAcrossYearBoundary() {
        let points = FinanceLedger().monthlyPoints(endingAt: ReportPeriod(kind: .month, year: 2026, month: 2), count: 4)
        XCTAssertEqual(points.map(\.period.month), [11, 12, 1, 2])
        XCTAssertEqual(points.map(\.period.year), [2025, 2025, 2026, 2026])
    }

    func testPercentChange() {
        XCTAssertEqual(FinanceLedger.percentChange(from: 200, to: 300) ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(FinanceLedger.percentChange(from: -100, to: 50) ?? 0, 1.5, accuracy: 0.0001)
        XCTAssertNil(FinanceLedger.percentChange(from: 0, to: 300))
    }

    func testLowestRunningGoldBalance() {
        let movements = [
            GoldPoint(date: date(2026, 1, 1), value: 10),
            GoldPoint(date: date(2026, 2, 1), value: -12),
            GoldPoint(date: date(2026, 3, 1), value: 5),
        ]
        XCTAssertEqual(FinanceLedger.lowestRunningBalance(of: movements), -2)
    }

    func testReportPeriodShiftingAndContainment() {
        let january = ReportPeriod(kind: .month, year: 2026, month: 1)
        XCTAssertEqual(january.previous, ReportPeriod(kind: .month, year: 2025, month: 12))
        XCTAssertEqual(january.shifted(by: 13), ReportPeriod(kind: .month, year: 2027, month: 2))
        XCTAssertTrue(january.contains(date(2026, 1, 31, hour: 23)))
        XCTAssertFalse(january.contains(date(2026, 2, 1, hour: 0)))
        XCTAssertEqual(ReportPeriod(kind: .year, year: 2026).previous.year, 2025)
    }

    func testDecimalInputParsing() {
        XCTAssertEqual(DecimalInput.parse("1250,50"), Decimal(string: "1250.5"))
        XCTAssertEqual(DecimalInput.parse("1250.50"), Decimal(string: "1250.5"))
        XCTAssertEqual(DecimalInput.parse("1.250,50"), Decimal(string: "1250.5"))
        XCTAssertEqual(DecimalInput.parse("1,250.50"), Decimal(string: "1250.5"))
        XCTAssertEqual(DecimalInput.parse("1.250.000"), 1_250_000)
        XCTAssertEqual(DecimalInput.parse(" 25 "), 25)
        XCTAssertEqual(DecimalInput.parse(",5"), Decimal(string: "0.5"))
        XCTAssertNil(DecimalInput.parse(""))
        XCTAssertNil(DecimalInput.parse("abc"))
        XCTAssertNil(DecimalInput.parse("12a"))
    }

    func testDecimalCodingRoundTripsExactly() {
        let value = Decimal(string: "12345678901234.56")!
        XCTAssertEqual(DecimalCoding.decimal(DecimalCoding.string(value)), value)
        XCTAssertEqual(DecimalCoding.string(Decimal(string: "0.1")! + Decimal(string: "0.2")!), "0.3")
    }

    func testCurrencyFormattingFollowsLanguage() {
        let value = Decimal(string: "1234.5")!
        XCTAssertEqual(value.currencyText(AppLanguage.turkish.locale), "₺1.234,50")
        XCTAssertEqual(value.currencyText(AppLanguage.english.locale), "₺1,234.50")
        XCTAssertEqual(value.currencyText(AppLanguage.english.locale, signed: true), "+₺1,234.50")
    }
}
