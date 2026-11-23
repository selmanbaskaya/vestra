import Foundation

extension Calendar {
    static var app: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}

enum PeriodKind: String, CaseIterable, Identifiable {
    case month
    case year

    var id: String { rawValue }
}

/// A calendar month or year. `month` is kept for yearly periods so switching back restores it.
struct ReportPeriod: Hashable {
    var kind: PeriodKind
    var year: Int
    var month: Int

    init(kind: PeriodKind, year: Int, month: Int = 1) {
        self.kind = kind
        self.year = year
        self.month = min(max(month, 1), 12)
    }

    static func containing(_ date: Date, kind: PeriodKind, calendar: Calendar = .app) -> ReportPeriod {
        let components = calendar.dateComponents([.year, .month], from: date)
        return ReportPeriod(kind: kind, year: components.year ?? 2000, month: components.month ?? 1)
    }

    func interval(calendar: Calendar = .app) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: kind == .month ? month : 1, day: 1))!
        let end = calendar.date(byAdding: kind == .month ? .month : .year, value: 1, to: start)!
        return DateInterval(start: start, end: end)
    }

    /// Start-inclusive, end-exclusive (unlike `DateInterval.contains`).
    func contains(_ date: Date, calendar: Calendar = .app) -> Bool {
        let interval = interval(calendar: calendar)
        return date >= interval.start && date < interval.end
    }

    func shifted(by offset: Int) -> ReportPeriod {
        switch kind {
        case .year:
            return ReportPeriod(kind: .year, year: year + offset, month: month)
        case .month:
            let index = year * 12 + (month - 1) + offset
            return ReportPeriod(kind: .month, year: index / 12, month: index % 12 + 1)
        }
    }

    var previous: ReportPeriod { shifted(by: -1) }
    var next: ReportPeriod { shifted(by: 1) }

    func hasStarted(now: Date = .now, calendar: Calendar = .app) -> Bool {
        interval(calendar: calendar).start <= now
    }

    func converted(to newKind: PeriodKind, now: Date = .now, calendar: Calendar = .app) -> ReportPeriod {
        var result = ReportPeriod(kind: newKind, year: year, month: month)
        if !result.hasStarted(now: now, calendar: calendar) {
            result = .containing(now, kind: newKind, calendar: calendar)
        }
        return result
    }

    func title(locale: Locale, calendar: Calendar = .app) -> String {
        switch kind {
        case .year:
            return String(year)
        case .month:
            let start = interval(calendar: calendar).start
            return start.formatted(.dateTime.month(.wide).year().locale(locale))
        }
    }

    func shortMonthTitle(locale: Locale) -> String {
        Self.shortMonthName(month, locale: locale)
    }

    static func monthName(_ month: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.standaloneMonthSymbols[month - 1].localizedCapitalized
    }

    static func shortMonthName(_ month: Int, locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        return calendar.shortStandaloneMonthSymbols[month - 1].localizedCapitalized
    }
}
