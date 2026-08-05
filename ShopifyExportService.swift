import AppKit
import Foundation

struct ShopifyExportService {

    static func buildCSV(items: [InventoryItem]) throws -> String {
        guard !items.isEmpty else {
            throw NSError(domain: "ShopifyExport", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No items with Action = Y found"])
        }

        let service = ShopifyService.shared
        let header = [
            "Handle", "Title", "Body (HTML)", "Vendor", "Type",
            "SEO Title", "SEO Description", "Tags", "Status", "Published",
            "Option1 Name", "Option1 Value",
            "Variant SKU", "Variant Grams", "Variant Inventory Qty",
            "Variant Price", "Variant Requires Shipping", "Variant Taxable",
            "Image Src", "Image Position",
            "Metafield: cin.edition", "Metafield: cin.gallery",
            "Metafield: cin.theme", "Metafield: cin.size",
            "Metafield: cin.width", "Metafield: cin.height",
            "Metafield: cin.type", "Metafield: cin.is_movie_poster",
            "Metafield: cin.edition_serial", "Metafield: cin.edition_total",
            "Metafield: cin.artist_slug", "Metafield: cin.gallery_slug",
            "Metafield: cin.pkg_length", "Metafield: cin.pkg_width",
            "Metafield: cin.pkg_height", "Metafield: cin.pkg_template"
        ]

        var rows: [[String]] = [header]

        for item in items {
            let title = item.shopifyTitle.isEmpty
                ? "\(item.artist) - \(item.title) - \(item.size) - Limited Edition Print"
                : item.shopifyTitle
            let handle = await_slugify(service, "\(item.artist) \(item.title) \(item.sku)")
            let body = item.shopifyDescription.isEmpty ? item.description : item.shopifyDescription
            let isPoster = item.size.contains("36") || item.printType.lowercased().contains("poster")
            let productType = isPoster ? "Poster" : "Print"
            let seoTitle = title
            let seoDesc = "\(title) \(item.size) limited edition poster print. Alternative movie poster for collectors."
            let tags = [item.artist, item.title, item.theme, item.franchise, item.printType,
                        "Alternative Movie Poster", "Movie Poster", "Poster"]
                .filter { !$0.isEmpty }.joined(separator: ", ")
            let grams = String(Int((item.weight > 0 ? item.weight : 2.0) * 453.592))
            let price = item.shopifyPrice > 0 ? String(format: "%.2f", item.shopifyPrice) : ""
            let size = await_parseSize(service, item.size)
            let pkg = await_packageForSize(service, item.size)
            let isMoviePoster = item.printType.lowercased().contains("movie") ? "true" : "false"

            var serial = ""; var total = ""
            if let match = item.edition.range(of: #"(\d+)\s*/\s*(\d+)"#, options: .regularExpression) {
                let parts = item.edition[match].components(separatedBy: "/")
                serial = parts[0].trimmingCharacters(in: .whitespaces)
                total  = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            }

            let artistSlug  = await_slugify(service, item.artist)
            let gallerySlug = await_slugify(service, item.gallery)

            let mainRow: [String] = [
                handle, title, body, item.artist, productType,
                seoTitle, seoDesc, tags, "draft", "FALSE",
                "Title", "Default Title",
                item.sku, grams, "1",
                price, "TRUE", "TRUE",
                item.images.first ?? "", item.images.isEmpty ? "" : "1",
                item.edition, item.gallery,
                item.theme, item.size,
                size.width, size.height,
                productType, isMoviePoster,
                serial, total,
                artistSlug, gallerySlug,
                String(pkg.length), String(pkg.width), String(pkg.height), pkg.template
            ]
            rows.append(mainRow)

            // Additional image rows
            for (i, imgUrl) in item.images.dropFirst().enumerated() {
                var imgRow = Array(repeating: "", count: header.count)
                imgRow[0]  = handle
                imgRow[18] = imgUrl
                imgRow[19] = String(i + 2)
                rows.append(imgRow)
            }
        }

        return rows.map { row in
            row.map { val in
                let s = val
                if s.contains(",") || s.contains("\"") || s.contains("\n") {
                    return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                }
                return s
            }.joined(separator: ",")
        }.joined(separator: "\n")
    }

    // Synchronous wrappers for actor methods used in sync context
    private static func await_slugify(_ service: ShopifyService, _ str: String) -> String {
        str.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    private static func await_parseSize(_ service: ShopifyService, _ s: String) -> (width: String, height: String) {
        let pattern = #"(\d+(?:\.\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r1 = Range(match.range(at: 1), in: s),
              let r2 = Range(match.range(at: 2), in: s) else {
            return ("", "")
        }
        return (String(s[r1]), String(s[r2]))
    }

    private static func await_packageForSize(_ service: ShopifyService, _ size: String) -> (length: Double, width: Double, height: Double, template: String) {
        if size.contains("36") { return (29, 3, 3, "large_tube") }
        if size.contains("24") { return (25, 3, 3, "medium_tube") }
        return (12, 12, 2, "flat_box")
    }

    // MARK: - Save via NSSavePanel

    @MainActor
    static func saveToFile(_ content: String, filename: String) throws -> URL {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.canCreateDirectories = true
        panel.message = "Choose where to save your Shopify export"
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        guard panel.runModal() == .OK, let url = panel.url else {
            throw NSError(domain: "ShopifyExport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Save cancelled"])
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
