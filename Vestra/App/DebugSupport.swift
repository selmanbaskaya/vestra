#if DEBUG
import Foundation
import SwiftData

/// Launch options for simulator testing. Compiled into Debug builds only.
///
/// - `-VestraInMemoryStore`: use a throwaway in-memory store.
/// - `-VestraStoreFile <name>`: use a separate store file; add `-VestraResetStore` to start empty.
/// - `-VestraDemoData`: fill an empty store with sample data.
enum DebugSupport {
    static func storeConfiguration() -> ModelConfiguration? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-VestraInMemoryStore") {
            return ModelConfiguration(isStoredInMemoryOnly: true)
        }
        guard let index = arguments.firstIndex(of: "-VestraStoreFile"), index + 1 < arguments.count else { return nil }
        let directory = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: arguments[index + 1])
        if arguments.contains("-VestraResetStore") {
            for suffix in ["", "-shm", "-wal"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }
        return ModelConfiguration(url: url)
    }

    static func seedDemoDataIfRequested(in context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-VestraDemoData"),
              (try? context.fetchCount(FetchDescriptor<FinanceTransaction>())) == 0
        else { return }

        let calendar = Calendar.app
        let thisMonth = ReportPeriod.containing(.now, kind: .month)
        func day(_ period: ReportPeriod, _ day: Int) -> Date {
            let date = calendar.date(from: DateComponents(year: period.year, month: period.month, day: day, hour: 12))!
            return min(date, .now)
        }

        context.insert(WalletProfile(openingBalance: 40_000))
        for offset in 0..<14 {
            let month = thisMonth.shifted(by: -offset)
            let variation = Decimal(offset % 4) * 1_250
            context.insert(FinanceTransaction(amount: 92_000, category: .salary, date: day(month, 1), note: "Maaş"))
            context.insert(FinanceTransaction(amount: 18_500, category: .rental, date: day(month, 5)))
            context.insert(FinanceTransaction(amount: 24_000, category: .home, date: day(month, 3), note: "Kira ve aidat"))
            context.insert(FinanceTransaction(amount: 31_400 + variation * 3, category: .creditCard, date: day(month, 15)))
            context.insert(FinanceTransaction(amount: 6_750 + variation, category: .cash, date: day(month, 20)))
            if offset % 3 == 0 {
                context.insert(FinanceTransaction(amount: 7_800, category: .dividend, date: day(month, 10)))
                context.insert(FinanceTransaction(amount: 4_200, category: .otherExpense, date: day(month, 22), note: "Hediye"))
            }
        }

        context.insert(GoldMovement(grams: 20, date: day(thisMonth.shifted(by: -13), 2), note: "Başlangıç"))
        context.insert(GoldMovement(grams: 5, date: day(thisMonth.shifted(by: -6), 8)))
        for offset in 0..<14 {
            let price = Decimal(6_000) - Decimal(offset) * 120
            context.insert(GoldPriceRecord(pricePerGram: price, date: day(thisMonth.shifted(by: -offset), 1)))
        }
        try? context.save()
    }
}
#endif
