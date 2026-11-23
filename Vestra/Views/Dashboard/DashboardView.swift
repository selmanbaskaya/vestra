import SwiftUI

struct DashboardView: View {
    let ledger: FinanceLedger
    let transactions: [FinanceTransaction]
    let catalog: CategoryCatalog
    @Binding var selectedTab: AppTab

    @Environment(\.locale) private var locale
    @State private var sheet: DashboardSheet?

    enum DashboardSheet: Identifiable {
        case newTransaction(TransactionType)
        case edit(FinanceTransaction)
        case goldPrice
        case goldQuantity
        case openingBalance

        var id: String {
            switch self {
            case let .newTransaction(type): "new-\(type.rawValue)"
            case let .edit(transaction): "edit-\(transaction.id)"
            case .goldPrice: "gold-price"
            case .goldQuantity: "gold-quantity"
            case .openingBalance: "opening-balance"
            }
        }
    }

    var body: some View {
        let current = ledger.current
        let thisMonth = ledger.summary(for: .containing(.now, kind: .month))

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                TotalBalanceCard(snapshot: current)
                quickActions
                tlCard(current)
                GoldCard(
                    snapshot: current,
                    onUpdatePrice: { sheet = .goldPrice },
                    onUpdateQuantity: { sheet = .goldQuantity }
                )
                monthCard(thisMonth)
                recentCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case let .newTransaction(type):
                TransactionEditorView(mode: .new(type: type, date: .now))
            case let .edit(transaction):
                TransactionEditorView(mode: .edit(transaction))
            case .goldPrice:
                GoldPriceEditorView(ledger: ledger)
            case .goldQuantity:
                GoldMovementEditorView(ledger: ledger)
            case .openingBalance:
                OpeningBalanceEditorView(ledger: ledger)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VestraMark(size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "Vestra")
                    .font(.title2.weight(.semibold))
                Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide).locale(locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.top, 4)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            QuickActionButton(titleKey: "Add Income", symbol: "arrow.down.left", color: Theme.income) {
                sheet = .newTransaction(.income)
            }
            QuickActionButton(titleKey: "Add Expense", symbol: "arrow.up.right", color: Theme.expense) {
                sheet = .newTransaction(.expense)
            }
        }
    }

    private func tlCard(_ snapshot: WealthSnapshot) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(titleKey: "TL Balance") {
                    Button {
                        sheet = .openingBalance
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel(Text("Opening TL Balance"))
                }
                Text(verbatim: snapshot.tlBalance.currencyText(locale))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.tlBalance < 0 ? Theme.expense : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("tlBalanceValue")
                Text("Opening balance: \(ledger.openingBalance.currencyText(locale))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func monthCard(_ summary: PeriodSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(titleKey: "This Month") {
                    Text(verbatim: summary.period.title(locale: locale))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                PeriodSummaryRow(income: summary.income, expense: summary.expense)
            }
        }
    }

    private var recentCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(titleKey: "Recent Transactions") {
                    if !transactions.isEmpty {
                        Button("See All") { selectedTab = .transactions }
                            .font(.subheadline.weight(.medium))
                    }
                }
                if transactions.isEmpty {
                    Text("No transactions yet. Add your first income or expense.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(Array(transactions.prefix(5).enumerated()), id: \.element.id) { index, transaction in
                        if index > 0 { Divider() }
                        Button {
                            sheet = .edit(transaction)
                        } label: {
                            TransactionRow(transaction: transaction, catalog: catalog)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct TotalBalanceCard: View {
    let snapshot: WealthSnapshot
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Total Balance")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.heroSecondaryText)
            Text(verbatim: snapshot.total.currencyText(locale))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("totalBalanceValue")

            if showsComposition {
                composition
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Theme.hero, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private var showsComposition: Bool {
        snapshot.tlBalance >= 0 && snapshot.goldValue >= 0 && snapshot.total > 0
    }

    private var tlShare: Double {
        (snapshot.tlBalance / snapshot.total).doubleValue
    }

    private var composition: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    if tlShare > 0 {
                        Capsule().fill(Theme.heroCash)
                            .frame(width: max(4, proxy.size.width * tlShare - 1.5))
                    }
                    if tlShare < 1 {
                        Capsule().fill(Theme.heroGold)
                    }
                }
            }
            .frame(height: 6)

            HStack(spacing: 16) {
                legend(color: Theme.heroCash, titleKey: "TL", share: tlShare)
                legend(color: Theme.heroGold, titleKey: "Gold", share: 1 - tlShare)
                Spacer()
            }
        }
    }

    private func legend(color: Color, titleKey: LocalizedStringKey, share: Double) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(titleKey)
                .foregroundStyle(Theme.heroSecondaryText)
            Text(verbatim: share.percentText(locale))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .font(.caption.weight(.medium))
    }
}

private struct GoldCard: View {
    let snapshot: WealthSnapshot
    let onUpdatePrice: () -> Void
    let onUpdateQuantity: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(titleKey: "Gold Balance") {
                    Image(systemName: "diamond.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.gold)
                }

                Text(verbatim: snapshot.goldGrams.gramsText(locale))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityIdentifier("goldGramsValue")

                VStack(spacing: 10) {
                    row("Selling Price / g") {
                        if let price = snapshot.goldPrice {
                            Text(verbatim: price.currencyText(locale))
                        } else {
                            Text("Not set").foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                    row("Gold Value") {
                        Text(verbatim: snapshot.goldValue.currencyText(locale))
                            .foregroundStyle(Theme.gold)
                            .accessibilityIdentifier("goldValue")
                    }
                }
                .font(.subheadline)

                if let date = snapshot.goldPriceDate {
                    Text("Price recorded on \(date.formatted(.dateTime.day().month(.wide).year().locale(locale)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enter the current selling price per gram to value your gold.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button(action: onUpdatePrice) {
                        Label("Update Price", systemImage: "tag")
                            .frame(maxWidth: .infinity)
                    }
                    Button(action: onUpdateQuantity) {
                        Label("Update Quantity", systemImage: "scalemass")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleOnly)
            }
        }
    }

    private func row<Value: View>(_ titleKey: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        HStack {
            Text(titleKey).foregroundStyle(.secondary)
            Spacer()
            value()
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

private struct QuickActionButton: View {
    let titleKey: LocalizedStringKey
    let symbol: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
