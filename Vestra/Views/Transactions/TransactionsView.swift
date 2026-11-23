import SwiftData
import SwiftUI

struct TransactionsView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case month
        case year
        case all

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .month: "Month"
            case .year: "Year"
            case .all: "All"
            }
        }
    }

    enum EditorRoute: Identifiable {
        case new(TransactionType, Date)
        case edit(FinanceTransaction)

        var id: String {
            switch self {
            case let .new(type, _): "new-\(type.rawValue)"
            case let .edit(transaction): "edit-\(transaction.id)"
            }
        }
    }

    /// Sorted newest first (date, then creation time).
    let transactions: [FinanceTransaction]
    let catalog: CategoryCatalog

    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @State private var scope: Scope = .month
    @State private var period = ReportPeriod.containing(.now, kind: .month)
    @State private var typeFilter: TransactionType?
    @State private var newestFirst = true
    @State private var editor: EditorRoute?

    private var filtered: [FinanceTransaction] {
        let matching = transactions.filter { transaction in
            (scope == .all || period.contains(transaction.date))
                && (typeFilter == nil || transaction.type == typeFilter)
        }
        return newestFirst ? matching : matching.reversed()
    }

    private func dayGroups(_ items: [FinanceTransaction]) -> [(day: Date, items: [FinanceTransaction])] {
        let calendar = Calendar.app
        var groups: [(day: Date, items: [FinanceTransaction])] = []
        for transaction in items {
            let day = calendar.startOfDay(for: transaction.date)
            if groups.last?.day == day {
                groups[groups.count - 1].items.append(transaction)
            } else {
                groups.append((day, [transaction]))
            }
        }
        return groups
    }

    /// New entries default to the period being viewed, so past months can be filled in directly.
    private var defaultDateForNewEntry: Date {
        guard scope != .all, !period.contains(.now) else { return .now }
        let start = period.interval().start
        return Calendar.app.date(byAdding: .hour, value: 12, to: start) ?? start
    }

    var body: some View {
        let items = filtered
        let income = items.reduce(Decimal(0)) { $1.type == .income ? $0 + $1.amount : $0 }
        let expense = items.reduce(Decimal(0)) { $1.type == .expense ? $0 + $1.amount : $0 }

        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $scope) {
                        ForEach(Scope.allCases) { scope in
                            Text(scope.titleKey).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    if scope != .all {
                        PeriodNavigator(period: $period)
                    }
                    PeriodSummaryRow(income: income, expense: expense)
                        .padding(.vertical, 4)
                }

                if items.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label("No Transactions", systemImage: "tray")
                        } description: {
                            Text("Tap + to add an income or expense. You can choose any past date.")
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(dayGroups(items), id: \.day) { group in
                        Section {
                            ForEach(group.items) { transaction in
                                Button {
                                    editor = .edit(transaction)
                                } label: {
                                    TransactionRow(transaction: transaction, catalog: catalog, showsDate: false)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        delete(transaction)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        editor = .edit(transaction)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(Theme.accent)
                                }
                            }
                        } header: {
                            Text(group.day, format: .dateTime.weekday(.wide).day().month(.wide).year().locale(locale))
                        }
                    }
                }
            }
            .screenBackground()
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Type", selection: $typeFilter) {
                            Text("All Types").tag(TransactionType?.none)
                            Text("Income").tag(TransactionType?.some(.income))
                            Text("Expenses").tag(TransactionType?.some(.expense))
                        }
                        Picker("Sort", selection: $newestFirst) {
                            Label("Newest First", systemImage: "arrow.down").tag(true)
                            Label("Oldest First", systemImage: "arrow.up").tag(false)
                        }
                    } label: {
                        Image(systemName: typeFilter == nil && newestFirst
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel(Text("Filter and Sort"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editor = .new(.income, defaultDateForNewEntry)
                        } label: {
                            Label("Add Income", systemImage: "arrow.down.left")
                        }
                        Button {
                            editor = .new(.expense, defaultDateForNewEntry)
                        } label: {
                            Label("Add Expense", systemImage: "arrow.up.right")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityLabel(Text("Add Transaction"))
                }
            }
            .onChange(of: scope) { _, newScope in
                if newScope != .all {
                    period = period.converted(to: newScope == .year ? .year : .month)
                }
            }
            .sheet(item: $editor) { route in
                switch route {
                case let .new(type, date):
                    TransactionEditorView(mode: .new(type: type, date: date))
                case let .edit(transaction):
                    TransactionEditorView(mode: .edit(transaction))
                }
            }
        }
    }

    private func delete(_ transaction: FinanceTransaction) {
        context.delete(transaction)
        try? context.save()
    }
}
