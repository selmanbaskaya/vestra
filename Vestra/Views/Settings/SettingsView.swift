import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let ledger: FinanceLedger

    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @AppStorage(AppPreferences.languageKey) private var language: AppLanguage = .english
    @AppStorage(AppPreferences.turkishEnabledKey) private var turkishEnabled = false
    @AppStorage(AppPreferences.appearanceKey) private var appearance: AppearanceMode = .system

    @State private var sheet: SettingsSheet?
    @State private var exportDocument: ExportDocument?
    @State private var exportContentType: UTType = .json
    @State private var exportFilename = ""
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingRestore: VestraBackup?
    @State private var showingDeleteConfirmation = false
    @State private var message: String?

    enum SettingsSheet: String, Identifiable {
        case openingBalance, goldPrice, goldQuantity
        var id: String { rawValue }
    }

    var body: some View {
        let current = ledger.current

        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        VestraMark(size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "Vestra")
                                .font(.title3.weight(.semibold))
                            Text("Personal Finance & Wealth Tracker")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    if turkishEnabled {
                        Picker("Language", selection: $language) {
                            Text(verbatim: AppLanguage.english.nativeName).tag(AppLanguage.english)
                            Text(verbatim: AppLanguage.turkish.nativeName).tag(AppLanguage.turkish)
                        }
                    } else {
                        LabeledContent("Language") {
                            Text(verbatim: AppLanguage.english.nativeName)
                        }
                    }
                    Toggle("Enable Turkish", isOn: $turkishEnabled)
                        .accessibilityIdentifier("turkishEnabledToggle")
                } header: {
                    Text("Language")
                } footer: {
                    Text("English is always available. Enable Turkish to use it as the application language.")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.titleKey).tag(mode)
                        }
                    }
                } header: {
                    Text("Appearance")
                }

                Section {
                    NavigationLink {
                        CategoryListView()
                    } label: {
                        Label("Categories", systemImage: "square.grid.2x2")
                    }
                }

                Section {
                    Button { sheet = .openingBalance } label: {
                        valueRow("Opening TL Balance", ledger.openingBalance.currencyText(locale))
                    }
                    LabeledContent("Current TL Balance") {
                        Text(verbatim: current.tlBalance.currencyText(locale)).monospacedDigit()
                    }
                } header: {
                    Text("TL Balance")
                }

                Section("Gold") {
                    Button { sheet = .goldPrice } label: {
                        valueRow("Selling Price / g", current.goldPrice?.currencyText(locale))
                    }
                    Button { sheet = .goldQuantity } label: {
                        valueRow("Gold Quantity", current.goldGrams.gramsText(locale))
                    }
                    NavigationLink {
                        GoldHistoryView()
                    } label: {
                        Label("Gold History", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section {
                    Button { exportBackup() } label: {
                        Label("Export Backup (JSON)", systemImage: "square.and.arrow.up")
                    }
                    Button { exportCSV() } label: {
                        Label("Export Transactions (CSV)", systemImage: "tablecells")
                    }
                    Button { showingImporter = true } label: {
                        Label("Restore from Backup", systemImage: "arrow.counterclockwise")
                    }
                    Button(role: .destructive) { showingDeleteConfirmation = true } label: {
                        Label("Delete All Data", systemImage: "trash")
                            .foregroundStyle(Theme.expense)
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("All data is stored only on this iPhone. Nothing is sent to any server.")
                }
                .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                    handleImport(result)
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .screenBackground()
            .navigationTitle("Settings")
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .openingBalance: OpeningBalanceEditorView(ledger: ledger)
                case .goldPrice: GoldPriceEditorView(ledger: ledger)
                case .goldQuantity: GoldMovementEditorView(ledger: ledger)
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportFilename
            ) { result in
                if case .failure = result { message = locale.localized("The file could not be exported.") }
            }
            .confirmationDialog(
                "Delete all data?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Data", role: .destructive, action: deleteAll)
            } message: {
                Text("All transactions, gold records and balances will be permanently removed. This cannot be undone.")
            }
            .confirmationDialog(
                "Restore this backup?",
                isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                titleVisibility: .visible,
                presenting: pendingRestore
            ) { backup in
                Button("Replace All Data", role: .destructive) { restore(backup) }
            } message: { backup in
                Text("Current data will be replaced with \(backup.transactions.count) transactions from \(backup.exportedAt.formatted(.dateTime.day().month(.wide).year().locale(locale))).")
            }
            .alert(
                Text(verbatim: message ?? ""),
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func valueRow(_ titleKey: LocalizedStringKey, _ value: String?) -> some View {
        HStack {
            Text(titleKey).foregroundStyle(Color.primary)
            Spacer()
            if let value {
                Text(verbatim: value)
                    .foregroundStyle(Color.secondary)
                    .monospacedDigit()
            } else {
                Text("Not set").foregroundStyle(Color.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var fileDateStamp: String {
        Date.now.formatted(.iso8601.year().month().day())
    }

    private func exportBackup() {
        do {
            exportDocument = ExportDocument(data: try BackupService.encode(BackupService.makeBackup(from: context)))
            exportContentType = .json
            exportFilename = "Vestra-Backup-\(fileDateStamp)"
            showingExporter = true
        } catch {
            message = locale.localized("The file could not be exported.")
        }
    }

    private func exportCSV() {
        do {
            exportDocument = ExportDocument(data: try BackupService.transactionsCSV(from: context))
            exportContentType = .commaSeparatedText
            exportFilename = "Vestra-Transactions-\(fileDateStamp)"
            showingExporter = true
        } catch {
            message = locale.localized("The file could not be exported.")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingRestore = try BackupService.decode(Data(contentsOf: url))
        } catch {
            message = locale.localized("This file is not a valid Vestra backup.")
        }
    }

    private func restore(_ backup: VestraBackup) {
        do {
            try BackupService.restore(backup, into: context)
            message = locale.localized("Backup restored.")
        } catch {
            message = locale.localized("The backup could not be restored.")
        }
        pendingRestore = nil
    }

    private func deleteAll() {
        do {
            try FinanceStore.deleteAllData(in: context)
            try CategoryStore.ensureDefaults(in: context)
        } catch {
            message = locale.localized("Could not save. Please try again.")
        }
    }
}
