import SwiftData
import SwiftUI

struct TransactionEditorView: View {
    enum Mode {
        case new(type: TransactionType, date: Date)
        case edit(FinanceTransaction)
    }

    let mode: Mode

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query(sort: [SortDescriptor(\FinanceCategory.sortOrder), SortDescriptor(\FinanceCategory.createdAt)])
    private var storedCategories: [FinanceCategory]

    @State private var type: TransactionType
    @State private var categoryID: String
    @State private var amountText = ""
    @State private var date: Date
    @State private var note: String
    @State private var didLoadAmount = false
    @State private var showingDeleteConfirmation = false
    @State private var showingSaveError = false
    @FocusState private var amountFocused: Bool

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case let .new(type, date):
            _type = State(initialValue: type)
            _categoryID = State(initialValue: "")
            _date = State(initialValue: min(date, .now))
            _note = State(initialValue: "")
        case let .edit(transaction):
            _type = State(initialValue: transaction.type)
            _categoryID = State(initialValue: transaction.categoryID)
            _date = State(initialValue: transaction.date)
            _note = State(initialValue: transaction.note)
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var title: Text {
        if isEditing { return Text("Edit Transaction") }
        return type == .income ? Text("New Income") : Text("New Expense")
    }

    private var catalog: CategoryCatalog {
        CategoryCatalog(storedCategories.map(\.info))
    }

    private var selectable: [CategoryInfo] {
        catalog.choices(for: type, selectedID: categoryID.isEmpty ? nil : categoryID)
    }

    private var selectedCategory: CategoryInfo? {
        selectable.first { $0.id == categoryID }
    }

    private var parsedAmount: Decimal? {
        guard let value = DecimalInput.parse(amountText), value > 0 else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                typeSection
                amountSection
                categorySection
                detailsSection
                if isEditing {
                    deleteSection
                }
            }
            .screenBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(parsedAmount == nil || selectedCategory == nil)
                }
            }
            .onChange(of: type) { _, _ in alignCategorySelection() }
            .onChange(of: categoryToken) { _, _ in alignCategorySelection() }
            .onAppear {
                alignCategorySelection()
                guard !didLoadAmount else { return }
                didLoadAmount = true
                if case let .edit(transaction) = mode {
                    amountText = DecimalInput.editingString(transaction.amount, locale: locale)
                } else {
                    amountFocused = true
                }
            }
            .confirmationDialog("Delete this transaction?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            } message: {
                Text("Balances and reports will be recalculated.")
            }
            .alert("Could not save. Please try again.", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $type) {
                ForEach(TransactionType.allCases) { type in
                    Text(LocalizedStringKey(type.titleKey)).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var amountSection: some View {
        Section {
            HStack(spacing: 8) {
                Text(verbatim: "₺")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                TextField(text: $amountText, prompt: Text(verbatim: "0")) {
                    Text("Amount")
                }
                .keyboardType(.decimalPad)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .focused($amountFocused)
                .accessibilityIdentifier("amountField")
            }
        } header: {
            Text("Amount")
        } footer: {
            if !amountText.isEmpty && parsedAmount == nil {
                Text("Enter a valid amount greater than zero.")
                    .foregroundStyle(Theme.expense)
            }
        }
    }

    private var categorySection: some View {
        Section {
            if selectable.isEmpty {
                Text("No active categories. Add one in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                CategoryPickerGrid(categories: selectable, selection: categoryID) { categoryID = $0 }
            }
        } header: {
            Text("Category")
        } footer: {
            if selectedCategory?.isArchived == true {
                Text("This category is archived and stays available for this transaction.")
            }
        }
    }

    private var detailsSection: some View {
        Section {
            DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
            TextField("Description (optional)", text: $note, axis: .vertical)
                .lineLimit(1...3)
        } footer: {
            Text("The transaction date decides which month and year it is reported in.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Text("Delete Transaction")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var categoryToken: String {
        storedCategories.map { "\($0.categoryID):\($0.isArchived):\($0.typeRaw)" }.sorted().joined(separator: "|")
    }

    private func alignCategorySelection() {
        let options = catalog.choices(for: type, selectedID: categoryID.isEmpty ? nil : categoryID)
        guard !options.contains(where: { $0.id == categoryID }) else { return }
        categoryID = options.first(where: { !$0.isArchived })?.id ?? options.first?.id ?? ""
    }

    private func save() {
        guard let amount = parsedAmount, let selectedCategory else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .new:
            context.insert(FinanceTransaction(
                amount: amount,
                categoryID: selectedCategory.id,
                type: selectedCategory.type,
                date: date,
                note: trimmedNote
            ))
        case let .edit(transaction):
            transaction.amount = amount
            transaction.setCategory(id: selectedCategory.id, type: selectedCategory.type)
            transaction.date = date
            transaction.note = trimmedNote
            transaction.updatedAt = .now
        }
        do {
            try context.save()
            dismiss()
        } catch {
            showingSaveError = true
        }
    }

    private func delete() {
        guard case let .edit(transaction) = mode else { return }
        context.delete(transaction)
        do {
            try context.save()
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}

private struct CategoryPickerGrid: View {
    let categories: [CategoryInfo]
    let selection: String
    let onSelect: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(categories) { item in
                CategoryChip(info: item, isSelected: item.id == selection) {
                    onSelect(item.id)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CategoryChip: View {
    let info: CategoryInfo
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: info.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(info.color)
                Text(verbatim: info.displayName(in: locale))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                isSelected ? info.color.opacity(0.14) : Theme.surfaceMuted,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? info.color : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
