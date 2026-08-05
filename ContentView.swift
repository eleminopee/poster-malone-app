import SwiftUI

// ============================================================================
// ContentView.swift — root router
// Visual change only: the whole window inherits the PM canvas (base + grain +
// forced dark) and a pink accent tint. Routing is unchanged.
// ============================================================================

struct ContentView: View {
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @Environment(ColumnSettings.self) var columnSettings
    @Environment(PMRouter.self) var router

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if router.isShowingToday {
                TodayView()
            } else if router.isShowingExpenses {
                ExpensesView()
            } else if router.isShowingTrash {
                TrashView()
            } else if router.isShowingComics {
                ComicsView()
                    .environment(ComicsStore.shared)
            } else {
                switch router.section {
                case .inventory:           InventoryView()
                case .sales:               SalesView()
                case .paperTrail:          PaperTrailView()
                case .analytics:           AnalyticsView()
                case .recommendations:     RecommendationsView()
                case .instagramAutomation: InstagramAutomationView()
                case .admin:               AdminView()
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(PM.pink)
        .pmScreen()
        .overlay { PMToastOverlay() }
    }
}
