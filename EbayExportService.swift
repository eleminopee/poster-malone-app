import AppKit
import Foundation

struct EbayExportService {

    // MARK: - Draft Export

    static func buildDraftCSV(items: [InventoryItem]) throws -> String {
        guard !items.isEmpty else {
            throw EbayService.EbayError.exportFailed("No items with Action = Y found")
        }

        let infoLines = [
            "#INFO\tVersion=0.0.2\tTemplate= eBay-draft-listings-template_US",
            "#INFO"
        ]

        let header = [
            "Action(SiteID=US|Country=US|Currency=USD|Version=1193|CC=UTF-8)",
            "Custom label (SKU)", "Category ID", "Title", "UPC", "Price",
            "Quantity", "Item photo URL", "Condition ID", "Description", "Format",
            "C:Artist", "C:Production Technique", "C:Features", "C:Theme",
            "C:Item Length", "C:Item Width", "Location",
            "PaymentProfileName", "ReturnProfileName", "ShippingProfileName"
        ]

        var rows: [[String]] = []

        for item in items {
            let conditionId = item.condition.lowercased().contains("used") ? "USED" : "NEW"
            let photoField  = item.images.joined(separator: "|")
            let size        = parseSize(item.size)

            rows.append([
                "Draft",
                item.sku,
                item.ebayCategoryId,
                item.ebayTitle,
                "",
                item.ebayPrice > 0 ? String(format: "%.2f", item.ebayPrice) : "",
                "1",
                photoField,
                conditionId,
                item.description,
                "FixedPrice",
                item.artist,
                item.productionTechnique,
                "Limited Edition",
                "Movies|Art",
                size.height,
                size.width,
                "Your City, ST",
                item.paymentProfileName,
                item.returnProfileName,
                item.shippingProfileName
            ])
        }

        var lines: [String] = []
        infoLines.forEach { lines.append($0) }
        lines.append(csvRow(header))
        rows.forEach { lines.append(csvRow($0)) }
        return lines.joined(separator: "\n")
    }

    // MARK: - Scheduled Export

    struct ScheduleConfig {
        var startDate: Date
        var intervalMinutes: Int
    }

    static func buildScheduledCSV(
        items: [InventoryItem],
        config: ScheduleConfig
    ) throws -> (csv: String, count: Int, hasLeadTimeWarning: Bool) {
        guard !items.isEmpty else {
            throw EbayService.EbayError.exportFailed("No items with Action = Y found")
        }

        let header = [
            "Action(SiteID=US|Country=US|Currency=USD|Version=1193|CC=UTF-8)",
            "Custom label (SKU)", "Category ID", "StoreCategory", "StoreCategory2",
            "Title", "UPC", "Price", "Quantity", "Item photo URL", "Condition ID",
            "Description", "Format", "Duration",
            "C:Artist", "C:Production Technique", "C:Features", "C:Theme",
            "C:Franchise", "C:Character", "C:Type",
            "C:Item Length", "C:Item Width",
            "Location", "PostalCode",
            "PaymentProfileName", "ReturnProfileName", "ShippingProfileName",
            "WeightMajor", "WeightMinor", "PackageLength", "PackageWidth", "PackageDepth",
            "BestOfferEnabled", "MinimumBestOfferPrice", "BestOfferAutoAcceptPrice",
            "ScheduleTime"
        ]

        let now = Date()
        let oneHourFromNow = now.addingTimeInterval(3600)
        var hasLeadTimeWarning = false
        var scheduleTime = config.startDate
        var rows: [[String]] = []

        for item in items {
            if scheduleTime < oneHourFromNow { hasLeadTimeWarning = true }

            let conditionId = item.condition.lowercased().contains("used") ? "USED" : "NEW"
            let photoField  = item.images.joined(separator: "|")
            let size        = parseSize(item.size)
            let pkg         = packageForWeight(item.weight)

            let minOffer   = item.ebayPrice > 0 ? String(format: "%.2f", item.ebayPrice * 0.80) : ""
            let autoAccept = item.ebayPrice > 0 ? String(format: "%.2f", item.ebayPrice * 0.90) : ""
            let schedStr   = formatEbayDateTime(scheduleTime)

            rows.append([
                "Add",
                item.sku,
                item.ebayCategoryId,
                item.storeCategory1,
                item.storeCategory2,
                item.ebayTitle,
                "",
                item.ebayPrice > 0 ? String(format: "%.2f", item.ebayPrice) : "",
                "1",
                photoField,
                conditionId,
                item.description,
                "FixedPrice",
                "GTC",
                item.artist,
                item.productionTechnique,
                "Limited Edition",
                "Movies|Art",
                item.franchise,
                item.character,
                item.printType,
                size.height,
                size.width,
                "Your City, State",
                "00000",
                item.paymentProfileName,
                item.returnProfileName,
                item.shippingProfileName,
                String(pkg.weightMajor),
                String(pkg.weightMinor),
                String(pkg.length),
                String(pkg.width),
                String(pkg.depth),
                "true",
                minOffer,
                autoAccept,
                schedStr
            ])

            scheduleTime = scheduleTime.addingTimeInterval(Double(config.intervalMinutes) * 60)
        }

        var lines = [csvRow(header)]
        rows.forEach { lines.append(csvRow($0)) }
        let csv = lines.joined(separator: "\n")
        return (csv, rows.count, hasLeadTimeWarning)
    }

    // MARK: - Helpers

    struct SizeParsed {
        let width: String
        let height: String
    }

    static func parseSize(_ sizeStr: String) -> SizeParsed {
        let pattern = #"(\d+(?:\.\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: sizeStr,
                range: NSRange(sizeStr.startIndex..., in: sizeStr)
              ),
              let r1 = Range(match.range(at: 1), in: sizeStr),
              let r2 = Range(match.range(at: 2), in: sizeStr)
        else {
            return SizeParsed(width: "", height: "")
        }
        return SizeParsed(width: String(sizeStr[r1]), height: String(sizeStr[r2]))
    }

    struct PackageDimensions {
        let weightMajor: Int
        let weightMinor: Int
        let length: Int
        let width: Int
        let depth: Int
    }

    static func packageForWeight(_ weight: Double) -> PackageDimensions {
        if weight >= 1.5 {
            return PackageDimensions(weightMajor: 2, weightMinor: 0, length: 29, width: 3, depth: 3)
        } else if weight >= 0.75 {
            return PackageDimensions(weightMajor: 1, weightMinor: 0, length: 25, width: 3, depth: 3)
        } else if weight > 0 {
            return PackageDimensions(weightMajor: 0, weightMinor: 8, length: 12, width: 12, depth: 2)
        }
        // Default: large tube
        return PackageDimensions(weightMajor: 2, weightMinor: 0, length: 29, width: 3, depth: 3)
    }

    static func formatEbayDateTime(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let y  = comps.year ?? 2025
        let mo = String(format: "%02d", comps.month ?? 1)
        let d  = String(format: "%02d", comps.day ?? 1)
        let h  = String(format: "%02d", comps.hour ?? 0)
        let mi = String(format: "%02d", comps.minute ?? 0)
        return "\(y)-\(mo)-\(d) \(h):\(mi):00"
    }

    static func csvRow(_ fields: [String]) -> String {
        fields.map { val -> String in
            let s = val
            if s.contains(",") || s.contains("\"") || s.contains("\n") {
                return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return s
        }.joined(separator: ",")
    }

    // MARK: - Silent Save (automation path — saves to ~/Downloads for easy File Exchange upload)

    static func silentSave(_ content: String, filename: String) throws -> URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let url = downloads.appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Save via NSSavePanel (sandbox-safe)
    // Must be called from MainActor — NSSavePanel.runModal() requires the main thread.

    @MainActor
    static func saveToDownloads(_ content: String, filename: String) throws -> URL {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        panel.message = "Choose where to save your eBay export"

        if let downloads = FileManager.default.urls(
            for: .downloadsDirectory, in: .userDomainMask
        ).first {
            panel.directoryURL = downloads
        }

        let response = panel.runModal()

        guard response == .OK, let url = panel.url else {
            throw EbayService.EbayError.exportFailed("Save cancelled")
        }

        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
