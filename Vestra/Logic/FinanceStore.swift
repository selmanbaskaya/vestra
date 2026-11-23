import Foundation
import SwiftData

enum FinanceStore {
    static func profile(in context: ModelContext) throws -> WalletProfile {
        if let existing = try context.fetch(FetchDescriptor<WalletProfile>()).first {
            return existing
        }
        let profile = WalletProfile()
        context.insert(profile)
        return profile
    }

    static func setOpeningBalance(_ amount: Decimal, in context: ModelContext) throws {
        try profile(in: context).openingBalance = amount
        try context.save()
    }

    /// Keeps one price per calendar day: recording again on the same day replaces that day's price.
    @discardableResult
    static func recordGoldPrice(
        _ price: Decimal,
        on date: Date,
        in context: ModelContext,
        calendar: Calendar = .app
    ) throws -> GoldPriceRecord {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        let descriptor = FetchDescriptor<GoldPriceRecord>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        let record: GoldPriceRecord
        if let existing = try context.fetch(descriptor).first {
            existing.pricePerGram = price
            existing.date = date
            existing.createdAt = .now
            record = existing
        } else {
            record = GoldPriceRecord(pricePerGram: price, date: date)
            context.insert(record)
        }
        try context.save()
        return record
    }

    static func deleteAllData(in context: ModelContext) throws {
        try context.fetch(FetchDescriptor<FinanceTransaction>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<FinanceCategory>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<GoldPriceRecord>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<GoldMovement>()).forEach(context.delete)
        try context.fetch(FetchDescriptor<WalletProfile>()).forEach(context.delete)
        try context.save()
    }
}
