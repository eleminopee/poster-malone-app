import SwiftUI

// ============================================================================
// InventoryTableView.swift — the trading floor
// Visual overhaul only. All mechanisms preserved:
//   • Bulk actions are driven by the checkbox column toggling action = "Y";
//     every bulk operation reads actionYItems, never selectedIDs.
//   • Sorting, column filters, search, context menu, sheets, notifications,
//     and toolbar quick-filters are byte-for-byte the same logic.
// New chrome: dark striped table, neon checkbox column, glow badges,
// pink-ringed filter chips, and a floating bulk-action dock that slides up
// from the bottom when 1+ items are checked.
// ============================================================================

// MARK: - Column Filter Model

struct ColumnFilter: Identifiable, Equatable {
    let id = UUID()
    let column: InventoryColumn
    var selectedValues: Set<String>   // empty = no filter (show all)

    var isActive: Bool { !selectedValues.isEmpty }

    func matches(_ item: InventoryItem) -> Bool {
        guard isActive else { return true }
        return selectedValues.contains(stringValue(for: item))
    }

    func stringValue(for item: InventoryItem) -> String {
        switch column {
        case .action:          return item.action.uppercased() == "Y" ? "Yes" : "No"
        case .photo:           return item.images.isEmpty ? "No Photo" : "Has Photo"
        case .sku:             return item.sku
        case .artist:          return item.artist
        case .title:           return item.title
        case .size:            return item.size
        case .gallery:         return item.gallery
        case .edition:         return item.edition
        case .printType:       return item.printType
        case .condition:       return item.condition
        case .signed:          return item.signed ? "Signed" : "Unsigned"
        case .drawer:          return item.drawer
        case .sleeve:          return item.sleeveNumber
        case .ebayPrice:       return item.ebayPrice > 0 ? item.ebayPrice.asCurrency : "No Price"
        case .shopifyPrice:    return item.shopifyPrice > 0 ? item.shopifyPrice.asCurrency : "No Price"
        case .netCost:         return item.netCost > 0 ? item.netCost.asCurrency : "No Cost"
        case .daysOwned:       return "\(item.daysSincePurchase) days"
        case .dateListed:      return item.dateListed?.shortDate ?? "Not Listed"
        case .datePurchased:   return item.datePurchased?.shortDate ?? "Unknown"
        case .franchise:       return item.franchise.isEmpty ? "(none)" : item.franchise
        case .theme:           return item.theme.isEmpty ? "(none)" : item.theme
        case .status:          return item.status.rawValue
        case .marketplace:     return item.listingMarketplace.rawValue
        case .ebayStatus:      return item.ebayListingStatus.isEmpty ? "Unlisted" : item.ebayListingStatus
        case .shopifyStatus:   return item.shopifyStatus.isEmpty ? "Not Listed" : item.shopifyStatus
        case .igPost:          return item.igStatus == "Posted" ? "Posted" : item.igPost ? "Queued" : "Not Queued"
        }
    }
}

// MARK: - Inventory Table View

struct InventoryTableView: View {
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @Environment(ColumnSettings.self) var columnSettings
    @Environment(PMRouter.self) var router
    let searchText: String
    @Binding var selectedItem: InventoryItem?

    // @State owns the Table selection — lives here so no parent rebuild can wipe it
    @State private var selectedIDs: Set<InventoryItem.ID> = []

    @State private var sortOrder: [KeyPathComparator<InventoryItem>] = [
        .init(\.sku, order: .reverse)
    ]

    // Filter state
    @State private var filters: [InventoryColumn: ColumnFilter] = [:]
    @State private var activeFilterColumn: InventoryColumn? = nil
    @State private var showFilterBar = false
    @State private var showingOldestListings = false
    @State private var showingNeedsListing = false
    @State private var showingNoDescription = false
    @State private var showingLongTitles = false
    @State private var showingNotOnShopify = false   // #1
    @State private var showingNeedsPhotos = false    // #5
    @State private var showingNeedsShopifyCopy = false   // missing Shopify title/desc

    // Sheet state — lives here because selectedIDs lives here
    @State private var showingEbay = false
    @State private var showingBulkSell = false
    @State private var showingBulkListed = false
    @State private var bulkListedDate = Date()

    private let oldestListingsCount = 25

    // ── SESSION 4: Saved Views + range filters ──────────────────────────
    /// Built-in view predicate currently applied (.all = none).
    @State private var selectedBuiltin: BuiltinInventoryView = .all
    /// Highlighted custom view chip (its filters are loaded into `filters`).
    @State private var selectedCustomViewID: UUID? = nil
    /// Range filters — applied after column filters in recomputeVisible.
    @State private var minPrice: Double? = nil
    @State private var maxPrice: Double? = nil
    @State private var minDaysOwned: Int? = nil
    /// Save-view popover state.
    @State private var showingSaveView = false
    @State private var newViewName = ""
    /// Visible rows not yet checked — drives the Check All button label.
    @State private var uncheckedVisibleCount = 0
    /// Count of items eligible for the Oldest view (non-sold, has purchase date).
    @State private var oldestEligibleCount = 0

    /// PERF: precomputed days-since-purchase per item, rebuilt once per data
    /// change. The model's `daysSincePurchase` calls Calendar.current on every
    /// access (expensive); reading it per-row-per-render and inside the sort
    /// comparator (O(n log n) accesses) was a major cost. We compute it ONCE
    /// here against a single cached calendar + captured "now", and the Days
    /// Owned cell + sort read from this map.
    @State private var daysOwnedByID: [InventoryItem.ID: Int] = [:]

    private let savedViewStore = SavedViewStore.shared

    /// Curated intent filters — the columns people actually filter by.
    /// Any other column remains filterable via right-click on its header;
    /// it then appears here as a temporary chip while active.
    private let curatedFilterColumns: [InventoryColumn] = [
        .status, .artist, .gallery, .size, .marketplace, .signed, .drawer
    ]

    var displayedFilterColumns: [InventoryColumn] {
        var cols = curatedFilterColumns
        for col in filters.keys where !cols.contains(col) { cols.append(col) }
        if let active = activeFilterColumn, !cols.contains(active) { cols.append(active) }
        return cols
    }

    var activeFilterCount: Int {
        filters.values.filter(\.isActive).count
            + ((minPrice != nil || maxPrice != nil) ? 1 : 0)
            + (minDaysOwned != nil ? 1 : 0)
    }

    // ════════════════════════════════════════════════════════════════════
    // PERFORMANCE: derived snapshots (Session 1 fix)
    // These were previously COMPUTED PROPERTIES evaluated inside body — and
    // the ID sets were evaluated inside per-row CELL closures, meaning every
    // visible row rebuilt the entire O(n) array+Set on every render. That
    // multiplication (≈900 rows × multiple full-inventory scans) was the
    // search-clear hang.
    //
    // Now they are @State snapshots rebuilt EXACTLY ONCE per change, off the
    // render path, triggered by onChange(of: store.lastSaved) — which the
    // store touches on every mutation (add/update/delete/sync/relist all
    // call save()), so the snapshots can never go stale. Row cells do O(1)
    // Set lookups. Business logic inside recomputeDerived()/recomputeVisible()
    // is byte-identical to the old computed properties.
    // ════════════════════════════════════════════════════════════════════

    /// The rows the Table displays — search + column filters + quick filters + sort applied.
    @State private var visibleItems: [InventoryItem] = []

    /// Items with Action = "Y" across ALL inventory — drives the bulk dock & bulk ops.
    @State private var actionYItems: [InventoryItem] = []

    /// Processed items with no Listed/Active/Auction sibling (same Artist+Title).
    @State private var orphanedProcessedItems: [InventoryItem] = []
    @State private var orphanedProcessedIDs: Set<InventoryItem.ID> = []

    /// Items missing an eBay description (excludes Sold/The Vault).
    @State private var noDescriptionItems: [InventoryItem] = []
    @State private var noDescriptionIDs: Set<InventoryItem.ID> = []

    /// Items whose eBay title exceeds 80 characters (excludes Sold/The Vault).
    @State private var longTitleItems: [InventoryItem] = []
    @State private var longTitleIDs: Set<InventoryItem.ID> = []

    /// Live on eBay, not on Shopify (#1) and needs-photos (#5) snapshots.
    @State private var notOnShopifyItems: [InventoryItem] = []
    @State private var needsPhotosItems: [InventoryItem] = []
    @State private var needsShopifyCopyItems: [InventoryItem] = []

    /// Debounced copy of searchText — filtering keys off this, not raw keystrokes.
    @State private var debouncedSearch = ""

    // Items currently checked (action = "Y") — used for bulk operations
    var selectedItems: [InventoryItem] {
        actionYItems
    }

    /// Shared calendar — Calendar.current re-resolves on every access, which
    /// is costly at 920×. One cached instance for all date math in this view.
    private static let cachedCalendar = Calendar.current

    /// Compute days-since-purchase for all items once, against a single "now".
    /// The model's `daysSincePurchase` calls Calendar.current per access; doing
    /// that per-row-per-render and inside the sort comparator (O(n log n)
    /// accesses) was the beachball. This runs once per data change instead.
    private func rebuildDaysOwnedCache() {
        let now = Date()
        let cal = Self.cachedCalendar
        var map: [InventoryItem.ID: Int] = [:]
        map.reserveCapacity(store.items.count)
        for item in store.items {
            if let purchased = item.datePurchased {
                map[item.id] = cal.dateComponents([.day], from: purchased, to: now).day ?? 0
            } else {
                map[item.id] = 0
            }
        }
        daysOwnedByID = map
    }

    private func daysOwned(_ item: InventoryItem) -> Int {
        daysOwnedByID[item.id] ?? 0
    }

    /// Refreshes the local snapshots from the store's precomputed sets, then
    /// the visible rows. SESSION 3 (audit #7): the O(n) business-rule scans
    /// that used to run here now run exactly once per mutation inside
    /// InventoryStore.recomputeDerivedSets() — these are O(1) copy-on-write
    /// assignments. Called on appear and whenever the store saves.
    private func recomputeDerived() {
        rebuildDaysOwnedCache()
        orphanedProcessedItems = store.needsListingItems
        orphanedProcessedIDs   = store.needsListingIDs
        noDescriptionItems     = store.noDescriptionItems
        noDescriptionIDs       = store.noDescriptionIDs
        longTitleItems         = store.longTitleItems
        longTitleIDs           = store.longTitleIDs
        actionYItems           = store.actionYItems
        notOnShopifyItems      = store.ebayNotShopifyItems
        needsPhotosItems       = store.needsPhotosItems
        needsShopifyCopyItems  = store.needsShopifyCopyItems

        oldestEligibleCount = store.items.lazy
            .filter { $0.datePurchased != nil && $0.status != .sold }
            .count

        recomputeVisible()
    }

    /// Rebuilds only the visible rows (search/filters/sort changed; data didn't).
    /// Filtering and quick-filter precedence are byte-identical to the old
    /// `filtered` computed property — only the search source (debounced) differs.
    private func recomputeVisible() {
        let _t0 = CFAbsoluteTimeGetCurrent()
        defer {
            let ms = (CFAbsoluteTimeGetCurrent() - _t0) * 1000
            if ms > 16 {   // only log when it exceeds one frame (~16ms)
                print("⏱ recomputeVisible: \(Int(ms)) ms for \(visibleItems.count) rows")
            }
        }
        var base = store.items

        // Saved view (built-in predicate) — search and filters compose on top.
        // SESSION 4.
        if selectedBuiltin != .all {
            base = base.filter { selectedBuiltin.matches($0) }
        }

        // Search (debounced)
        if !debouncedSearch.isEmpty {
            let q = debouncedSearch.lowercased()
            base = base.filter {
                $0.artist.lowercased().contains(q) ||
                $0.title.lowercased().contains(q) ||
                $0.sku.lowercased().contains(q) ||
                $0.gallery.lowercased().contains(q) ||
                $0.franchise.lowercased().contains(q)
            }
        }

        // Column filters
        for filter in filters.values where filter.isActive {
            base = base.filter { filter.matches($0) }
        }

        // Range filters — SESSION 4
        if let minPrice {
            base = base.filter { $0.ebayPrice >= minPrice }
        }
        if let maxPrice {
            base = base.filter { $0.ebayPrice > 0 && $0.ebayPrice <= maxPrice }
        }
        if let minDaysOwned {
            base = base.filter { $0.datePurchased != nil && $0.daysSincePurchase >= minDaysOwned }
        }

        // Detect a Days-Owned sort and handle it with the cached map (the
        // KeyPath \.daysSincePurchaseSortKey calls Calendar.current per access
        // — pathological inside a comparator). All other columns use cheap keys.
        let daysKeyPath: PartialKeyPath<InventoryItem> = \InventoryItem.daysSincePurchaseSortKey
        let isDaysOwnedSort = sortOrder.first.map { $0.keyPath == daysKeyPath } ?? false
        let ascending = (sortOrder.first?.order ?? .forward) == .forward

        func applySort(_ items: [InventoryItem]) -> [InventoryItem] {
            if isDaysOwnedSort {
                return items.sorted {
                    ascending ? daysOwned($0) < daysOwned($1)
                              : daysOwned($0) > daysOwned($1)
                }
            }
            return items.sorted(using: sortOrder)
        }

        let result: [InventoryItem]
        if showingNeedsListing {
            result = applySort(orphanedProcessedItems)
        } else if showingNoDescription {
            result = applySort(noDescriptionItems)
        } else if showingLongTitles {
            result = applySort(longTitleItems)
        } else if showingNotOnShopify {
            result = applySort(notOnShopifyItems)
        } else if showingNeedsPhotos {
            result = applySort(needsPhotosItems)
        } else if showingNeedsShopifyCopy {
            result = applySort(needsShopifyCopyItems)
        } else if showingOldestListings {
            // Oldest listings — top N by days since purchase (cached), only
            // non-sold items, then ordered for display.
            let candidates = base
                .filter { $0.datePurchased != nil && $0.status != .sold }
                .sorted { daysOwned($0) > daysOwned($1) }
            result = applySort(Array(candidates.prefix(oldestListingsCount)))
        } else {
            result = applySort(base)
        }

        visibleItems = result
        uncheckedVisibleCount = result.lazy.filter { $0.action.uppercased() != "Y" }.count
    }

    // MARK: - Session 4 actions

    private enum QuickFilter { case oldest, needsListing, noDescription, longTitle, notOnShopify, needsPhotos, needsShopifyCopy }

    /// Clear every attention quick filter in one place — keeps the six
    /// mutually-exclusive booleans honest as filters are added.
    private func clearQuickFilters() {
        showingOldestListings = false
        showingNeedsListing = false
        showingNoDescription = false
        showingLongTitles = false
        showingNotOnShopify = false
        showingNeedsPhotos = false
        showingNeedsShopifyCopy = false
    }

    /// Toggle one attention filter, clearing the others — exact mutual-
    /// exclusion semantics the old toolbar buttons had.
    private func toggleQuickFilter(_ which: QuickFilter) {
        withAnimation {
            // Capture the target's current state, clear all, then restore the toggle.
            let wasOn: Bool
            switch which {
            case .oldest:        wasOn = showingOldestListings
            case .needsListing:  wasOn = showingNeedsListing
            case .noDescription: wasOn = showingNoDescription
            case .longTitle:     wasOn = showingLongTitles
            case .notOnShopify:  wasOn = showingNotOnShopify
            case .needsPhotos:   wasOn = showingNeedsPhotos
            case .needsShopifyCopy: wasOn = showingNeedsShopifyCopy
            }
            clearQuickFilters()
            if !wasOn {
                switch which {
                case .oldest:        showingOldestListings = true
                case .needsListing:  showingNeedsListing = true
                case .noDescription: showingNoDescription = true
                case .longTitle:     showingLongTitles = true
                case .notOnShopify:  showingNotOnShopify = true
                case .needsPhotos:   showingNeedsPhotos = true
                case .needsShopifyCopy: showingNeedsShopifyCopy = true
                }
            }
        }
    }

    /// Selecting a view replaces filters/ranges/quick-filters; search persists.
    private func applyBuiltin(_ view: BuiltinInventoryView) {
        withAnimation {
            selectedBuiltin = view
            selectedCustomViewID = nil
            filters.removeAll()
            minPrice = nil; maxPrice = nil; minDaysOwned = nil
            clearQuickFilters()
        }
    }

    private func applyCustom(_ view: CustomSavedView) {
        withAnimation {
            selectedBuiltin = .all
            selectedCustomViewID = view.id
            filters = savedViewStore.filters(for: view)
            minPrice = nil; maxPrice = nil; minDaysOwned = nil
            clearQuickFilters()
        }
    }

    private func clearAllFilters() {
        withAnimation {
            filters.removeAll()
            minPrice = nil; maxPrice = nil; minDaysOwned = nil
            selectedCustomViewID = nil
            selectedBuiltin = .all
            clearQuickFilters()
        }
    }

    private func saveCurrentView() {
        if let created = savedViewStore.add(name: newViewName, filters: filters) {
            selectedBuiltin = .all
            selectedCustomViewID = created.id
        }
        newViewName = ""
        showingSaveView = false
    }

    /// Check All Visible — sets action = "Y" on every visible row in ONE
    /// store pass (updateBatch = one derived recompute + one coalesced save).
    /// Filter to NOT ON SHOPIFY → Check All → Shopify push: the batch flow.
    private func checkAllVisible() {
        let toCheck = visibleItems.filter { $0.action.uppercased() != "Y" }
        guard !toCheck.isEmpty else { return }
        var batch: [InventoryItem] = []
        batch.reserveCapacity(toCheck.count)
        for var item in toCheck {
            item.action = "Y"
            batch.append(item)
        }
        store.updateBatch(batch)
    }

    /// SESSION 5: apply a one-shot deep-link filter handed over by the Today
    /// cockpit, then clear it so normal navigation isn't affected.
    private func consumePendingIntent() {
        guard let intent = router.pendingInventoryFilter else { return }
        router.pendingInventoryFilter = nil
        switch intent {
        case .needsListing:  toggleIntoQuickFilter(.needsListing)
        case .noDescription: toggleIntoQuickFilter(.noDescription)
        case .longTitle:     toggleIntoQuickFilter(.longTitle)
        case .oldest:        toggleIntoQuickFilter(.oldest)
        case .notOnShopify:  toggleIntoQuickFilter(.notOnShopify)
        case .needsPhotos:   toggleIntoQuickFilter(.needsPhotos)
        case .needsShopifyCopy: toggleIntoQuickFilter(.needsShopifyCopy)
        case .builtin(let v): applyBuiltin(v)
        }
    }

    /// Force a quick filter ON (deep-link target), clearing the others —
    /// distinct from toggleQuickFilter which flips the current state.
    private func toggleIntoQuickFilter(_ which: QuickFilter) {
        // Reset everything, then turn on the requested one.
        clearQuickFilters()
        selectedBuiltin = .all; selectedCustomViewID = nil
        filters.removeAll()
        switch which {
        case .oldest:        showingOldestListings = true
        case .needsListing:  showingNeedsListing = true
        case .noDescription: showingNoDescription = true
        case .longTitle:     showingLongTitles = true
        case .notOnShopify:  showingNotOnShopify = true
        case .needsPhotos:   showingNeedsPhotos = true
        case .needsShopifyCopy: showingNeedsShopifyCopy = true
        }
        recomputeVisible()
    }

    // Unique values for a column across ALL items (not just filtered).
    // Called lazily — only when a filter chip's popover actually opens,
    // never during filter-bar rendering (was previously evaluated for every
    // chip on every render of the filter bar).
    func uniqueValues(for column: InventoryColumn) -> [String] {
        let filter = ColumnFilter(column: column, selectedValues: [])
        return Array(Set(store.items.map { filter.stringValue(for: $0) }))
            .filter { !$0.isEmpty }
            .sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            // SESSION 4 — unified command bar: saved views + attention chips
            // + Check All Visible + result count. Always visible.
            commandBar
            Divider().overlay(PM.borderSubtle)

            // Refine bar — intent filter chips, shown when active or toggled on
            if showFilterBar || activeFilterCount > 0 {
                filterBar
                PMNeonDivider(color: PM.pink).opacity(0.5)
            }

            Table(visibleItems, selection: $selectedIDs, sortOrder: $sortOrder) {
                TableColumnForEach(columnSettings.visibleColumns, id: \.self) { col in
                    columnDefinition(for: col)
                }
            }
            .scrollContentBackground(.hidden)
            .alternatingRowBackgrounds(.enabled)
            .onChange(of: selectedIDs) { _, newValue in
                selectedItem = store.items.first { newValue.contains($0.id) }
            }
            // Right-click on table to open filter for a column
            .contextMenu {
                // Bulk sell shortcut if selection contains items
                if !selectedIDs.isEmpty {
                    let count = selectedIDs.count
                    Button {
                        NotificationCenter.default.post(
                            name: .bulkMarkSoldRequested, object: nil
                        )
                    } label: {
                        Label("Mark \(count) Selected as Sold…", systemImage: "dollarsign.circle")
                    }

                    Divider()
                }

                // Select all Action=Y items
                if !actionYItems.isEmpty {
                    Button {
                        selectedIDs = Set(actionYItems.map(\.id))
                    } label: {
                        Label("Select All Pending (Action=Y) — \(actionYItems.count)", systemImage: "checkmark.circle.badge.xmark")
                    }
                    Divider()
                }

                Menu("Filter by Column") {
                    ForEach(columnSettings.visibleColumns, id: \.self) { col in
                        Button(col.rawValue) {
                            showFilterBar = true
                            activeFilterColumn = col
                        }
                    }
                }
                if activeFilterCount > 0 {
                    Divider()
                    Button("Clear All Filters", role: .destructive) {
                        clearAllFilters()
                    }
                }
            }
        }
        .pmScreen()
        // ── PERFORMANCE WIRING (Session 1) ────────────────────────────────
        // Seed the snapshots on first appearance.
        .onAppear {
            recomputeDerived()
            consumePendingIntent()
        }
        // Any store mutation (add/update/delete/sync/relist/mark-sold) calls
        // save(), which touches lastSaved — so this is a complete, never-stale
        // change signal without observing the items array in body.
        .onChange(of: store.lastSaved) { _, _ in recomputeDerived() }
        // View-only inputs: rows change, data didn't — cheaper recompute.
        // sortOrder IS here: Table(_:sortOrder:) with a plain array does not
        // auto-sort — the binding only tracks which header is active; we apply
        // the sort ourselves in recomputeVisible.
        .onChange(of: debouncedSearch)       { _, _ in recomputeVisible() }
        .onChange(of: filters)               { _, _ in recomputeVisible() }
        .onChange(of: sortOrder)             { _, _ in recomputeVisible() }
        .onChange(of: showingOldestListings) { _, _ in recomputeVisible() }
        .onChange(of: showingNeedsListing)   { _, _ in recomputeVisible() }
        .onChange(of: showingNoDescription)  { _, _ in recomputeVisible() }
        .onChange(of: showingLongTitles)     { _, _ in recomputeVisible() }
        // SESSION 4 inputs
        .onChange(of: selectedBuiltin)       { _, _ in recomputeVisible() }
        .onChange(of: minPrice)              { _, _ in recomputeVisible() }
        .onChange(of: maxPrice)              { _, _ in recomputeVisible() }
        .onChange(of: minDaysOwned)          { _, _ in recomputeVisible() }
        // Debounce: typing waits 200ms of quiet before filtering; CLEARING
        // applies instantly (the recompute is cheap now, and an instant clear
        // feels right).
        .task(id: searchText) {
            if searchText.isEmpty {
                debouncedSearch = ""
            } else {
                try? await Task.sleep(for: .milliseconds(200))
                if !Task.isCancelled { debouncedSearch = searchText }
            }
        }
        // ──────────────────────────────────────────────────────────────────
        // Floating bulk-action dock — slides up from the bottom when 1+ items
        // are checked. Still 100% driven by action = "Y" (actionYItems).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if actionYItems.count >= 1 {
                BulkActionDock(
                    checkedCount: actionYItems.count,
                    onMarkListed: {
                        bulkListedDate = Date()
                        showingBulkListed = true
                    },
                    onMarkSold: { showingBulkSell = true },
                    onEbay: { showingEbay = true },
                    onUncheckAll: {
                        // Uncheck all — set action = "" for all checked items
                        // (SESSION 4: one batch = one recompute + one save)
                        var batch: [InventoryItem] = []
                        for var item in actionYItems {
                            item.action = ""
                            batch.append(item)
                        }
                        store.updateBatch(batch)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(PM.Anim.slide, value: actionYItems.count >= 1)
        .sheet(isPresented: $showingEbay) {
            EbayAutomationView(preselectedIDs: Set(actionYItems.map(\.id)))
                .environment(store)
                .environment(credentials)
        }
        .sheet(isPresented: $showingBulkSell) {
            BulkMarkSoldSheet(items: selectedItems)
                .environment(store)
        }
        .sheet(isPresented: $showingBulkListed) {
            BulkMarkListedSheet(items: selectedItems, listedDate: $bulkListedDate) {
                // SESSION 4: one batch = one recompute + one save
                var batch: [InventoryItem] = []
                for var item in selectedItems {
                    item.status = .listed
                    item.dateListed = bulkListedDate
                    item.action = ""   // uncheck after marking listed
                    batch.append(item)
                }
                store.updateBatch(batch)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bulkMarkSoldRequested)) { _ in
            if !selectedItems.isEmpty { showingBulkSell = true }
        }
        .toolbar {
            // SESSION 4: the quick-filter buttons (Show Older Listings,
            // Needs Listing, No Description, Long Title) moved into the
            // command bar as attention chips — the toolbar is actions only.

            // Apply all suggested prices — only shown when viewing oldest listings
            if showingOldestListings {
                ToolbarItem(placement: .primaryAction) {
                    let eligible = visibleItems.filter { $0.suggestedSalePrice != nil }
                    Button {
                        // SESSION 4: one batch = one recompute + one save
                        var batch: [InventoryItem] = []
                        for var item in eligible {
                            guard let suggested = item.suggestedSalePrice else { continue }
                            item.ebayPrice    = suggested
                            item.shopifyPrice = (suggested * 0.80 * 100).rounded() / 100
                            item.priceUpdatedAt = Date()
                            batch.append(item)
                        }
                        store.updateBatch(batch)
                    } label: {
                        VStack(spacing: 1) {
                            Text("Apply All Suggestions")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text("\(eligible.count) item\(eligible.count == 1 ? "" : "s") eligible")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.orange)
                    .disabled(eligible.isEmpty)
                    .help("Apply suggested sale prices to all \(eligible.count) eligible items in this view")
                }
            }
            if !actionYItems.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        selectedIDs = Set(actionYItems.map(\.id))
                    } label: {
                        Label("Select Pending (\(actionYItems.count))", systemImage: "checkmark.circle.badge.xmark")
                    }
                    .help("Select all items with Action=Y (marked sold by Process Sold Listings)")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    withAnimation { showFilterBar.toggle() }
                } label: {
                    Label(
                        activeFilterCount > 0 ? "Refine (\(activeFilterCount))" : "Refine",
                        systemImage: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                    )
                }
                .foregroundStyle(activeFilterCount > 0 ? PM.pink : .primary)
                .help("Show/hide the refine bar — intent filters and price/days ranges")
            }
        }

    }

    // MARK: - Command Bar (SESSION 4)
    // One filtering home: saved views, attention chips, Check All Visible,
    // and the live result count.

    var commandBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("VIEWS")
                    .font(.pmBody(size: 11, weight: .semibold))
                    .foregroundStyle(PM.textTertiary)
                    .tracking(1.2)
                    .padding(.leading, 4)

                ForEach(BuiltinInventoryView.allCases) { view in
                    SavedViewChip(
                        label: view.label,
                        isOn: selectedBuiltin == view && selectedCustomViewID == nil,
                        help: view.help
                    ) {
                        applyBuiltin(view)
                    }
                }

                ForEach(savedViewStore.views) { custom in
                    SavedViewChip(
                        label: custom.name.uppercased(),
                        isOn: selectedCustomViewID == custom.id,
                        help: "Saved view — right-click to delete"
                    ) {
                        applyCustom(custom)
                    }
                    .contextMenu {
                        Button("Delete \"\(custom.name)\"", role: .destructive) {
                            if selectedCustomViewID == custom.id { selectedCustomViewID = nil }
                            savedViewStore.delete(custom.id)
                        }
                    }
                }

                // Save the current column filters as a named view
                if filters.values.contains(where: \.isActive) {
                    Button {
                        newViewName = ""
                        showingSaveView = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PM.cyan)
                    .background(PM.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(PM.cyan.opacity(0.35), lineWidth: 1))
                    .help("Save the current filters as a named view")
                    .popover(isPresented: $showingSaveView, arrowEdge: .bottom) {
                        saveViewPopover
                    }
                }

                Divider().frame(height: 16).overlay(PM.borderStrong)

                Text("ATTENTION")
                    .font(.pmBody(size: 11, weight: .semibold))
                    .foregroundStyle(PM.textTertiary)
                    .tracking(1.2)

                if !orphanedProcessedItems.isEmpty {
                    AttentionChip(
                        label: "Needs Listing", count: orphanedProcessedItems.count,
                        color: .orange, isOn: showingNeedsListing,
                        help: "Processed items with no active listing for the same Artist + Title"
                    ) { toggleQuickFilter(.needsListing) }
                }
                if !noDescriptionItems.isEmpty {
                    AttentionChip(
                        label: "No Description", count: noDescriptionItems.count,
                        color: .purple, isOn: showingNoDescription,
                        help: "Items missing an eBay description"
                    ) { toggleQuickFilter(.noDescription) }
                }
                if !longTitleItems.isEmpty {
                    AttentionChip(
                        label: "Long Title", count: longTitleItems.count,
                        color: .red, isOn: showingLongTitles,
                        help: "Items whose eBay title exceeds 80 characters — eBay's limit is 80"
                    ) { toggleQuickFilter(.longTitle) }
                }
                if !notOnShopifyItems.isEmpty {
                    AttentionChip(
                        label: "Not on Shopify", count: notOnShopifyItems.count,
                        color: PM.cyan, isOn: showingNotOnShopify,
                        help: "Live on eBay but not on Shopify (\(store.ebayNotShopifyValue.asCurrency) in listed value) — Check All, then push to Shopify"
                    ) { toggleQuickFilter(.notOnShopify) }
                }
                if !needsPhotosItems.isEmpty {
                    AttentionChip(
                        label: "Needs Photos", count: needsPhotosItems.count,
                        color: .yellow, isOn: showingNeedsPhotos,
                        help: "Sellable items with no photos — can't list, push to Shopify, or post to IG"
                    ) { toggleQuickFilter(.needsPhotos) }
                }
                if !needsShopifyCopyItems.isEmpty {
                    AttentionChip(
                        label: "Needs Shopify Copy", count: needsShopifyCopyItems.count,
                        color: PM.pink, isOn: showingNeedsShopifyCopy,
                        help: "Sellable items missing a Shopify title or description — filter, select, then Generate Title & Description"
                    ) { toggleQuickFilter(.needsShopifyCopy) }
                }
                AttentionChip(
                    label: "Oldest", count: min(oldestListingsCount, oldestEligibleCount),
                    color: .orange, isOn: showingOldestListings,
                    help: "The 25 oldest listings by days since purchase — pairs with Apply All Suggestions in the toolbar"
                ) { toggleQuickFilter(.oldest) }

                Divider().frame(height: 16).overlay(PM.borderStrong)

                // Check All Visible — sets action = "Y" on every visible row.
                Button {
                    checkAllVisible()
                } label: {
                    Label("Check All (\(uncheckedVisibleCount))", systemImage: "checkmark.square")
                        .font(.pmBody(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(uncheckedVisibleCount > 0 ? PM.pink : PM.textTertiary)
                .disabled(uncheckedVisibleCount == 0)
                .help("Check every visible row for bulk actions — e.g. NOT ON SHOPIFY → Check All → Shopify push")

                Spacer(minLength: 16)

                Text("\(visibleItems.count) of \(store.items.count)")
                    .font(.pmBody(size: 12))
                    .foregroundStyle(PM.textTertiary)
                    .monospacedDigit()
                    .padding(.trailing, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(PM.surface)
    }

    var saveViewPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SAVE VIEW")
                .font(.pmDisplay(size: 14))
                .foregroundStyle(PM.textPrimary)
                .tracking(1.0)
            TextField("View name", text: $newViewName)
                .textFieldStyle(.plain)
                .font(.pmBody(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(PM.base, in: RoundedRectangle(cornerRadius: PM.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: PM.Radius.sm)
                        .strokeBorder(PM.borderStrong, lineWidth: 1)
                )
                .onSubmit { saveCurrentView() }
            HStack {
                Button("Cancel") { showingSaveView = false }
                    .buttonStyle(PMGhostButtonStyle())
                Button("Save") { saveCurrentView() }
                    .buttonStyle(PMTintButtonStyle(tint: PM.pink))
                    .disabled(newViewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 240)
        .background(PM.raised)
        .preferredColorScheme(.dark)
    }

    // MARK: - Filter Bar

    var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("REFINE")
                    .font(.pmBody(size: 11, weight: .semibold))
                    .foregroundStyle(PM.textTertiary)
                    .tracking(1.2)
                    .padding(.leading, 4)

                // SESSION 4: curated intent filters, not a chip per visible
                // column. Other columns: right-click their header — they
                // appear here as a temporary chip while active.
                ForEach(displayedFilterColumns, id: \.self) { col in
                    ColumnFilterChip(
                        column: col,
                        filter: Binding(
                            get: { filters[col] ?? ColumnFilter(column: col, selectedValues: []) },
                            set: { newFilter in
                                if newFilter.isActive {
                                    filters[col] = newFilter
                                } else {
                                    filters.removeValue(forKey: col)
                                }
                            }
                        ),
                        uniqueValuesProvider: { uniqueValues(for: col) },
                        isOpen: activeFilterColumn == col,
                        onOpen: { activeFilterColumn = col },
                        onClose: { if activeFilterColumn == col { activeFilterColumn = nil } }
                    )
                }

                // SESSION 4: range filters
                PriceRangeChip(minValue: $minPrice, maxValue: $maxPrice)
                MinDaysChip(minDays: $minDaysOwned)

                if activeFilterCount > 0 {
                    Button {
                        clearAllFilters()
                    } label: {
                        Label("Clear All", systemImage: "xmark.circle.fill")
                            .font(.pmBody(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Remove all active filters and ranges")
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .background(PM.surface)
    }

    // MARK: - Column Definitions

    @TableColumnBuilder<InventoryItem, KeyPathComparator<InventoryItem>>
    func columnDefinition(for col: InventoryColumn) -> some TableColumnContent<InventoryItem, KeyPathComparator<InventoryItem>> {
        switch col {
        case .action:
            TableColumn("✓", value: \.action) { item in
                CheckboxCell(item: item) { updated in store.update(updated) }
            }
            .width(44)

        case .photo:
            TableColumn("", value: \.sku) { item in
                ThumbnailView(url: item.primaryImage, flat: true)
                    .frame(width: 36, height: 36)
            }
            .width(44)

        case .sku:
            TableColumn("SKU", value: \.sku) { item in
                HStack(spacing: 4) {
                    // Show all applicable indicators as stacked colored dots
                    let needsListing  = orphanedProcessedIDs.contains(item.id)
                    let titleTooLong  = longTitleIDs.contains(item.id)
                    let noDesc        = noDescriptionIDs.contains(item.id)
                    if needsListing || titleTooLong || noDesc {
                        VStack(spacing: 2) {
                            if needsListing {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.orange)
                                    .frame(width: 3, height: needsListing && (titleTooLong || noDesc) ? 8 : 16)
                            }
                            if titleTooLong {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.red)
                                    .frame(width: 3, height: titleTooLong && (needsListing || noDesc) ? 8 : 16)
                            }
                            if noDesc {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.purple)
                                    .frame(width: 3, height: noDesc && (needsListing || titleTooLong) ? 8 : 16)
                            }
                        }
                    }
                    Text(item.sku)
                        .font(.caption)
                        .foregroundStyle(needsListing ? .orange : .primary)
                }
            }
            .width(min: 80, ideal: 100)

        case .artist:
            TableColumn("Artist", value: \.artist)
                .width(min: 120, ideal: 150)

        case .title:
            TableColumn("Title", value: \.title)
                .width(min: 150, ideal: 220)

        case .size:
            TableColumn("Size", value: \.size)
                .width(min: 60, ideal: 80)

        case .gallery:
            TableColumn("Gallery", value: \.gallery)
                .width(min: 80, ideal: 110)

        case .edition:
            TableColumn("Edition", value: \.edition)
                .width(min: 70, ideal: 90)

        case .printType:
            TableColumn("Print Type", value: \.printType)
                .width(min: 90, ideal: 110)

        case .condition:
            TableColumn("Condition", value: \.condition)
                .width(min: 60, ideal: 80)

        case .signed:
            TableColumn("Signed", value: \.signedSortKey) { item in
                if item.signed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .width(60)

        case .drawer:
            TableColumn("Drawer", value: \.drawer)
                .width(min: 55, ideal: 70)

        case .sleeve:
            TableColumn("Sleeve #", value: \.sleeveNumber)
                .width(min: 55, ideal: 70)

        case .ebayPrice:
            TableColumn("eBay Price", value: \.ebayPrice) { item in
                Text(item.ebayPrice > 0 ? item.ebayPrice.asCurrency : "—")
                    .foregroundStyle(item.ebayPrice > 0 ? PM.cyan : PM.textTertiary)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90)

        case .shopifyPrice:
            TableColumn("Shopify Price", value: \.shopifyPrice) { item in
                Text(item.shopifyPrice > 0 ? item.shopifyPrice.asCurrency : "—")
                    .foregroundStyle(item.shopifyPrice > 0 ? PM.cyan : PM.textTertiary)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90)

        case .netCost:
            TableColumn("Cost", value: \.netCost) { item in
                Text(item.netCost > 0 ? item.netCost.asCurrency : "—")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 60, ideal: 80)

        case .daysOwned:
            TableColumn("Days Owned", value: \.daysSincePurchaseSortKey) { item in
                let days = daysOwned(item)   // cached — no Calendar per render
                HStack(spacing: 4) {
                    if days >= 180 {
                        Circle()
                            .fill(days >= 365 ? Color.red : Color.orange)
                            .frame(width: 6, height: 6)
                    }
                    Text(item.datePurchased != nil ? "\(days)" : "—")
                        .foregroundStyle(
                            days >= 365 ? .red :
                            days >= 180 ? .orange : .primary
                        )
                        .monospacedDigit()
                }
            }
            .width(min: 60, ideal: 80)

        case .dateListed:
            TableColumn("Date Listed", value: \.dateListedSortKey) { item in
                Text(item.dateListed?.shortDate ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)

        case .datePurchased:
            TableColumn("Date Purchased", value: \.datePurchasedSortKey) { item in
                Text(item.datePurchased?.shortDate ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110)

        case .franchise:
            TableColumn("Franchise", value: \.franchise)
                .width(min: 90, ideal: 120)

        case .theme:
            TableColumn("Theme", value: \.theme)
                .width(min: 80, ideal: 100)

        case .status:
            TableColumn("Status", value: \.status.rawValue) { item in
                StatusBadge(status: item.status, flat: true)
            }
            .width(min: 70, ideal: 90)

        case .marketplace:
            TableColumn("Marketplace", value: \.listingMarketplaceSortKey) { item in
                ListingMarketplaceBadge(marketplace: item.listingMarketplace)
            }
            .width(min: 80, ideal: 100)

        case .ebayStatus:
            TableColumn("eBay Status", value: \.ebayListingStatus) { item in
                EbayStatusBadge(status: item.ebayListingStatus)
            }
            .width(min: 70, ideal: 90)

        case .shopifyStatus:
            TableColumn("Shopify Status", value: \.shopifyStatus) { item in
                ShopifyStatusBadge(status: item.shopifyStatus)
            }
            .width(min: 80, ideal: 100)

        case .igPost:
            TableColumn("IG", value: \.igPostSortKey) { item in
                if item.igStatus == "Posted" {
                    Image(systemName: "camera.fill")
                        .foregroundStyle(PM.pink)
                        .help("Posted to Instagram")
                } else if item.igPost {
                    Image(systemName: "camera.badge.clock").foregroundStyle(.purple)
                        .help("Queued for Instagram")
                } else {
                    Image(systemName: "camera").foregroundStyle(.tertiary)
                }
            }
            .width(44)
        }
    }
}

// MARK: - Bulk Action Dock
// Floating glow-bordered bar that slides up from the bottom.
// Child struct receives plain values + closures — no store access, no
// computed props in a large body (re-render trap safe).
// Mechanism unchanged: visibility & counts come from actionYItems upstream.

struct BulkActionDock: View {
    let checkedCount: Int
    let onMarkListed: () -> Void
    let onMarkSold: () -> Void
    let onEbay: () -> Void
    let onUncheckAll: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PM.pink)
                    .pmGlow(PM.pink, radius: 5, opacity: 0.6)
                Text("\(checkedCount) ITEM\(checkedCount == 1 ? "" : "S") CHECKED")
                    .font(.pmDisplay(size: 15))
                    .foregroundStyle(PM.textPrimary)
                    .tracking(1.0)
            }

            Spacer()

            Button(action: onMarkListed) {
                Label("Mark as Listed", systemImage: "checkmark.circle")
            }
            .buttonStyle(PMTintButtonStyle(tint: .blue))
            .help("Set status to Listed and stamp today's date on all checked items")

            Button(action: onMarkSold) {
                Label("Mark as Sold", systemImage: "dollarsign.circle.fill")
            }
            .buttonStyle(PMTintButtonStyle(tint: .green))
            .help("Record all checked items as sold")

            Button(action: onEbay) {
                Label("eBay", systemImage: "cart.badge.plus")
            }
            .buttonStyle(PMTintButtonStyle(tint: .orange))
            .help("Open eBay Automation with the checked items preselected")

            Button(action: onUncheckAll) {
                Image(systemName: "xmark")
            }
            .buttonStyle(PMGhostButtonStyle())
            .help("Uncheck all")
        }
        .padding(.horizontal, PM.Space.lg)
        .padding(.vertical, PM.Space.md)
        .background(PM.raised.opacity(0.97), in: RoundedRectangle(cornerRadius: PM.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PM.Radius.xl, style: .continuous)
                .strokeBorder(PM.gradient, lineWidth: 1)
                .opacity(0.7)
        )
        .pmGlow(PM.pink, radius: 14, opacity: 0.20)
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 6)
        .padding(.horizontal, PM.Space.lg)
        .padding(.bottom, PM.Space.md)
    }
}

// MARK: - Column Filter Chip
// One chip per column in the filter bar. Shows a popover with checkboxes for each unique value.

struct ColumnFilterChip: View {
    let column: InventoryColumn
    @Binding var filter: ColumnFilter
    /// PERFORMANCE (Session 1): values are fetched lazily when the popover
    /// opens, not eagerly per chip per render — the old eager array meant
    /// every render of the filter bar scanned the full inventory once per
    /// visible column.
    let uniqueValuesProvider: () -> [String]
    let isOpen: Bool
    let onOpen: () -> Void
    let onClose: () -> Void

    @State private var showPopover = false
    @State private var searchText = ""
    @State private var hovering = false
    @State private var uniqueValues: [String] = []

    var isActive: Bool { filter.isActive }

    var displayedValues: [String] {
        searchText.isEmpty ? uniqueValues
            : uniqueValues.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Button {
            showPopover.toggle()
            if showPopover {
                uniqueValues = uniqueValuesProvider()   // lazy fetch — once per open
                onOpen()
            } else {
                onClose()
            }
        } label: {
            HStack(spacing: 4) {
                Text(column.rawValue)
                    .font(.pmBody(size: 12, weight: isActive ? .semibold : .medium))
                if isActive {
                    Text("\(filter.selectedValues.count)")
                        .font(.pmBody(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(PM.pink, in: Capsule())
                        .pmGlow(PM.pink, radius: 3, opacity: 0.5)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .rotationEffect(showPopover ? .degrees(180) : .zero)
            }
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
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            filterPopover
        }
        .help(isActive
              ? "Filtering \(column.rawValue) — \(filter.selectedValues.count) value(s) selected"
              : "Filter by \(column.rawValue)")
    }

    var filterPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(column.rawValue)
                    .font(.pmDisplay(size: 16))
                    .foregroundStyle(PM.textPrimary)
                    .tracking(0.8)
                Spacer()
                if filter.isActive {
                    Button("Clear") {
                        filter = ColumnFilter(column: column, selectedValues: [])
                    }
                    .font(.pmBody(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            PMNeonDivider(color: PM.pink).opacity(0.6)

            // Sort controls
            VStack(spacing: 0) {
                ForEach(["Sort A → Z", "Sort Z → A"], id: \.self) { label in
                    Button {
                        // Communicate sort direction back — handled via menu only since
                        // Table's sortOrder binding is the source of truth for sort.
                        // This is informational; user can click column header for sort.
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: label.contains("A →") ? "arrow.up" : "arrow.down")
                                .font(.caption)
                                .frame(width: 16)
                            Text(label)
                                .font(.pmBody(size: 13))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(PM.textSecondary)
                }
            }

            Divider().overlay(PM.borderSubtle)

            // Search within values
            if uniqueValues.count > 8 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(PM.textTertiary)
                        .font(.caption)
                    TextField("Search values...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.pmBody(size: 13))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(PM.base)

                Divider().overlay(PM.borderSubtle)
            }

            // Select All / Deselect All
            HStack(spacing: 12) {
                Button("Select All") {
                    filter = ColumnFilter(column: column,
                                         selectedValues: Set(uniqueValues))
                }
                .font(.pmBody(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(PM.cyan)

                Button("Deselect All") {
                    filter = ColumnFilter(column: column, selectedValues: [])
                }
                .font(.pmBody(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(PM.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider().overlay(PM.borderSubtle)

            // Value checkboxes
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(displayedValues, id: \.self) { value in
                        let isChecked = filter.selectedValues.contains(value)
                        Button {
                            var newSelected = filter.selectedValues
                            if isChecked {
                                newSelected.remove(value)
                            } else {
                                newSelected.insert(value)
                            }
                            filter = ColumnFilter(column: column, selectedValues: newSelected)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(isChecked ? PM.pink : PM.textTertiary)
                                    .font(.subheadline)
                                Text(value)
                                    .font(.pmBody(size: 13))
                                    .foregroundStyle(PM.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isChecked ? PM.pink.opacity(0.08) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 260)

            Divider().overlay(PM.borderSubtle)

            // Done
            HStack {
                Text("\(displayedValues.count) values")
                    .font(.pmBody(size: 11))
                    .foregroundStyle(PM.textTertiary)
                Spacer()
                Button("Done") {
                    showPopover = false
                    onClose()
                }
                .buttonStyle(PMTintButtonStyle(tint: PM.pink))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 240)
        .background(PM.raised)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Checkbox Cell
// Same mechanism: Toggle bound to item.isActive, which flips action "Y"/"".
// Only the visual style changed (neon checkbox).

struct CheckboxCell: View {
    let item: InventoryItem
    let onUpdate: (InventoryItem) -> Void

    var body: some View {
        Toggle("", isOn: Binding(
            get: { item.isActive },
            set: { newValue in
                var updated = item
                updated.isActive = newValue
                onUpdate(updated)
            }
        ))
        .toggleStyle(PMNeonCheckboxStyle())
        .labelsHidden()
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let bulkMarkSoldRequested  = Notification.Name("bulkMarkSoldRequested")
    static let openEbayMarkListed     = Notification.Name("openEbayMarkListed")
}

// MARK: - Listing Marketplace Badge

struct ListingMarketplaceBadge: View {
    let marketplace: ListingMarketplace

    var color: Color {
        switch marketplace {
        case .ebay:     return Color(red: 0.0, green: 0.4, blue: 0.8)   // eBay blue
        case .shopify:  return Color(red: 0.22, green: 0.67, blue: 0.33) // Shopify green
        case .both:     return .purple
        case .none:     return .secondary
        }
    }

    var icon: String {
        switch marketplace {
        case .ebay:    return "cart.fill"
        case .shopify: return "bag.fill"
        case .both:    return "arrow.left.arrow.right"
        case .none:    return "minus"
        }
    }

    var body: some View {
        if marketplace == .none {
            Text("—").font(.caption2).foregroundStyle(.tertiary)
        } else {
            PMGlowBadge(text: marketplace.rawValue, color: color, icon: icon, flat: true)
        }
    }
}

// MARK: - eBay Status Badge

struct EbayStatusBadge: View {
    let status: String

    var display: (label: String, color: Color, icon: String) {
        switch status.lowercased() {
        case "active":  return ("Active",   .green,     "checkmark.circle.fill")
        default:        return ("Unlisted", .secondary, "minus.circle")
        }
    }

    var body: some View {
        let d = display
        PMGlowBadge(text: d.label, color: d.color, icon: d.icon, flat: true)
    }
}

// MARK: - Shopify Status Badge

struct ShopifyStatusBadge: View {
    let status: String

    var display: (label: String, color: Color) {
        switch status.uppercased() {
        case "ACTIVE":   return ("Active",     .green)
        case "DRAFT":    return ("Draft",      Color(.systemGray))
        case "ARCHIVED": return ("Archived",   .orange)
        default:         return ("Not Listed", .secondary)
        }
    }

    var body: some View {
        let d = display
        PMGlowBadge(text: d.label, color: d.color, flat: true)
    }
}

// MARK: - Saved View Chip (SESSION 4)

struct SavedViewChip: View {
    let label: String
    let isOn: Bool
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.pmBody(size: 12, weight: isOn ? .semibold : .medium))
                .tracking(0.6)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isOn ? PM.cyan.opacity(0.14) :
                    hovering ? PM.raised : PM.card,
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(isOn ? PM.cyan.opacity(0.55) : PM.borderSubtle, lineWidth: 1))
                .foregroundStyle(isOn ? PM.cyan : PM.textSecondary)
                .pmGlow(PM.cyan, radius: isOn ? 5 : 0, opacity: isOn ? 0.25 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isIn in
            withAnimation(PM.Anim.hover) { hovering = isIn }
        }
        .help(help)
    }
}

// MARK: - Attention Chip (SESSION 4)
// The old toolbar quick-filter buttons, relocated — same toggle semantics.

struct AttentionChip: View {
    let label: String
    let count: Int
    let color: Color
    let isOn: Bool
    var help: String = ""
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.pmBody(size: 12, weight: isOn ? .semibold : .medium))
                Text("\(count)")
                    .font(.pmBody(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(color, in: Capsule())
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                isOn ? color.opacity(0.15) :
                hovering ? PM.raised : PM.card,
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.55) : PM.borderSubtle, lineWidth: 1))
            .foregroundStyle(isOn ? color : PM.textSecondary)
            .pmGlow(color, radius: isOn ? 5 : 0, opacity: isOn ? 0.30 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isIn in
            withAnimation(PM.Anim.hover) { hovering = isIn }
        }
        .help(help)
    }
}

// MARK: - Price Range Chip (SESSION 4)
// Filters on eBay price (primary channel). Min/max entered in a popover.

struct PriceRangeChip: View {
    @Binding var minValue: Double?
    @Binding var maxValue: Double?

    @State private var showPopover = false
    @State private var minText = ""
    @State private var maxText = ""
    @State private var hovering = false

    var isActive: Bool { minValue != nil || maxValue != nil }

    var label: String {
        switch (minValue, maxValue) {
        case let (lo?, hi?): return "eBay $\(Int(lo))–$\(Int(hi))"
        case let (lo?, nil): return "eBay ≥ $\(Int(lo))"
        case let (nil, hi?): return "eBay ≤ $\(Int(hi))"
        default:             return "eBay Price"
        }
    }

    var body: some View {
        Button {
            minText = minValue.map { String(Int($0)) } ?? ""
            maxText = maxValue.map { String(Int($0)) } ?? ""
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.pmBody(size: 12, weight: isActive ? .semibold : .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
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
        .help("Filter by eBay price range")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("EBAY PRICE")
                    .font(.pmDisplay(size: 14))
                    .foregroundStyle(PM.textPrimary)
                    .tracking(1.0)
                HStack(spacing: 8) {
                    TextField("Min", text: $minText)
                        .textFieldStyle(.plain)
                        .font(.pmBody(size: 13))
                        .frame(width: 70)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(PM.base, in: RoundedRectangle(cornerRadius: PM.Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: PM.Radius.sm).strokeBorder(PM.borderStrong, lineWidth: 1))
                    Text("to").font(.pmBody(size: 12)).foregroundStyle(PM.textTertiary)
                    TextField("Max", text: $maxText)
                        .textFieldStyle(.plain)
                        .font(.pmBody(size: 13))
                        .frame(width: 70)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(PM.base, in: RoundedRectangle(cornerRadius: PM.Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: PM.Radius.sm).strokeBorder(PM.borderStrong, lineWidth: 1))
                }
                HStack {
                    Button("Clear") {
                        minValue = nil
                        maxValue = nil
                        showPopover = false
                    }
                    .buttonStyle(PMGhostButtonStyle())
                    Button("Apply") {
                        minValue = Double(minText.trimmingCharacters(in: .whitespaces))
                        maxValue = Double(maxText.trimmingCharacters(in: .whitespaces))
                        showPopover = false
                    }
                    .buttonStyle(PMTintButtonStyle(tint: PM.pink))
                }
            }
            .padding(14)
            .background(PM.raised)
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Min Days Owned Chip (SESSION 4)

struct MinDaysChip: View {
    @Binding var minDays: Int?

    @State private var showPopover = false
    @State private var daysText = ""
    @State private var hovering = false

    var isActive: Bool { minDays != nil }

    var label: String {
        if let d = minDays { return "Owned ≥ \(d)d" }
        return "Days Owned"
    }

    var body: some View {
        Button {
            daysText = minDays.map(String.init) ?? ""
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.pmBody(size: 12, weight: isActive ? .semibold : .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
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
        .help("Show only items held at least this many days")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text("DAYS OWNED")
                    .font(.pmDisplay(size: 14))
                    .foregroundStyle(PM.textPrimary)
                    .tracking(1.0)
                HStack(spacing: 8) {
                    Text("At least").font(.pmBody(size: 12)).foregroundStyle(PM.textTertiary)
                    TextField("Days", text: $daysText)
                        .textFieldStyle(.plain)
                        .font(.pmBody(size: 13))
                        .frame(width: 60)
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(PM.base, in: RoundedRectangle(cornerRadius: PM.Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: PM.Radius.sm).strokeBorder(PM.borderStrong, lineWidth: 1))
                    Text("days").font(.pmBody(size: 12)).foregroundStyle(PM.textTertiary)
                }
                HStack {
                    Button("Clear") {
                        minDays = nil
                        showPopover = false
                    }
                    .buttonStyle(PMGhostButtonStyle())
                    Button("Apply") {
                        minDays = Int(daysText.trimmingCharacters(in: .whitespaces))
                        showPopover = false
                    }
                    .buttonStyle(PMTintButtonStyle(tint: PM.pink))
                }
            }
            .padding(14)
            .background(PM.raised)
            .preferredColorScheme(.dark)
        }
    }
}
