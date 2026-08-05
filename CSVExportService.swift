import Foundation

struct CSVExportService {

    // MARK: - Date Formatter

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        return f
    }()

    private static func fmt(_ date: Date?) -> String {
        guard let d = date else { return "" }
        return dateFmt.string(from: d)
    }

    private static func currency(_ value: Double) -> String {
        guard value != 0 else { return "" }
        return String(format: "$%.2f", value)
    }

    private static func pct(_ value: Double) -> String {
        guard value != 0 else { return "" }
        return String(format: "%.2f%%", value)
    }

    // Wrap a field in quotes if it contains commas, quotes, or newlines
    private static func escape(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") || s.contains("\r") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    private static func row(_ fields: [String]) -> String {
        fields.map { escape($0) }.joined(separator: ",")
    }

    // MARK: - Inventory CSV
    // Matches: Action,Sku,Status,Date Listed,Drawer,Sleeve #,Artist,Title of Print,
    //          Size,Edition,Signed,Imperfect,Production Technique,Print Type,Gallery,
    //          Condition (New/Used),Theme,Franchise,Tags,Description,Days in Inventory,
    //          Date Purchased,Net Cost,Tax & Shipping,Total Cost,Weight,Tube Size,
    //          eBay CategoryID,PaymentProfileName,ReturnProfileName,ShippingProfileName,
    //          eBay Price,Shopify Price,Shopify Status,Date Sold,Marketplace,Gross Sales,
    //          Taxes,Fees+Shipping,Net Sales,Profit,P/L%,Days to Sell,eBay Title,
    //          Image1..Image11,Shopify Description,Listed on Shopify,eBay title updated,
    //          eBay Status,Min Best Offer,Auto Accept Offer,Title Char Length,
    //          StoreCategory1,StoreCategory2,Shopify Title,IG_Post,IG_Caption,IG_Status,IG_Notes

    static func inventoryCSV(from items: [InventoryItem]) -> String {
        let header = "Action,Sku,Status,Date Listed,Drawer,Sleeve #,Artist,Title of Print,Size,Edition,Signed,Imperfect,Production Technique,Print Type,Gallery,Condition (New/Used),Theme,Franchise,Tags,Description,Days in Inventory,Date Purchased,Net Cost,Tax & Shipping,Total Cost,Weight,Tube Size,eBay CategoryID,PaymentProfileName,ReturnProfileName,ShippingProfileName,eBay Price,Shopify Price,Shopify Status,Date Sold,Marketplace,Gross Sales,Taxes,Fees+Shipping,Net Sales,Profit,P/L%,Days to Sell,eBay Title,Image1,Image2,Image3,Image4,Image5,Image6,Image7,Image8,Image9,Image10,Image11,Shopify Description,Listed on Shopify,eBay title updated,eBay Status,Min Best Offer,Auto Accept Offer,Title Char Length,StoreCategory1,StoreCategory2,Shopify Title,IG_Post,IG_Caption,IG_Status,IG_Notes"

        var lines = [header]

        for item in items {
            // Pad images array to 11 slots
            var imgs = item.images
            while imgs.count < 11 { imgs.append("") }

            let fields: [String] = [
                item.action,                                          // Action
                item.sku,                                             // Sku
                item.status.rawValue,                                 // Status
                fmt(item.dateListed),                                 // Date Listed
                item.drawer,                                          // Drawer
                item.sleeveNumber,                                    // Sleeve #
                item.artist,                                          // Artist
                item.title,                                           // Title of Print
                item.size,                                            // Size
                item.edition,                                         // Edition
                item.signed ? "Yes" : "",                             // Signed
                item.imperfect ? "Yes" : "",                          // Imperfect
                item.productionTechnique,                             // Production Technique
                item.printType,                                       // Print Type
                item.gallery,                                         // Gallery
                item.condition,                                       // Condition (New/Used)
                item.theme,                                           // Theme
                item.franchise,                                       // Franchise
                item.tags,                                            // Tags
                item.description,                                     // Description
                item.daysInInventory > 0 ? "\(item.daysInInventory)" : "",  // Days in Inventory
                fmt(item.datePurchased),                              // Date Purchased
                currency(item.netCost),                               // Net Cost
                currency(item.taxAndShipping),                        // Tax & Shipping
                currency(item.totalCost),                             // Total Cost
                item.weight > 0 ? String(format: "%.1f", item.weight) : "",  // Weight
                "",                                                   // Tube Size (not tracked in inventory)
                item.ebayCategoryId,                                  // eBay CategoryID
                item.paymentProfileName,                              // PaymentProfileName
                item.returnProfileName,                               // ReturnProfileName
                item.shippingProfileName,                             // ShippingProfileName
                currency(item.ebayPrice),                             // eBay Price
                currency(item.shopifyPrice),                          // Shopify Price
                item.shopifyStatus,                                   // Shopify Status
                "",                                                   // Date Sold (n/a for inventory)
                item.listingMarketplace.rawValue,                     // Marketplace
                "", "", "", "", "", "",                               // Sales fields (n/a)
                item.ebayTitle.count > 0 ? "\(item.ebayTitle.count)" : "", // Days to Sell placeholder / Title Char
                item.ebayTitle,                                       // eBay Title
                imgs[0], imgs[1], imgs[2], imgs[3], imgs[4],          // Image1-5
                imgs[5], imgs[6], imgs[7], imgs[8], imgs[9], imgs[10],// Image6-11
                item.shopifyDescription,                              // Shopify Description
                "",                                                   // Listed on Shopify
                "",                                                   // eBay title updated
                item.ebayListingStatus,                               // eBay Status
                item.minBestOffer > 0 ? currency(item.minBestOffer) : "",     // Min Best Offer
                item.autoAcceptOffer > 0 ? currency(item.autoAcceptOffer) : "", // Auto Accept Offer
                "\(item.ebayTitle.count)",                            // Title Char Length
                item.storeCategory1,                                  // StoreCategory1
                item.storeCategory2,                                  // StoreCategory2
                item.shopifyTitle,                                    // Shopify Title
                item.igPost ? "TRUE" : "",                            // IG_Post
                item.igCaption,                                       // IG_Caption
                item.igStatus,                                        // IG_Status
                ""                                                    // IG_Notes
            ]
            lines.append(row(fields))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Sales CSV
    // Matches: Action,Sku,Status,Date Listed,Drawer,Sleeve #,Artist,Title of Print,
    //          Size,Edition,Signed,Imperfect,Production Technique,Print Type,Gallery,
    //          Condition (New/Used),Theme,Franchise,Tags,Description,Days in Inventory,
    //          Date Purchased,Net Cost,Tax & Shipping,Total Cost,Shipping Weight (lbs),
    //          Tube Size,eBay CategoryID,eBay_Payments,30_Day_Return,Free_USPS_Ground,
    //          eBay Price,Shopify Price,Shopify Status,Date Sold,Marketplace,Gross Sales,
    //          Taxes,Fees+Shipping,Net Sales,Profit,P/L%,Days to Sell,eBay Title

    static func salesCSV(from sales: [SaleRecord]) -> String {
        let header = "Action,Sku,Status,Date Listed,Drawer,Sleeve #,Artist,Title of Print,Size,Edition,Signed,Imperfect,Production Technique,Print Type,Gallery,Condition (New/Used),Theme,Franchise,Tags,Description,Days in Inventory,Date Purchased,Net Cost,Tax & Shipping,Total Cost,Shipping Weight (lbs),Tube Size,eBay CategoryID,eBay_Payments,30_Day_Return,Free_USPS_Ground,eBay Price,Shopify Price,Shopify Status,Date Sold,Marketplace,Gross Sales,Taxes,Fees+Shipping,Net Sales,Profit,P/L%,Days to Sell,eBay Title"

        var lines = [header]

        for sale in sales {
            let fields: [String] = [
                "",                                                   // Action
                sale.sku,                                             // Sku
                "Sold",                                               // Status
                fmt(sale.dateListed),                                 // Date Listed
                sale.drawer,                                          // Drawer
                sale.sleeveNumber,                                    // Sleeve #
                sale.artist,                                          // Artist
                sale.title,                                           // Title of Print
                sale.size,                                            // Size
                sale.edition,                                         // Edition
                sale.signed ? "Yes" : "",                             // Signed
                sale.imperfect ? "Yes" : "",                          // Imperfect
                sale.productionTechnique,                             // Production Technique
                sale.printType,                                       // Print Type
                sale.gallery,                                         // Gallery
                sale.condition,                                       // Condition (New/Used)
                sale.theme,                                           // Theme
                sale.franchise,                                       // Franchise
                sale.tags,                                            // Tags
                "",                                                   // Description
                sale.daysInInventory > 0 ? "\(sale.daysInInventory)" : "", // Days in Inventory
                fmt(sale.datePurchased),                              // Date Purchased
                currency(sale.netCost),                               // Net Cost
                currency(sale.taxAndShipping),                        // Tax & Shipping
                currency(sale.totalCost),                             // Total Cost
                sale.weight > 0 ? String(format: "%.1f", sale.weight) : "", // Shipping Weight
                sale.tubeSize,                                        // Tube Size
                sale.ebayCategoryId,                                  // eBay CategoryID
                sale.paymentProfileName,                              // eBay_Payments
                sale.returnProfileName,                               // 30_Day_Return
                sale.shippingProfileName,                             // Free_USPS_Ground
                currency(sale.ebayPrice),                             // eBay Price
                currency(sale.shopifyPrice),                          // Shopify Price
                sale.shopifyStatus,                                   // Shopify Status
                fmt(sale.dateSold),                                   // Date Sold
                sale.marketplace.rawValue,                            // Marketplace
                currency(sale.grossSales),                            // Gross Sales
                currency(sale.taxes),                                 // Taxes
                currency(sale.feesAndShipping),                       // Fees+Shipping
                currency(sale.netSales),                              // Net Sales
                currency(sale.profit),                                // Profit
                pct(sale.profitLossPercent),                          // P/L%
                sale.daysToSell > 0 ? "\(sale.daysToSell)" : "",     // Days to Sell
                sale.ebayTitle                                        // eBay Title
            ]
            lines.append(row(fields))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Write to disk

    static func writeCSVBackup(inventoryCSV: String, salesCSV: String) throws -> (inventory: URL, sales: URL) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupDir = docs.appendingPathComponent("PosterMalone Backups")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let stamp = formatter.string(from: Date())

        let invURL   = backupDir.appendingPathComponent("inventory_\(stamp).csv")
        let salesURL = backupDir.appendingPathComponent("sales_\(stamp).csv")

        try inventoryCSV.write(to: invURL,   atomically: true, encoding: .utf8)
        try salesCSV.write(to: salesURL, atomically: true, encoding: .utf8)

        return (invURL, salesURL)
    }
}
