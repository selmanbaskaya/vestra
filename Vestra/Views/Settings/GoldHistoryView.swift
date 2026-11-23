import Charts
import SwiftData
import SwiftUI

struct GoldHistoryView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case prices
        case quantity
        var id: String { rawValue }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Query(sort: [SortDescriptor(\GoldPriceRecord.date, order: .reverse), SortDescriptor(\GoldPriceRecord.createdAt, order: .reverse)])
    private var prices: [GoldPriceRecord]
    @Query(sort: [SortDescriptor(\GoldMovement.date, order: .reverse), SortDescriptor(\GoldMovement.createdAt, order: .reverse)])
    private var movements: [GoldMovement]

    @State private var tab: Tab = .prices
    @State private var editingPrice: GoldPriceRecord?
    @State private var editingMovement: GoldMovement?
    @State private var addingPrice = false
    @State private var addingMovement = false

    private var ledger: FinanceLedger {
        FinanceLedger(goldPrices: prices.map(\.point), goldMovements: movements.map(\.point))
    }

    var body: some View {
        let ledger = ledger
        List {
            Section {
                Picker("History", selection: $tab) {
                    Text("Prices").tag(Tab.prices)
                    Text("Quantity").tag(Tab.quantity)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if tab == .prices {
                pricesSection(ledger)
            } else {
                movementsSection(ledger)
            }
        }
        .screenBackground()
        .navigationTitle("Gold History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if tab == .prices { addingPrice = true } else { addingMovement = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Add Record"))
            }
        }
        .sheet(item: $editingPrice) { GoldPriceEditorView(ledger: ledger, record: $0) }
        .sheet(item: $editingMovement) { GoldMovementEditorView(ledger: ledger, movement: $0) }
        .sheet(isPresented: $addingPrice) { GoldPriceEditorView(ledger: ledger) }
        .sheet(isPresented: $addingMovement) { GoldMovementEditorView(ledger: ledger) }
    }

    @ViewBuilder
    private func pricesSection(_ ledger: FinanceLedger) -> some View {
        if prices.count >= 2 {
            Section {
                Chart(prices) { record in
                    LineMark(x: .value("Date", record.date), y: .value("Price", record.pricePerGram.doubleValue))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.gold)
                    PointMark(x: .value("Date", record.date), y: .value("Price", record.pricePerGram.doubleValue))
                        .foregroundStyle(Theme.gold)
                        .symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        AxisValueLabel {
                            if let number = value.as(Double.self) { Text(verbatim: number.compactText(locale)) }
                        }
                    }
                }
                .frame(height: 180)
                .padding(.vertical, 8)
            }
        }

        Section {
            if prices.isEmpty {
                Text("No gold prices recorded yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(prices) { record in
                let grams = ledger.goldGrams(before: ledger.endOfDay(record.date))
                Button { editingPrice = record } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.date, format: .dateTime.day().month(.wide).year().locale(locale))
                                .font(.subheadline.weight(.medium))
                            Text("Holdings value: \((grams * record.pricePerGram).rounded(scale: 2).currencyText(locale)) (\(grams.gramsText(locale)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(record.pricePerGram.currencyText(locale)) / g")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                offsets.map { prices[$0] }.forEach(context.delete)
                try? context.save()
            }
        } footer: {
            Text("Each price is used for reports from its date until a newer price is recorded.")
        }
    }

    @ViewBuilder
    private func movementsSection(_ ledger: FinanceLedger) -> some View {
        let balances = runningBalances()
        Section {
            if movements.isEmpty {
                Text("No gold quantity changes recorded yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(movements) { movement in
                Button { editingMovement = movement } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(movement.date, format: .dateTime.day().month(.wide).year().locale(locale))
                                .font(.subheadline.weight(.medium))
                            Text("Total after: \((balances[movement.id] ?? 0).gramsText(locale))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !movement.note.isEmpty {
                                Text(verbatim: movement.note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(verbatim: movement.grams.gramsText(locale, signed: true))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(movement.grams >= 0 ? Theme.income : Theme.expense)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                let remaining = movements.enumerated().filter { !offsets.contains($0.offset) }.map(\.element.point)
                guard FinanceLedger.lowestRunningBalance(of: remaining) >= 0 else { return }
                offsets.map { movements[$0] }.forEach(context.delete)
                try? context.save()
            }
        } footer: {
            Text("Gold quantity changes never affect your TL balance.")
        }
    }

    private func runningBalances() -> [UUID: Decimal] {
        var running = Decimal(0)
        var result: [UUID: Decimal] = [:]
        for point in movements.map(\.point).sorted(by: GoldPoint.chronological) {
            running += point.value
            result[point.id] = running
        }
        return result
    }
}
