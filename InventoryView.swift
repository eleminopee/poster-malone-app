import SwiftUI

// ============================================================================
// InventoryView.swift — inventory screen shell
// Stat bar sits on PM.surface under a neon hairline; the new StatCard glow
// tiles arrive via the cascade. All sheets, search, and toolbar actions are
// unchanged in behavior.
// ============================================================================

struct InventoryView: View {
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @Environment(ColumnSettings.self) var columnSettings
    @State private var selectedItem: InventoryItem? = nil
    @State private var searchText = ""
    @State private var showingAddSheet = false
    @State private var showingEbay = false
    @State private var showingShopify = false

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        StatCard(label: "Items",        value: "\(store.items.count)",              icon: "archivebox")
                        StatCard(label: "Value",        value: store.totalInventoryValue.asCurrency, icon: "dollarsign")
                        StatCard(label: "Cost Basis",   value: store.totalCostBasis.asCurrency,      icon: "cart")
                        StatCard(label: "Avg Margin",   value: store.averageMargin.asPercent,         icon: "percent")
                        StatCard(label: "Total Sold",   value: "\(store.sales.count)",               icon: "checkmark.circle")
                        StatCard(label: "All-Time P/L", value: store.totalProfit.asCurrency,         icon: "chart.line.uptrend.xyaxis")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(PM.surface)

                PMNeonDivider(color: PM.pink).opacity(0.5)

                if store.items.isEmpty {
                    ContentUnavailableView {
                        Label("No Inventory", systemImage: "archivebox")
                            .font(.pmDisplay(size: 22))
                            .foregroundStyle(PM.textSecondary)
                    } description: {
                        Text("Add your first item or import from your spreadsheet.")
                            .font(.pmBody(size: 13))
                            .foregroundStyle(PM.textTertiary)
                    } actions: {
                        Button("Add Item") { showingAddSheet = true }
                            .buttonStyle(PMPrimaryButtonStyle())
                            .frame(maxWidth: 180)
                    }
                } else {
                    // Bulk bar and sheet triggers live in InventoryTableView (owns selectedIDs)
                    InventoryTableView(
                        searchText: searchText,
                        selectedItem: $selectedItem
                    )
                }
            }
            .frame(minWidth: 500)

            if let item = selectedItem {
                ItemDetailPanel(
                    item: item,
                    searchText: $searchText,
                    selectedItem: $selectedItem
                )
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)
                .id(item.id)
            }
        }
        .pmScreen()
        .navigationTitle("Inventory")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search artist, title, SKU...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Item", systemImage: "plus") { showingAddSheet = true }
                    .foregroundStyle(PM.pink)
                    .help("Add a new item to inventory with an auto-assigned SKU")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingShopify = true } label: {
                    Label("Shopify", systemImage: "bag")
                }
                .foregroundStyle(Color(red: 0.22, green: 0.67, blue: 0.33))
                .help("Shopify Automation — generate descriptions, push products to Shopify, or export CSV")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingEbay = true } label: {
                    Label("eBay", systemImage: "cart.badge.plus")
                }
                .foregroundStyle(.orange)
                .help("eBay Automation — export draft listings, schedule listings, process sold orders")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ItemEditSheet(item: InventoryItem())
                .environment(store)
                .environment(credentials)
        }
        .sheet(isPresented: $showingEbay) {
            EbayAutomationView()
                .environment(store)
                .environment(credentials)
        }
        .sheet(isPresented: $showingShopify) {
            ShopifyAutomationView()
                .environment(store)
                .environment(credentials)
        }
    }
}
