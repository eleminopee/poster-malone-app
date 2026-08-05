import Foundation

struct CSVImporter {

    // MARK: - Public entry points

    static func importInventory(from url: URL) throws -> [InventoryItem] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(raw)
        guard let header = rows.first else { throw ImportError.emptyFile }
        let H = headerMap(header)
        return rows.dropFirst().compactMap { parseInventoryRow($0, H: H) }
    }

    static func importSales(from url: URL) throws -> [SaleRecord] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(raw)
        guard let header = rows.first else { throw ImportError.emptyFile }
        let H = headerMap(header)
        return rows.dropFirst().compactMap { parseSaleRow($0, H: H) }
    }

    /// Reads ONLY the SKU and Status columns from a CSV.
    /// Returns a dictionary of [SKU: ItemStatus] for patching existing inventory
    /// without touching any other field. Safe to run at any time.
    static func syncStatusFromCSV(from url: URL) throws -> [String: ItemStatus] {
        let raw = try String(contentsOf: url, encoding: .utf8)
        let rows = parseCSV(raw)
        guard let header = rows.first else { throw ImportError.emptyFile }
        let H = headerMap(header)

        var result: [String: ItemStatus] = [:]
        for row in rows.dropFirst() {
            let sku = str(row, H, "Sku").trimmingCharacters(in: .whitespaces)
            let statusRaw = str(row, H, "Status").trimmingCharacters(in: .whitespaces)
            guard !sku.isEmpty else { continue }
            // Map to ItemStatus — fall back to .active for blank/unknown values
            let status = ItemStatus(rawValue: statusRaw) ?? (statusRaw.isEmpty ? .active : .active)
            result[sku] = status
        }
        return result
    }

    // MARK: - Row parsers

    private static func parseInventoryRow(_ row: [String], H: [String: Int]) -> InventoryItem? {
        let sku = str(row, H, "Sku")
        guard !sku.isEmpty else { return nil }

        var item = InventoryItem()
        item.sku                 = sku
        item.action              = str(row, H, "Action")
        item.title               = str(row, H, "Title of Print")
        item.artist              = str(row, H, "Artist")
        item.size                = str(row, H, "Size")
        item.edition             = str(row, H, "Edition")
        item.printType           = str(row, H, "Print Type")
        item.productionTechnique = str(row, H, "Production Technique")
        item.gallery             = str(row, H, "Gallery")
        item.franchise           = str(row, H, "Franchise")
        item.theme               = str(row, H, "Theme")
        item.condition           = str(row, H, "Condition (New/Used)")
        item.signed              = str(row, H, "Signed").lowercased() == "yes"
        item.imperfect           = str(row, H, "Imperfect").lowercased() == "yes"
        item.drawer              = str(row, H, "Drawer")
        item.sleeveNumber        = str(row, H, "Sleeve #")
        item.description         = str(row, H, "Description")
        item.tags                = str(row, H, "Tags")
        item.ebayTitle           = str(row, H, "eBay Title")
        item.ebayCategoryId      = str(row, H, "eBay CategoryID")
        item.ebayPrice           = money(row, H, "eBay Price")
        item.shopifyPrice        = money(row, H, "Shopify Price")
        item.shopifyStatus       = str(row, H, "Shopify Status")
        item.shopifyTitle        = str(row, H, "Shopify Title")
        item.paymentProfileName  = str(row, H, "PaymentProfileName")
        item.returnProfileName   = str(row, H, "ReturnProfileName")
        item.shippingProfileName = str(row, H, "ShippingProfileName")
        item.storeCategory1      = str(row, H, "StoreCategory1")
        item.storeCategory2      = str(row, H, "StoreCategory2")
        item.netCost             = money(row, H, "Net Cost")
        item.taxAndShipping      = money(row, H, "Tax & Shipping")
        item.weight              = dbl(row, H, "Weight")
        item.igPost              = str(row, H, "IG_Post").lowercased() == "true"
        item.igCaption           = str(row, H, "IG_Caption")
        item.igStatus            = str(row, H, "IG_Status")
        item.datePurchased       = date(row, H, "Date Purchased")
        item.dateListed          = date(row, H, "Date Listed")

        // Status — now maps all real values correctly
        let statusStr = str(row, H, "Status")
        item.status = ItemStatus(rawValue: statusStr) ?? .active

        // Images (Image1 through Image11)
        var images: [String] = []
        for i in 1...11 {
            let url = str(row, H, "Image\(i)")
            if !url.isEmpty { images.append(url) }
        }
        item.images = images

        return item
    }

    private static func parseSaleRow(_ row: [String], H: [String: Int]) -> SaleRecord? {
        let sku = str(row, H, "Sku")
        guard !sku.isEmpty else { return nil }

        var sale = SaleRecord()

        // Identity
        sale.sku                = sku
        sale.artist             = str(row, H, "Artist")
        sale.title              = str(row, H, "Title of Print")
        sale.size               = str(row, H, "Size")
        sale.edition            = str(row, H, "Edition")
        sale.printType          = str(row, H, "Print Type")
        sale.productionTechnique = str(row, H, "Production Technique")
        sale.gallery            = str(row, H, "Gallery")
        sale.franchise          = str(row, H, "Franchise")
        sale.theme              = str(row, H, "Theme")
        sale.condition          = str(row, H, "Condition (New/Used)")
        sale.signed             = str(row, H, "Signed").lowercased() == "yes"
        sale.imperfect          = str(row, H, "Imperfect").lowercased() == "yes"
        sale.tags               = str(row, H, "Tags")

        // Storage
        sale.drawer             = str(row, H, "Drawer")
        sale.sleeveNumber       = str(row, H, "Sleeve #")

        // Acquisition
        sale.datePurchased      = date(row, H, "Date Purchased")
        sale.netCost            = money(row, H, "Net Cost")
        sale.taxAndShipping     = money(row, H, "Tax & Shipping")
        sale.totalCost          = money(row, H, "Total Cost")
        sale.weight             = dbl(row, H, "Shipping Weight (lbs)")

        // Listing details
        sale.dateListed         = date(row, H, "Date Listed")
        let daysInvStr = str(row, H, "Days in Inventory")
        sale.daysInInventory    = Int(daysInvStr) ?? Int(Double(daysInvStr) ?? 0)
        sale.ebayTitle          = str(row, H, "eBay Title")
        sale.ebayCategoryId     = str(row, H, "eBay CategoryID")
        sale.ebayPrice          = money(row, H, "eBay Price")
        sale.shopifyPrice       = money(row, H, "Shopify Price")
        sale.shopifyStatus      = str(row, H, "Shopify Status")
        sale.paymentProfileName = str(row, H, "PaymentProfileName")
        sale.returnProfileName  = str(row, H, "ReturnProfileName")
        sale.shippingProfileName = str(row, H, "ShippingProfileName")

        // Sale financials
        sale.dateSold           = date(row, H, "Date Sold") ?? Date()
        sale.grossSales         = money(row, H, "Gross Sales")
        sale.taxes              = money(row, H, "Taxes")
        sale.feesAndShipping    = money(row, H, "Fees+Shipping")
        sale.netSales           = money(row, H, "Net Sales")
        sale.profit             = money(row, H, "Profit")
        sale.daysToSell         = Int(str(row, H, "Days to Sell")) ?? 0

        // P/L% — stored as "38.79%" in sheet
        let plStr = str(row, H, "P/L%")
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespaces)
        sale.profitLossPercent  = Double(plStr) ?? 0

        // Marketplace
        let mpStr = str(row, H, "Marketplace").lowercased()
        if mpStr.contains("shopify")        { sale.marketplace = .shopify }
        else if mpStr.contains("instagram") { sale.marketplace = .instagram }
        else if mpStr.contains("facebook")  { sale.marketplace = .facebook }
        else if mpStr.contains("person")    { sale.marketplace = .inPerson }
        else                                { sale.marketplace = .ebay }

        return sale
    }

    // MARK: - CSV Parser

    private static func parseCSV(_ raw: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var i = raw.startIndex

        while i < raw.endIndex {
            let c = raw[i]

            if inQuotes {
                if c == "\"" {
                    let next = raw.index(after: i)
                    if next < raw.endIndex && raw[next] == "\"" {
                        field.append("\"")
                        i = raw.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    current.append(field)
                    field = ""
                } else if c == "\n" || c == "\r\n" || c == "\r" {
                    current.append(field)
                    field = ""
                    if !current.allSatisfy({ $0.isEmpty }) {
                        rows.append(current)
                    }
                    current = []
                    if c == "\r" {
                        let next = raw.index(after: i)
                        if next < raw.endIndex && raw[next] == "\n" {
                            i = raw.index(after: next)
                            continue
                        }
                    }
                } else {
                    field.append(c)
                }
            }
            i = raw.index(after: i)
        }

        current.append(field)
        if !current.allSatisfy({ $0.isEmpty }) {
            rows.append(current)
        }

        return rows
    }

    // MARK: - Helpers

    private static func headerMap(_ headers: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (i, h) in headers.enumerated() {
            map[h.trimmingCharacters(in: .whitespacesAndNewlines)] = i
        }
        return map
    }

    private static func str(_ row: [String], _ H: [String: Int], _ key: String) -> String {
        guard let i = H[key], i < row.count else { return "" }
        return row[i].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func money(_ row: [String], _ H: [String: Int], _ key: String) -> Double {
        let s = str(row, H, key)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        return Double(s) ?? 0
    }

    private static func dbl(_ row: [String], _ H: [String: Int], _ key: String) -> Double {
        Double(str(row, H, key)) ?? 0
    }

    private static func date(_ row: [String], _ H: [String: Int], _ key: String) -> Date? {
        let s = str(row, H, key)
        guard !s.isEmpty else { return nil }
        for fmt in ["M/d/yyyy", "MM/dd/yyyy", "yyyy-MM-dd", "M/d/yy"] {
            let f = DateFormatter()
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    enum ImportError: LocalizedError {
        case emptyFile
        var errorDescription: String? { "The file appears to be empty." }
    }
}
