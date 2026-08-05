import SwiftUI

// ============================================================================
// SalesView.swift — the receipts floor
// Dark striped table with cyan money columns and semantic P/L coloring,
// glow marketplace badges, pink filter chips, and a restyled detail panel
// (Bebas header, glowing storage card, PM action buttons, carded P&L).
// All filtering, sorting, undo-to-inventory + Drive-move logic unchanged.
// ============================================================================

struct SalesView: View {
    @Environment(InventoryStore.self) var store
    @Environment(PMRouter.self) var router

    @State private var searchText = ""
    @State private var selectedSale: SaleRecord? = nil
    @State private var selectedIDs: Set<SaleRecord.ID> = []
    @State private var sortOrder: [KeyPathComparator<SaleRecord>] = [
        .init(\.dateSold, order: .reverse)
    ]
    @State private var filterMarketplace: Marketplace? = nil
    @State private var showingFilters = false
    /// SESSION 5: when true, show only sold records with no financials entered.
    @State private var showingMissingFinancials = false

    // MARK: - Filtering & Sorting

    var filtered: [SaleRecord] {
        var base = store.sales
        if showingMissingFinancials {
            base = base.filter { $0.grossSales == 0 }
        }
        if let mp = filterMarketplace {
            base = base.filter { $0.marketplace == mp }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            base = base.filter {
                $0.artist.lowercased().contains(q) ||
                $0.title.lowercased().contains(q) ||
                $0.sku.lowercased().contains(q) ||
                $0.gallery.lowercased().contains(q)
            }
        }
        return base.sorted(using: sortOrder)
    }

    // MARK: - Computed Stats (on filtered set)

    var totalGross: Double  { filtered.reduce(0) { $0 + $1.grossSales } }
    var totalProfit: Double { filtered.reduce(0) { $0 + $1.profit } }
    var totalCost: Double   { filtered.reduce(0) { $0 + $1.totalCost } }
    var avgMargin: Double {
        guard !filtered.isEmpty else { return 0 }
        return filtered.reduce(0) { $0 + $1.profitLossPercent } / Double(filtered.count)
    }
    var avgDaysToSell: Double {
        let withDays = filtered.filter { $0.daysToSell > 0 }
        guard !withDays.isEmpty else { return 0 }
        return Double(withDays.reduce(0) { $0 + $1.daysToSell }) / Double(withDays.count)
    }

    var body: some View {
        HSplitView {
            // MARK: Left — table
            VStack(spacing: 0) {

                // Stats bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        StatCard(label: "Sales",      value: "\(filtered.count)",                    icon: "cart.fill")
                        StatCard(label: "Gross",      value: totalGross.asCurrency,                  icon: "dollarsign.circle")
                        StatCard(label: "Profit",     value: totalProfit.asCurrency,                 icon: "chart.line.uptrend.xyaxis")
                        StatCard(label: "Cost",       value: totalCost.asCurrency,                   icon: "cart.badge.minus")
                        StatCard(label: "Avg Margin", value: avgMargin.asPercent,                    icon: "percent")
                        StatCard(label: "Avg Days",   value: String(format: "%.0f", avgDaysToSell),  icon: "clock")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(PM.surface)

                PMNeonDivider(color: PM.cyan).opacity(0.5)

                // Filter chips
                if showingFilters || filterMarketplace != nil || showingMissingFinancials {
                    salesFilterBar
                    Divider().overlay(PM.borderSubtle)
                }

                // Table
                if store.sales.isEmpty {
                    ContentUnavailableView {
                        Label("No Sales Yet", systemImage: "dollarsign.circle")
                            .font(.pmDisplay(size: 22))
                            .foregroundStyle(PM.textSecondary)
                    } description: {
                        Text("Sales will appear here after marking items as sold or importing your Sales CSV.")
                            .font(.pmBody(size: 13))
                            .foregroundStyle(PM.textTertiary)
                    }
                } else {
                    Table(filtered, selection: $selectedIDs, sortOrder: $sortOrder) {
                        salesColumns
                    }
                    .scrollContentBackground(.hidden)
                    .alternatingRowBackgrounds(.enabled)
                    .onChange(of: selectedIDs) { _, newValue in
                        selectedSale = store.sales.first { newValue.contains($0.id) }
                    }
                }
            }
            .frame(minWidth: 600)
            .navigationTitle("Sales")
            .searchable(text: $searchText, placement: .toolbar,
                        prompt: "Search artist, title, SKU, gallery...")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        withAnimation { showingFilters.toggle() }
                    } label: {
                        Label(
                            filterMarketplace != nil ? "Filtered" : "Filter",
                            systemImage: filterMarketplace != nil
                                ? "line.3.horizontal.decrease.circle.fill"
                                : "line.3.horizontal.decrease.circle"
                        )
                    }
                    .foregroundStyle(filterMarketplace != nil ? PM.pink : .primary)
                    .help("Filter sales by marketplace")
                }
            }

            // MARK: Right — detail panel
            if let sale = selectedSale {
                SaleDetailPanel(sale: sale, onUndo: {
                    selectedSale = nil
                    selectedIDs = []
                })
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                .id(sale.id)
            }
        }
        .pmScreen()
        .onAppear {
            if router.pendingSalesFilter == .missingFinancials {
                router.pendingSalesFilter = nil
                showingMissingFinancials = true
                filterMarketplace = nil
            }
        }
    }

    // MARK: - Table Columns

    @TableColumnBuilder<SaleRecord, KeyPathComparator<SaleRecord>>
    var salesColumns: some TableColumnContent<SaleRecord, KeyPathComparator<SaleRecord>> {
        TableColumn("Date", value: \.dateSold) { sale in
            Text(sale.dateSold.shortDate)
                .foregroundStyle(Color.secondary)
        }
        .width(min: 80, ideal: 95)

        TableColumn("SKU", value: \.sku)
            .width(min: 80, ideal: 95)

        TableColumn("Artist", value: \.artist)
            .width(min: 110, ideal: 140)

        TableColumn("Title", value: \.title)
            .width(min: 140, ideal: 200)

        TableColumn("Gallery", value: \.gallery)
            .width(min: 80, ideal: 110)

        TableColumn("Channel", value: \.marketplace.rawValue) { sale in
            MarketplaceBadge(marketplace: sale.marketplace, flat: true)
        }
        .width(min: 60, ideal: 80)

        TableColumn("Gross", value: \.grossSales) { sale in
            Text(sale.grossSales > 0 ? sale.grossSales.asCurrency : "—")
                .foregroundStyle(sale.grossSales > 0 ? PM.cyan : PM.textTertiary)
                .monospacedDigit()
        }
        .width(min: 65, ideal: 80)

        TableColumn("Profit", value: \.profit) { sale in
            Text(sale.grossSales > 0 ? sale.profit.asCurrency : "—")
                .foregroundStyle(sale.grossSales > 0
                                 ? (sale.profit >= 0 ? Color.green : Color.red)
                                 : PM.textTertiary)
                .monospacedDigit()
        }
        .width(min: 65, ideal: 80)

        TableColumn("P/L %", value: \.profitLossPercent) { sale in
            Text(sale.grossSales > 0 ? sale.profitLossPercent.asPercent : "—")
                .foregroundStyle(marginColor(sale.profitLossPercent))
                .monospacedDigit()
        }
        .width(min: 60, ideal: 75)

        TableColumn("Days", value: \.daysToSell) { sale in
            Text(sale.daysToSell > 0 ? "\(sale.daysToSell)" : "—")
                .foregroundStyle(sale.daysToSell > 365 ? Color.orange : Color.primary)
                .monospacedDigit()
        }
        .width(min: 45, ideal: 60)
    }

    // MARK: - Filter Bar

    var salesFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("CHANNEL")
                    .font(.pmBody(size: 11, weight: .semibold))
                    .foregroundStyle(PM.textTertiary)
                    .tracking(1.2)
                    .padding(.leading, 4)

                FilterChip(label: "All", isActive: filterMarketplace == nil && !showingMissingFinancials) {
                    filterMarketplace = nil
                    showingMissingFinancials = false
                }

                FilterChip(
                    label: "Missing Financials (\(store.sales.lazy.filter { $0.grossSales == 0 }.count))",
                    isActive: showingMissingFinancials
                ) {
                    showingMissingFinancials.toggle()
                }

                ForEach(Marketplace.allCases, id: \.self) { mp in
                    let count = store.sales.filter { $0.marketplace == mp }.count
                    if count > 0 {
                        FilterChip(
                            label: "\(mp.rawValue) (\(count))",
                            isActive: filterMarketplace == mp
                        ) {
                            filterMarketplace = filterMarketplace == mp ? nil : mp
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(PM.surface)
    }

    // MARK: - Helpers

    func marginColor(_ pct: Double) -> Color {
        if pct >= 40 { return .green }
        if pct >= 20 { return .primary }
        if pct >= 0  { return .orange }
        return .red
    }
}

// MARK: - Sale Detail Panel

struct SaleDetailPanel: View {
    let sale: SaleRecord
    let onUndo: () -> Void
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @Environment(PMRouter.self) var router
    @State private var showingEditSheet = false
    @State private var showingUndoConfirm = false

    private let soldFolderId     = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(sale.artist)
                        .font(.pmBody(size: 12, weight: .semibold))
                        .foregroundStyle(PM.pink)
                        .textCase(.uppercase)
                        .tracking(1.4)
                    Text(sale.title)
                        .font(.pmDisplay(size: 24))
                        .foregroundStyle(PM.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        MarketplaceBadge(marketplace: sale.marketplace)
                        Text("·").foregroundStyle(PM.textTertiary)
                        Text(sale.dateSold.shortDate)
                            .font(.pmBody(size: 13))
                            .foregroundStyle(PM.textSecondary)
                    }
                }

                // Storage location — shown prominently so you can find the item to ship
                if !sale.drawer.isEmpty || !sale.sleeveNumber.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "archivebox.fill")
                            .font(.caption)
                            .foregroundStyle(PM.cyan)
                            .pmGlow(PM.cyan, radius: 4, opacity: 0.4)
                        if !sale.drawer.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("DRAWER")
                                    .font(.pmBody(size: 10, weight: .semibold))
                                    .foregroundStyle(PM.textTertiary)
                                    .tracking(1.0)
                                Text(sale.drawer)
                                    .font(.pmDisplay(size: 17))
                                    .foregroundStyle(PM.textPrimary)
                            }
                        }
                        if !sale.drawer.isEmpty && !sale.sleeveNumber.isEmpty {
                            Divider().frame(height: 24).overlay(PM.borderStrong)
                        }
                        if !sale.sleeveNumber.isEmpty {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("SLEEVE")
                                    .font(.pmBody(size: 10, weight: .semibold))
                                    .foregroundStyle(PM.textTertiary)
                                    .tracking(1.0)
                                Text(sale.sleeveNumber)
                                    .font(.pmDisplay(size: 17))
                                    .foregroundStyle(PM.textPrimary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .pmCard(fill: PM.card, radius: PM.Radius.md, border: PM.cyan.opacity(0.25))
                }

                // Action buttons
                HStack(spacing: 8) {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Sale", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PMGhostButtonStyle(tint: PM.cyan))
                    .help("Edit financials, dates, and sale details")

                    Button(role: .destructive) {
                        showingUndoConfirm = true
                    } label: {
                        Label("Move to Inventory", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PMTintButtonStyle(tint: .orange, prominent: false))
                    .help("Move this item back to Inventory — use if marked sold by mistake")
                    .confirmationDialog(
                        "Move \"\(sale.title)\" back to Inventory?",
                        isPresented: $showingUndoConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Move to Inventory", role: .destructive) {
                            let sku = sale.sku
                            store.unmakeSold(sale)
                            onUndo()
                            // Move Drive folder Sold → Inventory. onUndo() clears
                            // this panel, so feedback goes to the global toast
                            // (was previously set on dead @State). Tier 2.
                            Task {
                                do {
                                    let moved = try await GoogleDriveService.shared.moveFolder(
                                        named: sku,
                                        fromParent: soldFolderId,
                                        toParent: GoogleDriveService.shared.inventoryFolderId,
                                        credentials: credentials
                                    )
                                    if moved {
                                        router.showToast(.success, "Drive folder for \(sku) moved to Inventory")
                                    } else {
                                        router.showToast(.warning, "Restored \(sku) — Drive folder not found (skipped)")
                                    }
                                } catch {
                                    router.showToast(.error, "Restored \(sku), but Drive move failed: \(error.localizedDescription)")
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This will remove the sale record for \(sale.sku) and restore it to your inventory with Listed status.")
                    }
                }

                PMNeonDivider(color: PM.cyan).opacity(0.5)

                // P&L breakdown
                VStack(spacing: 0) {
                    SaleFinancialRow(label: "Gross Sales",      value: sale.grossSales,       style: .normal)
                    SaleFinancialRow(label: "Taxes",            value: -sale.taxes,            style: .deduction)
                    SaleFinancialRow(label: "Fees & Shipping",  value: -sale.feesAndShipping,  style: .deduction)
                    SaleFinancialRow(label: "Net Sales",        value: sale.netSales,          style: .normal)
                    SaleFinancialRow(label: "Cost of Goods",    value: -sale.totalCost,        style: .deduction)
                    Divider().overlay(PM.borderStrong)
                    SaleFinancialRow(label: "Profit / Loss",    value: sale.profit,            style: .profit)
                    SaleFinancialRow(label: "P/L %",            value: sale.profitLossPercent, style: .percent)
                }
                .pmCard(fill: PM.card, radius: PM.Radius.md)

                // Show note if financials not yet entered
                if sale.grossSales == 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("Tap Edit Sale to enter financials")
                            .font(.pmBody(size: 12))
                            .foregroundStyle(PM.textSecondary)
                    }
                }

                PMNeonDivider(color: PM.pink).opacity(0.4)

                // Item snapshot
                DetailSection(title: "Item Details") {
                    DetailRow(label: "SKU",         value: sale.sku)
                    DetailRow(label: "Size",        value: sale.size)
                    DetailRow(label: "Edition",     value: sale.edition)
                    DetailRow(label: "Print Type",  value: sale.printType)
                    DetailRow(label: "Gallery",     value: sale.gallery)
                    DetailRow(label: "Franchise",   value: sale.franchise)
                    DetailRow(label: "Theme",       value: sale.theme)
                    DetailRow(label: "Condition",   value: sale.condition)
                    DetailRow(label: "Signed",      value: sale.signed ? "Yes" : "No")
                    DetailRow(label: "Imperfect",   value: sale.imperfect ? "Yes" : "No")
                    if !sale.drawer.isEmpty { DetailRow(label: "Drawer", value: sale.drawer) }
                    if !sale.sleeveNumber.isEmpty { DetailRow(label: "Sleeve #", value: sale.sleeveNumber) }
                }

                DetailSection(title: "Acquisition") {
                    DetailRow(label: "Date Purchased",  value: sale.datePurchased?.shortDate ?? "—")
                    DetailRow(label: "Net Cost",        value: sale.netCost.asCurrency)
                    DetailRow(label: "Tax & Shipping",  value: sale.taxAndShipping.asCurrency)
                    DetailRow(label: "Total Cost",      value: sale.totalCost.asCurrency)
                    DetailRow(label: "Weight",          value: sale.weight > 0 ? "\(sale.weight) lbs" : "—")
                }

                // Photo links — images persist from inventory into sale record
                if !sale.images.isEmpty {
                    DetailSection(title: "Photo Links") {
                        ForEach(Array(sale.images.enumerated()), id: \.offset) { i, url in
                            HStack(alignment: .top) {
                                Text(i == 0 ? "Cover" : "Photo \(i + 1)")
                                    .font(.pmBody(size: 13, weight: .medium))
                                    .foregroundStyle(PM.textTertiary)
                                    .textCase(.uppercase)
                                    .tracking(0.4)
                                    .frame(width: 110, alignment: .leading)
                                Text(url)
                                    .font(.pmBody(size: 11))
                                    .foregroundStyle(PM.textSecondary)
                                    .textSelection(.enabled)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundStyle(PM.cyan)
                                }
                                .buttonStyle(.plain)
                                .help("Copy URL to clipboard")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            Divider().padding(.leading, 10)
                        }
                    }
                }

                DetailSection(title: "Sale Details") {
                    DetailRow(label: "Date Sold",       value: sale.dateSold.shortDate)
                    DetailRow(label: "Date Listed",     value: sale.dateListed?.shortDate ?? "—")
                    DetailRow(label: "Days in Inv.",    value: sale.daysInInventory > 0 ? "\(sale.daysInInventory) days" : "—")
                    DetailRow(label: "Days to Sell",    value: sale.daysToSell > 0 ? "\(sale.daysToSell) days" : "—")
                    DetailRow(label: "eBay Price",      value: sale.ebayPrice > 0 ? sale.ebayPrice.asCurrency : "—")
                    DetailRow(label: "Shopify Price",   value: sale.shopifyPrice > 0 ? sale.shopifyPrice.asCurrency : "—")
                    DetailRow(label: "eBay Title",      value: sale.ebayTitle)
                }
            }
            .padding()
        }
        .pmScreen()
        .sheet(isPresented: $showingEditSheet) {
            SaleEditSheet(sale: sale)
                .environment(store)
        }
    }
}

// MARK: - Financial Row

struct SaleFinancialRow: View {
    let label: String
    let value: Double
    enum Style { case normal, deduction, profit, percent }
    let style: Style

    var displayValue: String {
        style == .percent ? value.asPercent : value.asCurrency
    }

    var color: Color {
        switch style {
        case .deduction: return PM.textSecondary
        case .profit:    return value >= 0 ? .green : .red
        case .percent:   return value >= 40 ? .green : value >= 0 ? PM.textPrimary : .red
        default:         return PM.cyan
        }
    }

    var isBold: Bool { style == .profit || style == .percent }

    var body: some View {
        HStack {
            Text(label)
                .font(.pmBody(size: 13, weight: isBold ? .semibold : .regular))
                .foregroundStyle(style == .deduction ? PM.textSecondary : PM.textPrimary)
            Spacer()
            Text(displayValue)
                .font(isBold ? .pmDisplay(size: 16) : .pmBody(size: 13, weight: .medium))
                .foregroundStyle(color)
                .monospacedDigit()
                .pmGlow(color, radius: isBold ? 4 : 0, opacity: isBold ? 0.30 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}

// MARK: - Marketplace Badge

struct MarketplaceBadge: View {
    let marketplace: Marketplace
    var flat: Bool = false   // true in the table column; detail header keeps the glow

    var color: Color {
        switch marketplace {
        case .ebay:      return .orange
        case .shopify:   return .green
        case .instagram: return .purple
        case .facebook:  return .blue
        case .inPerson:  return .teal
        case .other:     return Color(.systemGray)
        }
    }

    var body: some View {
        PMGlowBadge(text: marketplace.rawValue, color: color, flat: flat)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.pmBody(size: 12, weight: isActive ? .semibold : .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    isActive ? PM.pink.opacity(0.14) :
                    hovering ? PM.raised : PM.card,
                    in: RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                        .strokeBorder(isActive ? PM.pink.opacity(0.5) : PM.borderSubtle, lineWidth: 1)
                )
                .foregroundStyle(isActive ? PM.pink : PM.textSecondary)
                .pmGlow(PM.pink, radius: isActive ? 5 : 0, opacity: isActive ? 0.25 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isIn in
            withAnimation(PM.Anim.hover) { hovering = isIn }
        }
    }
}
