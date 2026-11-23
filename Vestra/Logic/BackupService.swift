import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct VestraBackup: Codable {
    struct TransactionItem: Codable {
        var id: UUID
        var amount: String
        var type: String
        var category: String
        var date: Date
        var note: String
        var createdAt: Date
        var updatedAt: Date
    }

    struct GoldPriceItem: Codable {
        var id: UUID
        var date: Date
        var pricePerGram: String
        var createdAt: Date
    }

    struct GoldMovementItem: Codable {
        var id: UUID
        var date: Date
        var grams: String
        var note: String
        var createdAt: Date
    }

    struct CategoryItem: Codable {
        var id: String
        var type: String
        var nameTurkish: String
        var nameEnglish: String
        var localizationKey: String
        var symbol: String
        var palette: String
        var isBuiltIn: Bool
        var isArchived: Bool
        var sortOrder: Int
        var createdAt: Date
    }

    static let formatIdentifier = "vestra-backup"
    /// Version 2 adds categories. Version 1 backups have no categories key and still restore.
    static let currentVersion = 2

    var format: String = formatIdentifier
    var version: Int = currentVersion
    var exportedAt: Date
    var openingBalance: String
    var transactions: [TransactionItem]
    var goldPrices: [GoldPriceItem]
    var goldMovements: [GoldMovementItem]
    /// Absent in backups written before categories could be customized.
    var categories: [CategoryItem]?
}

enum BackupError: Error {
    case invalidFile
}

enum BackupService {
    static func makeBackup(from context: ModelContext) throws -> VestraBackup {
        let opening = try context.fetch(FetchDescriptor<WalletProfile>()).first?.openingBalance ?? 0
        let transactions = try context.fetch(FetchDescriptor<FinanceTransaction>(sortBy: [SortDescriptor(\.date)]))
        let prices = try context.fetch(FetchDescriptor<GoldPriceRecord>(sortBy: [SortDescriptor(\.date)]))
        let movements = try context.fetch(FetchDescriptor<GoldMovement>(sortBy: [SortDescriptor(\.date)]))
        let categories = try context.fetch(FetchDescriptor<FinanceCategory>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]))
        return VestraBackup(
            exportedAt: .now,
            openingBalance: DecimalCoding.string(opening),
            transactions: transactions.map {
                .init(id: $0.id, amount: $0.amountRaw, type: $0.typeRaw, category: $0.categoryRaw,
                      date: $0.date, note: $0.note, createdAt: $0.createdAt, updatedAt: $0.updatedAt)
            },
            goldPrices: prices.map {
                .init(id: $0.id, date: $0.date, pricePerGram: $0.priceRaw, createdAt: $0.createdAt)
            },
            goldMovements: movements.map {
                .init(id: $0.id, date: $0.date, grams: $0.gramsRaw, note: $0.note, createdAt: $0.createdAt)
            },
            categories: categories.map {
                .init(id: $0.categoryID, type: $0.typeRaw, nameTurkish: $0.nameTurkish, nameEnglish: $0.nameEnglish,
                      localizationKey: $0.localizationKey, symbol: $0.symbol, palette: $0.paletteRaw,
                      isBuiltIn: $0.isBuiltIn, isArchived: $0.isArchived, sortOrder: $0.sortOrder, createdAt: $0.createdAt)
            }
        )
    }

    private static func isoFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter
    }

    static func encode(_ backup: VestraBackup) throws -> Data {
        let encoder = JSONEncoder()
        let formatter = isoFormatter(fractionalSeconds: true)
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    /// Decodes and validates a backup before anything is replaced.
    static func decode(_ data: Data) throws -> VestraBackup {
        let decoder = JSONDecoder()
        let precise = isoFormatter(fractionalSeconds: true)
        let plain = isoFormatter(fractionalSeconds: false)
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = precise.date(from: text) ?? plain.date(from: text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date")
            }
            return date
        }
        guard let backup = try? decoder.decode(VestraBackup.self, from: data), isValid(backup) else {
            throw BackupError.invalidFile
        }
        return backup
    }

    private static func isValid(_ backup: VestraBackup) -> Bool {
        guard backup.format == VestraBackup.formatIdentifier,
              backup.version <= VestraBackup.currentVersion,
              DecimalCoding.parseStrict(backup.openingBalance) != nil
        else { return false }

        let stored = backup.categories ?? []
        let identifiers = stored.map(\.id)
        guard Set(identifiers).count == identifiers.count, stored.allSatisfy(isValidCategory) else { return false }

        let known = Set(identifiers).union(BuiltInCategory.allCases.map(\.rawValue))
        let typesByID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.type) })
        let transactionsValid = backup.transactions.allSatisfy { item in
            guard known.contains(item.category),
                  TransactionType(rawValue: item.type) != nil,
                  item.category.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil,
                  (DecimalCoding.parseStrict(item.amount) ?? -1) > 0
            else { return false }
            return typesByID[item.category].map { $0 == item.type } ?? true
        }
        return transactionsValid
            && backup.goldPrices.allSatisfy { (DecimalCoding.parseStrict($0.pricePerGram) ?? -1) > 0 }
            && backup.goldMovements.allSatisfy { DecimalCoding.parseStrict($0.grams) != nil }
    }

    private static func isValidCategory(_ item: VestraBackup.CategoryItem) -> Bool {
        guard item.id.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil,
              TransactionType(rawValue: item.type) != nil,
              !item.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              item.symbol.count <= 80,
              item.nameTurkish.count <= 200,
              item.nameEnglish.count <= 200
        else { return false }
        if let builtIn = BuiltInCategory(rawValue: item.id), builtIn.type.rawValue != item.type {
            return false
        }
        return true
    }

    static func restore(_ backup: VestraBackup, into context: ModelContext) throws {
        try FinanceStore.deleteAllData(in: context)
        context.insert(WalletProfile(openingBalance: DecimalCoding.decimal(backup.openingBalance)))
        for item in backup.categories ?? [] {
            CategoryStore.insertImported(item, into: context)
        }
        try CategoryStore.ensureDefaults(in: context)
        for item in backup.transactions {
            guard let type = TransactionType(rawValue: item.type) else { continue }
            let transaction = FinanceTransaction(
                amount: DecimalCoding.decimal(item.amount), categoryID: item.category, type: type,
                date: item.date, note: item.note, createdAt: item.createdAt
            )
            transaction.id = item.id
            transaction.updatedAt = item.updatedAt
            context.insert(transaction)
        }
        for item in backup.goldPrices {
            let record = GoldPriceRecord(pricePerGram: DecimalCoding.decimal(item.pricePerGram), date: item.date, createdAt: item.createdAt)
            record.id = item.id
            context.insert(record)
        }
        for item in backup.goldMovements {
            let movement = GoldMovement(grams: DecimalCoding.decimal(item.grams), date: item.date, note: item.note, createdAt: item.createdAt)
            movement.id = item.id
            context.insert(movement)
        }
        try context.save()
    }

    /// Language-independent CSV (raw category identifiers, "." decimal separator) for spreadsheets.
    static func transactionsCSV(from context: ModelContext) throws -> Data {
        let transactions = try context.fetch(FetchDescriptor<FinanceTransaction>(sortBy: [SortDescriptor(\.date)]))
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        dateFormatter.timeZone = .current
        let timestampFormatter = ISO8601DateFormatter()

        var lines = ["date,type,category,amount,description,created_at"]
        for transaction in transactions {
            lines.append([
                dateFormatter.string(from: transaction.date),
                transaction.typeRaw,
                transaction.categoryRaw,
                transaction.amountRaw,
                csvEscaped(transaction.note),
                timestampFormatter.string(from: transaction.createdAt),
            ].joined(separator: ","))
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private static func csvEscaped(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
