import Foundation
import SwiftUI

enum InventoryColumn: String, CaseIterable, Codable, Identifiable {
    case action          = "✓"
    case photo           = "Photo"
    case sku             = "SKU"
    case artist          = "Artist"
    case title           = "Title"
    case size            = "Size"
    case gallery         = "Gallery"
    case edition         = "Edition"
    case printType       = "Print Type"
    case condition       = "Condition"
    case signed          = "Signed"
    case drawer          = "Drawer"
    case sleeve          = "Sleeve #"
    case ebayPrice       = "eBay Price"
    case shopifyPrice    = "Shopify Price"
    case netCost         = "Cost"
    case daysOwned      = "Days Owned"
    case dateListed      = "Date Listed"
    case datePurchased   = "Date Purchased"
    case franchise       = "Franchise"
    case theme           = "Theme"
    case status          = "Status"
    case marketplace     = "Marketplace"
    case ebayStatus      = "eBay Status"
    case shopifyStatus   = "Shopify Status"
    case igPost          = "IG Post"

    var id: String { rawValue }

    var defaultWidth: CGFloat {
        switch self {
        case .action:          return 44
        case .photo:           return 56
        case .sku:             return 100
        case .artist:          return 150
        case .title:           return 200
        case .size:            return 80
        case .gallery:         return 110
        case .edition:         return 90
        case .printType:       return 110
        case .condition:       return 80
        case .signed:          return 60
        case .drawer:          return 70
        case .sleeve:          return 70
        case .ebayPrice:       return 90
        case .shopifyPrice:    return 90
        case .netCost:         return 80
        case .daysOwned:      return 80
        case .dateListed:      return 100
        case .datePurchased:   return 110
        case .franchise:       return 120
        case .theme:           return 100
        case .status:          return 80
        case .marketplace:     return 100
        case .ebayStatus:      return 90
        case .shopifyStatus:   return 100
        case .igPost:          return 60
        }
    }
}

struct ColumnConfig: Codable, Identifiable {
    var id: InventoryColumn
    var isVisible: Bool
    var order: Int
}

@Observable
class ColumnSettings {
    var configs: [ColumnConfig] = []

    private let saveKey = "column_settings_v1"

    init() {
        load()
        if configs.isEmpty { applyDefaults() }
        ensureAllColumnsPresent()
    }

    var visibleColumns: [InventoryColumn] {
        configs
            .filter { $0.isVisible }
            .sorted { $0.order < $1.order }
            .map { $0.id }
    }

    var allOrdered: [ColumnConfig] {
        configs.sorted { $0.order < $1.order }
    }

    func toggle(_ column: InventoryColumn) {
        guard let i = configs.firstIndex(where: { $0.id == column }) else { return }
        let currentlyVisible = configs.filter { $0.isVisible }.count
        if configs[i].isVisible && currentlyVisible <= 1 { return }
        configs[i].isVisible.toggle()
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        var ordered = allOrdered
        ordered.move(fromOffsets: source, toOffset: destination)
        for (i, var config) in ordered.enumerated() {
            config.order = i
            if let idx = configs.firstIndex(where: { $0.id == config.id }) {
                configs[idx] = config
            }
        }
        save()
    }

    private func applyDefaults() {
        let defaultVisible: Set<InventoryColumn> = [
            .action, .photo, .sku, .artist, .title, .size,
            .gallery, .drawer, .sleeve, .shopifyPrice, .daysOwned, .marketplace
        ]
        configs = InventoryColumn.allCases.enumerated().map { i, col in
            ColumnConfig(id: col, isVisible: defaultVisible.contains(col), order: i)
        }
        save()
    }

    // Make sure any new columns added in code get added to saved configs
    private func ensureAllColumnsPresent() {
        let existing = Set(configs.map { $0.id })
        var maxOrder = configs.map { $0.order }.max() ?? 0
        for col in InventoryColumn.allCases {
            if !existing.contains(col) {
                maxOrder += 1
                configs.append(ColumnConfig(id: col, isVisible: false, order: maxOrder))
            }
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([ColumnConfig].self, from: data)
        else { return }
        configs = decoded
    }
}
