import SwiftUI

// MARK: - Per-item financial entry row

private struct BulkSaleItemRow: View {
    let item: InventoryItem
    @Binding var entry: BulkSaleEntry
    @State private var expanded = false

    var netSales: Double { entry.grossSales - entry.taxes - entry.feesAndShipping }
    var profit: Double   { netSales - item.totalCostComputed }

    var body: some View {
        VStack(spacing: 0) {
            // Summary row — always visible
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.artist) — \(item.title)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(item.sku)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Cost basis badge
                    Text(item.totalCostComputed.asCurrency)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Gross field — inline quick entry
                    TextField("Gross", value: $entry.grossSales, format: .currency(code: "USD"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)

                    // Profit indicator
                    if entry.grossSales > 0 {
                        Text(profit.asCurrency)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(profit >= 0 ? .green : .red)
                            .frame(width: 72, alignment: .trailing)
                    } else {
                        Text("—")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(width: 72, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded detail — taxes, fees
            if expanded {
                VStack(spacing: 6) {
                    HStack {
                        Text("Taxes Collected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)
                        TextField("0.00", value: $entry.taxes, format: .currency(code: "USD"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                            .multilineTextAlignment(.trailing)
                        Spacer()
                    }
                    HStack {
                        Text("Fees + Shipping")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)
                        TextField("0.00", value: $entry.feesAndShipping, format: .currency(code: "USD"))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                            .multilineTextAlignment(.trailing)
                        Spacer()
                    }
                    HStack {
                        Text("Net Sales")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 140, alignment: .leading)
                        Text(netSales.asCurrency)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                }
                .padding(.horizontal, 36)
                .padding(.bottom, 10)
                .padding(.top, 2)
                .background(Color.secondary.opacity(0.04))
            }

            Divider()
        }
    }
}

// MARK: - Entry model (per item financial values)

struct BulkSaleEntry {
    var grossSales: Double = 0
    var taxes: Double = 0
    var feesAndShipping: Double = 0
}

// MARK: - Main Sheet

struct BulkMarkSoldSheet: View {
    @Environment(InventoryStore.self) var store
    @Environment(\.dismiss) var dismiss

    let items: [InventoryItem]

    // Shared sale details
    @State private var marketplace: Marketplace = .ebay
    @State private var dateSold: Date = Date()

    // Per-item financial entries keyed by item.id
    @State private var entries: [UUID: BulkSaleEntry] = [:]

    // Bulk-fill helpers
    @State private var bulkGross: Double = 0
    @State private var bulkTaxes: Double = 0
    @State private var bulkFees: Double = 0
    @State private var showBulkFill = false

    // Confirmation
    @State private var showConfirm = false

    // MARK: Computed

    var sortedItems: [InventoryItem] {
        items.sorted { $0.artist < $1.artist }
    }

    var totalCostBasis: Double {
        items.reduce(0) { $0 + $1.totalCostComputed }
    }

    var totalGross: Double {
        entries.values.reduce(0) { $0 + $1.grossSales }
    }

    var totalProfit: Double {
        var p = 0.0
        for item in items {
            guard let e = entries[item.id], e.grossSales > 0 else { continue }
            let net = e.grossSales - e.taxes - e.feesAndShipping
            p += net - item.totalCostComputed
        }
        return p
    }

    var readyCount: Int {
        items.filter { (entries[$0.id]?.grossSales ?? 0) > 0 }.count
    }

    var allReady: Bool { readyCount == items.count }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Shared sale header ──────────────────────────────────
                Form {
                    Section {
                        Picker("Marketplace", selection: $marketplace) {
                            ForEach(Marketplace.allCases, id: \.self) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        DatePicker("Date Sold", selection: $dateSold,
                                   displayedComponents: .date)
                    } header: {
                        Text("Shared Sale Details")
                    } footer: {
                        Text("Marketplace and date apply to all \(items.count) items.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            .scrollContentBackground(.hidden)
                .frame(height: 150)

                Divider()

                // ── Bulk fill banner ─────────────────────────────────────
                VStack(spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showBulkFill.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: "wand.and.sparkles")
                                .font(.caption)
                            Text(showBulkFill ? "Hide Bulk Fill" : "Bulk Fill Financials")
                                .font(.caption)
                                .fontWeight(.medium)
                            Spacer()
                            Image(systemName: showBulkFill ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)

                    if showBulkFill {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Gross").font(.caption2).foregroundStyle(.secondary)
                                TextField("0.00", value: $bulkGross, format: .currency(code: "USD"))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Taxes").font(.caption2).foregroundStyle(.secondary)
                                TextField("0.00", value: $bulkTaxes, format: .currency(code: "USD"))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Fees+Ship").font(.caption2).foregroundStyle(.secondary)
                                TextField("0.00", value: $bulkFees, format: .currency(code: "USD"))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 90)
                            }
                            Spacer()
                            Button("Apply to All") {
                                for item in items {
                                    entries[item.id] = BulkSaleEntry(
                                        grossSales: bulkGross,
                                        taxes: bulkTaxes,
                                        feesAndShipping: bulkFees
                                    )
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(bulkGross <= 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.05))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Divider()
                }

                // ── Column header ────────────────────────────────────────
                HStack(spacing: 10) {
                    Color.clear.frame(width: 12)
                    Text("Item")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Cost")
                        .frame(width: 72, alignment: .trailing)
                    Text("Gross Sale")
                        .frame(width: 90, alignment: .trailing)
                    Text("Profit")
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(PM.surface)

                Divider()

                // ── Per-item rows ────────────────────────────────────────
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedItems) { item in
                            BulkSaleItemRow(
                                item: item,
                                entry: Binding(
                                    get: { entries[item.id] ?? BulkSaleEntry() },
                                    set: { entries[item.id] = $0 }
                                )
                            )
                        }
                    }
                }

                Divider()

                // ── Footer totals ────────────────────────────────────────
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Items Ready")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("\(readyCount) of \(items.count)")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(allReady ? .green : .orange)
                    }
                    Divider().frame(height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cost Basis")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(totalCostBasis.asCurrency)
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    Divider().frame(height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Gross")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(totalGross.asCurrency)
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    Divider().frame(height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Total Profit")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(totalProfit.asCurrency)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(totalProfit >= 0 ? .green : .red)
                    }

                    Spacer()

                    if !allReady {
                        Text("\(items.count - readyCount) item(s) missing gross sales")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(PM.surface)
            }
            .navigationTitle("Bulk Mark as Sold — \(items.count) Items")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm \(readyCount) Sale\(readyCount == 1 ? "" : "s")") {
                        showConfirm = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(readyCount == 0)
                }
            }
            .confirmationDialog(
                "Move \(readyCount) item\(readyCount == 1 ? "" : "s") to Sales?",
                isPresented: $showConfirm,
                titleVisibility: .visible
            ) {
                Button("Confirm Sale\(readyCount == 1 ? "" : "s")", role: .none) {
                    commitSales()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                if readyCount < items.count {
                    Text("\(items.count - readyCount) item(s) without a gross amount will be skipped.")
                } else {
                    Text("All \(readyCount) items will be moved to Sales.")
                }
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(width: 700, height: 680)
        .onAppear {
            // Pre-populate entries so bindings are always valid
            for item in items where entries[item.id] == nil {
                entries[item.id] = BulkSaleEntry()
            }
        }
    }

    // MARK: - Commit

    private func commitSales() {
        let soldDate = dateSold
        for item in items {
            guard let entry = entries[item.id], entry.grossSales > 0 else { continue }
            store.markAsSold(
                item,
                marketplace: marketplace,
                grossSales: entry.grossSales,
                taxes: entry.taxes,
                feesAndShipping: entry.feesAndShipping,
                dateSold: soldDate
            )
        }
    }
}
