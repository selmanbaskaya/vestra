import SwiftData
import SwiftUI

struct GoldPriceEditorView: View {
    let ledger: FinanceLedger
    var record: GoldPriceRecord?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var priceText = ""
    @State private var date: Date
    @State private var didLoad = false
    @State private var showingSaveError = false

    init(ledger: FinanceLedger, record: GoldPriceRecord? = nil) {
        self.ledger = ledger
        self.record = record
        _date = State(initialValue: record?.date ?? .now)
    }

    private var parsedPrice: Decimal? {
        guard let value = DecimalInput.parse(priceText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(text: $priceText, prompt: Text(verbatim: "0")) {
                            Text("Selling Price per Gram")
                        }
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("goldPriceField")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        Text(verbatim: "₺ / g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Selling Price per Gram")
                } footer: {
                    Text("Updating the gold price never creates an income or expense.")
                }

                Section {
                    DatePicker("Price Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("Each price is saved with its date. Reports for past periods keep using the price recorded for that time.")
                }

                if let price = parsedPrice {
                    let grams = ledger.goldGrams(before: ledger.endOfDay(date))
                    Section("Preview") {
                        LabeledContent("Gold Quantity", value: grams.gramsText(locale))
                        LabeledContent("Gold Value", value: (grams * price).rounded(scale: 2).currencyText(locale))
                    }
                }
            }
            .screenBackground()
            .navigationTitle(record == nil ? Text("Update Gold Price") : Text("Edit Gold Price"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(parsedPrice == nil)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if let price = record?.pricePerGram ?? ledger.current.goldPrice {
                    priceText = DecimalInput.editingString(price, locale: locale)
                }
            }
            .alert("Could not save. Please try again.", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard let price = parsedPrice else { return }
        do {
            if let record {
                record.pricePerGram = price
                record.date = date
                try context.save()
            } else {
                try FinanceStore.recordGoldPrice(price, on: date, in: context)
            }
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}

struct GoldMovementEditorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case add
        case remove
        case setTotal

        var id: String { rawValue }

        var titleKey: LocalizedStringKey {
            switch self {
            case .add: "Add"
            case .remove: "Remove"
            case .setTotal: "Set Total"
            }
        }
    }

    let ledger: FinanceLedger
    var movement: GoldMovement?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var mode: Mode
    @State private var gramsText = ""
    @State private var date: Date
    @State private var note: String
    @State private var didLoad = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSaveError = false

    init(ledger: FinanceLedger, movement: GoldMovement? = nil) {
        self.ledger = ledger
        self.movement = movement
        _mode = State(initialValue: (movement?.grams ?? 0) < 0 ? .remove : .add)
        _date = State(initialValue: movement?.date ?? .now)
        _note = State(initialValue: movement?.note ?? "")
    }

    /// Other movements, i.e. everything except the one being edited.
    private var otherMovements: [GoldPoint] {
        ledger.goldMovements.filter { $0.id != movement?.id }
    }

    private var quantityBefore: Decimal {
        let end = ledger.endOfDay(date)
        return otherMovements.reduce(Decimal(0)) { $1.date < end ? $0 + $1.value : $0 }
    }

    private var delta: Decimal? {
        guard let grams = DecimalInput.parse(gramsText) else { return nil }
        switch mode {
        case .add: return grams > 0 ? grams : nil
        case .remove: return grams > 0 ? -grams : nil
        case .setTotal:
            let change = grams - quantityBefore
            return change != 0 ? change : nil
        }
    }

    private var keepsHoldingsNonNegative: Bool {
        guard let delta else { return true }
        let updated = otherMovements + [GoldPoint(date: date, value: delta, createdAt: movement?.createdAt ?? .now)]
        return FinanceLedger.lowestRunningBalance(of: updated) >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Change", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.titleKey).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    HStack {
                        TextField(text: $gramsText, prompt: Text(verbatim: "0")) {
                            Text("Grams")
                        }
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("gramsField")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        Text(verbatim: "g")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    switch mode {
                    case .add: Text("Grams Added")
                    case .remove: Text("Grams Removed")
                    case .setTotal: Text("New Total Quantity")
                    }
                } footer: {
                    if !keepsHoldingsNonNegative {
                        Text("Gold quantity cannot be negative.")
                            .foregroundStyle(Theme.expense)
                    }
                }

                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    TextField("Note (optional)", text: $note)
                }

                Section("Summary") {
                    LabeledContent("Quantity Before", value: quantityBefore.gramsText(locale))
                    LabeledContent("Quantity After", value: (quantityBefore + (delta ?? 0)).gramsText(locale))
                }

                if movement != nil {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Text("Delete Record")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .screenBackground()
            .navigationTitle(movement == nil ? Text("Update Gold Quantity") : Text("Edit Gold Record"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(delta == nil || !keepsHoldingsNonNegative)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if let movement {
                    gramsText = DecimalInput.editingString(abs(movement.grams), locale: locale)
                }
            }
            .confirmationDialog("Delete this record?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
            .alert("Could not save. Please try again.", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard let delta else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if let movement {
            movement.grams = delta
            movement.date = date
            movement.note = trimmedNote
        } else {
            context.insert(GoldMovement(grams: delta, date: date, note: trimmedNote))
        }
        do {
            try context.save()
            dismiss()
        } catch {
            showingSaveError = true
        }
    }

    private func delete() {
        guard let movement else { return }
        context.delete(movement)
        do {
            try context.save()
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}

struct OpeningBalanceEditorView: View {
    let ledger: FinanceLedger

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var amountText = ""
    @State private var didLoad = false
    @State private var showingSaveError = false

    private var parsedAmount: Decimal? {
        amountText.isEmpty ? 0 : DecimalInput.parse(amountText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Text(verbatim: "₺")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        TextField(text: $amountText, prompt: Text(verbatim: "0")) {
                            Text("Opening TL Balance")
                        }
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("openingBalanceField")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    }
                } header: {
                    Text("Opening TL Balance")
                } footer: {
                    Text("Your TL balance is the opening balance plus all income minus all expenses.")
                }

                if let opening = parsedAmount {
                    Section {
                        LabeledContent("Resulting TL Balance") {
                            Text(verbatim: (opening + ledger.current.tlBalance - ledger.openingBalance).currencyText(locale))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .screenBackground()
            .navigationTitle(Text("Opening TL Balance"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(parsedAmount == nil)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                if ledger.openingBalance != 0 {
                    amountText = DecimalInput.editingString(ledger.openingBalance, locale: locale)
                }
            }
            .alert("Could not save. Please try again.", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func save() {
        guard let amount = parsedAmount else { return }
        do {
            try FinanceStore.setOpeningBalance(amount, in: context)
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}
