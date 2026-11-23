import SwiftData
import XCTest
@testable import Vestra

final class CategoryTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(VestraSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func seededContext() throws -> ModelContext {
        let context = try makeContext()
        try CategoryStore.ensureDefaults(in: context)
        return context
    }

    private func category(_ id: String, in context: ModelContext) throws -> FinanceCategory {
        let categories = try context.fetch(FetchDescriptor<FinanceCategory>())
        return try XCTUnwrap(categories.first { $0.categoryID == id })
    }

    func testBuiltInIdentifiersAndTranslationsArePreserved() throws {
        XCTAssertEqual(
            BuiltInCategory.allCases.map(\.rawValue),
            ["salary", "rental", "dividend", "otherIncome", "creditCard", "cash", "home", "otherExpense"]
        )
        let context = try seededContext()
        let categories = try context.fetch(FetchDescriptor<FinanceCategory>())
        XCTAssertEqual(categories.count, BuiltInCategory.allCases.count)
        let salary = try category("salary", in: context)
        XCTAssertEqual(salary.localizationKey, "Salary Income")
        XCTAssertEqual(salary.symbol, "briefcase.fill")
        XCTAssertEqual(salary.palette, .green)
        XCTAssertTrue(salary.isBuiltIn)
        XCTAssertFalse(salary.isArchived)
        XCTAssertEqual(salary.displayName(in: AppLanguage.turkish.locale), "Maaş Geliri")
        XCTAssertEqual(salary.displayName(in: AppLanguage.english.locale), "Salary Income")
        XCTAssertEqual(try category("creditCard", in: context).displayName(in: AppLanguage.turkish.locale), "Kredi Kartı Harcamaları")
    }

    func testEnsureDefaultsDoesNotDuplicateOrResetCustomizations() throws {
        let context = try seededContext()
        let salary = try category("salary", in: context)
        salary.nameTurkish = "Maaşım"
        salary.isArchived = true
        try context.save()

        try CategoryStore.ensureDefaults(in: context)
        let categories = try context.fetch(FetchDescriptor<FinanceCategory>())
        XCTAssertEqual(categories.filter { $0.categoryID == "salary" }.count, 1)
        XCTAssertEqual(categories.count, BuiltInCategory.allCases.count)
        let stored = try category("salary", in: context)
        XCTAssertEqual(stored.nameTurkish, "Maaşım")
        XCTAssertTrue(stored.isArchived)
        XCTAssertEqual(stored.nameEnglish, "")
    }

    func testCreateEditArchiveAndRestoreCategories() throws {
        let context = try seededContext()
        let income = try CategoryStore.create(
            type: .income, nameTurkish: "Fon Geliri", nameEnglish: "Fund Income",
            symbol: CategorySymbol.trend.rawValue, palette: .indigo, in: context
        )
        let expense = try CategoryStore.create(
            type: .expense, nameTurkish: "", nameEnglish: "Grocery",
            symbol: CategorySymbol.cart.rawValue, palette: .olive, in: context
        )
        XCTAssertEqual(income.type, .income)
        XCTAssertEqual(expense.type, .expense)
        XCTAssertNotEqual(income.categoryID, expense.categoryID)
        XCTAssertFalse(income.isBuiltIn)
        XCTAssertEqual(income.displayName(in: AppLanguage.english.locale), "Fund Income")
        XCTAssertEqual(income.displayName(in: AppLanguage.turkish.locale), "Fon Geliri")
        XCTAssertEqual(expense.nameTurkish, "")
        XCTAssertEqual(expense.displayName(in: AppLanguage.english.locale), "Grocery")
        XCTAssertEqual(expense.displayName(in: AppLanguage.turkish.locale), "Grocery", "A missing Turkish name uses the English name")

        let originalID = income.categoryID
        try CategoryStore.update(income, nameTurkish: "Fon", nameEnglish: "Funds", symbol: CategorySymbol.bag.rawValue, palette: .rose, in: context)
        XCTAssertEqual(income.categoryID, originalID)
        XCTAssertEqual(income.nameEnglish, "Funds")
        XCTAssertEqual(income.symbol, CategorySymbol.bag.rawValue)
        XCTAssertEqual(income.palette, .rose)

        try CategoryStore.setArchived(income, true, in: context)
        XCTAssertTrue(income.isArchived)
        try CategoryStore.setArchived(income, false, in: context)
        XCTAssertFalse(income.isArchived)

        XCTAssertThrowsError(try CategoryStore.create(
            type: .income, nameTurkish: "Fon", nameEnglish: "   ", symbol: "tag.fill", palette: .slate, in: context
        )) { error in
            XCTAssertEqual(error as? CategoryStoreError, .nameRequired)
        }
    }

    func testMissingEnglishNameIsCopiedFromTurkishWithoutChangingTransactions() throws {
        let context = try seededContext()
        let legacyID = UUID().uuidString
        let legacy = FinanceCategory(
            categoryID: legacyID,
            type: .expense,
            nameTurkish: "Market",
            nameEnglish: "",
            symbol: "cart.fill",
            palette: .olive,
            isBuiltIn: false,
            sortOrder: 9
        )
        context.insert(legacy)
        let salary = try category("salary", in: context)
        salary.nameTurkish = "Maaşım"
        context.insert(FinanceTransaction(amount: 10, categoryID: legacyID, type: .expense, date: .now))
        try context.save()

        try CategoryStore.migrateStoredNames(in: context)
        XCTAssertEqual(legacy.nameEnglish, "Market")
        XCTAssertEqual(legacy.nameTurkish, "Market")
        XCTAssertEqual(salary.nameEnglish, "")
        XCTAssertEqual(salary.nameTurkish, "Maaşım")
        XCTAssertEqual(salary.symbol, BuiltInCategory.salary.symbol)
        let transactions = try context.fetch(FetchDescriptor<FinanceTransaction>())
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.categoryID, legacyID)
        XCTAssertEqual(transactions.first?.amount, 10)

        legacy.nameEnglish = "Grocery"
        try context.save()
        try CategoryStore.migrateStoredNames(in: context)
        XCTAssertEqual(legacy.nameEnglish, "Grocery")
        XCTAssertEqual(legacy.nameTurkish, "Market")
        let catalog = CategoryCatalog([legacy.info, salary.info])
        XCTAssertEqual(catalog.info(for: legacyID).displayName(in: AppLanguage.english.locale), "Grocery")
        XCTAssertEqual(catalog.info(for: legacyID).displayName(in: AppLanguage.turkish.locale), "Market")
        XCTAssertEqual(catalog.info(for: "salary").displayName(in: AppLanguage.english.locale), "Salary Income")
        XCTAssertEqual(catalog.info(for: "salary").displayName(in: AppLanguage.turkish.locale), "Maaşım")
        let summary = FinanceLedger(entries: transactions.map(\.ledgerEntry)).summary(for: .containing(.now, kind: .month))
        XCTAssertEqual(summary.expenseByCategory.map(\.categoryID), [legacyID])
        XCTAssertEqual(summary.expense, 10)
    }

    func testLanguageSwitchDoesNotChangeStoredCategory() throws {
        let context = try seededContext()
        let fund = try CategoryStore.create(
            type: .income, nameTurkish: "Fon Geliri", nameEnglish: "Fund Income",
            symbol: "tag.fill", palette: .indigo, in: context
        )
        let salary = try category("salary", in: context)
        _ = fund.displayName(in: AppLanguage.turkish.locale)
        _ = fund.displayName(in: AppLanguage.english.locale)
        _ = salary.displayName(in: AppLanguage.turkish.locale)
        _ = salary.displayName(in: AppLanguage.english.locale)
        XCTAssertEqual(fund.nameTurkish, "Fon Geliri")
        XCTAssertEqual(fund.nameEnglish, "Fund Income")
        XCTAssertEqual(salary.nameTurkish, "")
        XCTAssertEqual(salary.nameEnglish, "")
        XCTAssertEqual(try context.fetch(FetchDescriptor<FinanceCategory>()).count, BuiltInCategory.allCases.count + 1)
    }

    func testBuiltInRenameKeepsCatalogFallbackUntilOverridden() throws {
        let context = try seededContext()
        let salary = try category("salary", in: context)
        try CategoryStore.update(
            salary, nameTurkish: "Maaş Geliri", nameEnglish: "Paycheck",
            symbol: salary.symbol, palette: salary.palette, in: context
        )
        XCTAssertEqual(salary.nameTurkish, "", "Unchanged Turkish name stays on the localization catalog")
        XCTAssertEqual(salary.nameEnglish, "Paycheck")
        XCTAssertEqual(salary.displayName(in: AppLanguage.turkish.locale), "Maaş Geliri")
        XCTAssertEqual(salary.displayName(in: AppLanguage.english.locale), "Paycheck")
    }

    func testDeletionIsBlockedWhenCategoryIsBuiltInOrUsed() throws {
        let context = try seededContext()
        let salary = try category("salary", in: context)
        XCTAssertThrowsError(try CategoryStore.delete(salary, in: context)) { error in
            XCTAssertEqual(error as? CategoryStoreError, .builtInProtected)
        }

        let grocery = try CategoryStore.create(
            type: .expense, nameTurkish: "Market", nameEnglish: "Grocery",
            symbol: "cart.fill", palette: .olive, in: context
        )
        let transaction = FinanceTransaction(amount: 120, categoryID: grocery.categoryID, type: .expense, date: .now)
        context.insert(transaction)
        try context.save()

        XCTAssertThrowsError(try CategoryStore.delete(grocery, in: context)) { error in
            XCTAssertEqual(error as? CategoryStoreError, .inUse(1))
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FinanceTransaction>()), 1)
        XCTAssertEqual(transaction.categoryID, grocery.categoryID)

        context.delete(transaction)
        try context.save()
        try CategoryStore.delete(grocery, in: context)
        XCTAssertFalse(try context.fetch(FetchDescriptor<FinanceCategory>()).contains { $0.categoryID == grocery.categoryID })
    }

    func testArchivingKeepsTransactionsReportsAndBalances() throws {
        let context = try seededContext()
        let grocery = try CategoryStore.create(
            type: .expense, nameTurkish: "Market", nameEnglish: "Grocery",
            symbol: "cart.fill", palette: .olive, in: context
        )
        context.insert(FinanceTransaction(amount: 80, categoryID: grocery.categoryID, type: .expense, date: .now))
        context.insert(FinanceTransaction(amount: 50, category: .salary, date: .now))
        try context.save()

        let ledger = {
            try FinanceLedger(entries: context.fetch(FetchDescriptor<FinanceTransaction>()).map(\.ledgerEntry))
        }
        let before = try ledger().current.tlBalance
        try CategoryStore.setArchived(grocery, true, in: context)

        let after = try ledger()
        XCTAssertEqual(after.current.tlBalance, before)
        XCTAssertEqual(after.current.tlBalance, -30)
        let summary = after.summary(for: .containing(.now, kind: .month))
        XCTAssertEqual(summary.expenseByCategory.map(\.categoryID), [grocery.categoryID])
        XCTAssertEqual(summary.incomeByCategory.map(\.categoryID), ["salary"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FinanceTransaction>()), 2)

        let catalog = CategoryCatalog(try context.fetch(FetchDescriptor<FinanceCategory>()).map(\.info))
        let freshChoices = catalog.choices(for: .expense, selectedID: nil).map(\.id)
        XCTAssertFalse(freshChoices.contains(grocery.categoryID))
        let editingChoices = catalog.choices(for: .expense, selectedID: grocery.categoryID).map(\.id)
        XCTAssertTrue(editingChoices.contains(grocery.categoryID))
        XCTAssertEqual(catalog.info(for: grocery.categoryID).displayName(in: AppLanguage.english.locale), "Grocery")
        XCTAssertTrue(catalog.info(for: grocery.categoryID).isArchived)
    }

    func testExistingTransactionIdentifierSurvivesSeeding() throws {
        let context = try makeContext()
        let transaction = FinanceTransaction(amount: Decimal(string: "10.50")!, category: .home, date: .now, note: "Aidat")
        context.insert(transaction)
        try context.save()
        try CategoryStore.ensureDefaults(in: context)

        let stored = try XCTUnwrap(context.fetch(FetchDescriptor<FinanceTransaction>()).first)
        XCTAssertEqual(stored.categoryID, "home")
        XCTAssertEqual(stored.type, .expense)
        XCTAssertEqual(stored.note, "Aidat")
        XCTAssertEqual(stored.amount, Decimal(string: "10.50"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<FinanceCategory>()).count, BuiltInCategory.allCases.count)
    }

    func testCustomCategoryRoundTripsThroughBackupAndVersion1BackupStillRestores() throws {
        let source = try seededContext()
        let fund = try CategoryStore.create(
            type: .income, nameTurkish: "Fon Geliri", nameEnglish: "Fund Income",
            symbol: "chart.line.uptrend.xyaxis", palette: .indigo, in: source
        )
        try CategoryStore.setArchived(try category("cash", in: source), true, in: source)
        source.insert(FinanceTransaction(amount: 400, categoryID: fund.categoryID, type: .income, date: .now, note: "Fon"))
        try source.save()

        let decoded = try BackupService.decode(BackupService.encode(BackupService.makeBackup(from: source)))
        XCTAssertEqual(decoded.version, 2)
        let target = try makeContext()
        try BackupService.restore(decoded, into: target)

        let restoredFund = try category(fund.categoryID, in: target)
        XCTAssertEqual(restoredFund.nameTurkish, "Fon Geliri")
        XCTAssertEqual(restoredFund.nameEnglish, "Fund Income")
        XCTAssertEqual(restoredFund.type, .income)
        XCTAssertFalse(restoredFund.isBuiltIn)
        XCTAssertTrue(try category("cash", in: target).isArchived)
        XCTAssertEqual(try category("salary", in: target).displayName(in: AppLanguage.turkish.locale), "Maaş Geliri")
        let transactions = try target.fetch(FetchDescriptor<FinanceTransaction>())
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.categoryID, fund.categoryID)
        XCTAssertEqual(try FinanceLedger(entries: transactions.map(\.ledgerEntry)).current.tlBalance, 400)

        let legacySource = try makeContext()
        legacySource.insert(FinanceTransaction(amount: 15, category: .rental, date: .now, note: "Eski yedek"))
        try legacySource.save()
        var object = try JSONSerialization.jsonObject(with: BackupService.encode(BackupService.makeBackup(from: legacySource))) as! [String: Any]
        object.removeValue(forKey: "categories")
        object["version"] = 1
        let legacy = try BackupService.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.categories)
        XCTAssertEqual(legacy.version, 1)
        let legacyTarget = try makeContext()
        legacyTarget.insert(FinanceTransaction(amount: 9, category: .cash, date: .now))
        try legacyTarget.save()
        try BackupService.restore(legacy, into: legacyTarget)
        let legacyTransactions = try legacyTarget.fetch(FetchDescriptor<FinanceTransaction>())
        XCTAssertEqual(legacyTransactions.count, 1)
        XCTAssertEqual(legacyTransactions.first?.categoryID, "rental")
        XCTAssertEqual(legacyTransactions.first?.note, "Eski yedek")
        XCTAssertEqual(try legacyTarget.fetch(FetchDescriptor<FinanceCategory>()).count, BuiltInCategory.allCases.count)
        XCTAssertFalse(try category("cash", in: legacyTarget).isArchived)
    }

    func testExistingStoreMigratesWhenCategoryModelIsAdded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vestra-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        let original = Schema([
            FinanceTransaction.self,
            GoldPriceRecord.self,
            GoldMovement.self,
            WalletProfile.self,
        ])
        do {
            let container = try ModelContainer(for: original, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            context.insert(FinanceTransaction(amount: 42, category: .salary, date: .now, note: "Eski"))
            context.insert(WalletProfile(openingBalance: 7))
            try context.save()
        }

        let upgraded = try ModelContainer(for: Schema(VestraSchema.models), configurations: ModelConfiguration(url: url))
        let context = ModelContext(upgraded)
        let transactions = try context.fetch(FetchDescriptor<FinanceTransaction>())
        XCTAssertEqual(transactions.count, 1)
        XCTAssertEqual(transactions.first?.categoryID, "salary")
        XCTAssertEqual(transactions.first?.amount, 42)
        XCTAssertEqual(transactions.first?.note, "Eski")
        XCTAssertEqual(try context.fetch(FetchDescriptor<WalletProfile>()).first?.openingBalance, 7)
        try CategoryStore.ensureDefaults(in: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FinanceCategory>()).count, BuiltInCategory.allCases.count)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FinanceTransaction>()).first?.categoryID, "salary")
        XCTAssertEqual(try context.fetch(FetchDescriptor<FinanceTransaction>()).first?.note, "Eski")
    }

    func testChoicesHideArchivedCategoriesUnlessSelected() {
        let active = sample("salary", type: .income, archived: false, order: 0)
        let archived = sample("fund", type: .income, archived: true, order: 1)
        let expense = sample("home", type: .expense, archived: false, order: 0)
        let catalog = CategoryCatalog([expense, archived, active])

        XCTAssertEqual(catalog.choices(for: .income, selectedID: nil).map(\.id), ["salary"])
        XCTAssertEqual(catalog.choices(for: .income, selectedID: "fund").map(\.id), ["salary", "fund"])
        XCTAssertEqual(catalog.choices(for: .expense, selectedID: "missing").map(\.id), ["home", "missing"])
        XCTAssertEqual(catalog.info(for: "missing").displayName(in: AppLanguage.english.locale), "missing")
    }

    private func sample(_ id: String, type: TransactionType, archived: Bool, order: Int) -> CategoryInfo {
        CategoryInfo(
            id: id, type: type, nameTurkish: id, nameEnglish: "", localizationKey: "",
            symbol: "tag.fill", palette: .slate, isBuiltIn: false, isArchived: archived,
            sortOrder: order, createdAt: .now
        )
    }
}
