import Foundation
import SwiftUI

// ============================================================================
// SavedViews.swift — SESSION 4
// One-click inventory views. Two kinds:
//   • Built-in views: code predicates for the recurring business questions
//     (live on eBay, not on Shopify, stale, CCP). These can't drift out of
//     sync with data formats the way serialized column filters could.
//   • Custom views: named snapshots of the column-filter dictionary,
//     persisted in UserDefaults (same pattern as ColumnSettings).
// Selecting a view REPLACES the current filters; search composes on top.
// ============================================================================

// MARK: - Built-in Views

enum BuiltinInventoryView: String, CaseIterable, Identifiable {
    case all
    case liveOnEbay
    case notOnShopify
    case stale
    case ccp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:          return "ALL"
        case .liveOnEbay:   return "LIVE ON EBAY"
        case .notOnShopify: return "NOT ON SHOPIFY"
        case .stale:        return "STALE 180+"
        case .ccp:          return "CCP"
        }
    }

    var help: String {
        switch self {
        case .all:          return "Every item in inventory"
        case .liveOnEbay:   return "Items with an active eBay listing"
        case .notOnShopify: return "Sellable items not live on Shopify — filter, Check All Visible, then bulk push"
        case .stale:        return "Items held 180+ days (excludes Sold)"
        case .ccp:          return "Cult Classic Prints — items tagged CCP"
        }
    }

    func matches(_ item: InventoryItem) -> Bool {
        switch self {
        case .all:
            return true
        case .liveOnEbay:
            return item.ebayListingStatus.lowercased() == "active"
        case .notOnShopify:
            return item.status != .sold &&
                   item.status != .theVault &&
                   item.shopifyStatus.uppercased() != "ACTIVE"
        case .stale:
            return item.status != .sold &&
                   item.datePurchased != nil &&
                   item.daysSincePurchase >= 180
        case .ccp:
            return item.tags.uppercased().contains("CCP")
        }
    }
}

// MARK: - Custom Saved Views

struct CustomSavedView: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Column rawValue → selected filter values (the serialized form of the
    /// filters dictionary at save time).
    var filterPayload: [String: [String]]
}

@MainActor
@Observable
final class SavedViewStore {
    static let shared = SavedViewStore()

    private(set) var views: [CustomSavedView] = []
    private let saveKey = "inventory_saved_views_v1"

    init() {
        load()
    }

    /// Snapshot the active column filters under a name. Returns the created
    /// view so the UI can highlight it, or nil if nothing was active.
    @discardableResult
    func add(name: String, filters: [InventoryColumn: ColumnFilter]) -> CustomSavedView? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var payload: [String: [String]] = [:]
        for (col, filter) in filters where filter.isActive {
            payload[col.rawValue] = Array(filter.selectedValues).sorted()
        }
        guard !payload.isEmpty else { return nil }
        let view = CustomSavedView(name: trimmed, filterPayload: payload)
        views.append(view)
        save()
        return view
    }

    func delete(_ id: UUID) {
        views.removeAll { $0.id == id }
        save()
    }

    /// Rehydrate a custom view's payload into live ColumnFilters. Columns
    /// whose raw value no longer exists are silently skipped.
    func filters(for view: CustomSavedView) -> [InventoryColumn: ColumnFilter] {
        var result: [InventoryColumn: ColumnFilter] = [:]
        for (raw, values) in view.filterPayload {
            if let col = InventoryColumn(rawValue: raw), !values.isEmpty {
                result[col] = ColumnFilter(column: col, selectedValues: Set(values))
            }
        }
        return result
    }

    // MARK: Persistence (UserDefaults, mirrors ColumnSettings)

    private func save() {
        guard let data = try? JSONEncoder().encode(views) else { return }
        UserDefaults.standard.set(data, forKey: saveKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let decoded = try? JSONDecoder().decode([CustomSavedView].self, from: data)
        else { return }
        views = decoded
    }
}
