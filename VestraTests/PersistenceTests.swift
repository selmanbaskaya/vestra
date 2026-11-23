import SwiftData
import XCTest
@testable import Vestra

final class PersistenceTests: XCTestCase {
    private func makeInMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(VestraSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func ledger(in context: ModelContext) throws -> FinanceLedger {
        FinanceLedger(
            openingBalance: try context.fetch(FetchDescriptor<WalletProfile>()).first?.openingBalance ?? 0,
            entries: try context.fetch(FetchDescriptor<FinanceTransaction>()).map(\.ledgerEntry),
            goldPrices: try context.fetch(FetchDescriptor<GoldPriceRecord>()).map(\.point),
            goldMovements: try context.fetch(FetchDescriptor<GoldMovement>()).map(\.point)
        )
    }

    func testAddEditDeleteRecalculatesBalances() throws {
        let context = try makeInMemoryContext()
        try FinanceStore.setOpeningBalance(1_000, in: context)

        let salary = FinanceTransaction(amount: 5_000, category: .salary, date: .now)
        let rent = FinanceTransaction(amount: 2_000, category: .home, date: .now)
        context.insert(salary)
        context.insert(rent)
        try context.save()
        XCTAssertEqual(try ledger(in: context).current.tlBalance, 4_000)

        rent.amount = 2_500
        try context.save()
        XCTAssertEqual(try ledger(in: context).current.tlBalance, 3_500)

        rent.setCategory(.salary)
        try context.save()
        XCTAssertEqual(rent.type, .income, "Changing category updates the transaction type")
        XCTAssertEqual(try ledger(in: context).current.tlBalance, 8_500)

        context.delete(salary)
        try context.save()
        XCTAssertEqual(try ledger(in: context).current.tlBalance, 3_500)
    }

    func testHistoricalTransactionLandsInItsMonth() throws {
        let context = try makeInMemoryContext()
        let january = ReportPeriod(kind: .month, year: 2026, month: 1)
        let date = Calendar.app.date(byAdding: .day, value: 9, to: january.interval().start)!
        context.insert(FinanceTransaction(amount: 750, category: .cash, date: date, createdAt: .now))
        try context.save()

        let ledger = try ledger(in: context)
        XCTAssertEqual(ledger.summary(for: january).expense, 750)
        XCTAssertEqual(ledger.summary(for: .containing(.now, kind: .month)).expense, ReportPeriod.containing(.now, kind: .month) == january ? 750 : 0)
    }

    func testGoldPriceIsUpsertedPerDayAndCreatesNoTransactions() throws {
        let context = try makeInMemoryContext()
        try FinanceStore.recordGoldPrice(5_900, on: .now, in: context)
        try FinanceStore.recordGoldPrice(6_000, on: .now, in: context)
        let yesterday = Calendar.app.date(byAdding: .day, value: -1, to: .now)!
        try FinanceStore.recordGoldPrice(5_800, on: yesterday, in: context)

        let prices = try context.fetch(FetchDescriptor<GoldPriceRecord>())
        XCTAssertEqual(prices.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FinanceTransaction>()), 0)
        XCTAssertEqual(try ledger(in: context).current.goldPrice, 6_000)
    }

    func testDataPersistsAcrossContainerReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vestra-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        try assertReopenedStore(at: url)
    }

    private func assertReopenedStore(at url: URL) throws {
        do {
            let container = try ModelContainer(for: Schema(VestraSchema.models), configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            context.insert(FinanceTransaction(amount: Decimal(string: "1234.56")!, category: .dividend, date: .now, note: "Test"))
            context.insert(GoldMovement(grams: Decimal(string: "12.5")!, date: .now))
            context.insert(GoldPriceRecord(pricePerGram: 6_000, date: .now))
            context.insert(WalletProfile(openingBalance: 100))
            try context.save()
        }

        let reopened = try ModelContainer(for: Schema(VestraSchema.models), configurations: ModelConfiguration(url: url))
        let context = ModelContext(reopened)
        let transactions = try context.fetch(FetchDescriptor<FinanceTransaction>())
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.amount, Decimal(string: "1234.56")!)
        XCTAssertEqual(transactions.first?.categoryID, BuiltInCategory.dividend.rawValue)
        XCTAssertEqual(transactions.first?.note, "Test")
        let current = try ledger(in: context).current
        XCTAssertEqual(current.tlBalance, Decimal(string: "1334.56")!)
        XCTAssertEqual(current.goldValue, 75_000)
        XCTAssertEqual(current.total, Decimal(string: "76334.56")!)
    }

    func testBackupRoundTripAndValidation() throws {
        let source = try makeInMemoryContext()
        try FinanceStore.setOpeningBalance(Decimal(string: "500.25")!, in: source)
        source.insert(FinanceTransaction(amount: 3_000, category: .rental, date: .now, note: "Ocak, \"kira\""))
        source.insert(GoldMovement(grams: 10, date: .now))
        source.insert(GoldPriceRecord(pricePerGram: Decimal(string: "6100.5")!, date: .now))
        try source.save()

        let data = try BackupService.encode(BackupService.makeBackup(from: source))
        let target = try makeInMemoryContext()
        target.insert(FinanceTransaction(amount: 1, category: .cash, date: .now))
        try target.save()
        try BackupService.restore(BackupService.decode(data), into: target)

        let restored = try ledger(in: target).current
        let original = try ledger(in: source).current
        XCTAssertEqual(restored.tlBalance, original.tlBalance)
        XCTAssertEqual(restored.goldGrams, original.goldGrams)
        XCTAssertEqual(restored.goldPrice, original.goldPrice)
        XCTAssertEqual(restored.total, original.total)
        XCTAssertEqual(
            restored.goldPriceDate?.timeIntervalSinceReferenceDate ?? 0,
            original.goldPriceDate?.timeIntervalSinceReferenceDate ?? 0,
            accuracy: 0.001
        )
        XCTAssertEqual(try target.fetchCount(FetchDescriptor<FinanceTransaction>()), 1)

        XCTAssertThrowsError(try BackupService.decode(Data("{}".utf8)))

        let csv = String(decoding: try BackupService.transactionsCSV(from: source), as: UTF8.self)
        XCTAssertTrue(csv.hasPrefix("date,type,category,amount,description,created_at\n"))
        XCTAssertTrue(csv.contains(",income,rental,3000,\"Ocak, \"\"kira\"\"\","))
    }

    func testDeleteAllData() throws {
        let context = try makeInMemoryContext()
        context.insert(FinanceTransaction(amount: 1, category: .cash, date: .now))
        context.insert(GoldMovement(grams: 1, date: .now))
        try FinanceStore.setOpeningBalance(10, in: context)
        try FinanceStore.deleteAllData(in: context)
        XCTAssertEqual(try ledger(in: context).current, WealthSnapshot(tlBalance: 0, goldGrams: 0))
    }
}

final class LocalizationTests: XCTestCase {
    func testTurkishAndEnglishLookups() {
        let turkish = AppLanguage.turkish.locale
        let english = AppLanguage.english.locale
        XCTAssertEqual(turkish.localized("Total Balance"), "Toplam Bakiye")
        XCTAssertEqual(turkish.localized("TL Balance"), "TL Bakiyesi")
        XCTAssertEqual(turkish.localized("Gold Balance"), "Altın Bakiyesi")
        XCTAssertEqual(turkish.localized("Dividend Income"), "Kâr Payı Geliri")
        XCTAssertEqual(turkish.localized("Credit Card Expenses"), "Kredi Kartı Harcamaları")
        XCTAssertEqual(turkish.localized("Statistics"), "İstatistikler")
        XCTAssertEqual(english.localized("Total Balance"), "Total Balance")
        XCTAssertEqual(english.localized("Statistics"), "Statistics")
    }

    func testEveryCategoryIsTranslated() {
        let turkish = AppLanguage.turkish.locale
        for category in BuiltInCategory.allCases {
            XCTAssertNotEqual(turkish.localized(category.localizationKey), category.localizationKey, category.rawValue)
        }
    }

    func testEnglishBundleExists() {
        XCTAssertNotNil(AppLanguage.english.bundle)
        XCTAssertNotNil(AppLanguage.turkish.bundle)
    }
}
