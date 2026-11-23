import SwiftData
import SwiftUI

struct CategoryListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.locale) private var locale
    @Query(sort: [SortDescriptor(\FinanceCategory.sortOrder), SortDescriptor(\FinanceCategory.createdAt)])
    private var categories: [FinanceCategory]

    @State private var type: TransactionType = .income
    @State private var editor: CategoryEditorRoute?
    @State private var pendingDelete: FinanceCategory?
    @State private var inUseCategory: FinanceCategory?
    @State private var inUseCount = 0
    @State private var message: String?

    private var visible: [FinanceCategory] {
        categories.filter { $0.type == type }
    }

    var body: some View {
        List {
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

            Section {
                if visible.allSatisfy(\.isArchived) {
                    Text("No active categories.")
                        .foregroundStyle(.secondary)
                }
                ForEach(visible.filter { !$0.isArchived }, id: \.categoryID) { category in
                    categoryRow(category)
                }
            } footer: {
                Text("Archived categories remain in your history and reports, but are hidden from new transactions.")
            }

            let archived = visible.filter(\.isArchived)
            if !archived.isEmpty {
                Section("Archived") {
                    ForEach(archived, id: \.categoryID) { category in
                        categoryRow(category)
                    }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = .create(type)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("New Category"))
            }
        }
        .sheet(item: $editor) { route in
            CategoryEditorView(route: route)
        }
        .confirmationDialog("Delete this category?", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { performDelete(pendingDelete) }
            }
        }
        .confirmationDialog(
            Text("This category is used by \(inUseCount) transactions. Archive it instead of deleting it."),
            isPresented: Binding(get: { inUseCategory != nil }, set: { if !$0 { inUseCategory = nil } }),
            titleVisibility: .visible
        ) {
            Button("Archive") {
                if let inUseCategory { setArchived(inUseCategory, true) }
                inUseCategory = nil
            }
        }
        .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .onAppear { try? CategoryStore.ensureDefaults(in: context) }
    }

    private func categoryRow(_ category: FinanceCategory) -> some View {
        Button {
            editor = .edit(category.categoryID)
        } label: {
            HStack(spacing: 12) {
                CategoryIcon(symbol: category.symbol, color: category.palette.color, size: 36)
                Text(verbatim: category.displayName(in: locale))
                    .font(.body)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if category.isArchived {
                Button("Restore") { setArchived(category, false) }
                    .tint(Theme.income)
            } else {
                Button("Archive") { setArchived(category, true) }
                    .tint(Theme.accent)
            }
            if !category.isBuiltIn {
                Button("Delete", role: .destructive) { pendingDelete = category }
            }
        }
    }

    private func setArchived(_ category: FinanceCategory, _ archived: Bool) {
        do {
            try CategoryStore.setArchived(category, archived, in: context)
        } catch {
            message = locale.localized("Could not save. Please try again.")
        }
    }

    private func performDelete(_ category: FinanceCategory) {
        pendingDelete = nil
        do {
            try CategoryStore.delete(category, in: context)
        } catch CategoryStoreError.inUse(let count) {
            inUseCount = count
            inUseCategory = category
        } catch CategoryStoreError.builtInProtected {
            message = locale.localized("Built-in categories can be archived, not deleted.")
        } catch {
            message = locale.localized("Could not save. Please try again.")
        }
    }
}

enum CategoryEditorRoute: Identifiable {
    case create(TransactionType)
    case edit(String)

    var id: String {
        switch self {
        case let .create(type): "create-\(type.rawValue)"
        case let .edit(categoryID): "edit-\(categoryID)"
        }
    }
}

struct CategoryEditorView: View {
    let route: CategoryEditorRoute

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Query private var categories: [FinanceCategory]

    @AppStorage(AppPreferences.turkishEnabledKey) private var turkishEnabled = false
    @State private var nameTurkish = ""
    @State private var nameEnglish = ""
    @State private var symbol = CategorySymbol.default.rawValue
    @State private var palette: CategoryPalette = .indigo
    @State private var didLoad = false
    @State private var showingArchiveConfirmation = false
    @State private var showingDeleteConfirmation = false
    @State private var inUseCount = 0
    @State private var showingInUse = false
    @State private var message: String?

    private var editedID: String? {
        if case let .edit(categoryID) = route { return categoryID }
        return nil
    }

    private var category: FinanceCategory? {
        guard let editedID else { return nil }
        return categories.first { $0.categoryID == editedID }
    }

    private var categoryType: TransactionType {
        switch route {
        case let .create(type): type
        case .edit: category?.type ?? .expense
        }
    }

    private var trimmedEnglish: String {
        nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        category?.isBuiltIn == true || !trimmedEnglish.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("English Category Name", text: $nameEnglish)
                        .accessibilityIdentifier("categoryEnglishField")
                    if turkishEnabled {
                        TextField("Turkish Category Name", text: $nameTurkish)
                            .accessibilityIdentifier("categoryTurkishField")
                    }
                    LabeledContent("Type") {
                        Text(LocalizedStringKey(categoryType.titleKey))
                    }
                } footer: {
                    if turkishEnabled {
                        Text("The English name is required. The Turkish name is optional.")
                    } else {
                        Text("The English name is required.")
                    }
                }

                Section("Icon") {
                    symbolGrid
                }

                Section("Color") {
                    colorGrid
                }

                if category != nil {
                    Section {
                        Button {
                            if category?.isArchived == true {
                                setArchived(false)
                            } else {
                                showingArchiveConfirmation = true
                            }
                        } label: {
                            if category?.isArchived == true {
                                Text("Restore Category")
                            } else {
                                Text("Archive Category")
                            }
                        }
                        if category?.isBuiltIn == false {
                            Button("Delete Category", role: .destructive) {
                                showingDeleteConfirmation = true
                            }
                        }
                    } footer: {
                        if category?.isBuiltIn == true {
                            Text("Built-in categories can be archived, not deleted.")
                        }
                    }
                }
            }
            .screenBackground()
            .navigationTitle(category == nil ? Text("New Category") : Text("Edit Category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .confirmationDialog("Archive this category?", isPresented: $showingArchiveConfirmation, titleVisibility: .visible) {
                Button("Archive") { setArchived(true) }
            } message: {
                Text("Archived categories remain in your history and reports, but are hidden from new transactions.")
            }
            .confirmationDialog("Delete this category?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deleteCategory)
            }
            .confirmationDialog(
                Text("This category is used by \(inUseCount) transactions. Archive it instead of deleting it."),
                isPresented: $showingInUse,
                titleVisibility: .visible
            ) {
                Button("Archive") { setArchived(true) }
            }
            .alert(Text(verbatim: message ?? ""), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
            ForEach(CategorySymbol.allCases) { item in
                Button {
                    symbol = item.rawValue
                } label: {
                    Image(systemName: item.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(symbol == item.rawValue ? palette.color : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(
                            symbol == item.rawValue ? palette.color.opacity(0.16) : Theme.surfaceMuted,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: item.rawValue))
                .accessibilityAddTraits(symbol == item.rawValue ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var colorGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
            ForEach(CategoryPalette.allCases) { item in
                Button {
                    palette = item
                } label: {
                    Circle()
                        .fill(item.color)
                        .frame(width: 28, height: 28)
                        .overlay {
                            if palette == item {
                                Circle().strokeBorder(Color.primary, lineWidth: 2).padding(-4)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: item.rawValue))
                .accessibilityAddTraits(palette == item ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let category else { return }
        let key = category.localizationKey
        nameTurkish = category.nameTurkish.isEmpty && !key.isEmpty
            ? AppLanguage.turkish.locale.localized(key)
            : category.nameTurkish
        nameEnglish = category.nameEnglish.isEmpty && !key.isEmpty
            ? AppLanguage.english.locale.localized(key)
            : category.nameEnglish
        symbol = category.symbol
        palette = category.palette
    }

    private func save() {
        let english = nameEnglish.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let category {
                try CategoryStore.update(
                    category,
                    nameTurkish: nameTurkish,
                    nameEnglish: english,
                    symbol: symbol,
                    palette: palette,
                    in: context
                )
            } else {
                try CategoryStore.create(
                    type: categoryType,
                    nameTurkish: nameTurkish,
                    nameEnglish: english,
                    symbol: symbol,
                    palette: palette,
                    in: context
                )
            }
            dismiss()
        } catch CategoryStoreError.nameRequired {
            message = locale.localized("The English name is required.")
        } catch {
            message = locale.localized("Could not save. Please try again.")
        }
    }

    private func setArchived(_ archived: Bool) {
        guard let category else { return }
        do {
            try CategoryStore.setArchived(category, archived, in: context)
            dismiss()
        } catch {
            message = locale.localized("Could not save. Please try again.")
        }
    }

    private func deleteCategory() {
        guard let category else { return }
        do {
            try CategoryStore.delete(category, in: context)
            dismiss()
        } catch CategoryStoreError.inUse(let count) {
            inUseCount = count
            showingInUse = true
        } catch CategoryStoreError.builtInProtected {
            message = locale.localized("Built-in categories can be archived, not deleted.")
        } catch {
            message = locale.localized("Could not save. Please try again.")
        }
    }
}
