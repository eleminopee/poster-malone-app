import SwiftUI

// ============================================================================
// ExpensesView.swift — Tier 2
// Two panes: an expense ledger (add/edit/delete business costs) and a year
// tax summary built by TaxReportService, exportable to CSV. Reached via the
// sidebar and the Today cockpit.
// ============================================================================

struct ExpensesView: View {
    @Environment(InventoryStore.self) var store

    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var showingAdd = false
    @State private var editingExpense: ExpenseRecord? = nil
    @State private var exportMessage: String? = nil

    private var availableYears: [Int] {
        let cal = Calendar.current
        let saleYears = store.sales.map { cal.component(.year, from: $0.dateSold) }
        let expYears  = store.expenses.map { cal.component(.year, from: $0.date) }
        let all = Set(saleYears + expYears + [cal.component(.year, from: Date())])
        return all.sorted(by: >)
    }

    private var yearExpenses: [ExpenseRecord] {
        let cal = Calendar.current
        return store.expenses
            .filter { cal.component(.year, from: $0.date) == year }
            .sorted { $0.date > $1.date }
    }

    private var report: TaxReportService.AnnualReport {
        TaxReportService.build(year: year, sales: store.sales, expenses: store.expenses)
    }

    var body: some View {
        HSplitView {
            ledgerPane
                .frame(minWidth: 420)
            summaryPane
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 460)
        }
        .pmScreen()
        .navigationTitle("Expenses & Tax")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("Year", selection: $year) {
                    ForEach(availableYears, id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: {
                    Label("Add Expense", systemImage: "plus")
                }
                .foregroundStyle(PM.pink)
            }
        }
        .sheet(isPresented: $showingAdd) {
            ExpenseEditSheet(expense: ExpenseRecord(), isNew: true)
                .environment(store)
        }
        .sheet(item: $editingExpense) { exp in
            ExpenseEditSheet(expense: exp, isNew: false)
                .environment(store)
        }
    }

    // MARK: - Ledger Pane

    private var ledgerPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("EXPENSES \(String(year))")
                    .font(.pmDisplay(size: 18))
                    .foregroundStyle(PM.textPrimary)
                    .tracking(0.8)
                Spacer()
                Text("\(yearExpenses.count) entries · \(yearExpenses.reduce(0){$0+$1.amount}.asCurrency)")
                    .font(.pmBody(size: 12))
                    .foregroundStyle(PM.textTertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PM.surface)

            PMNeonDivider(color: PM.pink).opacity(0.5)

            if yearExpenses.isEmpty {
                ContentUnavailableView {
                    Label("No Expenses in \(String(year))", systemImage: "receipt")
                        .font(.pmDisplay(size: 20))
                        .foregroundStyle(PM.textSecondary)
                } description: {
                    Text("Track tubes, fees, storage, and marketing spend so your net profit and tax summary are accurate.")
                        .font(.pmBody(size: 13))
                        .foregroundStyle(PM.textTertiary)
                } actions: {
                    Button("Add Expense") { showingAdd = true }
                        .buttonStyle(PMPrimaryButtonStyle())
                        .frame(maxWidth: 180)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(yearExpenses) { exp in
                            ExpenseRow(expense: exp)
                                .contentShape(Rectangle())
                                .onTapGesture { editingExpense = exp }
                                .contextMenu {
                                    Button("Edit") { editingExpense = exp }
                                    Button("Delete", role: .destructive) { store.deleteExpense(exp) }
                                }
                            Rectangle().fill(PM.borderSubtle).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Summary Pane

    private var summaryPane: some View {
        let r = report
        return ScrollView {
            VStack(alignment: .leading, spacing: PM.Space.lg) {
                Text("\(String(year)) TAX SUMMARY")
                    .font(.pmDisplay(size: 18))
                    .foregroundStyle(PM.textPrimary)
                    .tracking(0.8)

                VStack(spacing: 0) {
                    TaxLine(label: "Gross Receipts", value: r.grossReceipts, tint: PM.cyan, bold: true)
                    TaxLine(label: "Cost of Goods Sold", value: -r.cogs)
                    TaxLine(label: "Gross Profit", value: r.grossProfit, tint: PM.cyan, bold: true)
                    Rectangle().fill(PM.borderStrong).frame(height: 1).padding(.vertical, 2)
                    TaxLine(label: "Total Expenses", value: -r.totalExpenses)
                    TaxLine(label: "Net Profit", value: r.netProfit,
                            tint: r.netProfit >= 0 ? .green : .red, bold: true, big: true)
                }
                .padding(.vertical, 4)
                .pmCard(fill: PM.card, radius: PM.Radius.md)

                if !r.expenseByCategory.isEmpty {
                    Text("EXPENSES BY CATEGORY")
                        .font(.pmBody(size: 11, weight: .semibold))
                        .foregroundStyle(PM.textTertiary)
                        .tracking(1.2)
                    VStack(spacing: 0) {
                        ForEach(r.expenseByCategory, id: \.category) { row in
                            HStack {
                                Text(row.category.rawValue)
                                    .font(.pmBody(size: 13))
                                    .foregroundStyle(PM.textPrimary)
                                Spacer()
                                Text(row.total.asCurrency)
                                    .font(.pmBody(size: 13, weight: .medium))
                                    .foregroundStyle(PM.textSecondary)
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            if row.category != r.expenseByCategory.last?.category {
                                Rectangle().fill(PM.borderSubtle).frame(height: 1).padding(.leading, 12)
                            }
                        }
                    }
                    .pmCard(fill: PM.card, radius: PM.Radius.md)
                    Text("Includes platform fees + shipping pulled from sale records.")
                        .font(.pmBody(size: 11))
                        .foregroundStyle(PM.textTertiary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "building.columns")
                        .font(.caption)
                        .foregroundStyle(PM.textTertiary)
                    Text("Sales tax collected: \(r.salesTax.asCurrency) (pass-through, not income)")
                        .font(.pmBody(size: 11))
                        .foregroundStyle(PM.textTertiary)
                }

                Button {
                    exportReport()
                } label: {
                    Label("Export Tax CSV", systemImage: "arrow.down.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PMPrimaryButtonStyle())

                if let exportMessage {
                    Text(exportMessage)
                        .font(.pmBody(size: 12))
                        .foregroundStyle(.green)
                }

                Text("Not tax advice — a worksheet mapping your data to Schedule C lines. Verify with a CPA.")
                    .font(.pmBody(size: 11))
                    .foregroundStyle(PM.textTertiary)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(PM.base)
    }

    private func exportReport() {
        do {
            let csv = TaxReportService.csv(report)
            let url = try TaxReportService.saveCSV(csv, year: year)
            exportMessage = "✓ Saved to \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportMessage = nil
        }
    }
}

// MARK: - Expense Row

struct ExpenseRow: View {
    let expense: ExpenseRecord

    private var tint: Color {
        switch expense.category {
        case .shippingSupplies: return .blue
        case .platformFees:     return .orange
        case .acquisition:      return .mint
        case .storage:          return .purple
        case .marketing:        return PM.pink
        case .other:            return Color(.systemGray)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: PM.Radius.sm))
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.description.isEmpty ? expense.category.rawValue : expense.description)
                    .font(.pmBody(size: 14, weight: .medium))
                    .foregroundStyle(PM.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    PMGlowBadge(text: expense.category.rawValue, color: tint, flat: true)
                    Text(expense.date.shortDate)
                        .font(.pmBody(size: 11))
                        .foregroundStyle(PM.textTertiary)
                }
            }
            Spacer()
            Text(expense.amount.asCurrency)
                .font(.pmDisplay(size: 16))
                .foregroundStyle(PM.textPrimary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Tax Line

struct TaxLine: View {
    let label: String
    let value: Double
    var tint: Color = PM.textPrimary
    var bold: Bool = false
    var big: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.pmBody(size: big ? 14 : 13, weight: bold ? .semibold : .regular))
                .foregroundStyle(value < 0 ? PM.textSecondary : PM.textPrimary)
            Spacer()
            Text(value < 0 ? "(\(abs(value).asCurrency))" : value.asCurrency)
                .font(bold ? .pmDisplay(size: big ? 20 : 16) : .pmBody(size: 13, weight: .medium))
                .foregroundStyle(value < 0 ? PM.textSecondary : tint)
                .monospacedDigit()
                .pmGlow(tint, radius: bold && tint != PM.textPrimary ? 4 : 0, opacity: 0.3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, big ? 9 : 7)
    }
}

// MARK: - Expense Edit Sheet

struct ExpenseEditSheet: View {
    @Environment(InventoryStore.self) var store
    @Environment(\.dismiss) var dismiss

    let isNew: Bool
    @State private var date: Date
    @State private var category: ExpenseCategory
    @State private var description: String
    @State private var amount: Double
    @State private var receipt: String
    private let expenseId: UUID

    init(expense: ExpenseRecord, isNew: Bool) {
        self.isNew = isNew
        self.expenseId = expense.id
        _date        = State(initialValue: expense.date)
        _category    = State(initialValue: expense.category)
        _description = State(initialValue: expense.description)
        _amount      = State(initialValue: expense.amount)
        _receipt     = State(initialValue: expense.receipt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Expense") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Description", text: $description)
                    TextField("Amount", value: $amount, format: .currency(code: "USD"))
                }
                Section("Reference (optional)") {
                    TextField("Receipt # or note", text: $receipt)
                }
                if !isNew {
                    Section {
                        Button("Delete Expense", role: .destructive) {
                            store.deleteExpense(currentRecord())
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(isNew ? "Add Expense" : "Edit Expense")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isNew { store.addExpense(currentRecord()) }
                        else      { store.updateExpense(currentRecord()) }
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(width: 420, height: 460)
    }

    private func currentRecord() -> ExpenseRecord {
        var e = ExpenseRecord()
        e.id = expenseId
        e.date = date
        e.category = category
        e.description = description
        e.amount = amount
        e.receipt = receipt
        return e
    }
}
