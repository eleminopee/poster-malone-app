import SwiftUI
import UniformTypeIdentifiers

// ============================================================================
// PaperTrailView.swift — the ledger
// Stats become glow pills, filter chips take the PM treatment in each
// action's semantic color, table goes dark-striped. CSV export, search,
// sort, and the 6 action colors are unchanged.
// ============================================================================

struct PaperTrailView: View {
    @Environment(InventoryStore.self) var store
    @State private var searchText = ""
    @State private var selectedAction: PaperTrailAction? = nil
    @State private var sortOrder = [KeyPathComparator(\PaperTrailEntry.date, order: .reverse)]
    @State private var isExporting = false

    var filtered: [PaperTrailEntry] {
        var result = store.paperTrail
        if let action = selectedAction {
            result = result.filter { $0.action == action }
        }
        if !searchText.isEmpty {
            let q = searchText
            result = result.filter {
                $0.sku.localizedCaseInsensitiveContains(q) ||
                $0.artist.localizedCaseInsensitiveContains(q) ||
                $0.title.localizedCaseInsensitiveContains(q)
            }
        }
        return result.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(PM.surface)
            PMNeonDivider(color: PM.pink).opacity(0.5)
            filterChips
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider().overlay(PM.borderSubtle)
            paperTrailTable
        }
        .pmScreen()
        .navigationTitle("Paper Trail")
        .searchable(text: $searchText, prompt: "Search SKU, artist, title...")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { exportCSV() } label: {
                    Label("Export CSV", systemImage: "arrow.down.doc")
                }
                .disabled(store.paperTrail.isEmpty)
            }
        }
        .overlay {
            if store.paperTrail.isEmpty {
                ContentUnavailableView {
                    Label("No Paper Trail Yet", systemImage: "doc.text.magnifyingglass")
                        .font(.pmDisplay(size: 22))
                        .foregroundStyle(PM.textSecondary)
                } description: {
                    Text("Listing, relisting, Shopify pushes, and Instagram posts appear here.")
                        .font(.pmBody(size: 13))
                        .foregroundStyle(PM.textTertiary)
                }
            }
        }
    }

    // MARK: - Table (columns split into a separate var to avoid compiler timeout)

    private var paperTrailTable: some View {
        Table(filtered, sortOrder: $sortOrder) {
            TableColumn("Date", value: \.date) { e in
                Text(e.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .width(140)
            TableColumn("Action", value: \.action.rawValue) { e in
                Label(e.action.rawValue, systemImage: e.action.icon)
                    .font(.caption)
                    .foregroundStyle(e.action.color)
                    .labelStyle(.titleAndIcon)
            }
            .width(160)
            TableColumn("SKU", value: \.sku) { e in
                Text(e.sku).font(.caption).fontWeight(.medium)
            }
            .width(90)
            TableColumn("Artist", value: \.artist) { e in
                Text(e.artist).font(.caption)
            }
            .width(150)
            TableColumn("Title", value: \.title) { e in
                Text(e.title).font(.caption).lineLimit(1)
            }
            TableColumn("Drawer", value: \.drawer) { e in
                Text(e.drawer).font(.caption).foregroundStyle(.secondary)
            }
            .width(70)
            TableColumn("Price", value: \.price) { e in
                Text(e.price > 0 ? e.price.asCurrency : "—")
                    .font(.caption)
                    .foregroundStyle(e.price > 0 ? PM.cyan : PM.textTertiary)
                    .monospacedDigit()
            }
            .width(80)
            TableColumn("Days", value: \.daysOwned) { e in
                Text(e.daysOwned > 0 ? "\(e.daysOwned)d" : "—")
                    .font(.caption).foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(60)
        }
        .scrollContentBackground(.hidden)
        .alternatingRowBackgrounds(.enabled)
    }

    // MARK: - Stats Bar

    private var statsBar: some View {
        let total     = store.paperTrail.count
        let listed    = store.paperTrail.filter { $0.action == .listedEbay }.count
        let relisted  = store.paperTrail.filter { $0.action == .relistedEbay }.count
        let shopify   = store.paperTrail.filter { $0.action == .pushedShopify }.count
        let instagram = store.paperTrail.filter { $0.action == .postedInstagram }.count
        return HStack(spacing: 12) {
            statPill("Total",     "\(total)",     PM.cyan)
            statPill("Listed",    "\(listed)",    Color.green)
            statPill("Relisted",  "\(relisted)",  Color.orange)
            statPill("Shopify",   "\(shopify)",   Color.blue)
            statPill("Instagram", "\(instagram)", PM.pink)
            Spacer()
            Text("\(filtered.count) shown")
                .font(.pmBody(size: 12))
                .foregroundStyle(PM.textTertiary)
        }
    }

    private func statPill(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.pmDisplay(size: 15))
                .foregroundStyle(color)
                .monospacedDigit()
                .pmGlow(color, radius: 4, opacity: 0.35)
            Text(label)
                .font(.pmBody(size: 11, weight: .medium))
                .foregroundStyle(PM.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PM.card, in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1))
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("All", nil)
                ForEach(PaperTrailAction.allCases, id: \.self) { action in
                    filterChip(action.rawValue, action, color: action.color)
                }
            }
        }
    }

    private func filterChip(_ label: String, _ action: PaperTrailAction?, color: Color = PM.pink) -> some View {
        let isSelected = selectedAction == action
        return Button { selectedAction = action } label: {
            Text(label)
                .font(.pmBody(size: 12, weight: isSelected ? .semibold : .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? color.opacity(0.15) : PM.card, in: Capsule())
                .foregroundStyle(isSelected ? color : PM.textSecondary)
                .overlay(Capsule().strokeBorder(isSelected ? color.opacity(0.5) : PM.borderSubtle, lineWidth: 1))
                .pmGlow(color, radius: isSelected ? 5 : 0, opacity: isSelected ? 0.30 : 0)
        }
        .buttonStyle(.plain)
    }

    // MARK: - CSV Export

    private func exportCSV() {
        var lines = ["Date,Action,SKU,Artist,Title,Drawer,Price,Days Owned"]
        for e in filtered {
            let dateStr = e.date.formatted(date: .abbreviated, time: .shortened)
            let price   = e.price > 0 ? String(format: "%.2f", e.price) : ""
            let days    = e.daysOwned > 0 ? "\(e.daysOwned)" : ""
            let row = [dateStr, e.action.rawValue, e.sku, e.artist, e.title, e.drawer, price, days]
                .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                .joined(separator: ",")
            lines.append(row)
        }
        let csv = lines.joined(separator: "\n")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = docs.appendingPathComponent("PosterMalone Backups")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HHmm"
        let file = dir.appendingPathComponent("paper_trail_\(fmt.string(from: Date())).csv")
        try? csv.write(to: file, atomically: true, encoding: .utf8)
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}
