import Charts
import SwiftUI

/// Grouped income vs. expense bars, one group per month.
struct IncomeExpenseChart: View {
    let points: [MonthPoint]
    @Environment(\.locale) private var locale

    private struct Bar: Identifiable {
        let id: String
        let label: String
        let series: String
        let value: Double
    }

    var body: some View {
        let incomeName = locale.localized("Income")
        let expenseName = locale.localized("Expenses")
        let bars = points.flatMap { point -> [Bar] in
            let label = point.period.shortMonthTitle(locale: locale)
            return [
                Bar(id: point.id + "-i", label: label, series: incomeName, value: point.income.doubleValue),
                Bar(id: point.id + "-e", label: label, series: expenseName, value: point.expense.doubleValue),
            ]
        }

        Chart(bars) { bar in
            BarMark(
                x: .value("Month", bar.label),
                y: .value("Amount", bar.value)
            )
            .foregroundStyle(by: .value("Type", bar.series))
            .position(by: .value("Type", bar.series))
            .cornerRadius(3)
        }
        .chartForegroundStyleScale(domain: [incomeName, expenseName], range: [Theme.income, Theme.expense])
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxis { compactAxis(locale) }
        .frame(height: 220)
    }
}

/// Monthly net result bars: green above zero, red below.
struct NetResultChart: View {
    let points: [MonthPoint]
    @Environment(\.locale) private var locale

    var body: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Month", point.period.shortMonthTitle(locale: locale)),
                    y: .value("Net", point.net.doubleValue)
                )
                .foregroundStyle(point.net >= 0 ? Theme.income : Theme.expense)
                .cornerRadius(3)
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYAxis { compactAxis(locale) }
        .frame(height: 200)
    }
}

/// Donut chart of category shares with the period total in the centre.
struct CategoryDonutChart: View {
    let items: [CategoryAmount]
    let catalog: CategoryCatalog
    let total: Decimal
    @Environment(\.locale) private var locale

    var body: some View {
        Chart(items) { item in
            SectorMark(
                angle: .value("Amount", item.amount.doubleValue),
                innerRadius: .ratio(0.64),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(catalog.info(for: item.categoryID).color)
        }
        .chartLegend(.hidden)
        .frame(height: 200)
        .overlay {
            VStack(spacing: 2) {
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: total.currencyText(locale, fractionDigits: 0))
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: 120)
        }
    }
}

/// Exact values for each category, shown alongside the charts.
struct CategoryBreakdownList: View {
    let items: [CategoryAmount]
    let catalog: CategoryCatalog
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 12) {
            ForEach(items) { item in
                let info = catalog.info(for: item.categoryID)
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: info.symbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(info.color)
                            .frame(width: 18)
                        Text(verbatim: info.displayName(in: locale))
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                        Text(verbatim: item.share.percentText(locale))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(verbatim: item.amount.currencyText(locale))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceMuted)
                            Capsule().fill(info.color)
                                .frame(width: max(4, proxy.size.width * item.share))
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
    }
}

private func compactAxis(_ locale: Locale) -> some AxisContent {
    AxisMarks(position: .leading) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
        AxisValueLabel {
            if let number = value.as(Double.self) {
                Text(verbatim: number.compactText(locale))
            }
        }
    }
}
