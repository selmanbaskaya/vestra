import Foundation
import SwiftData

enum VestraSchema {
    /// `FinanceCategory` is additive. An existing store gains an empty table and keeps every
    /// transaction; `categoryRaw` still holds the original identifiers ("salary", "creditCard", …).
    /// Missing built-in rows are inserted by `CategoryStore.ensureDefaults` and are never duplicated.
    static let models: [any PersistentModel.Type] = [
        FinanceTransaction.self,
        FinanceCategory.self,
        GoldPriceRecord.self,
        GoldMovement.self,
        WalletProfile.self,
    ]
}

/// Monetary and gram values are stored as plain decimal strings so they round-trip exactly.
@Model
final class FinanceTransaction {
    var id: UUID = UUID()
    var amountRaw: String = "0"
    var typeRaw: String = TransactionType.expense.rawValue
    var categoryRaw: String = BuiltInCategory.otherExpense.rawValue
    var date: Date = Date.now
    var note: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    convenience init(amount: Decimal, category: BuiltInCategory, date: Date, note: String = "", createdAt: Date = .now) {
        self.init(amount: amount, categoryID: category.rawValue, type: category.type, date: date, note: note, createdAt: createdAt)
    }

    init(amount: Decimal, categoryID: String, type: TransactionType, date: Date, note: String = "", createdAt: Date = .now) {
        self.id = UUID()
        self.amountRaw = DecimalCoding.string(amount)
        self.typeRaw = type.rawValue
        self.categoryRaw = categoryID
        self.date = date
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var amount: Decimal {
        get { DecimalCoding.decimal(amountRaw) }
        set { amountRaw = DecimalCoding.string(newValue) }
    }

    var type: TransactionType {
        TransactionType(rawValue: typeRaw) ?? .expense
    }

    /// Stable category identifier. Built-in values are unchanged from earlier versions of Vestra.
    var categoryID: String {
        get { categoryRaw }
        set { categoryRaw = newValue }
    }

    func setCategory(id: String, type: TransactionType) {
        categoryRaw = id
        typeRaw = type.rawValue
    }

    func setCategory(_ category: BuiltInCategory) {
        setCategory(id: category.rawValue, type: category.type)
    }

    var ledgerEntry: LedgerEntry {
        LedgerEntry(amount: amount, categoryID: categoryID, type: type, date: date)
    }
}

/// A user-managed income or expense category. Transactions keep their own copy of `categoryID`,
/// so archiving or renaming a category never rewrites historical records.
@Model
final class FinanceCategory {
    @Attribute(.unique) var categoryID: String = UUID().uuidString
    var typeRaw: String = TransactionType.expense.rawValue
    var nameTurkish: String = ""
    var nameEnglish: String = ""
    var localizationKey: String = ""
    var symbol: String = CategorySymbol.default.rawValue
    var paletteRaw: String = CategoryPalette.slate.rawValue
    var isBuiltIn: Bool = false
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    init(
        categoryID: String,
        type: TransactionType,
        nameTurkish: String = "",
        nameEnglish: String = "",
        localizationKey: String = "",
        symbol: String,
        palette: CategoryPalette,
        isBuiltIn: Bool,
        isArchived: Bool = false,
        sortOrder: Int,
        createdAt: Date = .now
    ) {
        self.categoryID = categoryID
        self.typeRaw = type.rawValue
        self.nameTurkish = nameTurkish
        self.nameEnglish = nameEnglish
        self.localizationKey = localizationKey
        self.symbol = symbol
        self.paletteRaw = palette.rawValue
        self.isBuiltIn = isBuiltIn
        self.isArchived = isArchived
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var type: TransactionType {
        get { TransactionType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var palette: CategoryPalette {
        get { CategoryPalette(rawValue: paletteRaw) ?? .slate }
        set { paletteRaw = newValue.rawValue }
    }

    func displayName(in locale: Locale) -> String {
        CategoryNaming.displayName(
            nameTurkish: nameTurkish,
            nameEnglish: nameEnglish,
            localizationKey: localizationKey,
            identifier: categoryID,
            locale: locale
        )
    }

    var info: CategoryInfo {
        CategoryInfo(
            id: categoryID,
            type: type,
            nameTurkish: nameTurkish,
            nameEnglish: nameEnglish,
            localizationKey: localizationKey,
            symbol: symbol,
            palette: palette,
            isBuiltIn: isBuiltIn,
            isArchived: isArchived,
            sortOrder: sortOrder,
            createdAt: createdAt
        )
    }
}

/// A dated gold selling price per gram. Reports use the latest record on or before a period's end.
@Model
final class GoldPriceRecord {
    var id: UUID = UUID()
    var date: Date = Date.now
    var priceRaw: String = "0"
    var createdAt: Date = Date.now

    init(pricePerGram: Decimal, date: Date, createdAt: Date = .now) {
        self.id = UUID()
        self.priceRaw = DecimalCoding.string(pricePerGram)
        self.date = date
        self.createdAt = createdAt
    }

    var pricePerGram: Decimal {
        get { DecimalCoding.decimal(priceRaw) }
        set { priceRaw = DecimalCoding.string(newValue) }
    }

    var point: GoldPoint {
        GoldPoint(id: id, date: date, value: pricePerGram, createdAt: createdAt)
    }
}

/// A signed change in gold holdings (grams). Holdings at a date are the sum of earlier movements.
@Model
final class GoldMovement {
    var id: UUID = UUID()
    var date: Date = Date.now
    var gramsRaw: String = "0"
    var note: String = ""
    var createdAt: Date = Date.now

    init(grams: Decimal, date: Date, note: String = "", createdAt: Date = .now) {
        self.id = UUID()
        self.gramsRaw = DecimalCoding.string(grams)
        self.date = date
        self.note = note
        self.createdAt = createdAt
    }

    var grams: Decimal {
        get { DecimalCoding.decimal(gramsRaw) }
        set { gramsRaw = DecimalCoding.string(newValue) }
    }

    var point: GoldPoint {
        GoldPoint(id: id, date: date, value: grams, createdAt: createdAt)
    }
}

/// Single-row record holding the opening TL balance.
@Model
final class WalletProfile {
    var id: UUID = UUID()
    var openingBalanceRaw: String = "0"
    var createdAt: Date = Date.now

    init(openingBalance: Decimal = 0) {
        self.id = UUID()
        self.openingBalanceRaw = DecimalCoding.string(openingBalance)
        self.createdAt = .now
    }

    var openingBalance: Decimal {
        get { DecimalCoding.decimal(openingBalanceRaw) }
        set { openingBalanceRaw = DecimalCoding.string(newValue) }
    }
}
