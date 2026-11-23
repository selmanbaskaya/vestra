import SwiftUI

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

struct CardHeader<Trailing: View>: View {
    let titleKey: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titleKey)
                .font(.headline)
            Spacer()
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(_ titleKey: LocalizedStringKey) {
        self.init(titleKey: titleKey) { EmptyView() }
    }
}

/// The Vestra brand mark: a folded geometric "V" on an ink tile (same geometry as the app icon).
struct VestraMark: View {
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(Theme.brandInk)
            VestraVShape(arm: .right)
                .fill(Theme.brandDeep)
            VestraVShape(arm: .left)
                .fill(Theme.brandLight)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct VestraVShape: Shape {
    enum Arm { case left, right }
    let arm: Arm

    func path(in rect: CGRect) -> Path {
        let points: [CGPoint] = switch arm {
        case .left: [CGPoint(x: 0.22, y: 0.27), CGPoint(x: 0.38, y: 0.27), CGPoint(x: 0.58, y: 0.75), CGPoint(x: 0.42, y: 0.75)]
        case .right: [CGPoint(x: 0.62, y: 0.27), CGPoint(x: 0.78, y: 0.27), CGPoint(x: 0.58, y: 0.75), CGPoint(x: 0.42, y: 0.75)]
        }
        var path = Path()
        path.addLines(points.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
        path.closeSubpath()
        return path
    }
}

struct CategoryIcon: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct TransactionRow: View {
    let transaction: FinanceTransaction
    let catalog: CategoryCatalog
    var showsDate = true
    @Environment(\.locale) private var locale

    private var category: CategoryInfo {
        catalog.info(for: transaction.categoryID, type: transaction.type)
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(symbol: category.symbol, color: category.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: category.displayName(in: locale))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: signedAmount.currencyText(locale, signed: true))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(transaction.type == .income ? Theme.income : Color.primary)
        }
        .contentShape(Rectangle())
    }

    private var signedAmount: Decimal {
        transaction.type == .income ? transaction.amount : -transaction.amount
    }

    private var subtitle: String? {
        let note = transaction.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = showsDate ? transaction.date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)) : nil
        let parts = [date, note.isEmpty ? nil : note].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Small labelled figure used in summary rows (income / expenses / net).
struct MetricColumn: View {
    let titleKey: LocalizedStringKey
    let value: Decimal
    var color: Color = .primary
    var signed = false
    var alignment: HorizontalAlignment = .leading
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(titleKey)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value.currencyText(locale, signed: signed))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
    }
}

struct PeriodSummaryRow: View {
    let income: Decimal
    let expense: Decimal

    var body: some View {
        HStack(spacing: 12) {
            MetricColumn(titleKey: "Income", value: income, color: Theme.income)
            MetricColumn(titleKey: "Expenses", value: expense, color: income == 0 && expense == 0 ? .primary : Theme.expense)
            MetricColumn(titleKey: "Net", value: income - expense, color: Theme.signColor(income - expense), signed: true, alignment: .trailing)
        }
    }
}

struct PeriodNavigator: View {
    @Binding var period: ReportPeriod
    @Environment(\.locale) private var locale
    @State private var showingPicker = false

    var body: some View {
        HStack {
            Button {
                period = period.previous
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 36)
            }
            .accessibilityLabel(Text("Previous Period"))

            Spacer()

            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: period.title(locale: locale))
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.primary)
            }

            Spacer()

            Button {
                period = period.next
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 36)
            }
            .disabled(!period.next.hasStarted())
            .accessibilityLabel(Text("Next Period"))
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $showingPicker) {
            PeriodPickerSheet(period: $period)
                .presentationDetents([.height(340)])
        }
    }
}

struct PeriodPickerSheet: View {
    @Binding var period: ReportPeriod
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var month: Int
    @State private var year: Int

    private let years: [Int] = Array(2000...ReportPeriod.containing(.now, kind: .year).year)

    init(period: Binding<ReportPeriod>) {
        _period = period
        _month = State(initialValue: period.wrappedValue.month)
        _year = State(initialValue: period.wrappedValue.year)
    }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                if period.kind == .month {
                    Picker("Month", selection: $month) {
                        ForEach(1...12, id: \.self) { month in
                            Text(verbatim: ReportPeriod.monthName(month, locale: locale)).tag(month)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { year in
                        Text(verbatim: String(year)).tag(year)
                    }
                }
                .pickerStyle(.wheel)
            }
            .padding(.horizontal)
            .navigationTitle(period.kind == .month ? Text("Select Month") : Text("Select Year"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let selected = ReportPeriod(kind: period.kind, year: year, month: month)
                        period = selected.hasStarted() ? selected : .containing(.now, kind: period.kind)
                        dismiss()
                    }
                }
            }
        }
    }
}

extension View {
    func screenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}
