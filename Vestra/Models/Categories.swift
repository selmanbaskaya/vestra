import SwiftUI

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case income
    case expense

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .income: "Income"
        case .expense: "Expense"
        }
    }
}

/// Built-in categories. Raw values are the historical identifiers already stored on transactions.
enum BuiltInCategory: String, CaseIterable, Identifiable {
    case salary
    case rental
    case dividend
    case otherIncome
    case creditCard
    case cash
    case home
    case otherExpense

    var id: String { rawValue }

    var type: TransactionType {
        switch self {
        case .salary, .rental, .dividend, .otherIncome: .income
        case .creditCard, .cash, .home, .otherExpense: .expense
        }
    }

    /// Existing localization key. Kept so built-in names continue to follow the string catalog
    /// until the user explicitly renames the category.
    var localizationKey: String {
        switch self {
        case .salary: "Salary Income"
        case .rental: "Rental Income"
        case .dividend: "Dividend Income"
        case .otherIncome: "Other Income"
        case .creditCard: "Credit Card Expenses"
        case .cash: "Cash Expenses"
        case .home: "Home Expenses"
        case .otherExpense: "Other Expenses"
        }
    }

    var symbol: String {
        switch self {
        case .salary: "briefcase.fill"
        case .rental: "building.2.fill"
        case .dividend: "chart.line.uptrend.xyaxis"
        case .otherIncome: "plus.circle.fill"
        case .creditCard: "creditcard.fill"
        case .cash: "banknote.fill"
        case .home: "house.fill"
        case .otherExpense: "ellipsis.circle.fill"
        }
    }

    var palette: CategoryPalette {
        switch self {
        case .salary: .green
        case .rental: .blue
        case .dividend: .gold
        case .otherIncome: .slate
        case .creditCard: .purple
        case .cash: .orange
        case .home: .teal
        case .otherExpense: .gray
        }
    }

    var sortOrder: Int {
        switch self {
        case .salary, .creditCard: 0
        case .rental, .cash: 1
        case .dividend, .home: 2
        case .otherIncome, .otherExpense: 3
        }
    }
}

enum CategoryPalette: String, CaseIterable, Identifiable {
    case green, blue, gold, slate, purple, orange, teal, gray
    case rose, indigo, olive, cocoa

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .green: Color(light: 0x2F9E6E, dark: 0x4CC38A)
        case .blue: Color(light: 0x3B7DD8, dark: 0x5E9EF2)
        case .gold: Color(light: 0xA9823A, dark: 0xD9B46A)
        case .slate: Color(light: 0x6F7787, dark: 0x9AA1AE)
        case .purple: Color(light: 0x6A5ACD, dark: 0x9184F2)
        case .orange: Color(light: 0xD27A22, dark: 0xF0A04B)
        case .teal: Color(light: 0x23919E, dark: 0x4CC0CC)
        case .gray: Color(light: 0x8A8F98, dark: 0xA3A8B0)
        case .rose: Color(light: 0xC4476A, dark: 0xF08AA4)
        case .indigo: Color(light: 0x4454A8, dark: 0x8C9AEE)
        case .olive: Color(light: 0x6B8F3C, dark: 0xA8D06A)
        case .cocoa: Color(light: 0x8D5A3B, dark: 0xD09A72)
        }
    }
}

/// SF Symbols a category may use. Built-in symbols are included so they can be reselected.
enum CategorySymbol: String, CaseIterable, Identifiable {
    case briefcase = "briefcase.fill"
    case building = "building.2.fill"
    case trend = "chart.line.uptrend.xyaxis"
    case plus = "plus.circle.fill"
    case creditCard = "creditcard.fill"
    case banknote = "banknote.fill"
    case house = "house.fill"
    case other = "ellipsis.circle.fill"
    case tag = "tag.fill"
    case cart = "cart.fill"
    case bag = "bag.fill"
    case car = "car.fill"
    case fuel = "fuelpump.fill"
    case tram = "tram.fill"
    case dining = "fork.knife"
    case gift = "gift.fill"
    case heart = "heart.fill"
    case medical = "cross.case.fill"
    case education = "graduationcap.fill"
    case travel = "airplane"
    case pet = "pawprint.fill"
    case bolt = "bolt.fill"
    case phone = "phone.fill"
    case entertainment = "tv.fill"

    var id: String { rawValue }
    static let `default` = CategorySymbol.tag
}

enum CategoryNaming {
    /// English is the primary name. Turkish is used only while the app language is Turkish,
    /// and a missing Turkish name falls back to English. Nothing is translated automatically.
    static func displayName(
        nameTurkish: String,
        nameEnglish: String,
        localizationKey: String,
        identifier: String,
        locale: Locale
    ) -> String {
        let turkish = nameTurkish.trimmingCharacters(in: .whitespacesAndNewlines)
        let english = nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        let builtinEnglish = localizationKey.isEmpty ? "" : AppLanguage.english.locale.localized(localizationKey)
        let builtinTurkish = localizationKey.isEmpty ? "" : AppLanguage.turkish.locale.localized(localizationKey)
        if AppLanguage(locale: locale) == .turkish {
            if !turkish.isEmpty { return turkish }
            if !builtinTurkish.isEmpty { return builtinTurkish }
            if !english.isEmpty { return english }
            if !builtinEnglish.isEmpty { return builtinEnglish }
            return identifier
        }
        if !english.isEmpty { return english }
        if !builtinEnglish.isEmpty { return builtinEnglish }
        if !turkish.isEmpty { return turkish }
        return identifier
    }
}

struct CategoryInfo: Identifiable, Hashable {
    var id: String
    var type: TransactionType
    var nameTurkish: String
    var nameEnglish: String
    var localizationKey: String
    var symbol: String
    var palette: CategoryPalette
    var isBuiltIn: Bool
    var isArchived: Bool
    var sortOrder: Int
    var createdAt: Date

    var color: Color { palette.color }

    func displayName(in locale: Locale) -> String {
        CategoryNaming.displayName(
            nameTurkish: nameTurkish,
            nameEnglish: nameEnglish,
            localizationKey: localizationKey,
            identifier: id,
            locale: locale
        )
    }

    static func unknown(id: String, type: TransactionType) -> CategoryInfo {
        CategoryInfo(
            id: id,
            type: type,
            nameTurkish: "",
            nameEnglish: "",
            localizationKey: "",
            symbol: "questionmark.circle",
            palette: .slate,
            isBuiltIn: false,
            isArchived: true,
            sortOrder: .max,
            createdAt: .distantPast
        )
    }
}

struct CategoryCatalog {
    private var byID: [String: CategoryInfo]
    private var ordered: [CategoryInfo]

    init(_ categories: [CategoryInfo]) {
        ordered = categories.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
        byID = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
    }

    static let empty = CategoryCatalog([])

    func info(for id: String, type: TransactionType = .expense) -> CategoryInfo {
        byID[id] ?? .unknown(id: id, type: type)
    }

    /// Active categories of this type. The selected category is included even when archived,
    /// so a transaction can keep its original category while being edited.
    func choices(for type: TransactionType, selectedID: String?) -> [CategoryInfo] {
        var result = ordered.filter { info in
            info.type == type && (!info.isArchived || info.id == selectedID)
        }
        if let selectedID, !selectedID.isEmpty, !result.contains(where: { $0.id == selectedID }) {
            result.append(info(for: selectedID, type: type))
        }
        return result
    }
}
