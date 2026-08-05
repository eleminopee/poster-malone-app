import SwiftUI

// ============================================================================
// ComicsView.swift — the Comics module UI
// One sidebar destination, four tabs inside: Inventory, Sales, Personal
// Collection, Analytics. Inventory and Collection share the same list view
// (identical structure, different shelf), per the workflow requirement.
// ============================================================================

struct ComicsView: View {
    @Environment(ComicsStore.self) var comicsStore

    enum ComicsTab: String, CaseIterable, Identifiable {
        case inventory  = "Inventory"
        case sales      = "Sales"
        case collection = "Personal Collection"
        case analytics  = "Analytics"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .inventory:  return "books.vertical.fill"
            case .sales:      return "dollarsign.circle.fill"
            case .collection: return "heart.fill"
            case .analytics:  return "chart.bar.fill"
            }
        }
    }

    @State private var tab: ComicsTab = .inventory

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — same cyan-underline pattern as Analytics
            HStack(spacing: 0) {
                ForEach(ComicsTab.allCases) { t in
                    Button {
                        tab = t
                    } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Image(systemName: t.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(t.rawValue)
                                    .font(.pmBody(size: 14, weight: tab == t ? .semibold : .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .foregroundStyle(tab == t ? PM.cyan : PM.textSecondary)
                            Rectangle()
                                .fill(tab == t ? PM.cyan : Color.clear)
                                .frame(height: 2)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .background(PM.surface)

            Divider().overlay(PM.borderSubtle)

            switch tab {
            case .inventory:  ComicShelfTab(shelf: .inventory)
            case .sales:      ComicsSalesTab()
            case .collection: ComicShelfTab(shelf: .collection)
            case .analytics:  ComicsAnalyticsTab()
            }
        }
        .pmScreen()
        .navigationTitle("Comics")
    }
}

// MARK: - Shelf Tab (Inventory & Personal Collection share this)

struct ComicShelfTab: View {
    let shelf: ComicShelf
    @Environment(ComicsStore.self) var comicsStore
    @Environment(CredentialsManager.self) var credentials
    @Environment(PMRouter.self) var router

    @State private var searchText = ""
    @State private var checkedIDs: Set<UUID> = []
    @State private var showingAdd = false
    @State private var editingComic: ComicRecord? = nil
    @State private var markingSold: ComicRecord? = nil
    @State private var showingExport = false

    private var shelfComics: [ComicRecord] {
        let base = comicsStore.comics.filter { $0.shelf == shelf }
        let sorted = base.sorted { $0.dateAdded > $1.dateAdded }
        guard !searchText.isEmpty else { return sorted }
        let q = searchText.lowercased()
        return sorted.filter {
            $0.title.lowercased().contains(q) ||
            $0.artist.lowercased().contains(q) ||
            $0.publisher.lowercased().contains(q) ||
            $0.isbn.contains(q)
        }
    }

    private var checkedComics: [ComicRecord] {
        shelfComics.filter { checkedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: stats + search + add
            HStack(spacing: 14) {
                if shelf == .inventory {
                    TodayStat(label: "Books", value: "\(comicsStore.inventory.count)", tint: PM.cyan)
                    TodayStat(label: "Cost Basis", value: comicsStore.inventoryCostBasis.asCurrency, tint: PM.cyan)
                    TodayStat(label: "Asking Value", value: comicsStore.inventoryAskingValue.asCurrency, tint: PM.pink)
                } else {
                    TodayStat(label: "In Collection", value: "\(comicsStore.collection.count)", tint: PM.pink)
                    TodayStat(label: "Invested",
                              value: comicsStore.collection.reduce(0) { $0 + $1.pricePaid }.asCurrency,
                              tint: PM.cyan)
                }

                Spacer()

                TextField("Search title, artist, publisher, ISBN…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.pmBody(size: 13))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(width: 260)
                    .background(PM.base, in: RoundedRectangle(cornerRadius: PM.Radius.sm))
                    .overlay(RoundedRectangle(cornerRadius: PM.Radius.sm).strokeBorder(PM.borderStrong, lineWidth: 1))

                Button {
                    showingAdd = true
                } label: {
                    Label("Add Book", systemImage: "plus")
                }
                .buttonStyle(PMPrimaryButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().overlay(PM.borderSubtle)

            if shelfComics.isEmpty {
                ContentUnavailableView {
                    Label(shelf == .inventory ? "No Books in Inventory" : "No Books in Collection",
                          systemImage: "books.vertical")
                        .font(.pmDisplay(size: 20))
                        .foregroundStyle(PM.textSecondary)
                } description: {
                    Text(shelf == .inventory
                         ? "Add graphic novels and omnibuses — enter an ISBN and details fill in automatically."
                         : "Books you're keeping. Same tracking as inventory: photos, details, purchase info.")
                        .font(.pmBody(size: 13))
                        .foregroundStyle(PM.textTertiary)
                } actions: {
                    Button("Add Book") { showingAdd = true }
                        .buttonStyle(PMPrimaryButtonStyle())
                        .frame(maxWidth: 160)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shelfComics) { comic in
                            ComicRow(
                                comic: comic,
                                isChecked: checkedIDs.contains(comic.id),
                                onToggleCheck: {
                                    if checkedIDs.contains(comic.id) { checkedIDs.remove(comic.id) }
                                    else { checkedIDs.insert(comic.id) }
                                }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { editingComic = comic }
                            .contextMenu {
                                Button("Edit") { editingComic = comic }
                                if shelf == .inventory {
                                    Button("Mark as Sold") { markingSold = comic }
                                    Button("Move to Personal Collection") {
                                        comicsStore.moveToShelf(comic, shelf: .collection)
                                        router.showToast(.success, "Moved \"\(comic.title)\" to Personal Collection")
                                    }
                                } else {
                                    Button("Move to Inventory") {
                                        comicsStore.moveToShelf(comic, shelf: .inventory)
                                        router.showToast(.success, "Moved \"\(comic.title)\" to Inventory")
                                    }
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    comicsStore.delete(comic)
                                    router.showToast(.warning, "Deleted \"\(comic.title)\"")
                                }
                            }
                            Rectangle().fill(PM.borderSubtle).frame(height: 1)
                        }
                    }
                }
            }
        }
        // Bulk action bar — inventory only (export/list are selling actions)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shelf == .inventory && !checkedIDs.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PM.pink)
                    Text("\(checkedIDs.count) CHECKED")
                        .font(.pmDisplay(size: 14))
                        .foregroundStyle(PM.textPrimary)
                        .tracking(1.0)

                    Spacer()

                    Button {
                        showingExport = true
                    } label: {
                        Label("Export eBay CSV", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(PMTintButtonStyle(tint: .orange))
                    .help("Download a File Exchange CSV with scheduled listing times — same workflow as posters")

                    Button {
                        markCheckedListed()
                    } label: {
                        Label("Mark Listed", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(PMTintButtonStyle(tint: .green))
                    .help("Stamp checked books as Listed with today's date")

                    Button {
                        checkedIDs.removeAll()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(PMGhostButtonStyle())
                    .help("Uncheck all")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(PM.raised)
                .overlay(Rectangle().fill(PM.borderStrong).frame(height: 1), alignment: .top)
            }
        }
        .sheet(isPresented: $showingAdd) {
            ComicEditSheet(comic: {
                var c = ComicRecord()
                c.shelf = shelf
                return c
            }(), isNew: true)
        }
        .sheet(item: $editingComic) { comic in
            ComicEditSheet(comic: comic, isNew: false)
        }
        .sheet(item: $markingSold) { comic in
            ComicMarkSoldSheet(comic: comic)
        }
        .sheet(isPresented: $showingExport) {
            ComicsExportSheet(comics: checkedComics) {
                checkedIDs.removeAll()
            }
        }
    }

    private func markCheckedListed() {
        for var comic in checkedComics {
            comic.status = .listed
            comic.dateListed = Date()
            comicsStore.update(comic)
        }
        router.showToast(.success, "Marked \(checkedComics.count) book\(checkedComics.count == 1 ? "" : "s") as Listed")
        checkedIDs.removeAll()
    }
}

// MARK: - Comic Row

struct ComicRow: View {
    let comic: ComicRecord
    let isChecked: Bool
    let onToggleCheck: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggleCheck) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isChecked ? PM.pink : PM.textTertiary)
            }
            .buttonStyle(.plain)

            ThumbnailView(url: comic.images.first, flat: true)
                .frame(width: 38, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(comic.title)
                    .font(.pmBody(size: 14, weight: .medium))
                    .foregroundStyle(PM.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !comic.artist.isEmpty {
                        Text(comic.artist)
                            .font(.pmBody(size: 12))
                            .foregroundStyle(PM.textSecondary)
                            .lineLimit(1)
                    }
                    if !comic.publisher.isEmpty {
                        Text("· \(comic.publisher)")
                            .font(.pmBody(size: 12))
                            .foregroundStyle(PM.textTertiary)
                            .lineLimit(1)
                    }
                    if !comic.year.isEmpty {
                        Text("· \(comic.year)")
                            .font(.pmBody(size: 12))
                            .foregroundStyle(PM.textTertiary)
                    }
                }
            }

            Spacer()

            PMGlowBadge(text: comic.format.rawValue, color: PM.cyan, flat: true)

            if comic.shelf == .inventory {
                PMGlowBadge(text: comic.status.rawValue, color: comic.status.color, flat: true)
            }

            VStack(alignment: .trailing, spacing: 1) {
                if comic.askingPrice > 0 {
                    Text(comic.askingPrice.asCurrency)
                        .font(.pmDisplay(size: 15))
                        .foregroundStyle(PM.textPrimary)
                        .monospacedDigit()
                }
                if comic.pricePaid > 0 {
                    Text("paid \(comic.pricePaid.asCurrency)")
                        .font(.pmBody(size: 10))
                        .foregroundStyle(PM.textTertiary)
                        .monospacedDigit()
                }
            }
            .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Sales Tab

struct ComicsSalesTab: View {
    @Environment(ComicsStore.self) var comicsStore
    @Environment(PMRouter.self) var router

    @State private var editingSale: ComicSaleRecord? = nil

    private var needFinancials: Int {
        comicsStore.sales.lazy.filter { $0.soldPrice == 0 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                TodayStat(label: "Sold", value: "\(comicsStore.sales.count)", tint: PM.cyan)
                TodayStat(label: "Gross", value: comicsStore.totalSalesGross.asCurrency, tint: PM.cyan)
                TodayStat(label: "Profit", value: comicsStore.totalSalesProfit.asCurrency,
                          tint: comicsStore.totalSalesProfit >= 0 ? .green : .red)
                if needFinancials > 0 {
                    TodayStat(label: "Need Financials", value: "\(needFinancials)", tint: .orange)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider().overlay(PM.borderSubtle)

            if comicsStore.sales.isEmpty {
                ContentUnavailableView {
                    Label("No Comic Sales Yet", systemImage: "dollarsign.circle")
                        .font(.pmDisplay(size: 20))
                        .foregroundStyle(PM.textSecondary)
                } description: {
                    Text("Mark a book sold from Inventory and it lands here — enter the sale price and fees, and Analytics updates.")
                        .font(.pmBody(size: 13))
                        .foregroundStyle(PM.textTertiary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(comicsStore.sales) { sale in
                            ComicSaleRow(sale: sale)
                                .contentShape(Rectangle())
                                .onTapGesture { editingSale = sale }
                                .contextMenu {
                                    Button("Edit Sale") { editingSale = sale }
                                    Button("Return to Inventory") {
                                        comicsStore.returnToInventory(sale)
                                        router.showToast(.success, "\"\(sale.comic.title)\" returned to Inventory")
                                    }
                                    Divider()
                                    Button("Delete Sale Record", role: .destructive) {
                                        comicsStore.deleteSale(sale)
                                    }
                                }
                            Rectangle().fill(PM.borderSubtle).frame(height: 1)
                        }
                    }
                }
            }
        }
        .sheet(item: $editingSale) { sale in
            ComicSaleEditSheet(sale: sale)
        }
    }
}

struct ComicSaleRow: View {
    let sale: ComicSaleRecord

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: sale.comic.images.first, flat: true)
                .frame(width: 38, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(sale.comic.title)
                    .font(.pmBody(size: 14, weight: .medium))
                    .foregroundStyle(PM.textPrimary)
                    .lineLimit(1)
                Text("\(sale.comic.format.rawValue) · sold \(sale.dateSold.shortDate)")
                    .font(.pmBody(size: 11))
                    .foregroundStyle(PM.textTertiary)
            }

            Spacer()

            if sale.soldPrice == 0 {
                PMGlowBadge(text: "Needs Financials", color: .orange, flat: true)
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(sale.soldPrice.asCurrency)
                        .font(.pmDisplay(size: 15))
                        .foregroundStyle(PM.textPrimary)
                        .monospacedDigit()
                    Text("profit \(sale.profit.asCurrency)")
                        .font(.pmBody(size: 10))
                        .foregroundStyle(sale.profit >= 0 ? .green : .red)
                        .monospacedDigit()
                }
                .frame(width: 100, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Analytics Tab

struct ComicsAnalyticsTab: View {
    @Environment(ComicsStore.self) var comicsStore

    private var avgMargin: Double {
        let withPrice = comicsStore.sales.filter { $0.soldPrice > 0 && $0.comic.pricePaid > 0 }
        guard !withPrice.isEmpty else { return 0 }
        let total = withPrice.reduce(0.0) { $0 + ($1.profit / $1.comic.pricePaid * 100) }
        return total / Double(withPrice.count)
    }

    private var byPublisher: [(String, Int, Double)] {
        var map: [String: (count: Int, profit: Double)] = [:]
        for s in comicsStore.sales {
            let key = s.comic.publisher.isEmpty ? "Unknown" : s.comic.publisher
            map[key, default: (0, 0)].count += 1
            map[key]!.profit += s.profit
        }
        return map.map { ($0.key, $0.value.count, $0.value.profit) }
            .sorted { $0.2 > $1.2 }
    }

    private var byFormat: [(String, Int, Double)] {
        var map: [String: (count: Int, profit: Double)] = [:]
        for s in comicsStore.sales {
            map[s.comic.format.rawValue, default: (0, 0)].count += 1
            map[s.comic.format.rawValue]!.profit += s.profit
        }
        return map.map { ($0.key, $0.value.count, $0.value.profit) }
            .sorted { $0.2 > $1.2 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PM.Space.xl) {
                Text("COMICS OVERVIEW")
                    .font(.pmBody(size: 11, weight: .semibold))
                    .foregroundStyle(PM.textTertiary)
                    .tracking(1.5)

                HStack(spacing: 14) {
                    TodayStat(label: "In Inventory", value: "\(comicsStore.inventory.count)", tint: PM.cyan)
                    TodayStat(label: "Cost Basis", value: comicsStore.inventoryCostBasis.asCurrency, tint: PM.cyan)
                    TodayStat(label: "Total Sold", value: "\(comicsStore.sales.count)", tint: PM.cyan)
                    TodayStat(label: "Gross Sales", value: comicsStore.totalSalesGross.asCurrency, tint: PM.cyan)
                    TodayStat(label: "Total Profit", value: comicsStore.totalSalesProfit.asCurrency,
                              tint: comicsStore.totalSalesProfit >= 0 ? .green : .red)
                    TodayStat(label: "Avg Margin",
                              value: String(format: "%.0f%%", avgMargin),
                              tint: avgMargin >= 0 ? .green : .red)
                }

                if !byPublisher.isEmpty {
                    breakdown(title: "PROFIT BY PUBLISHER", rows: byPublisher)
                }
                if !byFormat.isEmpty {
                    breakdown(title: "PROFIT BY FORMAT", rows: byFormat)
                }

                if comicsStore.sales.isEmpty {
                    Text("Sell a few books and profit breakdowns by publisher and format appear here.")
                        .font(.pmBody(size: 13))
                        .foregroundStyle(PM.textTertiary)
                }
            }
            .padding(PM.Space.xl)
        }
    }

    private func breakdown(title: String, rows: [(String, Int, Double)]) -> some View {
        VStack(alignment: .leading, spacing: PM.Space.sm) {
            Text(title)
                .font(.pmBody(size: 11, weight: .semibold))
                .foregroundStyle(PM.textTertiary)
                .tracking(1.5)
            VStack(spacing: 0) {
                ForEach(rows.prefix(10), id: \.0) { row in
                    HStack {
                        Text(row.0)
                            .font(.pmBody(size: 13))
                            .foregroundStyle(PM.textPrimary)
                        Spacer()
                        Text("\(row.1) sold")
                            .font(.pmBody(size: 12))
                            .foregroundStyle(PM.textTertiary)
                        Text(row.2.asCurrency)
                            .font(.pmBody(size: 13, weight: .medium))
                            .foregroundStyle(row.2 >= 0 ? .green : .red)
                            .monospacedDigit()
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    if row.0 != rows.prefix(10).last?.0 {
                        Rectangle().fill(PM.borderSubtle).frame(height: 1).padding(.leading, 12)
                    }
                }
            }
            .pmCard(fill: PM.card, radius: PM.Radius.md)
        }
    }
}
