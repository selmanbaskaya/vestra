import Foundation

struct LedgerEntry: Hashable {
    var amount: Decimal
    var categoryID: String
    var type: TransactionType
    var date: Date

    init(amount: Decimal, categoryID: String, type: TransactionType, date: Date) {
        self.amount = amount
        self.categoryID = categoryID
        self.type = type
        self.date = date
    }

    init(amount: Decimal, category: BuiltInCategory, date: Date) {
        self.init(amount: amount, categoryID: category.rawValue, type: category.type, date: date)
    }
}

struct GoldPoint: Hashable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var value: Decimal
    var createdAt: Date = .distantPast

    static func chronological(_ lhs: GoldPoint, _ rhs: GoldPoint) -> Bool {
        lhs.date == rhs.date ? lhs.createdAt < rhs.createdAt : lhs.date < rhs.date
    }
}

struct WealthSnapshot: Equatable {
    var tlBalance: Decimal
    var goldGrams: Decimal
    var goldPrice: Decimal?
    var goldPriceDate: Date?

    /// Rounded to kuruş so that the displayed TL and gold values always add up to the displayed total.
    var goldValue: Decimal {
        guard let goldPrice else { return 0 }
        return (goldGrams * goldPrice).rounded(scale: 2)
    }

    var total: Decimal { tlBalance + goldValue }
}

struct CategoryAmount: Identifiable, Hashable {
    var categoryID: String
    var amount: Decimal
    var share: Double

    var id: String { categoryID }
}

struct PeriodSummary {
    var period: ReportPeriod
    var income: Decimal
    var expense: Decimal
    var incomeByCategory: [CategoryAmount]
    var expenseByCategory: [CategoryAmount]
    var transactionCount: Int
    var closing: WealthSnapshot

    var net: Decimal { income - expense }
}

struct MonthPoint: Identifiable, Hashable {
    var period: ReportPeriod
    var income: Decimal
    var expense: Decimal

    var net: Decimal { income - expense }
    var id: String { "\(period.year)-\(period.month)" }
}

/// Pure calculation layer. Every figure in the app is derived from these inputs, so editing or deleting
/// any record automatically recalculates balances and reports.
struct FinanceLedger {
    var openingBalance: Decimal
    var entries: [LedgerEntry]
    var goldPrices: [GoldPoint]
    var goldMovements: [GoldPoint]
    var calendar: Calendar

    init(
        openingBalance: Decimal = 0,
        entries: [LedgerEntry] = [],
        goldPrices: [GoldPoint] = [],
        goldMovements: [GoldPoint] = [],
        calendar: Calendar = .app
    ) {
        self.openingBalance = openingBalance
        self.entries = entries
        self.goldPrices = goldPrices.sorted(by: GoldPoint.chronological)
        self.goldMovements = goldMovements.sorted(by: GoldPoint.chronological)
        self.calendar = calendar
    }

    var current: WealthSnapshot { snapshot(before: .distantFuture) }

    /// Wealth position including every record dated strictly before `end`.
    func snapshot(before end: Date) -> WealthSnapshot {
        let price = goldPrices.last { $0.date < end }
        return WealthSnapshot(
            tlBalance: tlBalance(before: end),
            goldGrams: goldGrams(before: end),
            goldPrice: price?.value,
            goldPriceDate: price?.date
        )
    }

    func tlBalance(before end: Date) -> Decimal {
        entries.reduce(openingBalance) { balance, entry in
            guard entry.date < end else { return balance }
            return entry.type == .income ? balance + entry.amount : balance - entry.amount
        }
    }

    func goldGrams(before end: Date) -> Decimal {
        goldMovements.reduce(Decimal(0)) { $1.date < end ? $0 + $1.value : $0 }
    }

    func endOfDay(_ date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
    }

    func summary(for period: ReportPeriod) -> PeriodSummary {
        let interval = period.interval(calendar: calendar)
        let inPeriod = entries.filter { $0.date >= interval.start && $0.date < interval.end }
        let income = Self.total(of: inPeriod, type: .income)
        let expense = Self.total(of: inPeriod, type: .expense)
        return PeriodSummary(
            period: period,
            income: income,
            expense: expense,
            incomeByCategory: Self.breakdown(of: inPeriod, type: .income, total: income),
            expenseByCategory: Self.breakdown(of: inPeriod, type: .expense, total: expense),
            transactionCount: inPeriod.count,
            closing: snapshot(before: interval.end)
        )
    }

    func monthlyPoints(year: Int) -> [MonthPoint] {
        (1...12).map { monthPoint(ReportPeriod(kind: .month, year: year, month: $0)) }
    }

    func monthlyPoints(endingAt period: ReportPeriod, count: Int) -> [MonthPoint] {
        let last = ReportPeriod(kind: .month, year: period.year, month: period.month)
        return (0..<count).reversed().map { monthPoint(last.shifted(by: -$0)) }
    }

    private func monthPoint(_ period: ReportPeriod) -> MonthPoint {
        let interval = period.interval(calendar: calendar)
        let inPeriod = entries.filter { $0.date >= interval.start && $0.date < interval.end }
        return MonthPoint(
            period: period,
            income: Self.total(of: inPeriod, type: .income),
            expense: Self.total(of: inPeriod, type: .expense)
        )
    }

    static func total(of entries: [LedgerEntry], type: TransactionType) -> Decimal {
        entries.reduce(Decimal(0)) { $1.type == type ? $0 + $1.amount : $0 }
    }

    /// Groups whatever category identifiers are present. Archived and custom categories stay in the
    /// report; categories with no transactions in the period are omitted. Names and colors are applied
    /// later, so this calculation does not depend on a fixed category list.
    static func breakdown(of entries: [LedgerEntry], type: TransactionType, total: Decimal) -> [CategoryAmount] {
        var totals: [String: Decimal] = [:]
        for entry in entries where entry.type == type {
            totals[entry.categoryID, default: 0] += entry.amount
        }
        return totals.compactMap { categoryID, amount in
            guard amount > 0 else { return nil }
            let share = total > 0 ? (amount / total).doubleValue : 0
            return CategoryAmount(categoryID: categoryID, amount: amount, share: share)
        }
        .sorted { lhs, rhs in
            if lhs.amount == rhs.amount { return lhs.categoryID < rhs.categoryID }
            return lhs.amount > rhs.amount
        }
    }

    /// Lowest running gold balance across the given movements; negative means more was removed than held.
    static func lowestRunningBalance(of movements: [GoldPoint]) -> Decimal {
        var running = Decimal(0)
        var lowest = Decimal(0)
        for movement in movements.sorted(by: GoldPoint.chronological) {
            running += movement.value
            lowest = min(lowest, running)
        }
        return lowest
    }

    /// Relative change, or nil when the previous value is zero.
    static func percentChange(from previous: Decimal, to current: Decimal) -> Double? {
        guard previous != 0 else { return nil }
        return ((current - previous) / abs(previous)).doubleValue
    }
}
