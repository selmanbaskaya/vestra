import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case transactions
    case statistics
    case settings
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\FinanceTransaction.date, order: .reverse), SortDescriptor(\FinanceTransaction.createdAt, order: .reverse)])
    private var transactions: [FinanceTransaction]
    @Query private var goldPrices: [GoldPriceRecord]
    @Query private var goldMovements: [GoldMovement]
    @Query private var profiles: [WalletProfile]
    @Query(sort: [SortDescriptor(\FinanceCategory.sortOrder), SortDescriptor(\FinanceCategory.createdAt)])
    private var storedCategories: [FinanceCategory]
    @State private var selection: AppTab = .dashboard

    private var catalog: CategoryCatalog {
        CategoryCatalog(storedCategories.map(\.info))
    }

    private var ledger: FinanceLedger {
        FinanceLedger(
            openingBalance: profiles.first?.openingBalance ?? 0,
            entries: transactions.map(\.ledgerEntry),
            goldPrices: goldPrices.map(\.point),
            goldMovements: goldMovements.map(\.point)
        )
    }

    var body: some View {
        let ledger = ledger
        TabView(selection: $selection) {
            DashboardView(ledger: ledger, transactions: transactions, catalog: catalog, selectedTab: $selection)
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
                .tag(AppTab.dashboard)

            TransactionsView(transactions: transactions, catalog: catalog)
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle.portrait.fill") }
                .tag(AppTab.transactions)

            StatisticsView(ledger: ledger, catalog: catalog)
                .tabItem { Label("Statistics", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.statistics)

            SettingsView(ledger: ledger)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .onAppear { try? CategoryStore.ensureDefaults(in: context) }
        #if DEBUG
        .task { DebugSupport.seedDemoDataIfRequested(in: context) }
        #endif
    }
}
