import Foundation
import SwiftUI

@MainActor
@Observable
class InventoryStore {

    static let shared = InventoryStore()

    var items: [InventoryItem] = []
    var sales: [SaleRecord] = []
    var expenses: [ExpenseRecord] = []
    var paperTrail: [PaperTrailEntry] = []
    var igQueue: [IGScheduledPost] = []
    /// Soft-deleted inventory items, kept 30 days (Tier 2 robustness). Restorable.
    var trash: [TrashedItem] = []
    var isLoading: Bool = false
    var lastSaved: Date? = nil
    var errorMessage: String? = nil

    // MARK: - CCP computed vars (on the store so @Observable tracks them correctly)
    var ccpInInventory: [InventoryItem] { items.filter { $0.tags.uppercased().contains("CCP") } }
    var ccpSold: [SaleRecord]           { sales.filter { $0.tags.uppercased().contains("CCP") } }
    var ccpTotalPurchased: Int          { ccpInInventory.count + ccpSold.count }
    var ccpTotalSpent: Double           { ccpInInventory.reduce(0){$0+$1.totalCostComputed} + ccpSold.reduce(0){$0+$1.totalCost} }
    var ccpOutstandingCost: Double      { ccpInInventory.reduce(0){$0+$1.totalCostComputed} }
    var ccpNetSales: Double             { ccpSold.reduce(0){$0+$1.netSales} }
    var ccpProfit: Double               { ccpSold.reduce(0){$0+$1.profit} }
    var ccpOutstandingValue: Double     { ccpInInventory.reduce(0){$0+$1.shopifyPrice} }
    var ccpUnrealizedProfit: Double     { ccpOutstandingValue - ccpOutstandingCost }

    private let saveURL: URL
    private let salesURL: URL
    private let expensesURL: URL
    private let paperTrailURL: URL
    private let igQueueURL: URL
    private let trashURL: URL
    private var backupTask: Task<Void, Never>?

    // ════════════════════════════════════════════════════════════════════
    // SESSION 3 (audit #5): coalesced persistence
    // Before: save() synchronously encoded ALL FIVE files (920 items + 2,300
    // sales + expenses + paper trail + IG queue) and wrote them to disk on
    // the MAIN THREAD on every mutation — one checkbox = 5 encodes + 5
    // writes; bulk-unchecking 30 items = 150 encodes/writes.
    // Now: save() marks dirty + debounces 500ms; a burst of mutations
    // encodes ONCE. Encoding happens on the main actor (coalesced, tens of
    // ms per burst); the resulting Data blobs are written on a SERIAL
    // DispatchQueue — strict FIFO, so writes can never land out of order,
    // and flushNow()'s queue.sync drains every earlier write before
    // returning. That sync-drain property is what makes the automation
    // terminate path safe (PosterMaloneApp calls flushNow() before
    // NSApp.terminate).
    // ════════════════════════════════════════════════════════════════════
    private var saveDebounceTask: Task<Void, Never>?
    private var isDirty = false
    nonisolated private static let writeQueue =
        DispatchQueue(label: "com.postermalone.persistence", qos: .utility)

    // ════════════════════════════════════════════════════════════════════
    // SESSION 3 (audit #7): derived business sets — stored, recomputed ONCE
    // per mutation in save(). Replaces the duplicated O(n) logic that lived
    // in SidebarView.needsListingCount AND InventoryTableView (two separate
    // implementations of the same rule, both re-run inside view bodies).
    // Views read these as plain stored properties — zero recompute on access.
    // ════════════════════════════════════════════════════════════════════
    /// Processed items with no Listed/Active/Auction sibling (same Artist+Title).
    private(set) var needsListingItems: [InventoryItem] = []
    private(set) var needsListingIDs: Set<InventoryItem.ID> = []
    /// Items missing an eBay description (excludes Sold/The Vault).
    private(set) var noDescriptionItems: [InventoryItem] = []
    private(set) var noDescriptionIDs: Set<InventoryItem.ID> = []
    /// Items whose eBay title exceeds 80 characters (excludes Sold/The Vault).
    private(set) var longTitleItems: [InventoryItem] = []
    private(set) var longTitleIDs: Set<InventoryItem.ID> = []
    /// Items with Action = "Y" — drives the bulk dock and bulk operations.
    private(set) var actionYItems: [InventoryItem] = []
    /// Live on eBay but NOT live on Shopify — the channel-migration gap.
    private(set) var ebayNotShopifyItems: [InventoryItem] = []
    private(set) var ebayNotShopifyIDs: Set<InventoryItem.ID> = []
    /// Listed value (shopifyPrice, fallback ebayPrice) of the eBay-not-Shopify gap.
    private(set) var ebayNotShopifyValue: Double = 0
    /// Sellable items with no photos — blocks listing, Shopify, and IG.
    private(set) var needsPhotosItems: [InventoryItem] = []
    private(set) var needsPhotosIDs: Set<InventoryItem.ID> = []
    /// Sellable items missing a Shopify title OR Shopify description — the
    /// AI-generated copy hasn't been created/pushed yet.
    private(set) var needsShopifyCopyItems: [InventoryItem] = []
    private(set) var needsShopifyCopyIDs: Set<InventoryItem.ID> = []

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("PosterMalone", isDirectory: true)

        try? FileManager.default.createDirectory(
            at: support, withIntermediateDirectories: true
        )

        saveURL       = support.appendingPathComponent("inventory.json")
        salesURL      = support.appendingPathComponent("sales.json")
        expensesURL   = support.appendingPathComponent("expenses.json")
        paperTrailURL = support.appendingPathComponent("paper_trail.json")
        igQueueURL    = support.appendingPathComponent("ig_queue.json")
        trashURL      = support.appendingPathComponent("trash.json")

        load()
    }

    // MARK: - Persistence

    func load() {
        print("InventoryStore: loading from \(saveURL.path)")

        // Try primary location
        var loadedItems: [InventoryItem]? = decode(from: saveURL)

        // If primary is empty/missing, check Documents backup folder as fallback
        if loadedItems == nil || loadedItems!.isEmpty {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let backupDir = docs.appendingPathComponent("PosterMalone Backups")
            // Find most recent backup
            if let files = try? FileManager.default.contentsOfDirectory(
                at: backupDir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) {
                let sorted = files
                    .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("inventory_") }
                    .sorted {
                        let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                        return d1 > d2
                    }
                if let latest = sorted.first {
                    print("InventoryStore: primary empty, trying backup \(latest.lastPathComponent)")
                    loadedItems = decode(from: latest)
                    if let items = loadedItems, !items.isEmpty {
                        // Write back to primary location so next load works
                        if let data = try? JSONEncoder().encode(items) {
                            try? data.write(to: saveURL, options: .atomic)
                            print("InventoryStore: restored \(items.count) items from backup")
                        }
                    }
                }
            }
        }

        items      = loadedItems ?? []
        sales      = decode(from: salesURL)      ?? []
        expenses   = decode(from: expensesURL)   ?? []
        paperTrail = decode(from: paperTrailURL) ?? []
        igQueue    = decode(from: igQueueURL) ?? []
        trash      = decode(from: trashURL) ?? []
        // Purge trash older than 30 days on launch (soft-delete retention)
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let beforeCount = trash.count
        trash.removeAll { $0.deletedAt < cutoff }
        if trash.count != beforeCount {
            encode(trash, to: trashURL)
        }
        print("InventoryStore: loaded \(items.count) items, \(sales.count) sales")

        // Fix dates stored using Apple reference date (Jan 1 2001) instead of Unix epoch (Jan 1 1970)
        migrateAppleDatesIfNeeded()

        // Seed the derived business sets (Session 3, audit #7)
        recomputeDerivedSets()
    }

    func save() {
        // Derived sets + the change signal update IMMEDIATELY — the UI keys
        // off lastSaved (Session 1 wiring) and must never lag a mutation.
        recomputeDerivedSets()
        lastSaved = Date()
        isDirty = true
        scheduleBackup()

        // Debounced flush: a burst of mutations (bulk uncheck, Mark Listed
        // loop, relist batch, CSV sync) encodes once after 500ms of quiet
        // instead of once per call.
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flush(synchronously: false)
        }
    }

    /// Synchronous flush — encodes any pending changes and BLOCKS until every
    /// queued disk write (including earlier async ones) has landed. Called by
    /// the app delegate on quit/resign-active and by the automation path
    /// before NSApp.terminate. Cheap no-op when nothing is dirty (still
    /// drains the write queue so in-flight writes complete before exit).
    func flushNow() {
        flush(synchronously: true)
    }

    private func flush(synchronously: Bool) {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil

        guard isDirty else {
            // Nothing new to encode — but a synchronous caller (terminate)
            // still needs in-flight writes drained before the process exits.
            if synchronously { Self.writeQueue.sync { } }
            return
        }
        isDirty = false

        // Encode on the main actor — coalesced to once per burst — then hand
        // Sendable Data blobs to the serial writer.
        let blobs: [(Data, URL)] = [
            encodedData(items,      for: saveURL),
            encodedData(sales,      for: salesURL),
            encodedData(expenses,   for: expensesURL),
            encodedData(paperTrail, for: paperTrailURL),
            encodedData(igQueue,    for: igQueueURL)
        ].compactMap { $0 }

        let work: @Sendable () -> Void = {
            for (data, url) in blobs {
                try? data.write(to: url, options: .atomic)
            }
        }
        if synchronously { Self.writeQueue.sync(execute: work) }
        else             { Self.writeQueue.async(execute: work) }
    }

    private func encodedData<T: Encodable>(_ value: T, for url: URL) -> (Data, URL)? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return nil }
        return (data, url)
    }

    /// One pass over the inventory rebuilding every derived business set.
    /// Logic is byte-identical to the old SidebarView/InventoryTableView
    /// computed properties.
    func recomputeDerivedSets() {
        let all = items

        let activePairs: Set<String> = Set(
            all.filter { $0.status == .listed || $0.status == .active || $0.status == .auction }
               .map { "\($0.artist.lowercased())||||\($0.title.lowercased())" }
        )
        let orphaned = all.filter {
            $0.status == .processed &&
            !activePairs.contains("\($0.artist.lowercased())||||\($0.title.lowercased())")
        }
        needsListingItems = orphaned
        needsListingIDs   = Set(orphaned.map(\.id))

        let noDesc = all.filter {
            $0.status != .sold &&
            $0.status != .theVault &&
            $0.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        noDescriptionItems = noDesc
        noDescriptionIDs   = Set(noDesc.map(\.id))

        let longTitles = all.filter {
            $0.status != .sold &&
            $0.status != .theVault &&
            $0.ebayTitle.count > 80
        }
        longTitleItems = longTitles
        longTitleIDs   = Set(longTitles.map(\.id))

        actionYItems = all.filter { $0.action.uppercased() == "Y" }

        // eBay→Shopify gap: live on eBay, not yet live on Shopify (#1).
        // Drives the channel-migration nudge — your strategic goal of growing
        // direct Shopify sales. Value uses shopifyPrice, falling back to eBay.
        let ebayGap = all.filter {
            $0.ebayListingStatus.lowercased() == "active" &&
            $0.shopifyStatus.uppercased() != "ACTIVE"
        }
        ebayNotShopifyItems = ebayGap
        ebayNotShopifyIDs   = Set(ebayGap.map(\.id))
        ebayNotShopifyValue = ebayGap.reduce(0) {
            $0 + ($1.shopifyPrice > 0 ? $1.shopifyPrice : $1.ebayPrice)
        }

        // Needs photos: sellable items with no images — silently blocks
        // listing, Shopify push, and IG posting (#5).
        let needsPhotos = all.filter {
            $0.status != .sold &&
            $0.status != .theVault &&
            $0.images.isEmpty
        }
        needsPhotosItems = needsPhotos
        needsPhotosIDs   = Set(needsPhotos.map(\.id))

        // Needs Shopify copy: sellable items missing the Shopify title OR the
        // Shopify description (the AI-generated copy isn't done yet). Flags
        // gaps before a push so listings aren't created with blank fields.
        let needsShopCopy = all.filter {
            $0.status != .sold &&
            $0.status != .theVault &&
            ($0.shopifyTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             $0.shopifyDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        needsShopifyCopyItems = needsShopCopy
        needsShopifyCopyIDs   = Set(needsShopCopy.map(\.id))
    }

    private func decode<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else {
            print("InventoryStore: could not read file at \(url.path)")
            return nil
        }
        do {
            let decoder = JSONDecoder()
            // Dates are stored as Unix timestamps (seconds since 1970)
            decoder.dateDecodingStrategy = .secondsSince1970
            return try decoder.decode(T.self, from: data)
        } catch {
            print("InventoryStore: decode failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) {
        // Direct writes (paper trail, IG queue) keep their immediate-write
        // semantics, routed through the serial writer so they can never
        // reorder against flushes — and flushNow()'s sync drain guarantees
        // they are on disk before the automation path terminates.
        guard let (data, target) = encodedData(value, for: url) else { return }
        Self.writeQueue.async {
            try? data.write(to: target, options: .atomic)
        }
    }

    // MARK: - Date Migration
    // Old JSONEncoder used .deferredToDate = seconds since Jan 1 2001 (Apple reference).
    // New encoder uses .secondsSince1970. The offset is 978307200 seconds (31 years).
    // This migrates all sale/inventory dates from Apple reference to Unix timestamps.

    private let appleToUnixOffset: Double = 978307200  // seconds between 1970 and 2001

    func migrateAppleDatesIfNeeded() {
        let flagKey = "dates_migrated_unix_v1"
        guard !UserDefaults.standard.bool(forKey: flagKey) else { return }

        var migrated = 0

        // Fix sales dates — these are the main ones showing wrong years
        sales = sales.map { sale in
            var s = sale
            // If date is before 2000, it was stored as Apple reference time — add offset
            if s.dateSold.timeIntervalSince1970 < 978307200 {
                s.dateSold = Date(timeIntervalSince1970: s.dateSold.timeIntervalSince1970 + appleToUnixOffset)
                migrated += 1
            }
            if let dp = s.datePurchased, dp.timeIntervalSince1970 < 978307200 {
                s.datePurchased = Date(timeIntervalSince1970: dp.timeIntervalSince1970 + appleToUnixOffset)
            }
            if let dl = s.dateListed, dl.timeIntervalSince1970 < 978307200 {
                s.dateListed = Date(timeIntervalSince1970: dl.timeIntervalSince1970 + appleToUnixOffset)
            }
            return s
        }

        // Fix inventory dates too
        items = items.map { item in
            var i = item
            if let dp = i.datePurchased, dp.timeIntervalSince1970 < 978307200 {
                i.datePurchased = Date(timeIntervalSince1970: dp.timeIntervalSince1970 + appleToUnixOffset)
            }
            if let dl = i.dateListed, dl.timeIntervalSince1970 < 978307200 {
                i.dateListed = Date(timeIntervalSince1970: dl.timeIntervalSince1970 + appleToUnixOffset)
            }
            return i
        }

        if migrated > 0 {
            save()
            print("InventoryStore: migrated \(migrated) sale dates from Apple reference to Unix")
        }

        UserDefaults.standard.set(true, forKey: flagKey)
    }



    // MARK: - Inventory CRUD

    func add(_ item: InventoryItem) {
        items.append(item)
        save()
    }

    func update(_ item: InventoryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i] = item
        save()
    }

    /// Call after a successful Shopify push. Sets shopifyStatus = ACTIVE and
    /// rolls up listingMarketplace:
    ///   • already live on eBay  → .both (eBay+Shopify)
    ///   • otherwise             → .shopify
    /// One coalesced save. Idempotent — safe to call on every push.
    func markListedOnShopify(_ item: InventoryItem) {
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[i].shopifyStatus = "ACTIVE"
        let onEbay = items[i].ebayListingStatus.lowercased() == "active"
        items[i].listingMarketplace = onEbay ? .both : .shopify
        items[i].shopifyAPIUpdates = Date()
        save()
    }

    /// SESSION 4: apply many item mutations with ONE derived-set recompute
    /// and ONE coalesced save. Bulk operations (Check All Visible, uncheck
    /// all, bulk Mark Listed, Apply All Suggestions) previously looped
    /// update() — N saves and N recomputeDerivedSets passes. Semantics per
    /// item are identical to update(); unknown IDs are skipped the same way.
    func updateBatch(_ updatedItems: [InventoryItem]) {
        guard !updatedItems.isEmpty else { return }
        var indexByID: [InventoryItem.ID: Int] = [:]
        indexByID.reserveCapacity(items.count)
        for (i, item) in items.enumerated() { indexByID[item.id] = i }
        for updated in updatedItems {
            if let i = indexByID[updated.id] { items[i] = updated }
        }
        save()
    }

    /// Soft delete — moves the item to trash (30-day retention) instead of
    /// erasing it. Restorable via restoreFromTrash(). Tier 2 robustness.
    func delete(_ item: InventoryItem) {
        items.removeAll { $0.id == item.id }
        trash.removeAll { $0.item.id == item.id }   // avoid dupes
        trash.insert(TrashedItem(item: item, deletedAt: Date()), at: 0)
        encode(trash, to: trashURL)
        save()
    }

    /// Restore a trashed item back into inventory.
    func restoreFromTrash(_ trashed: TrashedItem) {
        guard !items.contains(where: { $0.id == trashed.item.id }) else {
            trash.removeAll { $0.id == trashed.id }
            encode(trash, to: trashURL)
            return
        }
        items.append(trashed.item)
        trash.removeAll { $0.id == trashed.id }
        encode(trash, to: trashURL)
        save()
    }

    /// Permanently remove a single trashed item (cannot be undone).
    func permanentlyDelete(_ trashed: TrashedItem) {
        trash.removeAll { $0.id == trashed.id }
        encode(trash, to: trashURL)
    }

    /// Empty the entire trash (cannot be undone).
    func emptyTrash() {
        trash.removeAll()
        encode(trash, to: trashURL)
    }

    // MARK: - Mark as Sold
    // Captures a complete snapshot of the item at time of sale,
    // mirroring all columns from the Poster Malone Tracker Sales sheet.
    // dateSold defaults to now; pass a specific date for bulk/backdated sales.

    func markAsSold(_ item: InventoryItem, marketplace: Marketplace,
                    grossSales: Double, taxes: Double, feesAndShipping: Double,
                    dateSold: Date = Date()) {
        let net    = grossSales - taxes - feesAndShipping
        let profit = net - item.totalCostComputed
        // P/L% = Profit / Cost * 100 (matches spreadsheet formula)
        let pl     = item.totalCostComputed > 0 ? (profit / item.totalCostComputed) * 100 : 0
        let daysSold = item.daysInInventory

        var sale = SaleRecord()

        // Identity snapshot
        sale.images             = item.images   // preserve lh3 URLs after sale
        sale.sku                = item.sku
        sale.artist             = item.artist
        sale.title              = item.title
        sale.size               = item.size
        sale.edition            = item.edition
        sale.printType          = item.printType
        sale.productionTechnique = item.productionTechnique
        sale.gallery            = item.gallery
        sale.franchise          = item.franchise
        sale.theme              = item.theme
        sale.condition          = item.condition
        sale.signed             = item.signed
        sale.imperfect          = item.imperfect
        sale.tags               = item.tags

        // Storage
        sale.drawer             = item.drawer
        sale.sleeveNumber       = item.sleeveNumber

        // Acquisition
        sale.datePurchased      = item.datePurchased
        sale.netCost            = item.netCost
        sale.taxAndShipping     = item.taxAndShipping
        sale.totalCost          = item.totalCostComputed
        sale.weight             = item.weight

        // Listing details
        sale.dateListed         = item.dateListed
        sale.daysInInventory    = daysSold
        sale.ebayTitle          = item.ebayTitle
        sale.ebayCategoryId     = item.ebayCategoryId
        sale.ebayPrice          = item.ebayPrice
        sale.shopifyPrice       = item.shopifyPrice
        sale.shopifyStatus      = item.shopifyStatus
        sale.paymentProfileName = item.paymentProfileName
        sale.returnProfileName  = item.returnProfileName
        sale.shippingProfileName = item.shippingProfileName

        // Sale financials
        sale.dateSold           = dateSold
        sale.marketplace        = marketplace
        sale.grossSales         = grossSales
        sale.taxes              = taxes
        sale.feesAndShipping    = feesAndShipping
        sale.netSales           = net
        sale.profit             = profit
        sale.profitLossPercent  = pl
        sale.daysToSell         = daysSold

        sales.append(sale)
        items.removeAll { $0.id == item.id }
        save()
    }

    // MARK: - Expenses (SESSION: Tier 2)
    // Business costs that aren't per-item COGS — shipping supplies, platform
    // fees, storage, marketing (e.g. Google Ads), etc. Feed the tax export's
    // true-net calculation. All route through the coalesced save path.

    func addExpense(_ expense: ExpenseRecord) {
        expenses.append(expense)
        save()
    }

    func updateExpense(_ expense: ExpenseRecord) {
        guard let i = expenses.firstIndex(where: { $0.id == expense.id }) else { return }
        expenses[i] = expense
        save()
    }

    func deleteExpense(_ expense: ExpenseRecord) {
        expenses.removeAll { $0.id == expense.id }
        save()
    }

    // MARK: - Quick Mark as Sold (no financials yet — fill in later via Edit Sale)

    func markAsSoldQuick(_ item: InventoryItem,
                         marketplace: Marketplace = .ebay,
                         dateSold: Date = Date()) {
        var sale = SaleRecord()
        sale.images              = item.images
        sale.sku                 = item.sku
        sale.artist              = item.artist
        sale.title               = item.title
        sale.size                = item.size
        sale.edition             = item.edition
        sale.printType           = item.printType
        sale.productionTechnique = item.productionTechnique
        sale.gallery             = item.gallery
        sale.franchise           = item.franchise
        sale.theme               = item.theme
        sale.condition           = item.condition
        sale.signed              = item.signed
        sale.imperfect           = item.imperfect
        sale.tags                = item.tags
        sale.drawer              = item.drawer
        sale.sleeveNumber        = item.sleeveNumber
        sale.datePurchased       = item.datePurchased
        sale.netCost             = item.netCost
        sale.taxAndShipping      = item.taxAndShipping
        sale.totalCost           = item.totalCostComputed
        sale.weight              = item.weight
        sale.dateListed          = item.dateListed
        sale.daysInInventory     = item.daysInInventory
        sale.ebayTitle           = item.ebayTitle
        sale.ebayCategoryId      = item.ebayCategoryId
        sale.ebayPrice           = item.ebayPrice
        sale.shopifyPrice        = item.shopifyPrice
        sale.shopifyStatus       = item.shopifyStatus
        sale.paymentProfileName  = item.paymentProfileName
        sale.returnProfileName   = item.returnProfileName
        sale.shippingProfileName = item.shippingProfileName
        sale.dateSold            = dateSold
        sale.marketplace         = marketplace
        sale.grossSales          = 0
        sale.taxes               = 0
        sale.feesAndShipping     = 0
        sale.netSales            = 0
        sale.profit              = 0
        sale.profitLossPercent   = 0
        sale.daysToSell          = item.daysInInventory
        sales.append(sale)
        items.removeAll { $0.id == item.id }
        save()
    }

    // MARK: - Bulk Mark as Sold
    // Processes multiple items in a single pass, calling save() only once at the end.
    // Items without a matching entry (grossSales == 0) are silently skipped.

    func markMultipleAsSold(
        _ itemsToSell: [InventoryItem],
        entries: [UUID: BulkSaleEntry],
        marketplace: Marketplace,
        dateSold: Date
    ) {
        let soldIDs = itemsToSell.compactMap { item -> UUID? in
            guard let entry = entries[item.id], entry.grossSales > 0 else { return nil }

            let grossSales       = entry.grossSales
            let taxes            = entry.taxes
            let feesAndShipping  = entry.feesAndShipping
            let net              = grossSales - taxes - feesAndShipping
            let profit           = net - item.totalCostComputed
            let pl               = item.totalCostComputed > 0 ? (profit / item.totalCostComputed) * 100 : 0
            let daysSold         = item.daysInInventory

            var sale = SaleRecord()

            sale.images              = item.images   // preserve lh3 URLs after sale
            sale.sku                 = item.sku
            sale.artist              = item.artist
            sale.title               = item.title
            sale.size                = item.size
            sale.edition             = item.edition
            sale.printType           = item.printType
            sale.productionTechnique = item.productionTechnique
            sale.gallery             = item.gallery
            sale.franchise           = item.franchise
            sale.theme               = item.theme
            sale.condition           = item.condition
            sale.signed              = item.signed
            sale.imperfect           = item.imperfect
            sale.tags                = item.tags
            sale.drawer              = item.drawer
            sale.sleeveNumber        = item.sleeveNumber
            sale.datePurchased       = item.datePurchased
            sale.netCost             = item.netCost
            sale.taxAndShipping      = item.taxAndShipping
            sale.totalCost           = item.totalCostComputed
            sale.weight              = item.weight
            sale.dateListed          = item.dateListed
            sale.daysInInventory     = daysSold
            sale.ebayTitle           = item.ebayTitle
            sale.ebayCategoryId      = item.ebayCategoryId
            sale.ebayPrice           = item.ebayPrice
            sale.shopifyPrice        = item.shopifyPrice
            sale.shopifyStatus       = item.shopifyStatus
            sale.paymentProfileName  = item.paymentProfileName
            sale.returnProfileName   = item.returnProfileName
            sale.shippingProfileName = item.shippingProfileName
            sale.dateSold            = dateSold
            sale.marketplace         = marketplace
            sale.grossSales          = grossSales
            sale.taxes               = taxes
            sale.feesAndShipping     = feesAndShipping
            sale.netSales            = net
            sale.profit              = profit
            sale.profitLossPercent   = pl
            sale.daysToSell          = daysSold

            sales.append(sale)
            return item.id
        }

        let soldIDSet = Set(soldIDs)
        items.removeAll { soldIDSet.contains($0.id) }
        save()
    }

    // MARK: - Undo Sale (move back to Inventory)
    // Reconstructs the InventoryItem from the SaleRecord snapshot
    // and removes the sale record.

    func unmakeSold(_ sale: SaleRecord) {
        var item = InventoryItem()
        item.sku                = sale.sku
        item.artist             = sale.artist
        item.title              = sale.title
        item.size               = sale.size
        item.edition            = sale.edition
        item.printType          = sale.printType
        item.productionTechnique = sale.productionTechnique
        item.gallery            = sale.gallery
        item.franchise          = sale.franchise
        item.theme              = sale.theme
        item.condition          = sale.condition
        item.signed             = sale.signed
        item.imperfect          = sale.imperfect
        item.tags               = sale.tags
        item.drawer             = sale.drawer
        item.sleeveNumber       = sale.sleeveNumber
        item.datePurchased      = sale.datePurchased
        item.netCost            = sale.netCost
        item.taxAndShipping     = sale.taxAndShipping
        item.dateListed         = sale.dateListed
        item.weight             = sale.weight
        item.ebayTitle          = sale.ebayTitle
        item.ebayCategoryId     = sale.ebayCategoryId
        item.ebayPrice          = sale.ebayPrice
        item.shopifyPrice       = sale.shopifyPrice
        item.shopifyStatus      = sale.shopifyStatus
        item.paymentProfileName = sale.paymentProfileName
        item.returnProfileName  = sale.returnProfileName
        item.shippingProfileName = sale.shippingProfileName
        item.status             = ItemStatus.listed  // restore to listed status

        items.append(item)
        sales.removeAll { $0.id == sale.id }
        save()
    }

    // MARK: - SKU Generation

    var nextSKU: String {
        let allSKUs = items.map(\.sku) + sales.map(\.sku)
        let highest = allSKUs
            .compactMap { sku -> Int? in
                guard sku.uppercased().hasPrefix("PM-") else { return nil }
                return Int(sku.dropFirst(3))
            }
            .max() ?? 0
        return String(format: "PM-%04d", highest + 1)
    }

    // MARK: - Duplicate Item

    /// Creates `count` copies of `item`, each with a fresh sequential SKU.
    /// Returns the list of SKUs that were created.
    @discardableResult
    func duplicateItem(_ item: InventoryItem,
                       count: Int,
                       resetStatus: Bool = true,
                       clearImages: Bool = true) -> [String] {
        var created: [String] = []
        for _ in 0..<count {
            var copy             = item
            copy.id              = UUID()
            copy.sku             = nextSKU
            copy.action          = ""
            copy.shopifyHandle   = ""
            copy.shopifyStatus   = ""
            copy.ebayListingStatus = ""
            copy.dateListed      = nil
            if resetStatus { copy.status = .pending }
            if clearImages { copy.images = [] }
            copy.drawer          = ""
            copy.sleeveNumber    = ""
            items.append(copy)
            created.append(copy.sku)
        }
        save()
        return created
    }

    // MARK: - Computed Stats

    var activeItems: [InventoryItem]   { items.filter { $0.status == .active } }
    var totalInventoryValue: Double    { items.reduce(0) { $0 + $1.shopifyPrice } }
    var totalCostBasis: Double         { items.reduce(0) { $0 + $1.totalCostComputed } }
    var totalRevenue: Double           { sales.reduce(0) { $0 + $1.grossSales } }
    var totalProfit: Double            { sales.reduce(0) { $0 + $1.profit } }
    var averageMargin: Double {
        guard !sales.isEmpty else { return 0 }
        return sales.reduce(0) { $0 + $1.profitLossPercent } / Double(sales.count)
    }
    var averageDaysToSell: Double {
        let withDays = sales.filter { $0.daysToSell > 0 }
        guard !withDays.isEmpty else { return 0 }
        return Double(withDays.reduce(0) { $0 + $1.daysToSell }) / Double(withDays.count)
    }

    // MARK: - Backup

    func scheduleBackup() {
        backupTask?.cancel()
        backupTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            writeBackup()
        }
    }

    private func writeBackup() {
        // SESSION 3: the CSV builds (920 + 2,300 rows of string formatting)
        // previously ran on the MAIN actor — a periodic mid-session stall.
        // Now: enqueue any pending data flush FIRST (so the file we copy is
        // current), snapshot the arrays, and run the entire backup — file
        // copies, pruning, CSV builds — on the serial writer queue. FIFO
        // ordering guarantees the backup always copies the freshest flush.
        flush(synchronously: false)

        let itemsSnapshot = items
        let salesSnapshot = sales
        let primaryURL    = saveURL

        Self.writeQueue.async {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HHmm"
            let stamp = formatter.string(from: Date())

            // Primary backup: ~/Documents/PosterMalone Backups/ — survives app container wipes
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let externalDir = docs.appendingPathComponent("PosterMalone Backups", isDirectory: true)
            try? FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
            let dest = externalDir.appendingPathComponent("inventory_\(stamp).json")
            try? FileManager.default.copyItem(at: primaryURL, to: dest)
            Self.pruneOldBackups(in: externalDir)

            // Secondary backup: inside app container (legacy location)
            let support = primaryURL.deletingLastPathComponent()
            let internalDir = support.appendingPathComponent("Backups", isDirectory: true)
            try? FileManager.default.createDirectory(at: internalDir, withIntermediateDirectories: true)
            let dest2 = internalDir.appendingPathComponent("inventory_\(stamp).json")
            try? FileManager.default.copyItem(at: primaryURL, to: dest2)
            Self.pruneOldBackups(in: internalDir)

            // CSV backup — write alongside JSON backups in the external dir
            // Only write if there's actual data to avoid empty files on first launch
            if !itemsSnapshot.isEmpty || !salesSnapshot.isEmpty {
                let invCSV   = CSVExportService.inventoryCSV(from: itemsSnapshot)
                let salesCSV = CSVExportService.salesCSV(from: salesSnapshot)
                let invCSVURL   = externalDir.appendingPathComponent("inventory_\(stamp).csv")
                let salesCSVURL = externalDir.appendingPathComponent("sales_\(stamp).csv")
                try? invCSV.write(to: invCSVURL,   atomically: true, encoding: .utf8)
                try? salesCSV.write(to: salesCSVURL, atomically: true, encoding: .utf8)
            }
        }
    }

    nonisolated private static func pruneOldBackups(in dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }
        let sorted = files.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return d1 > d2
        }
        sorted.dropFirst(30).forEach { try? FileManager.default.removeItem(at: $0) }
    }

    // MARK: - Paper Trail

    func addPaperTrailEntry(action: PaperTrailAction, item: InventoryItem) {
        let entry = PaperTrailEntry(action: action, item: item)
        paperTrail.insert(entry, at: 0) // newest first
        encode(paperTrail, to: paperTrailURL)
        encode(igQueue,    to: igQueueURL)
    }

    // MARK: - Automation: Silent Relist
    // Called by the URL scheme handler (postermalone://relist).
    // Runs the full relist workflow headlessly — no UI state, no sheets.
    // Returns a summary string for logging.

    func relistSilently(credentials: CredentialsManager, batchSize: Int = 7, isTest: Bool = false) async -> String {
        let now      = Date()
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now

        // Select items — same logic as relistItems computed var
        let listed = items.filter {
            $0.status == .listed &&
            $0.ebayPrice > 0 &&
            ($0.dateListed ?? .distantPast) <= now
        }
        let due = listed
            .filter { ($0.dateListed ?? .distantPast) <= ninetyDaysAgo }
            .sorted { ($0.dateListed ?? .distantPast) < ($1.dateListed ?? .distantPast) }
        let fillPool = listed
            .filter { item in !due.contains(where: { $0.id == item.id }) }
            .sorted { ($0.dateListed ?? .distantPast) < ($1.dateListed ?? .distantPast) }
        let needed  = max(0, batchSize - due.count)
        let batch   = due.prefix(batchSize) + fillPool.prefix(needed)

        guard !batch.isEmpty else {
            let msg = "Automation: no eligible items to relist"
            if !isTest { writeLastRunResult(msg) }
            return msg
        }

        // Verify we have a refresh token before starting — fail fast with clear message
        guard !credentials.ebayRefreshToken.isEmpty else {
            let msg = "⚠️ Automation failed: No eBay refresh token. Open PosterMalone → Admin → eBay → Sign into eBay."
            if !isTest { writeLastRunResult(msg) }
            try? AppleScriptService.sendRecapEmail(
                to: credentials.recapEmail,
                ended: [],
                scheduled: [],
                inventorySnapshot: InventorySnapshot(from: self),
                isTestRun: isTest
            )
            return msg
        }

        // Calculate slots
        let frontier = nextSchedulingFrontier()
        let slots    = relistSlots(startingFrom: frontier, count: batch.count)

        var endedCount   = 0
        var schedCount   = 0
        var errors: [String] = []

        // Step 1a — Auto-sync missing eBay Item IDs for batch items before ending
        let missingIds = batch.filter { $0.ebayItemId.isEmpty }
        if !missingIds.isEmpty {
            do {
                let skuToId = try await EbayService.shared.fetchSkuToItemIdMap(credentials: credentials)
                for item in missingIds {
                    if let itemId = skuToId[item.sku] {
                        var updated = item
                        updated.ebayItemId = itemId
                        update(updated)
                    }
                }
            } catch {
                errors.append("Item ID sync: \(error.localizedDescription)")
            }
        }

        // Re-read batch with updated Item IDs
        let batchIds = Set(batch.map(\.id))
        let syncedBatch = items.filter { batchIds.contains($0.id) }

        // Step 1b — End listings
        for item in syncedBatch {
            guard !item.ebayItemId.isEmpty else {
                errors.append("Skipped EndItem \(item.sku) — no Item ID found")
                continue
            }
            do {
                try await EbayService.shared.endItem(itemId: item.ebayItemId, credentials: credentials)
                endedCount += 1
                if !isTest { addPaperTrailEntry(action: .delistedEbay, item: item) }
            } catch {
                errors.append("EndItem \(item.sku): \(error.localizedDescription)")
            }
        }

        // Step 2 — Update dateListed, clear ItemID
        for (index, item) in syncedBatch.enumerated() {
            guard index < slots.count else { continue }
            var updated       = item
            updated.dateListed  = slots[index]
            updated.ebayItemId  = ""
            updated.action      = ""
            update(updated)
        }

        // Step 3 — Schedule new listings via AddFixedPriceItem
        var scheduledItems: [InventoryItem] = []
        for (index, item) in syncedBatch.enumerated() {
            guard index < slots.count else { continue }
            var updated = item; updated.dateListed = slots[index]
            scheduledItems.append(updated)
            do {
                let newId = try await EbayService.shared.addFixedPriceItem(
                    item: item, scheduleTime: slots[index], credentials: credentials
                )
                var stored = items.first { $0.id == item.id } ?? item
                stored.ebayItemId = newId
                update(stored)
                schedCount += 1
                if !isTest { addPaperTrailEntry(action: .relistedEbay, item: item) }
            } catch {
                errors.append("Schedule \(item.sku): \(error.localizedDescription)")
            }
        }

        // Step 4 — Export CSV backup
        let config = EbayExportService.ScheduleConfig(startDate: slots.first ?? now, intervalMinutes: 30)
        let ts     = DateFormatter().apply { $0.dateFormat = "yyyyMMdd_HHmm" }.string(from: now)
        if let result = try? EbayExportService.buildScheduledCSV(items: scheduledItems, config: config) {
            _ = try? EbayExportService.silentSave(result.csv, filename: "ebay_relist_\(ts).csv")
        }

        // Step 5 — Send recap email
        let endedSummary   = syncedBatch.map { (sku: $0.sku, title: $0.title, price: $0.ebayPrice) }
        let scheduledSummary = zip(scheduledItems, slots).map {
            (sku: $0.0.sku, title: $0.0.title, price: $0.0.ebayPrice, slot: $0.1)
        }
        let snapshot = InventorySnapshot(from: self)
        try? AppleScriptService.sendRecapEmail(
            to: credentials.recapEmail,
            ended: endedSummary,
            scheduled: scheduledSummary,
            inventorySnapshot: snapshot,
            isTestRun: isTest
        )

        var summary = "✓ Ended \(endedCount), scheduled \(schedCount)"
        if !errors.isEmpty { summary += " | Errors: \(errors.joined(separator: "; "))" }
        if !isTest { writeLastRunResult(summary) }
        return summary
    }

    // MARK: - Scheduling helpers (mirrors EbayAutomationView logic)

    private func nextSchedulingFrontier() -> Date {
        let cst = TimeZone(identifier: "America/Chicago")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = cst
        let futureDates = items.compactMap { $0.dateListed }.filter { $0 > Date() }
        let frontier    = futureDates.max() ?? Date()
        var comps       = cal.dateComponents([.year, .month, .day], from: frontier)
        comps.timeZone  = cst
        let day         = cal.date(from: comps) ?? frontier
        return cal.date(byAdding: .day, value: futureDates.isEmpty ? 0 : 1, to: day) ?? day
    }

    private func relistSlots(startingFrom date: Date, count: Int) -> [Date] {
        let cst = TimeZone(identifier: "America/Chicago")!
        var cal = Calendar(identifier: .gregorian); cal.timeZone = cst
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.timeZone = cst
        var slots: [Date] = []; var hour = 18; var minute = 0
        for _ in 0..<count {
            comps.hour = hour; comps.minute = minute
            if let slot = cal.date(from: comps) { slots.append(slot) }
            minute += 30; if minute >= 60 { minute = 0; hour += 1 }
        }
        return slots
    }

    // MARK: - Last Run Tracking

    private var lastRunURL: URL {
        saveURL.deletingLastPathComponent().appendingPathComponent("last_relist.txt")
    }

    func hasRunToday() -> Bool {
        guard let contents = try? String(contentsOf: lastRunURL),
              let stored   = ISO8601DateFormatter().date(from: contents.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return Calendar.current.isDateInToday(stored)
    }

    func writeLastRunResult(_ result: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? "\(stamp)|\(result)".write(to: lastRunURL, atomically: true, encoding: .utf8)
    }

    func lastRunInfo() -> (date: Date?, result: String?) {
        guard let contents = try? String(contentsOf: lastRunURL) else { return (nil, nil) }
        let parts = contents.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 1)
        let date  = parts.first.flatMap { ISO8601DateFormatter().date(from: String($0)) }
        let result = parts.count > 1 ? String(parts[1]) : nil
        return (date, result)
    }

    // MARK: - IG Queue Management

    func addToIGQueue(_ post: IGScheduledPost) {
        var normalized = post
        // Normalize to start of day so items are due at any time on scheduled date
        normalized.scheduledDate = Calendar.current.startOfDay(for: post.scheduledDate)
        igQueue.append(normalized)
        igQueue.sort { $0.scheduledDate < $1.scheduledDate }
        encode(igQueue, to: igQueueURL)
    }

    func updateIGQueueItem(_ post: IGScheduledPost) {
        if let idx = igQueue.firstIndex(where: { $0.id == post.id }) {
            igQueue[idx] = post
            encode(igQueue, to: igQueueURL)
        }
    }

    func removeFromIGQueue(id: UUID) {
        igQueue.removeAll { $0.id == id }
        encode(igQueue, to: igQueueURL)
    }

    var pendingIGPosts: [IGScheduledPost] { igQueue.filter { $0.status == .pending } }
    var dueIGPosts: [IGScheduledPost] {
        let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: Date()) ?? Date()
        return igQueue.filter { $0.status == .pending && $0.scheduledDate <= endOfToday }
    }

    // MARK: - IG Paper Trail

    func addIGPaperTrailEntry(post: IGScheduledPost) {
        var entry = PaperTrailEntry()
        entry.date   = Date()
        entry.action = .postedInstagram
        entry.sku    = post.sku
        entry.artist = post.artist
        entry.title  = post.title
        paperTrail.insert(entry, at: 0)
        encode(paperTrail, to: paperTrailURL)
    }

    // MARK: - External Change Detection

    // Copies file from ~/Library/Application Support/PosterMalone/ to sandbox if sandbox copy is missing/empty
    private func migrateFromRealPathIfNeeded(filename: String, to sandboxURL: URL) {
        // Check if sandbox already has data
        if let data = try? Data(contentsOf: sandboxURL), data.count > 5 { return }
        // Try to read from real (non-sandbox) path
        let realPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/PosterMalone/\(filename)")
        guard let data = try? Data(contentsOf: realPath), data.count > 5 else { return }
        try? data.write(to: sandboxURL, options: .atomic)
        print("InventoryStore: migrated \(filename) from real path to sandbox")
    }

    func refreshIGStatuses() {
        guard let fresh: [InventoryItem] = decode(from: saveURL) else { return }
        for freshItem in fresh {
            if let idx = items.firstIndex(where: { $0.id == freshItem.id }),
               items[idx].igStatus != freshItem.igStatus {
                items[idx].igStatus = freshItem.igStatus
            }
        }
        igQueue    = (decode(from: igQueueURL)    as [IGScheduledPost]?)    ?? igQueue
        paperTrail = (decode(from: paperTrailURL) as [PaperTrailEntry]?)    ?? paperTrail
    }
}

// DateFormatter apply helper
extension DateFormatter {
    @discardableResult
    func apply(_ block: (DateFormatter) -> Void) -> DateFormatter {
        block(self); return self
    }
}
