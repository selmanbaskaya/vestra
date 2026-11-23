import SwiftUI

struct StatisticsView: View {
    let ledger: FinanceLedger
    let catalog: CategoryCatalog

    @Environment(\.locale) private var locale
    @State private var kind: PeriodKind = .month
    @State private var period = ReportPeriod.containing(.now, kind: .month)

    var body: some View {
        let summary = ledger.summary(for: period)
        let previous = ledger.summary(for: period.previous)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("View", selection: $kind) {
                        Text("Monthly").tag(PeriodKind.month)
                        Text("Yearly").tag(PeriodKind.year)
                    }
                    .pickerStyle(.segmented)

                    Card(padding: 8) {
                        PeriodNavigator(period: $period)
                    }

                    resultCard(summary)
                    comparisonCard(summary, previous)

                    if kind == .month {
                        monthlyCharts(summary, previous)
                    } else {
                        yearlyCharts(summary)
                    }

                    breakdownCard(titleKey: "Expenses by Category", items: summary.expenseByCategory, total: summary.expense, showsChart: true)
                    breakdownCard(titleKey: "Income by Category", items: summary.incomeByCategory, total: summary.income, showsChart: false)
                    NetWorthCard(summary: summary, previous: previous)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Statistics")
            .onChange(of: kind) { _, newKind in
                period = period.converted(to: newKind)
            }
        }
    }

    private func resultCard(_ summary: PeriodSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Net Result")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(verbatim: summary.net.currencyText(locale, signed: true))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.signColor(summary.net))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                HStack(spacing: 12) {
                    MetricColumn(titleKey: kind == .month ? "Total Income" : "Annual Income", value: summary.income, color: Theme.income)
                    MetricColumn(titleKey: kind == .month ? "Total Expenses" : "Annual Expenses", value: summary.expense, color: summary.expense == 0 ? .primary : Theme.expense)
                }
                Text("\(summary.transactionCount) transactions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func comparisonCard(_ summary: PeriodSummary, _ previous: PeriodSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(kind == .month ? "Compared with Previous Month" : "Compared with Previous Year")
                Text(verbatim: previous.period.title(locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, -10)
                ComparisonRow(titleKey: "Income", current: summary.income, previous: previous.income, higherIsBetter: true)
                Divider()
                ComparisonRow(titleKey: "Expenses", current: summary.expense, previous: previous.expense, higherIsBetter: false)
                Divider()
                ComparisonRow(titleKey: "Net Result", current: summary.net, previous: previous.net, higherIsBetter: true)
            }
        }
    }

    @ViewBuilder
    private func monthlyCharts(_ summary: PeriodSummary, _ previous: PeriodSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader("Income vs. Expenses")
                IncomeExpenseChart(points: ledger.monthlyPoints(endingAt: period, count: 2))
            }
        }
        let trend = ledger.monthlyPoints(endingAt: period, count: 6)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader("Monthly Net Result")
                Text("Last 6 months")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, -8)
                NetResultChart(points: trend)
                MonthValuesList(points: trend)
            }
        }
    }

    @ViewBuilder
    private func yearlyCharts(_ summary: PeriodSummary) -> some View {
        let months = ledger.monthlyPoints(year: period.year)
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader("Monthly Income and Expenses")
                IncomeExpenseChart(points: months)
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader("Monthly Net Result")
                NetResultChart(points: months)
                MonthValuesList(points: months.filter { $0.income != 0 || $0.expense != 0 })
            }
        }
    }

    private func breakdownCard(titleKey: LocalizedStringKey, items: [CategoryAmount], total: Decimal, showsChart: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(titleKey)
                if items.isEmpty {
                    Text("No records in this period.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    if showsChart {
                        CategoryDonutChart(items: items, catalog: catalog, total: total)
                    }
                    CategoryBreakdownList(items: items, catalog: catalog)
                }
            }
        }
    }
}

private struct ComparisonRow: View {
    let titleKey: LocalizedStringKey
    let current: Decimal
    let previous: Decimal
    let higherIsBetter: Bool
    @Environment(\.locale) private var locale

    var body: some View {
        let change = current - previous
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(titleKey)
                    .font(.subheadline)
                Spacer()
                Text(verbatim: current.currencyText(locale))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            HStack {
                Text("Previous: \(previous.currencyText(locale))")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: changeText(change))
                    .foregroundStyle(changeColor(change))
                    .monospacedDigit()
            }
            .font(.caption)
        }
    }

    private func changeText(_ change: Decimal) -> String {
        let amount = change.currencyText(locale, signed: true)
        guard let percent = FinanceLedger.percentChange(from: previous, to: current) else { return amount }
        return "\(amount) (\(percent.percentText(locale, signed: true)))"
    }

    private func changeColor(_ change: Decimal) -> Color {
        guard change != 0 else { return .secondary }
        return (change > 0) == higherIsBetter ? Theme.income : Theme.expense
    }
}

/// Exact monthly figures shown under the trend charts.
private struct MonthValuesList: View {
    let points: [MonthPoint]
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 10) {
            ForEach(points) { point in
                VStack(spacing: 3) {
                    HStack {
                        Text(verbatim: point.period.title(locale: locale))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(verbatim: point.net.currencyText(locale, signed: true))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.signColor(point.net))
                    }
                    HStack(spacing: 14) {
                        Label { Text(verbatim: point.income.currencyText(locale)) } icon: {
                            Image(systemName: "arrow.down.left").foregroundStyle(Theme.income)
                        }
                        Label { Text(verbatim: point.expense.currencyText(locale)) } icon: {
                            Image(systemName: "arrow.up.right").foregroundStyle(Theme.expense)
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .monospacedDigit()
            }
        }
        .padding(.top, 4)
    }
}

/// Period-end net worth, valued with the gold price recorded on or before the period's end.
private struct NetWorthCard: View {
    let summary: PeriodSummary
    let previous: PeriodSummary
    @Environment(\.locale) private var locale

    var body: some View {
        let closing = summary.closing
        let change = closing.total - previous.closing.total
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(titleKey: "Net Worth at Period End") {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
                row("TL Balance", closing.tlBalance.currencyText(locale))
                row("Gold Quantity", closing.goldGrams.gramsText(locale))
                if let price = closing.goldPrice, let date = closing.goldPriceDate {
                    row("Gold Price Used", price.currencyText(locale))
                    Text("Recorded on \(date.formatted(.dateTime.day().month(.wide).year().locale(locale)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No gold price recorded for this period.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                row("Gold Value", closing.goldValue.currencyText(locale))
                Divider()
                HStack {
                    Text("Total Balance").font(.headline)
                    Spacer()
                    Text(verbatim: closing.total.currencyText(locale))
                        .font(.headline)
                        .monospacedDigit()
                }
                HStack {
                    Text("Change since previous period end")
                    Spacer()
                    Text(verbatim: change.currencyText(locale, signed: true))
                        .foregroundStyle(Theme.signColor(change))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func row(_ titleKey: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(titleKey).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.subheadline)
    }
}
