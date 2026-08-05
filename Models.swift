import Foundation
import SwiftUI

// MARK: - Core Inventory Item

struct InventoryItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var sku: String = ""
    var action: String = ""
    var status: ItemStatus = .active
    var isActive: Bool {
        get { action.uppercased() == "Y" }
        set { action = newValue ? "Y" : "" }
    }

    var title: String = ""
    var artist: String = ""
    var size: String = ""
    var edition: String = ""
    var printType: String = ""
    var productionTechnique: String = ""
    var gallery: String = ""
    var franchise: String = ""
    var character: String = ""
    var theme: String = ""
    var condition: String = "New"
    var signed: Bool = false
    var imperfect: Bool = false

    var drawer: String = ""
    var sleeveNumber: String = ""

    var datePurchased: Date? = nil
    var netCost: Double = 0
    var taxAndShipping: Double = 0
    var totalCost: Double = 0

    var dateListed: Date? = nil
    var weight: Double = 0
    var tags: String = ""
    var description: String = ""
    var shopifyDescription: String = ""

    var ebayTitle: String = ""
    var ebayCategoryId: String = ""
    var ebayPrice: Double = 0
    var minBestOffer: Double = 0
    var autoAcceptOffer: Double = 0
    var storeCategory1: String = ""
    var storeCategory2: String = ""
    var paymentProfileName: String = ""
    var returnProfileName: String = ""
    var shippingProfileName: String = ""
    var ebayItemId: String = ""

    var shopifyTitle: String = ""
    var shopifyPrice: Double = 0
    var shopifyStatus: String = ""
    var shopifyHandle: String = ""
    var shopifyAPIUpdates: Date? = nil
    var priceUpdatedAt: Date? = nil   // timestamp of last eBay/Shopify price change
    var ebayListingStatus: String = ""  // "Active", "Ended", "Unlisted" — synced from eBay

    var images: [String] = []

    var igPost: Bool = false
    var igCaption: String = ""
    var igStatus: String = ""
    var listingMarketplace: ListingMarketplace = .none

    // Computed
    var primaryImage: String? { images.first }
    var artistSlug: String { artist.lowercased().replacingOccurrences(of: " ", with: "-") }
    var daysInInventory: Int {
        guard let listed = dateListed else { return 0 }
        return Calendar.current.dateComponents([.day], from: listed, to: Date()).day ?? 0
    }
    var totalCostComputed: Double { netCost + taxAndShipping }
    var estimatedProfit: Double { shopifyPrice - totalCostComputed }
    var margin: Double {
        guard shopifyPrice > 0 else { return 0 }
        return (estimatedProfit / shopifyPrice) * 100
    }

    // Days since purchase — used for aging (more accurate than days listed,
    // captures time spent in Ordered/Processed before listing)
    var daysSincePurchase: Int {
        guard let purchased = datePurchased else { return 0 }
        return Calendar.current.dateComponents([.day], from: purchased, to: Date()).day ?? 0
    }

    // Aging tiers based on days since purchase
    enum AgingTier { case fresh, aging, old, stale }
    var agingTier: AgingTier {
        switch daysSincePurchase {
        case 0..<180:   return .fresh
        case 180..<365: return .aging
        case 365..<730: return .old
        default:        return .stale
        }
    }

    // Suggested sale price: 15% off at 180+ days, 25% off at 365+ days, 30% off at 730+
    var suggestedSalePrice: Double? {
        guard ebayPrice > 0 else { return nil }
        switch agingTier {
        case .fresh:  return nil
        case .aging:  return (ebayPrice * 0.85 * 100).rounded() / 100
        case .old:    return (ebayPrice * 0.75 * 100).rounded() / 100
        case .stale:  return (ebayPrice * 0.70 * 100).rounded() / 100
        }
    }

    // Sort key proxies
    var listingMarketplaceSortKey: String { listingMarketplace.rawValue }
    var signedSortKey: String    { signed ? "1" : "0" }
    var igPostSortKey: String    { igPost  ? "1" : "0" }
    var dateListedSortKey: Double    { dateListed?.timeIntervalSince1970    ?? 0 }
    var datePurchasedSortKey: Double { datePurchased?.timeIntervalSince1970 ?? 0 }
    var daysSincePurchaseSortKey: Int { daysSincePurchase }

    // No-arg init so InventoryItem() still compiles after adding custom Codable init
    init() {}

    // Custom decoder so backups missing new fields still load correctly
    enum CodingKeys: String, CodingKey {
        case id, sku, action, status, title, artist, size, edition, printType
        case productionTechnique, gallery, franchise, character, theme, condition
        case signed, imperfect, drawer, sleeveNumber, datePurchased, netCost
        case taxAndShipping, totalCost, dateListed, weight, tags, description
        case shopifyDescription, ebayTitle, ebayCategoryId, ebayPrice
        case minBestOffer, autoAcceptOffer, storeCategory1, storeCategory2
        case paymentProfileName, returnProfileName, shippingProfileName, ebayItemId
        case shopifyTitle, shopifyPrice, shopifyStatus, shopifyHandle, shopifyAPIUpdates
        case images, igPost, igCaption, igStatus, listingMarketplace, priceUpdatedAt, ebayListingStatus
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                  = try c.decodeIfPresent(UUID.self,               forKey: .id)                  ?? UUID()
        sku                 = try c.decodeIfPresent(String.self,             forKey: .sku)                 ?? ""
        action              = try c.decodeIfPresent(String.self,             forKey: .action)              ?? ""
        status              = try c.decodeIfPresent(ItemStatus.self,         forKey: .status)              ?? .active
        title               = try c.decodeIfPresent(String.self,             forKey: .title)               ?? ""
        artist              = try c.decodeIfPresent(String.self,             forKey: .artist)              ?? ""
        size                = try c.decodeIfPresent(String.self,             forKey: .size)                ?? ""
        edition             = try c.decodeIfPresent(String.self,             forKey: .edition)             ?? ""
        printType           = try c.decodeIfPresent(String.self,             forKey: .printType)           ?? ""
        productionTechnique = try c.decodeIfPresent(String.self,             forKey: .productionTechnique) ?? ""
        gallery             = try c.decodeIfPresent(String.self,             forKey: .gallery)             ?? ""
        franchise           = try c.decodeIfPresent(String.self,             forKey: .franchise)           ?? ""
        character           = try c.decodeIfPresent(String.self,             forKey: .character)           ?? ""
        theme               = try c.decodeIfPresent(String.self,             forKey: .theme)               ?? ""
        condition           = try c.decodeIfPresent(String.self,             forKey: .condition)           ?? "New"
        signed              = try c.decodeIfPresent(Bool.self,               forKey: .signed)              ?? false
        imperfect           = try c.decodeIfPresent(Bool.self,               forKey: .imperfect)           ?? false
        drawer              = try c.decodeIfPresent(String.self,             forKey: .drawer)              ?? ""
        sleeveNumber        = try c.decodeIfPresent(String.self,             forKey: .sleeveNumber)        ?? ""
        netCost             = try c.decodeIfPresent(Double.self,             forKey: .netCost)             ?? 0
        taxAndShipping      = try c.decodeIfPresent(Double.self,             forKey: .taxAndShipping)      ?? 0
        totalCost           = try c.decodeIfPresent(Double.self,             forKey: .totalCost)           ?? 0
        weight              = try c.decodeIfPresent(Double.self,             forKey: .weight)              ?? 0
        tags                = try c.decodeIfPresent(String.self,             forKey: .tags)                ?? ""
        description         = try c.decodeIfPresent(String.self,             forKey: .description)         ?? ""
        shopifyDescription  = try c.decodeIfPresent(String.self,             forKey: .shopifyDescription)  ?? ""
        ebayTitle           = try c.decodeIfPresent(String.self,             forKey: .ebayTitle)           ?? ""
        ebayCategoryId      = try c.decodeIfPresent(String.self,             forKey: .ebayCategoryId)      ?? ""
        ebayPrice           = try c.decodeIfPresent(Double.self,             forKey: .ebayPrice)           ?? 0
        minBestOffer        = try c.decodeIfPresent(Double.self,             forKey: .minBestOffer)        ?? 0
        autoAcceptOffer     = try c.decodeIfPresent(Double.self,             forKey: .autoAcceptOffer)     ?? 0
        storeCategory1      = try c.decodeIfPresent(String.self,             forKey: .storeCategory1)      ?? ""
        storeCategory2      = try c.decodeIfPresent(String.self,             forKey: .storeCategory2)      ?? ""
        paymentProfileName  = try c.decodeIfPresent(String.self,             forKey: .paymentProfileName)  ?? ""
        returnProfileName   = try c.decodeIfPresent(String.self,             forKey: .returnProfileName)   ?? ""
        shippingProfileName = try c.decodeIfPresent(String.self,             forKey: .shippingProfileName) ?? ""
        ebayItemId          = try c.decodeIfPresent(String.self,             forKey: .ebayItemId)          ?? ""
        shopifyTitle        = try c.decodeIfPresent(String.self,             forKey: .shopifyTitle)        ?? ""
        shopifyPrice        = try c.decodeIfPresent(Double.self,             forKey: .shopifyPrice)        ?? 0
        shopifyStatus       = try c.decodeIfPresent(String.self,             forKey: .shopifyStatus)       ?? ""
        shopifyHandle       = try c.decodeIfPresent(String.self,             forKey: .shopifyHandle)       ?? ""
        shopifyAPIUpdates   = try c.decodeIfPresent(Date.self,               forKey: .shopifyAPIUpdates)
        images              = try c.decodeIfPresent([String].self,           forKey: .images)              ?? []
        igPost              = try c.decodeIfPresent(Bool.self,               forKey: .igPost)              ?? false
        igCaption           = try c.decodeIfPresent(String.self,             forKey: .igCaption)           ?? ""
        igStatus            = try c.decodeIfPresent(String.self,             forKey: .igStatus)            ?? ""
        listingMarketplace  = try c.decodeIfPresent(ListingMarketplace.self, forKey: .listingMarketplace)  ?? .none
        priceUpdatedAt      = try c.decodeIfPresent(Date.self,               forKey: .priceUpdatedAt)
        ebayListingStatus   = try c.decodeIfPresent(String.self,             forKey: .ebayListingStatus)   ?? ""
        datePurchased       = try c.decodeIfPresent(Date.self,               forKey: .datePurchased)
        dateListed          = try c.decodeIfPresent(Date.self,               forKey: .dateListed)
    }
}

// MARK: - Sale Record
// Captures a complete snapshot of the item at time of sale,
// matching all columns in the Poster Malone Tracker Sales sheet.

struct SaleRecord: Identifiable, Codable {
    var id: UUID = UUID()

    // Identity
    var sku: String = ""
    var artist: String = ""
    var title: String = ""
    var size: String = ""
    var edition: String = ""
    var printType: String = ""
    var productionTechnique: String = ""
    var gallery: String = ""
    var franchise: String = ""
    var theme: String = ""
    var condition: String = ""
    var signed: Bool = false
    var imperfect: Bool = false
    var tags: String = ""

    // Storage at time of sale
    var drawer: String = ""
    var sleeveNumber: String = ""

    // Acquisition
    var datePurchased: Date? = nil
    var netCost: Double = 0
    var taxAndShipping: Double = 0
    var totalCost: Double = 0
    var weight: Double = 0
    var tubeSize: String = ""

    // Listing details at time of sale
    var dateListed: Date? = nil
    var daysInInventory: Int = 0
    var ebayTitle: String = ""
    var ebayCategoryId: String = ""
    var ebayPrice: Double = 0
    var shopifyPrice: Double = 0
    var shopifyStatus: String = ""
    var paymentProfileName: String = ""
    var returnProfileName: String = ""
    var shippingProfileName: String = ""

    // Image URLs (lh3.googleusercontent.com links — persist after sale)
    var images: [String] = []

    // Sale financials
    var dateSold: Date = Date()
    var marketplace: Marketplace = .ebay
    var grossSales: Double = 0
    var taxes: Double = 0
    var feesAndShipping: Double = 0

    // Calculated fields (auto-computed, stored for display)
    var netSales: Double = 0       // Gross - Taxes - Fees+Shipping
    var profit: Double = 0         // Net Sales - Total Cost
    var profitLossPercent: Double = 0  // (Profit / Total Cost) * 100
    var daysToSell: Int = 0        // Date Sold - Date Purchased
}

// MARK: - Expense Record

struct ExpenseRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date = Date()
    var category: ExpenseCategory = .shippingSupplies
    var description: String = ""
    var amount: Double = 0
    var receipt: String = ""
}

// MARK: - Enums

enum ItemStatus: String, Codable, CaseIterable {
    case auction   = "Auction"
    case draft     = "Draft"
    case listed    = "Listed"
    case ordered   = "Ordered"
    case pending   = "Pending"
    case processed = "Processed"
    case research  = "Research"
    case theVault  = "The Vault"
    case active    = "Active"
    case sold      = "Sold"
    case onHold    = "On Hold"
}

enum ListingMarketplace: String, Codable, CaseIterable {
    case ebay        = "eBay"
    case shopify     = "Shopify"
    case both        = "eBay+Shopify"
    case none        = "None"
}

enum Marketplace: String, Codable, CaseIterable {
    case ebay      = "eBay"
    case shopify   = "Shopify"
    case instagram = "Instagram"
    case facebook  = "Facebook"
    case inPerson  = "In Person"
    case other     = "Other"
}

enum ExpenseCategory: String, Codable, CaseIterable {
    case shippingSupplies = "Shipping Supplies"
    case platformFees     = "Platform Fees"
    case acquisition      = "Acquisition"
    case storage          = "Storage"
    case marketing        = "Marketing"
    case other            = "Other"
}

// MARK: - Paper Trail

enum PaperTrailAction: String, Codable, CaseIterable {
    case delistedEbay      = "Delisted - eBay"
    case relistedEbay      = "Relisted - eBay"
    case listedEbay        = "Listed - eBay"
    case pushedShopify     = "Pushed - Shopify"
    case delistedShopify   = "Delisted - Shopify"
    case postedInstagram   = "Posted - Instagram"

    var color: Color {
        switch self {
        case .delistedEbay:    return Color.red
        case .relistedEbay:    return Color.orange
        case .listedEbay:      return Color.green
        case .pushedShopify:   return Color.blue
        case .delistedShopify: return Color.purple
        case .postedInstagram: return Color.pink
        }
    }

    var icon: String {
        switch self {
        case .delistedEbay:    return "xmark.circle"
        case .relistedEbay:    return "arrow.clockwise.circle"
        case .listedEbay:      return "checkmark.circle"
        case .pushedShopify:   return "arrow.up.circle"
        case .delistedShopify: return "minus.circle"
        case .postedInstagram: return "camera.circle"
        }
    }
}

struct PaperTrailEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date = Date()
    var action: PaperTrailAction = .listedEbay
    var sku: String = ""
    var artist: String = ""
    var title: String = ""
    var drawer: String = ""
    var sleeveNumber: String = ""
    var daysOwned: Int = 0
    var price: Double = 0

    init() {}

    init(action: PaperTrailAction, item: InventoryItem) {
        self.id           = UUID()
        self.date         = Date()
        self.action       = action
        self.sku          = item.sku
        self.artist       = item.artist
        self.title        = item.title
        self.drawer       = item.drawer
        self.sleeveNumber = item.sleeveNumber
        self.daysOwned    = item.daysSincePurchase
        self.price        = item.ebayPrice > 0 ? item.ebayPrice : item.shopifyPrice
    }
}

// MARK: - Instagram Queue

enum IGQueueStatus: String, Codable, CaseIterable {
    case pending  = "Pending"
    case posted   = "Posted"
    case failed   = "Failed"
    case skipped  = "Skipped"

    var color: Color {
        switch self {
        case .pending:  return Color.orange
        case .posted:   return Color.green
        case .failed:   return Color.red
        case .skipped:  return Color.secondary
        }
    }
}

struct IGScheduledPost: Identifiable, Codable {
    var id: UUID = UUID()
    var sku: String = ""
    var artist: String = ""
    var title: String = ""
    var size: String = ""
    var scheduledDate: Date = Date()
    var customNote: String = ""
    var status: IGQueueStatus = .pending
    var postedAt: Date? = nil
    var errorMessage: String? = nil
    var images: [String] = []
    var igCaption: String = ""

    var displayTitle: String {
        [artist, title].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    var isDue: Bool {
        status == .pending && scheduledDate <= Date()
    }
}

enum AppSection: String, CaseIterable {
    case inventory             = "Inventory"
    case sales                 = "Sales"
    case paperTrail            = "Paper Trail"
    case analytics             = "Analytics"
    case recommendations       = "Recommendations"
    case instagramAutomation   = "Instagram"
    case admin                 = "Admin"

    var icon: String {
        switch self {
        case .inventory:           return "archivebox.fill"
        case .sales:               return "dollarsign.circle.fill"
        case .paperTrail:          return "doc.text.magnifyingglass"
        case .analytics:           return "chart.bar.fill"
        case .recommendations:     return "sparkles"
        case .instagramAutomation: return "camera.fill"
        case .admin:               return "gearshape.fill"
        }
    }
}
