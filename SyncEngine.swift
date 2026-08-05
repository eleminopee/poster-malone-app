import Foundation

struct SyncResult {
    var inventoryAdded: Int = 0
    var inventoryUpdated: Int = 0
    var inventorySkipped: Int = 0
    var inventoryRemovedSold: Int = 0
    var salesAdded: Int = 0
    var salesUpdated: Int = 0
    var errors: [String] = []

    var summary: String {
        var lines: [String] = []
        lines.append("Inventory: \(inventoryAdded) added, \(inventoryUpdated) updated, \(inventorySkipped) skipped")
        if inventoryRemovedSold > 0 {
            lines.append("Removed \(inventoryRemovedSold) items already in Sales (sold SKUs)")
        }
        if salesAdded > 0 || salesUpdated > 0 {
            lines.append("Sales: \(salesAdded) added, \(salesUpdated) updated")
        }
        if !errors.isEmpty {
            lines.append("\(errors.count) error(s) — check console for details")
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
struct SyncEngine {

    // MARK: - Inventory sync

    static func syncInventory(
        incoming: [InventoryItem],
        into store: InventoryStore
    ) -> SyncResult {
        var result = SyncResult()

        // Build set of SKUs already in Sales — these should never appear in Inventory
        let soldSKUs = Set(store.sales.map { $0.sku })

        for incoming in incoming {
            // Skip items that are already recorded as sold
            if soldSKUs.contains(incoming.sku) {
                result.inventorySkipped += 1
                continue
            }

            if let existingIndex = store.items.firstIndex(where: { $0.sku == incoming.sku }) {
                // Update existing — merge carefully
                var existing = store.items[existingIndex]
                existing = mergeInventoryItem(existing: existing, incoming: incoming)
                store.items[existingIndex] = existing
                result.inventoryUpdated += 1
            } else {
                // New item
                store.items.append(incoming)
                result.inventoryAdded += 1
            }
        }

        // Also remove any items already in store.items that are now in Sales
        // (catches the case where items were sold via the app after the last import)
        let toRemove = store.items.filter { soldSKUs.contains($0.sku) }
        if !toRemove.isEmpty {
            store.items.removeAll { soldSKUs.contains($0.sku) }
            result.inventoryRemovedSold += toRemove.count
        }

        store.save()
        return result
    }

    // MARK: - Sales sync

    static func syncSales(
        incoming: [SaleRecord],
        into store: InventoryStore
    ) -> SyncResult {
        var result = SyncResult()

        for incoming in incoming {
            if let existingIndex = store.sales.firstIndex(where: { $0.sku == incoming.sku }) {
                store.sales[existingIndex] = incoming
                result.salesUpdated += 1
            } else {
                store.sales.append(incoming)
                result.salesAdded += 1
            }
        }

        store.save()
        return result
    }

    // MARK: - Merge strategy
    // App-side changes win for: shopifyDescription, shopifyTitle, igCaption, images (if already set)
    // Sheet-side wins for: prices, eBay fields, descriptions, status, dates, storage

    private static func mergeInventoryItem(
        existing: InventoryItem,
        incoming: InventoryItem
    ) -> InventoryItem {
        var merged = existing

        // Always take from sheet (automation manages these)
        merged.artist              = incoming.artist
        merged.title               = incoming.title
        merged.size                = incoming.size
        merged.edition             = incoming.edition
        merged.printType           = incoming.printType
        merged.productionTechnique = incoming.productionTechnique
        merged.gallery             = incoming.gallery
        merged.franchise           = incoming.franchise
        merged.theme               = incoming.theme
        merged.condition           = incoming.condition
        merged.signed              = incoming.signed
        merged.imperfect           = incoming.imperfect
        merged.drawer              = incoming.drawer
        merged.sleeveNumber        = incoming.sleeveNumber
        merged.ebayTitle           = incoming.ebayTitle
        merged.ebayCategoryId      = incoming.ebayCategoryId
        merged.storeCategory1      = incoming.storeCategory1
        merged.storeCategory2      = incoming.storeCategory2
        merged.paymentProfileName  = incoming.paymentProfileName
        merged.returnProfileName   = incoming.returnProfileName
        merged.shippingProfileName = incoming.shippingProfileName
        merged.ebayPrice           = incoming.ebayPrice
        merged.shopifyPrice        = incoming.shopifyPrice
        merged.minBestOffer        = incoming.minBestOffer
        merged.autoAcceptOffer     = incoming.autoAcceptOffer
        merged.netCost             = incoming.netCost
        merged.taxAndShipping      = incoming.taxAndShipping
        merged.totalCost           = incoming.totalCost
        merged.weight              = incoming.weight
        merged.tags                = incoming.tags
        merged.status              = incoming.status

        // Shopify title: keep app version if it exists (AI-generated), else take sheet
        if merged.shopifyTitle.isEmpty {
            merged.shopifyTitle = incoming.shopifyTitle
        }

        // Shopify status from sheet
        merged.shopifyStatus = incoming.shopifyStatus

        // Always take images from sheet — sheet reflects current Google Drive state
        if !incoming.images.isEmpty {
            merged.images = incoming.images
        }

        // Take eBay/Shopify descriptions from sheet only if app has none
        if merged.description.isEmpty {
            merged.description = incoming.description
        }
        if merged.shopifyDescription.isEmpty {
            merged.shopifyDescription = incoming.shopifyDescription
        }

        // Keep dates from whichever has them
        if merged.dateListed == nil    { merged.dateListed    = incoming.dateListed }
        if merged.datePurchased == nil { merged.datePurchased = incoming.datePurchased }

        return merged
    }
}
