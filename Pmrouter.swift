import SwiftUI

// ============================================================================
// PMRouter.swift — SESSION 5
// Lightweight navigation + deep-link state shared via @Environment.
//
// Why this exists: the "Today" cockpit needs to switch sections AND tell the
// destination what to show ("open Inventory filtered to Needs Listing",
// "open Sales filtered to missing financials"). AppSection lives in
// Models.swift (a no-touch file) and can't gain a `today` case, so the router
// owns an `isShowingToday` flag layered above AppSection. Destinations read a
// one-shot `pendingInventoryFilter` / `pendingSalesFilter` on appear, then
// clear it — so the intent fires once and normal navigation is unaffected.
// ============================================================================

/// One-shot filter intent handed to InventoryView when navigated from Today.
enum InventoryIntent: Equatable {
    case needsListing
    case noDescription
    case longTitle
    case oldest
    case notOnShopify   // #1 — eBay→Shopify migration gap
    case needsPhotos    // #5 — sellable items with no images
    case needsShopifyCopy   // missing Shopify title or description
    case builtin(BuiltinInventoryView)
}

/// One-shot filter intent handed to SalesView when navigated from Today.
enum SalesIntent: Equatable {
    case missingFinancials
}

@MainActor
@Observable
final class PMRouter {
    /// When true, the detail pane shows the Today cockpit instead of an
    /// AppSection. Set false the moment the user picks any section.
    var isShowingToday: Bool = true

    /// When true, the detail pane shows the Expenses & Tax view (Tier 2).
    /// Layered above AppSection like Today, for the same Models.swift reason.
    var isShowingExpenses: Bool = false

    /// When true, the detail pane shows the Trash (soft-deleted items).
    var isShowingTrash: Bool = false

    /// When true, the detail pane shows the Comics module.
    var isShowingComics: Bool = false

    // MARK: Toast (transient global feedback — Drive moves, restores, etc.)
    struct Toast: Equatable {
        enum Kind { case success, warning, error }
        let kind: Kind
        let message: String
    }
    /// Current toast; the app-level overlay shows it and auto-dismisses.
    var toast: Toast? = nil

    func showToast(_ kind: Toast.Kind, _ message: String) {
        toast = Toast(kind: kind, message: message)
    }

    /// The AppSection shown when not on Today.
    var section: AppSection = .inventory

    /// One-shot intents consumed (and cleared) by the destination on appear.
    var pendingInventoryFilter: InventoryIntent? = nil
    var pendingSalesFilter: SalesIntent? = nil

    /// Navigate to Inventory carrying a filter intent.
    func openInventory(_ intent: InventoryIntent) {
        pendingInventoryFilter = intent
        section = .inventory
        isShowingToday = false
        isShowingExpenses = false
        isShowingTrash = false
        isShowingComics = false
    }

    /// Navigate to Sales carrying a filter intent.
    func openSales(_ intent: SalesIntent) {
        pendingSalesFilter = intent
        section = .sales
        isShowingToday = false
        isShowingExpenses = false
        isShowingTrash = false
        isShowingComics = false
    }

    /// Plain section navigation (sidebar taps).
    func go(_ section: AppSection) {
        self.section = section
        isShowingToday = false
        isShowingExpenses = false
        isShowingTrash = false
        isShowingComics = false
    }

    func goToday() {
        isShowingToday = true
        isShowingExpenses = false
        isShowingTrash = false
        isShowingComics = false
    }

    func goExpenses() {
        isShowingExpenses = true
        isShowingToday = false
        isShowingTrash = false
        isShowingComics = false
    }

    func goTrash() {
        isShowingTrash = true
        isShowingToday = false
        isShowingExpenses = false
        isShowingComics = false
    }

    func goComics() {
        isShowingComics = true
        isShowingToday = false
        isShowingExpenses = false
        isShowingTrash = false
    }
}
