import Foundation
import SwiftData

enum CategoryStoreError: Error, Equatable {
    case nameRequired
    case inUse(Int)
    case builtInProtected
}

enum CategoryStore {
    static let maximumNameLength = 60

    /// Inserts any missing built-in category. Existing rows, including archived or renamed ones, are left untouched.
    static func ensureDefaults(in context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<FinanceCategory>())
        let ids = Set(existing.map(\.categoryID))
        var inserted = false
        for builtIn in BuiltInCategory.allCases where !ids.contains(builtIn.rawValue) {
            context.insert(FinanceCategory(
                categoryID: builtIn.rawValue,
                type: builtIn.type,
                localizationKey: builtIn.localizationKey,
                symbol: builtIn.symbol,
                palette: builtIn.palette,
                isBuiltIn: true,
                sortOrder: builtIn.sortOrder
            ))
            inserted = true
        }
        if inserted { try context.save() }
        try migrateStoredNames(in: context)
    }

    /// Custom categories created when Turkish was the only entered name keep that text as their English name.
    /// Built-in categories are left alone so their catalog translations continue to follow the language.
    static func migrateStoredNames(in context: ModelContext) throws {
        let categories = try context.fetch(FetchDescriptor<FinanceCategory>())
        var changed = false
        for category in categories where !category.isBuiltIn {
            let english = category.nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
            let turkish = category.nameTurkish.trimmingCharacters(in: .whitespacesAndNewlines)
            guard english.isEmpty, !turkish.isEmpty else { continue }
            category.nameEnglish = turkish
            changed = true
        }
        if changed { try context.save() }
    }

    @discardableResult
    static func create(
        type: TransactionType,
        nameTurkish: String,
        nameEnglish: String,
        symbol: String,
        palette: CategoryPalette,
        in context: ModelContext
    ) throws -> FinanceCategory {
        let english = clip(nameEnglish)
        guard !english.isEmpty else { throw CategoryStoreError.nameRequired }
        let peers = try context.fetch(FetchDescriptor<FinanceCategory>()).filter { $0.type == type }
        let nextOrder = (peers.map(\.sortOrder).max() ?? -1) + 1
        let category = FinanceCategory(
            categoryID: UUID().uuidString,
            type: type,
            nameTurkish: clip(nameTurkish),
            nameEnglish: english,
            symbol: resolvedSymbol(symbol),
            palette: palette,
            isBuiltIn: false,
            sortOrder: nextOrder
        )
        context.insert(category)
        try context.save()
        return category
    }

    /// Stores name overrides. For a built-in category, a name that matches its catalog translation
    /// (or is left empty) is cleared so the category keeps following the selected language.
    static func update(
        _ category: FinanceCategory,
        nameTurkish: String,
        nameEnglish: String,
        symbol: String,
        palette: CategoryPalette,
        in context: ModelContext
    ) throws {
        let turkish = clip(nameTurkish)
        let english = clip(nameEnglish)
        if category.isBuiltIn {
            let key = category.localizationKey
            let defaultTurkish = key.isEmpty ? "" : AppLanguage.turkish.locale.localized(key)
            let defaultEnglish = key.isEmpty ? "" : AppLanguage.english.locale.localized(key)
            category.nameTurkish = (turkish.isEmpty || turkish == defaultTurkish) ? "" : turkish
            category.nameEnglish = (english.isEmpty || english == defaultEnglish) ? "" : english
        } else {
            guard !english.isEmpty else { throw CategoryStoreError.nameRequired }
            category.nameTurkish = turkish
            category.nameEnglish = english
        }
        if CategorySymbol(rawValue: symbol) != nil {
            category.symbol = symbol
        }
        category.palette = palette
        try context.save()
    }

    static func setArchived(_ category: FinanceCategory, _ archived: Bool, in context: ModelContext) throws {
        category.isArchived = archived
        try context.save()
    }

    static func transactionCount(for categoryID: String, in context: ModelContext) throws -> Int {
        let identifier = categoryID
        let descriptor = FetchDescriptor<FinanceTransaction>(
            predicate: #Predicate { $0.categoryRaw == identifier }
        )
        return try context.fetchCount(descriptor)
    }

    /// Permanently removes a custom category that has never been used. Built-in categories and
    /// categories referenced by transactions are refused; those must be archived instead.
    static func delete(_ category: FinanceCategory, in context: ModelContext) throws {
        if category.isBuiltIn { throw CategoryStoreError.builtInProtected }
        let count = try transactionCount(for: category.categoryID, in: context)
        guard count == 0 else { throw CategoryStoreError.inUse(count) }
        context.delete(category)
        try context.save()
    }

    static func insertImported(_ item: VestraBackup.CategoryItem, into context: ModelContext) {
        let builtIn = BuiltInCategory(rawValue: item.id)
        let type = TransactionType(rawValue: item.type) ?? builtIn?.type ?? .expense
        let palette = CategoryPalette(rawValue: item.palette) ?? builtIn?.palette ?? .slate
        let localizationKey = item.localizationKey.isEmpty ? (builtIn?.localizationKey ?? "") : item.localizationKey
        context.insert(FinanceCategory(
            categoryID: item.id,
            type: type,
            nameTurkish: item.nameTurkish,
            nameEnglish: item.nameEnglish,
            localizationKey: localizationKey,
            symbol: item.symbol.isEmpty ? (builtIn?.symbol ?? CategorySymbol.default.rawValue) : item.symbol,
            palette: palette,
            isBuiltIn: item.isBuiltIn || builtIn != nil,
            isArchived: item.isArchived,
            sortOrder: item.sortOrder,
            createdAt: item.createdAt
        ))
    }

    private static func clip(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumNameLength else { return trimmed }
        return String(trimmed.prefix(maximumNameLength))
    }

    private static func resolvedSymbol(_ symbol: String) -> String {
        CategorySymbol(rawValue: symbol)?.rawValue ?? CategorySymbol.default.rawValue
    }
}
