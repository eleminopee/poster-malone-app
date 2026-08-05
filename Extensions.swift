import Foundation
import SwiftUI

extension Double {
    var asCurrency: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    var asPercent: String {
        String(format: "%.1f%%", self)
    }
}

extension String {
    var slugified: String {
        self.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: .alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined()
    }
}

extension Date {
    var shortDate: String {
        formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - InventoryItem content generators
// Shared by ItemEditSheet (single item) and EbayAutomationView (bulk fill)

extension InventoryItem {

    // eBay Title: "Title Mondo Size Poster Artist Limited Edition Print"
    // Gracefully trims to ≤80 chars by dropping suffix tokens if needed.
    func generatedEbayTitle() -> String {
        let t = title.trimmingCharacters(in: .whitespaces)
        let s = size.trimmingCharacters(in: .whitespaces)
        let a = artist.trimmingCharacters(in: .whitespaces)

        func build(_ parts: [String]) -> String { parts.filter { !$0.isEmpty }.joined(separator: " ") }

        let full     = build([t, "Mondo", s, "Poster", a, "Limited Edition Print"])
        if full.count <= 80 { return full }

        let noSuffix = build([t, "Mondo", s, "Poster", a])
        if noSuffix.count <= 80 { return noSuffix }

        let noMondo  = build([t, s, "Poster", a])
        if noMondo.count <= 80 { return noMondo }

        return String(noMondo.prefix(80))
    }

    // Template-based HTML eBay description — no AI, deterministic from item fields.
    func generatedEbayDescription() -> String {
        var lines: [String] = []

        lines.append("<p><strong>Product Details</strong></p>")
        lines.append("<p>")
        lines.append("<strong>Title:</strong> \(title)<br>")
        lines.append("<strong>Artist:</strong> \(artist)<br>")
        if !size.isEmpty      { lines.append("<strong>Dimensions:</strong> \(size) inches<br>") }
        if !edition.isEmpty   { lines.append("<strong>Edition Size:</strong> \(edition)<br>") }
        if !productionTechnique.isEmpty {
            lines.append("<strong>Production Technique:</strong> \(productionTechnique) on gallery-quality paper<br>")
        }
        if !gallery.isEmpty   { lines.append("<strong>Gallery:</strong> \(gallery)<br>") }
        if signed             { lines.append("<strong>Signed:</strong> This piece is signed by the artist<br>") }
        if imperfect {
            lines.append("<strong>Condition:</strong> Item marked as imperfect on the back — please review all photos as the item pictured is the item you will receive<br>")
        } else {
            lines.append("<strong>Condition:</strong> Please review all photos as the item pictured is the item you will receive<br>")
        }
        lines.append("</p>")

        lines.append("<p><strong>About This Print</strong></p>")
        lines.append("<p>")
        let tech       = productionTechnique.isEmpty ? "fine art" : productionTechnique
        let galleryStr = gallery.isEmpty ? "" : " by \(gallery) Gallery"
        lines.append("Authentic \(title) art print by \(artist)\(galleryStr). This \(edition) limited edition piece features professional \(tech) printing on gallery-quality paper. Perfect for collectors of alternative movie posters and fine art prints.")
        lines.append("</p>")

        lines.append("<p><strong>Volume Discounts</strong></p>")
        lines.append("<p>")
        lines.append("Buy multiple prints and save: Buy 2 save 5% | Buy 3 save 10% | Buy 4 save 15%<br>")
        lines.append("<br>")
        lines.append("Browse my store for exclusive limited edition movie posters and rare prints from Mondo, Bottleneck, Vice Press, Mad Duck, Grey Matter, Spoke Art, Coda, Apollo, and Mutant.")
        lines.append("</p>")

        lines.append("<p><strong>Shipping &amp; Packaging</strong></p>")
        lines.append("<p>")
        let shippingText: String
        if size.contains("36")      { shippingText = "Large prints (24x36) ship rolled in acid-free tissue and Kraft paper, secured in a protective 28x3-inch tube." }
        else if size.contains("24") { shippingText = "Medium prints (18x24) ship rolled in acid-free tissue and Kraft paper, secured in a protective 24x3-inch tube." }
        else                        { shippingText = "Smaller prints ship flat between sturdy cardboard within a protective box." }
        lines.append("\(shippingText) All items ship from a smoke-free home with careful handling to ensure perfect condition.")
        lines.append("</p>")

        lines.append("<p><strong>About the Seller</strong></p>")
        lines.append("<p>")
        lines.append("Nearly a decade of experience curating alternative movie posters and fine art prints. All artwork stored in professional flat-file conditions.")
        lines.append("</p>")

        return lines.joined(separator: "\n")
    }
}
