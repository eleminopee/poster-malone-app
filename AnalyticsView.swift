import SwiftUI

// MARK: - Analytics View

struct AnalyticsView: View {
    @Environment(InventoryStore.self) var store

    // SESSION 6: decision-oriented tabs + time range.
    enum AnalyticsTab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case buying   = "Buying"
        case pricing  = "Pricing & Velocity"
        case health   = "Health"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .buying:   return "cart.fill"
            case .pricing:  return "speedometer"
            case .health:   return "heart.text.square.fill"
            }
        }
    }
    @State private var tab: AnalyticsTab = .overview

    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var showingStatusChart = false
    @State private var showingAgingChart = false
    @State private var showingOldestPrints = false
    @State private var sellingCategory: SellingCategory = .artist
    @State private var sellingMetric: SellingMetric = .profit
    @State private var yoyYear1: Int = 2024
    @State private var yoyYear2: Int = 2025
    @State private var restockMetric: RestockSort = .score
    @State private var showingConcentrationDetail = false
    @State private var rollingMetric: RollingMetric = .prints

    enum RestockSort: String, CaseIterable {
        case score   = "Score"
        case roi     = "ROI %"
        case speed   = "Speed"
        case volume  = "# Sold"
    }

    enum RollingMetric: String, CaseIterable {
        case prints   = "Prints Sold"
        case netSales = "Net Sales"
        case profit   = "Profit"
    }

    enum SellingCategory: String, CaseIterable {
        case artist    = "Artists"
        case theme     = "Themes"
        case franchise = "Franchises"
        case gallery   = "Galleries"
        case printType = "Print Types"
    }

    enum SellingMetric: String, CaseIterable {
        case profit = "Profit"
        case gross  = "Gross"
        case volume = "Sales"
    }

    // MARK: Year helpers
    var allYears: [Int] {
        Array(Set(store.sales.map { Calendar.current.component(.year, from: $0.dateSold) })).sorted()
    }
    var salesForYear: [SaleRecord] {
        store.sales.filter { Calendar.current.component(.year, from: $0.dateSold) == selectedYear }
    }
    var monthlyData: [MonthData] {
        var m: [Int: (Double, Double, Int)] = [:]
        for s in salesForYear {
            let mo = Calendar.current.component(.month, from: s.dateSold)
            let ex = m[mo] ?? (0,0,0)
            m[mo] = (ex.0 + s.grossSales, ex.1 + s.profit, ex.2 + 1)
        }
        return (1...12).map { mo in
            let d = m[mo] ?? (0,0,0)
            return MonthData(month: mo, gross: d.0, profit: d.1, count: d.2)
        }
    }

    // MARK: All-time stats
    var allTimeGross: Double  { store.sales.reduce(0) { $0 + $1.grossSales } }
    var allTimeProfit: Double { store.sales.reduce(0) { $0 + $1.profit } }
    var allTimeCount: Int     { store.sales.count }
    var avgMargin: Double {
        guard !store.sales.isEmpty else { return 0 }
        return store.sales.reduce(0) { $0 + $1.profitLossPercent } / Double(store.sales.count)
    }
    var avgDaysToSell: Double {
        let v = store.sales.filter { $0.daysToSell > 0 }
        guard !v.isEmpty else { return 0 }
        return Double(v.reduce(0) { $0 + $1.daysToSell }) / Double(v.count)
    }
    var bestMonth: String {
        var m: [String: Double] = [:]
        let fmt = DateFormatter(); fmt.dateFormat = "MMM yyyy"
        for s in store.sales { m[fmt.string(from: s.dateSold), default: 0] += s.grossSales }
        return m.max(by: { $0.value < $1.value })?.key ?? "—"
    }

    // MARK: Portfolio line chart data
    var portfolioData: [PortfolioPoint] {
        var byMonth: [String: (netSales: Double, profit: Double)] = [:]
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM"
        for s in store.sales where s.grossSales > 0 {
            let key = fmt.string(from: s.dateSold)
            let ex = byMonth[key] ?? (0, 0)
            byMonth[key] = (ex.netSales + s.netSales, ex.profit + s.profit)
        }
        var runningRevenue = 0.0
        var runningProfit  = 0.0
        return byMonth.keys.sorted().compactMap { key -> PortfolioPoint? in
            guard let date = fmt.date(from: key) else { return nil }
            runningRevenue += byMonth[key]?.netSales ?? 0
            runningProfit  += byMonth[key]?.profit   ?? 0
            return PortfolioPoint(date: date, revenue: runningRevenue, profit: runningProfit)
        }
    }

    // MARK: Best Selling stats
    struct CategoryStat: Identifiable {
        let id = UUID()
        let name: String; let profit: Double; let gross: Double; let count: Int
    }

    func statsFor(_ category: SellingCategory) -> [CategoryStat] {
        var data: [String: (Double, Double, Int)] = [:]
        for s in store.sales {
            let key: String
            switch category {
            case .artist:    key = s.artist
            case .theme:     key = s.theme.isEmpty ? s.franchise : s.theme
            case .franchise: key = s.franchise
            case .gallery:   key = s.gallery
            case .printType: key = s.printType
            }
            guard !key.isEmpty else { continue }
            let ex = data[key] ?? (0,0,0)
            data[key] = (ex.0 + s.profit, ex.1 + s.grossSales, ex.2 + 1)
        }
        let all = data.map { CategoryStat(name: $0.key, profit: $0.value.0, gross: $0.value.1, count: $0.value.2) }
        switch sellingMetric {
        case .profit: return Array(all.sorted { $0.profit > $1.profit }.prefix(10))
        case .gross:  return Array(all.sorted { $0.gross  > $1.gross  }.prefix(10))
        case .volume: return Array(all.sorted { $0.count  > $1.count  }.prefix(10))
        }
    }

    var topStats: [CategoryStat] { statsFor(sellingCategory) }
    var topMaxValue: Double {
        switch sellingMetric {
        case .profit: return topStats.map(\.profit).max() ?? 1
        case .gross:  return topStats.map(\.gross).max()  ?? 1
        case .volume: return Double(topStats.map(\.count).max() ?? 1)
        }
    }
    func topValue(_ s: CategoryStat) -> Double {
        switch sellingMetric {
        case .profit: return s.profit
        case .gross:  return s.gross
        case .volume: return Double(s.count)
        }
    }
    func topLabel(_ s: CategoryStat) -> String {
        switch sellingMetric {
        case .profit: return s.profit.asCurrency
        case .gross:  return s.gross.asCurrency
        case .volume: return "\(s.count)"
        }
    }

    // MARK: Print Type stats
    struct PrintTypeStat: Identifiable {
        let id = UUID()
        let name: String; let sold: Int; let inStock: Int; let grossSales: Double
    }
    var printTypeStats: [PrintTypeStat] {
        var soldMap: [String: (Int, Double)] = [:]
        for s in store.sales where !s.printType.isEmpty {
            let ex = soldMap[s.printType] ?? (0,0); soldMap[s.printType] = (ex.0+1, ex.1+s.grossSales)
        }
        var stockMap: [String: Int] = [:]
        for item in store.items where !item.printType.isEmpty { stockMap[item.printType, default: 0] += 1 }
        return Set(soldMap.keys).union(stockMap.keys).map { k in
            let s = soldMap[k] ?? (0,0)
            return PrintTypeStat(name: k, sold: s.0, inStock: stockMap[k] ?? 0, grossSales: s.1)
        }.sorted { $0.sold > $1.sold }
    }

    // MARK: Inventory health
    func daysSincePurchase(_ item: InventoryItem) -> Int {
        guard let p = item.datePurchased else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: p, to: Date()).day ?? 0)
    }
    var inventoryValue: Double   { store.items.reduce(0) { $0 + $1.shopifyPrice } }
    var inventoryCost: Double    { store.items.reduce(0) { $0 + $1.totalCostComputed } }
    var inventoryProfit: Double  { inventoryValue - inventoryCost }
    var under90Days: Int   { store.items.filter { daysSincePurchase($0) <= 90 && $0.datePurchased != nil }.count }
    var days90to180: Int   { store.items.filter { let d = daysSincePurchase($0); return d > 90 && d <= 180 }.count }
    var over180Days: Int   { store.items.filter { daysSincePurchase($0) > 180 && $0.datePurchased != nil }.count }
    var days180to365: Int  { store.items.filter { let d = daysSincePurchase($0); return d > 180 && d <= 365 }.count }
    var days365to730: Int  { store.items.filter { let d = daysSincePurchase($0); return d > 365 && d <= 730 }.count }
    var days730to1095: Int { store.items.filter { let d = daysSincePurchase($0); return d > 730 && d <= 1095 }.count }
    var over1095Days: Int  { store.items.filter { daysSincePurchase($0) > 1095 && $0.datePurchased != nil }.count }
    var over365Days: Int   { store.items.filter { daysSincePurchase($0) > 365 && $0.datePurchased != nil }.count }
    var noDateCount: Int   { store.items.filter { $0.datePurchased == nil }.count }
    var orderedCount: Int   { store.items.filter { $0.status == .ordered }.count }
    var processedCount: Int { store.items.filter { $0.status == .processed }.count }
    var listedCount: Int    { store.items.filter { $0.status == .listed }.count }
    var statusCounts: [(status: ItemStatus, count: Int)] {
        ItemStatus.allCases.compactMap { s in
            let c = store.items.filter { $0.status == s }.count
            return c > 0 ? (s, c) : nil
        }.sorted { $0.count > $1.count }
    }
    var oldest25Items: [InventoryItem] {
        store.items.filter { $0.datePurchased != nil }
            .sorted { daysSincePurchase($0) > daysSincePurchase($1) }
            .prefix(25).map { $0 }
    }

    // MARK: - Price bracket analysis

    struct PriceBracket: Identifiable {
        let id = UUID()
        let label: String; let lo: Double; let hi: Double
        let count: Int; let avgDays: Double; let avgMargin: Double
    }

    var priceBrackets: [PriceBracket] {
        let defs: [(String, Double, Double)] = [
            ("Under $50", 0, 50), ("$50–100", 50, 100),
            ("$100–200", 100, 200), ("$200+", 200, 99999)
        ]
        return defs.map { label, lo, hi in
            let b = store.sales.filter { $0.grossSales >= lo && $0.grossSales < hi && $0.daysToSell > 0 }
            let avgDays   = b.isEmpty ? 0 : Double(b.reduce(0){$0+$1.daysToSell}) / Double(b.count)
            let avgMargin = b.isEmpty ? 0 : b.compactMap { $0.totalCost > 0 ? $0.profitLossPercent : nil }
                                              .reduce(0,+) / Double(b.count)
            return PriceBracket(label: label, lo: lo, hi: hi, count: b.count, avgDays: avgDays, avgMargin: avgMargin)
        }
    }

    // MARK: - Gallery ROI

    struct GalleryStat: Identifiable {
        let id = UUID()
        let name: String; let roi: Double; let count: Int; let avgDays: Double; let profit: Double
    }

    var galleryROI: [GalleryStat] {
        var data: [String: (profit: Double, cost: Double, count: Int, days: [Int])] = [:]
        for s in store.sales where !s.gallery.isEmpty && s.totalCost > 0 {
            let ex = data[s.gallery] ?? (0,0,0,[])
            data[s.gallery] = (ex.profit+s.profit, ex.cost+s.totalCost, ex.count+1,
                               s.daysToSell > 0 ? ex.days+[s.daysToSell] : ex.days)
        }
        return data.compactMap { name, d -> GalleryStat? in
            guard d.count >= 3 else { return nil }
            let roi = d.cost > 0 ? (d.profit/d.cost)*100 : 0
            let avgDays = d.days.isEmpty ? 0 : Double(d.days.reduce(0,+))/Double(d.days.count)
            return GalleryStat(name: name, roi: roi, count: d.count, avgDays: avgDays, profit: d.profit)
        }.sorted { $0.roi > $1.roi }
    }

    // MARK: - Artist restock score

    struct RestockStat: Identifiable {
        let id = UUID()
        let name: String; let score: Double; let roi: Double; let avgDays: Double; let count: Int
    }

    var restockStats: [RestockStat] {
        var data: [String: (profit: Double, cost: Double, count: Int, days: [Int])] = [:]
        for s in store.sales where !s.artist.isEmpty && s.totalCost > 0 {
            let ex = data[s.artist] ?? (0,0,0,[])
            data[s.artist] = (ex.profit+s.profit, ex.cost+s.totalCost, ex.count+1,
                              s.daysToSell > 0 ? ex.days+[s.daysToSell] : ex.days)
        }
        let stats = data.compactMap { name, d -> RestockStat? in
            guard d.count >= 5, d.cost > 0 else { return nil }
            let roi = (d.profit/d.cost)*100
            let avgDays = d.days.isEmpty ? 999 : Double(d.days.reduce(0,+))/Double(d.days.count)
            let score = roi / max(avgDays, 1) * 100
            return RestockStat(name: name, score: score, roi: roi, avgDays: avgDays, count: d.count)
        }
        switch restockMetric {
        case .score:  return Array(stats.sorted { $0.score   > $1.score   }.prefix(10))
        case .roi:    return Array(stats.sorted { $0.roi     > $1.roi     }.prefix(10))
        case .speed:  return Array(stats.sorted { $0.avgDays < $1.avgDays }.prefix(10))
        case .volume: return Array(stats.sorted { $0.count   > $1.count   }.prefix(10))
        }
    }

    var restockMax: Double {
        switch restockMetric {
        case .score:  return restockStats.map(\.score).max()   ?? 1
        case .roi:    return restockStats.map(\.roi).max()     ?? 1
        case .speed:  return restockStats.map(\.avgDays).max() ?? 1
        case .volume: return Double(restockStats.map(\.count).max() ?? 1)
        }
    }

    func restockValue(_ s: RestockStat) -> Double {
        switch restockMetric {
        case .score:  return s.score
        case .roi:    return s.roi
        case .speed:  return s.avgDays
        case .volume: return Double(s.count)
        }
    }

    func restockLabel(_ s: RestockStat) -> String {
        switch restockMetric {
        case .score:  return String(format: "%.0f", s.score)
        case .roi:    return s.roi.asPercent
        case .speed:  return "\(Int(s.avgDays))d"
        case .volume: return "\(s.count)"
        }
    }

    // MARK: - Day of week

    struct DayStat: Identifiable {
        let id = UUID()
        let name: String; let short: String; let count: Int; let gross: Double
    }

    var dayOfWeekStats: [DayStat] {
        let order = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
        let shorts = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
        var data: [String: (Int, Double)] = [:]
        let fmt = DateFormatter(); fmt.dateFormat = "EEEE"
        for s in store.sales {
            let day = fmt.string(from: s.dateSold)
            let ex = data[day] ?? (0,0)
            data[day] = (ex.0+1, ex.1+s.grossSales)
        }
        return order.enumerated().compactMap { i, day in
            guard let d = data[day] else { return nil }
            return DayStat(name: day, short: shorts[i], count: d.0, gross: d.1)
        }
    }

    // MARK: - YoY comparison

    struct YoYMonth: Identifiable {
        let id = UUID()
        let month: Int; let abbrev: String
        let gross1: Double; let gross2: Double
    }

    var yoyData: [YoYMonth] {
        let abbrevs = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        var m1: [Int: Double] = [:]; var m2: [Int: Double] = [:]
        for s in store.sales {
            let y = Calendar.current.component(.year, from: s.dateSold)
            let m = Calendar.current.component(.month, from: s.dateSold)
            if y == yoyYear1 { m1[m, default: 0] += s.grossSales }
            if y == yoyYear2 { m2[m, default: 0] += s.grossSales }
        }
        return (1...12).map { m in
            YoYMonth(month: m, abbrev: abbrevs[m-1], gross1: m1[m] ?? 0, gross2: m2[m] ?? 0)
        }
    }

    // MARK: - Concentration risk

    struct ConcentrationStat: Identifiable {
        let id = UUID()
        let name: String; let value: Double; let pct: Double; let count: Int
    }

    var concentrationStats: [ConcentrationStat] {
        var artistVal: [String: (Double, Int)] = [:]
        for item in store.items where item.shopifyPrice > 0 && !item.artist.isEmpty {
            let ex = artistVal[item.artist] ?? (0,0)
            artistVal[item.artist] = (ex.0+item.shopifyPrice, ex.1+1)
        }
        let total = inventoryValue
        guard total > 0 else { return [] }
        return artistVal.map { name, d in
            ConcentrationStat(name: name, value: d.0, pct: d.0/total*100, count: d.1)
        }.sorted { $0.value > $1.value }.prefix(12).map { $0 }
    }

    // MARK: - Rolling window data

    struct RollingWindow: Identifiable {
        let id = UUID()
        let label: String
        let days: Int
        let count: Int
        let netSales: Double
        let profit: Double
    }

    var rollingWindows: [RollingWindow] {
        let windows: [(String, Int)] = [
            ("7d", 7), ("14d", 14), ("30d", 30),
            ("60d", 60), ("90d", 90), ("180d", 180), ("1yr", 365)
        ]
        let now = Date()
        var result: [RollingWindow] = []
        for (label, days) in windows {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
            let filtered = store.sales.filter { $0.dateSold >= cutoff }
            result.append(RollingWindow(
                label: label, days: days,
                count: filtered.count,
                netSales: filtered.reduce(0) { $0 + $1.netSales },
                profit: filtered.reduce(0) { $0 + $1.profit }
            ))
        }
        return result
    }

    // MARK: - Forecast (linear regression over 30-day buckets)

    struct ForecastWindow: Identifiable {
        let id = UUID()
        let label: String
        let days: Int
        let count: Double
        let netSales: Double
        let profit: Double
    }

    private func forecastPerDay() -> (count: Double, netSales: Double, profit: Double) {
        // Build monthly 30-day bucket totals over ALL historical data, then fit linear regression
        guard !store.sales.isEmpty else { return (0, 0, 0) }
        let now = Date()
        guard let oldest = store.sales.map(\.dateSold).min() else { return (0, 0, 0) }
        let totalDays = max(1, Calendar.current.dateComponents([.day], from: oldest, to: now).day ?? 1)
        let numBuckets = max(1, totalDays / 30)
        // Build per-bucket totals
        var bucketCount: [Int: Int]    = [:]
        var bucketNet:   [Int: Double] = [:]
        var bucketProfit:[Int: Double] = [:]
        for s in store.sales {
            let age = Calendar.current.dateComponents([.day], from: oldest, to: s.dateSold).day ?? 0
            let bucket = age / 30
            bucketCount[bucket,  default: 0] += 1
            bucketNet[bucket,    default: 0] += s.netSales
            bucketProfit[bucket, default: 0] += s.profit
        }
        // Simple linear regression: y = a + b*x  (x = bucket index)
        func linearRegression(_ values: [Int: Double], n: Int) -> (a: Double, b: Double) {
            guard n > 1 else {
                let avg = values.values.reduce(0, +) / Double(max(1, values.count))
                return (avg, 0)
            }
            let xs = (0..<n).map { Double($0) }
            let ys = (0..<n).map { values[$0] ?? 0.0 }
            let xMean = xs.reduce(0,+) / Double(n)
            let yMean = ys.reduce(0,+) / Double(n)
            let num = zip(xs,ys).reduce(0) { $0 + ($1.0 - xMean)*($1.1 - yMean) }
            let den = xs.reduce(0) { $0 + ($1 - xMean)*($1 - xMean) }
            let b = den > 0 ? num/den : 0
            return (yMean - b*xMean, b)
        }
        func linearRegressionInt(_ values: [Int: Int], n: Int) -> (a: Double, b: Double) {
            let dvals = values.mapValues { Double($0) }
            return linearRegression(dvals, n: n)
        }
        let nextBucket = Double(numBuckets)   // the "next" 30-day bucket
        let (ca, cb) = linearRegressionInt(bucketCount, n: numBuckets)
        let (na, nb) = linearRegression(bucketNet,     n: numBuckets)
        let (pa, pb) = linearRegression(bucketProfit,  n: numBuckets)
        // Predicted value for the next bucket (30 days), clamped to minimum 0
        let predicted30Count  = max(0, ca + cb * nextBucket)
        let predicted30Net    = max(0, na + nb * nextBucket)
        let predicted30Profit = max(0, pa + pb * nextBucket)
        // Return per-day rates
        return (predicted30Count/30, predicted30Net/30, predicted30Profit/30)
    }

    var forecastWindows: [ForecastWindow] {
        let windows: [(String, Int)] = [
            ("7d", 7), ("14d", 14), ("30d", 30), ("60d", 60), ("90d", 90)
        ]
        let (cRate, nRate, pRate) = forecastPerDay()
        return windows.map { label, days in
            ForecastWindow(
                label: label, days: days,
                count: cRate * Double(days),
                netSales: nRate * Double(days),
                profit: pRate * Double(days)
            )
        }
    }

    func rollingMaxActual() -> Double {
        switch rollingMetric {
        case .prints:   return Double(rollingWindows.map(\.count).max() ?? 1)
        case .netSales: return rollingWindows.map(\.netSales).max() ?? 1
        case .profit:   return rollingWindows.map(\.profit).max() ?? 1
        }
    }
    func rollingMaxForecast() -> Double {
        switch rollingMetric {
        case .prints:   return forecastWindows.map(\.count).max() ?? 1
        case .netSales: return forecastWindows.map(\.netSales).max() ?? 1
        case .profit:   return forecastWindows.map(\.profit).max() ?? 1
        }
    }
    func rollingActualValue(_ w: RollingWindow) -> Double {
        switch rollingMetric {
        case .prints:   return Double(w.count)
        case .netSales: return w.netSales
        case .profit:   return w.profit
        }
    }
    func rollingForecastValue(_ w: ForecastWindow) -> Double {
        switch rollingMetric {
        case .prints:   return w.count
        case .netSales: return w.netSales
        case .profit:   return w.profit
        }
    }
    func rollingLabel(_ v: Double) -> String {
        switch rollingMetric {
        case .prints:   return String(format: "%.0f", v)
        case .netSales: return v.asCurrency
        case .profit:   return v.asCurrency
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            analyticsTabBar
            Divider().overlay(PM.borderSubtle)
            insightStrip
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    switch tab {
                    case .overview:
                        allTimeSection
                        rollingSection
                        portfolioSection
                        monthlySection
                        yoySection
                    case .buying:
                        bestSellingSection
                        restockSection
                        galleryROISection
                        ccpSection
                    case .pricing:
                        priceBracketSection
                        dayOfWeekSection
                        printTypeSection
                    case .health:
                        inventoryHealthSection
                        concentrationSection
                        breakEvenSection
                    }
                }
                .padding(20)
            }
        }
        .pmScreen()
        .navigationTitle("Analytics")
    }

    // MARK: - Tab Bar (SESSION 6)

    private var analyticsTabBar: some View {
        HStack(spacing: 0) {
            ForEach(AnalyticsTab.allCases) { t in
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
                            .pmGlow(PM.cyan, radius: tab == t ? 4 : 0, opacity: tab == t ? 0.5 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(PM.Anim.hover, value: tab)
            }
            Spacer()
        }
        .background(PM.surface)
    }

    // MARK: - Headline Insight Strip (SESSION 6)

    private var insightStrip: some View {
        let heldValue = oldest25Items.filter { daysSincePurchase($0) > 365 }.reduce(0) { $0 + $1.shopifyPrice }
        let staleCount = over365Days
        return HStack(spacing: 10) {
            Image(systemName: staleCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: 14))
                .foregroundStyle(staleCount > 0 ? .orange : .green)
                .pmGlow(staleCount > 0 ? .orange : .green, radius: 5, opacity: 0.4)
            if staleCount > 0 {
                Text("\(staleCount) item\(staleCount == 1 ? "" : "s") over 1 year old holding \(heldValue.asCurrency) in listed value — review pricing in Health.")
                    .font(.pmBody(size: 13, weight: .medium))
                    .foregroundStyle(PM.textPrimary)
            } else {
                Text("Inventory is moving well — nothing held over a year.")
                    .font(.pmBody(size: 13, weight: .medium))
                    .foregroundStyle(PM.textPrimary)
            }
            Spacer()
            Text("\(allTimeCount) sales · \(allTimeGross.asCurrency) gross all-time")
                .font(.pmBody(size: 12))
                .foregroundStyle(PM.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(PM.base)
    }

    // MARK: - Rolling Performance & Forecast

    var rollingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle("Rolling Performance & Forecast")
                    Text("Actual results for recent windows + linear-regression forecast based on all historical data.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $rollingMetric) {
                    ForEach(RollingMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            // Actual rolling windows
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill").font(.caption2).foregroundStyle(PM.cyan)
                    Text("ACTUAL — Last N Days").font(.caption).fontWeight(.semibold).foregroundStyle(PM.cyan)
                }
                RollingActualChart(
                    windows: rollingWindows,
                    maxValue: rollingMaxActual(),
                    valueForWindow: rollingActualValue,
                    labelForValue: rollingLabel,
                    metric: rollingMetric
                )
            }
            .padding(12)
            .background(PM.cyan.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            // Forecast windows
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars").font(.caption2).foregroundStyle(.purple)
                    Text("FORECAST — Next N Days").font(.caption).fontWeight(.semibold).foregroundStyle(.purple)
                    Spacer()
                    Text("Linear regression on 30-day buckets").font(.caption2).foregroundStyle(.tertiary)
                }
                RollingForecastChart(
                    windows: forecastWindows,
                    maxValue: max(rollingMaxForecast(), 1),
                    valueForWindow: rollingForecastValue,
                    labelForValue: rollingLabel,
                    metric: rollingMetric
                )
            }
            .padding(12)
            .background(Color.purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    // MARK: - All-Time Section

    var allTimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("All-Time Performance")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                AnalyticCard(label: "Total Sales",       value: "\(allTimeCount)",          icon: "cart.fill",                 color: .blue)
                AnalyticCard(label: "Gross Revenue",     value: allTimeGross.asCurrency,    icon: "dollarsign.circle.fill",    color: .green)
                AnalyticCard(label: "Total Profit",      value: allTimeProfit.asCurrency,   icon: "chart.line.uptrend.xyaxis", color: .mint)
                AnalyticCard(label: "Avg Margin",        value: avgMargin.asPercent,        icon: "percent",                   color: .orange)
                AnalyticCard(label: "Avg Days to Sell",  value: String(format: "%.0f days", avgDaysToSell), icon: "clock.fill", color: .purple)
                AnalyticCard(label: "Best Month",        value: bestMonth,                  icon: "star.fill",                 color: .yellow)
            }
        }
    }

    var portfolioSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Revenue Over Time")
                Text("Cumulative net sales (gross minus taxes & fees, before cost of goods) — shows total cash collected since your first sale.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            PortfolioLineChart(data: portfolioData).frame(height: 220)
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    var monthlySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Monthly Revenue")
                Spacer()
                Picker("Year", selection: $selectedYear) {
                    ForEach(allYears, id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.menu).fixedSize()
            }
            HStack(spacing: 20) {
                Label { Text("\(salesForYear.count) sales").font(.caption).foregroundStyle(.secondary) }
                    icon: { Image(systemName: "cart").font(.caption2).foregroundStyle(.secondary) }
                Label { Text(salesForYear.reduce(0){$0+$1.grossSales}.asCurrency).font(.caption).foregroundStyle(.secondary) }
                    icon: { Image(systemName: "dollarsign").font(.caption2).foregroundStyle(.green) }
                Label { Text(salesForYear.reduce(0){$0+$1.profit}.asCurrency).font(.caption).foregroundStyle(.secondary) }
                    icon: { Image(systemName: "chart.line.uptrend.xyaxis").font(.caption2).foregroundStyle(.mint) }
            }
            MonthlyBarChart(data: monthlyData).frame(height: 220)
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    var bestSellingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                SectionTitle("Best Selling")
                Picker("Category", selection: $sellingCategory) {
                    ForEach(SellingCategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                .fixedSize()  // expands to fit the longest label

                Spacer()

                HStack(spacing: 6) {
                    Text("By")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $sellingMetric) {
                        ForEach(SellingMetric.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            CategoryBarChart(
                stats: topStats, maxValue: topMaxValue,
                valueForStat: topValue, labelForStat: topLabel,
                color: sellingMetric == .profit ? .mint : sellingMetric == .gross ? .green : .blue
            )
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    var printTypeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Sales by Print Type")
                Text("Sold vs. currently in inventory").font(.caption).foregroundStyle(.secondary)
            }
            PrintTypeChart(stats: printTypeStats)
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    // MARK: YoY Comparison

    var yoySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle("Year-over-Year")
                Spacer()
                HStack(spacing: 6) {
                    Picker("", selection: $yoyYear1) {
                        ForEach(allYears.filter { $0 < Calendar.current.component(.year, from: Date()) }, id: \.self) {
                            Text(String($0)).tag($0)
                        }
                    }.pickerStyle(.menu).frame(width: 80)
                    Text("vs").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $yoyYear2) {
                        ForEach(allYears, id: \.self) { Text(String($0)).tag($0) }
                    }.pickerStyle(.menu).frame(width: 80)
                }
            }
            YoYChart(data: yoyData, year1: yoyYear1, year2: yoyYear2)
                .frame(height: 160)
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    // MARK: Price Bracket

    var priceBracketSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Price vs. Velocity")
                Text("Higher-priced prints sell faster and at better margins — you may be underpricing your mid-range items.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            PriceBracketChart(brackets: priceBrackets)
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    // MARK: Gallery ROI

    var galleryROISection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Gallery ROI")
                Text("Return on investment by source — helps prioritize which gallery drops to buy from.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GalleryROIChart(stats: galleryROI)
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    // MARK: Restock Recommendations

    var restockSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle("Best Artists to Restock")
                    Text("Score = ROI ÷ avg days held × 100. Higher = faster money.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $restockMetric) {
                    ForEach(RestockSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).fixedSize()
            }
            RestockChart(
                stats: restockStats, maxValue: restockMax,
                valueForStat: restockValue, labelForStat: restockLabel
            )
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    // MARK: Day of Week

    var dayOfWeekSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Sales by Day of Week")
                Text("Weekends (Sat/Sun) drive the most volume — consider scheduling new listings to go live Friday evening.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DayOfWeekChart(stats: dayOfWeekStats)
                .frame(height: 120)
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    // MARK: Concentration Risk

    var concentrationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Inventory Concentration Risk")
                Text("How much of your listed value is tied up in each artist. No single artist exceeds 6% — well diversified.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ConcentrationChart(stats: concentrationStats, total: inventoryValue)
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    var ccpSection: some View {
        CCPSection(items: store.items, sales: store.sales)
    }

    var inventoryHealthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Inventory Health")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                Button { showingStatusChart.toggle() } label: {
                    AnalyticCard(
                        label: showingStatusChart ? "Items — collapse ▲" : "Items — tap for breakdown",
                        value: "\(store.items.count)", icon: "archivebox.fill", color: .blue
                    )
                }.buttonStyle(.plain)
                AnalyticCard(label: "Listed Value",      value: inventoryValue.asCurrency,  icon: "tag.fill",                  color: .green)
                AnalyticCard(label: "Cost Basis",        value: inventoryCost.asCurrency,   icon: "cart.fill",                 color: .orange)
                AnalyticCard(label: "Potential Profit",  value: inventoryProfit.asCurrency, icon: "chart.line.uptrend.xyaxis", color: .mint)
                AnalyticCard(label: "Avg Cost/Item",
                             value: store.items.isEmpty ? "—" : (inventoryCost/Double(store.items.count)).asCurrency,
                             icon: "equal.circle.fill", color: .indigo)
                AnalyticCard(label: "Avg List Price",
                             value: store.items.isEmpty ? "—" : (inventoryValue/Double(store.items.count)).asCurrency,
                             icon: "tag.circle.fill", color: .teal)
            }

            if showingStatusChart {
                StatusBreakdownChart(statusCounts: statusCounts, total: store.items.count)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                AnalyticCard(label: "Listed",    value: "\(listedCount) items",    icon: "checkmark.circle.fill", color: .green)
                AnalyticCard(label: "Processed", value: "\(processedCount) items", icon: "gearshape.fill",        color: .blue)
                AnalyticCard(label: "Ordered",   value: "\(orderedCount) items",   icon: "shippingbox.fill",      color: .orange)
            }

            Divider()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                AnalyticCard(label: "< 90 Days",   value: "\(under90Days) items",  icon: "checkmark.circle.fill",       color: .green)
                AnalyticCard(label: "90–180 Days", value: "\(days90to180) items",  icon: "clock.fill",                  color: .yellow)
                Button { showingAgingChart.toggle() } label: {
                    AnalyticCard(
                        label: showingAgingChart ? "> 180 Days — collapse ▲" : "> 180 Days — tap for breakdown",
                        value: "\(over180Days) items", icon: "exclamationmark.circle.fill",
                        color: over180Days > 50 ? .red : .orange
                    )
                }.buttonStyle(.plain)
            }

            if showingAgingChart {
                AgingBreakdownChart(
                    buckets: [
                        ("180–365 days", days180to365, Color.yellow),
                        ("1–2 years",    days365to730,  Color.orange),
                        ("2–3 years",    days730to1095, Color.red),
                        ("3+ years",     over1095Days,  Color(red:0.75, green:0, blue:0))
                    ],
                    total: over180Days
                ).transition(.opacity.combined(with: .move(edge: .top)))
            }

            InventoryAgingBar(
                total: store.items.filter { $0.datePurchased != nil }.count,
                under90: under90Days, mid: days90to180,
                over180: over180Days, over365: over365Days, noDate: noDateCount
            )

            DisclosureGroup(isExpanded: $showingOldestPrints) {
                VStack(spacing: 0) {
                    ForEach(Array(oldest25Items.enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 10) {
                            Text("#\(idx+1)").font(.caption2).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.artist) — \(item.title)").font(.caption).lineLimit(1)
                                Text(item.sku).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(daysSincePurchase(item)) days")
                                    .font(.caption).fontWeight(.medium)
                                    .foregroundStyle(daysSincePurchase(item) > 1095 ? Color.red : Color.orange)
                                if let dp = item.datePurchased {
                                    Text(dp.shortDate).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 5).padding(.horizontal, 8)
                        if idx < oldest25Items.count - 1 { Divider().padding(.leading, 42) }
                    }
                }
                .background(PM.base.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .padding(.top, 6)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange).font(.caption)
                    Text("Top 25 Oldest Prints").font(.caption).fontWeight(.medium)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }

    // MARK: Break-Even Tracker

    var breakEvenSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Break-Even Tracker")
                Text("At your current sell-through rate, when will your remaining cost basis be fully recovered?")
                    .font(.caption).foregroundStyle(.secondary)
            }
            BreakEvenView(store: store)
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }
}

// MARK: - Portfolio Line Chart

struct PortfolioPoint: Identifiable {
    let id = UUID()
    let date: Date
    let revenue: Double  // cumulative net sales
    let profit: Double   // cumulative profit (net sales - cost of goods)
}

struct PortfolioLineChart: View {
    let data: [PortfolioPoint]

    var maxVal: Double { data.map(\.revenue).max() ?? 1 }

    // Labels every ~6 months
    var xLabels: [(xFrac: CGFloat, label: String)] {
        guard data.count > 1 else { return [] }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM ''yy"
        var labels: [(CGFloat, String)] = []
        var lastMonth = -99
        for (i, p) in data.enumerated() {
            let cal = Calendar.current
            let idx = cal.component(.year, from: p.date) * 12 + cal.component(.month, from: p.date)
            if idx - lastMonth >= 6 {
                labels.append((CGFloat(i) / CGFloat(data.count - 1), fmt.string(from: p.date)))
                lastMonth = idx
            }
        }
        return labels
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height - 22  // bottom margin for x-axis labels

            // X positions
            let xs: [CGFloat] = data.indices.map { i in
                data.count > 1 ? w * CGFloat(i) / CGFloat(data.count - 1) : w / 2
            }

            // Y positions (both series share the same scale based on max revenue)
            let revPts: [CGPoint] = data.indices.map { i in
                CGPoint(x: xs[i], y: h - h * CGFloat(data[i].revenue / max(maxVal, 1)))
            }
            let profPts: [CGPoint] = data.indices.map { i in
                CGPoint(x: xs[i], y: h - h * CGFloat(max(0, data[i].profit) / max(maxVal, 1)))
            }

            ZStack(alignment: .topLeading) {
                if data.count > 1 {
                    // ── Revenue area (cyan, bottom layer) ──
                    Path { path in
                        path.move(to: CGPoint(x: revPts[0].x, y: h))
                        revPts.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: revPts.last!.x, y: h))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [PM.cyan.opacity(0.30), PM.cyan.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    ))

                    Path { path in
                        path.move(to: revPts[0])
                        revPts.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(PM.cyan.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))

                    // ── Profit area (mint, top layer) ──
                    Path { path in
                        path.move(to: CGPoint(x: profPts[0].x, y: h))
                        profPts.forEach { path.addLine(to: $0) }
                        path.addLine(to: CGPoint(x: profPts.last!.x, y: h))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color.mint.opacity(0.55), Color.mint.opacity(0.1)],
                        startPoint: .top, endPoint: .bottom
                    ))

                    Path { path in
                        path.move(to: profPts[0])
                        profPts.dropFirst().forEach { path.addLine(to: $0) }
                    }
                    .stroke(Color.mint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))

                    // End dots
                    if let lastRev = revPts.last {
                        Circle().fill(PM.cyan.opacity(0.85)).frame(width: 7, height: 7).position(lastRev)
                    }
                    if let lastProf = profPts.last {
                        Circle().fill(Color.mint).frame(width: 7, height: 7).position(lastProf)
                    }
                }

                // Y-axis labels
                Text(maxVal.asCurrency)
                    .font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                    .position(x: 32, y: 8)
                Text("$0")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .position(x: 10, y: h - 4)

                // Current value callouts — staggered vertically to avoid overlap
                if let last = data.last {
                    if let lastRevPt = revPts.last {
                        Text(last.revenue.asCurrency)
                            .font(.system(size: 10)).fontWeight(.semibold).foregroundStyle(PM.cyan)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(PM.raised.opacity(0.95), in: RoundedRectangle(cornerRadius: 4))
                            .position(x: max(60, lastRevPt.x - 55), y: max(14, lastRevPt.y - 20))
                    }
                    if let lastProfPt = profPts.last {
                        Text(last.profit.asCurrency)
                            .font(.system(size: 10)).fontWeight(.semibold).foregroundStyle(.mint)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(PM.raised.opacity(0.95), in: RoundedRectangle(cornerRadius: 4))
                            .position(x: max(60, lastProfPt.x - 55), y: lastProfPt.y + 20)
                    }
                }

                // Legend — top center
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(PM.cyan.opacity(0.8)).frame(width: 10, height: 10)
                        Text("Net Revenue").font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.mint).frame(width: 10, height: 10)
                        Text("Cumul. Profit").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .position(x: w / 2, y: 10)

                // X-axis tick marks + labels
                ForEach(xLabels, id: \.label) { item in
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 1, height: 5)
                        Text(item.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .position(x: item.xFrac * w, y: h + 10)
                }
            }
        }
    }
}

// MARK: - Category Bar Chart

struct CategoryBarChart: View {
    let stats: [AnalyticsView.CategoryStat]
    let maxValue: Double
    let valueForStat: (AnalyticsView.CategoryStat) -> Double
    let labelForStat: (AnalyticsView.CategoryStat) -> String
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            ForEach(stats) { stat in
                HStack(spacing: 8) {
                    Text(stat.name).font(.caption).lineLimit(1).frame(width: 130, alignment: .trailing)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 18)
                            RoundedRectangle(cornerRadius: 3).fill(color.gradient)
                                .frame(width: max(4, geo.size.width * CGFloat(min(1.0, valueForStat(stat)/max(maxValue,1)))), height: 18)
                        }
                    }
                    .frame(height: 18)
                    Text(labelForStat(stat)).font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 70, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Print Type Chart

struct PrintTypeChart: View {
    let stats: [AnalyticsView.PrintTypeStat]
    var maxSold: Int  { stats.map(\.sold).max()    ?? 1 }
    var maxStock: Int { stats.map(\.inStock).max() ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 6) {
                Text("Type")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
                Text("Sold")
                    .font(.caption2).foregroundStyle(.mint)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("In Stock")
                    .font(.caption2).foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text("Gross")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            ForEach(stats) { stat in
                HStack(spacing: 6) {
                    Text(stat.name)
                        .font(.caption).lineLimit(1)
                        .frame(width: 100, alignment: .leading)

                    // Sold bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 18)
                            RoundedRectangle(cornerRadius: 3).fill(Color.mint.gradient)
                                .frame(width: maxSold > 0 ? max(4, geo.size.width * CGFloat(stat.sold) / CGFloat(maxSold)) : 4, height: 18)
                            Text("\(stat.sold)")
                                .font(.caption2).fontWeight(.semibold).foregroundStyle(.white).padding(.leading, 6)
                        }
                    }
                    .frame(height: 18)

                    // Stock bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 18)
                            RoundedRectangle(cornerRadius: 3).fill(Color.blue.gradient)
                                .frame(width: maxStock > 0 ? max(4, geo.size.width * CGFloat(stat.inStock) / CGFloat(maxStock)) : 4, height: 18)
                            Text("\(stat.inStock)")
                                .font(.caption2).fontWeight(.semibold).foregroundStyle(.white).padding(.leading, 6)
                        }
                    }
                    .frame(height: 18)

                    Text(stat.grossSales.asCurrency)
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
        }
        .padding(.vertical, 10)
        .background(PM.base.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Status Breakdown Chart

struct StatusBreakdownChart: View {
    let statusCounts: [(status: ItemStatus, count: Int)]
    let total: Int

    func color(for s: ItemStatus) -> Color {
        switch s {
        case .active: return .blue; case .listed: return .green; case .processed: return .cyan
        case .ordered: return .orange; case .draft: return .gray; case .auction: return .purple
        case .pending: return .yellow; case .theVault: return .indigo; case .onHold: return .pink
        case .research: return Color(red: 1.0, green: 0.2, blue: 0.6)
        case .sold: return .mint
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Breakdown by Status").font(.caption).foregroundStyle(.secondary)
            ForEach(statusCounts, id: \.status) { entry in
                HStack(spacing: 8) {
                    Text(entry.status.rawValue).font(.caption).frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 16)
                            RoundedRectangle(cornerRadius: 3).fill(color(for: entry.status).gradient)
                                .frame(width: total > 0 ? max(4, geo.size.width * CGFloat(entry.count)/CGFloat(total)) : 4, height: 16)
                        }
                    }
                    .frame(height: 16)
                    Text("\(entry.count)").font(.caption).fontWeight(.medium).monospacedDigit().frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(PM.base.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Monthly Bar Chart

struct MonthData {
    let month: Int; let gross: Double; let profit: Double; let count: Int
    var monthAbbrev: String {
        let f = DateFormatter(); f.dateFormat = "MMM"
        var c = DateComponents(); c.month = month; c.year = 2000
        return f.string(from: Calendar.current.date(from: c) ?? Date())
    }
}

struct MonthlyBarChart: View {
    let data: [MonthData]
    var maxGross: Double { data.map(\.gross).max() ?? 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(data, id: \.month) { d in
                VStack(spacing: 3) {
                    if d.gross > 0 {
                        Text(d.gross > 999 ? "$\(Int(d.gross/1000))k" : "$\(Int(d.gross))")
                            .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.green.opacity(0.25))
                            .frame(height: d.gross > 0 ? max(4, CGFloat(d.gross/maxGross)*160) : 4)
                        RoundedRectangle(cornerRadius: 3).fill(d.profit >= 0 ? Color.mint : Color.red)
                            .frame(height: d.profit != 0 ? max(3, CGFloat(abs(d.profit)/maxGross)*160) : 0)
                    }
                    Text(d.monthAbbrev).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.4)).frame(width: 10, height: 10)
                    Text("Gross").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.mint).frame(width: 10, height: 10)
                    Text("Profit").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Aging Breakdown Chart

struct AgingBreakdownChart: View {
    let buckets: [(label: String, count: Int, color: Color)]
    let total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Age Breakdown — Items Over 180 Days").font(.caption).foregroundStyle(.secondary)
            ForEach(buckets, id: \.label) { b in
                HStack(spacing: 8) {
                    Text(b.label).font(.caption).frame(width: 100, alignment: .trailing).foregroundStyle(.secondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 20)
                            if b.count > 0 {
                                RoundedRectangle(cornerRadius: 3).fill(b.color.gradient)
                                    .frame(width: total > 0 ? max(4, geo.size.width * CGFloat(b.count)/CGFloat(total)) : 4, height: 20)
                                Text("\(b.count) items").font(.caption2).fontWeight(.medium).foregroundStyle(.white).padding(.leading, 8)
                            }
                        }
                    }
                    .frame(height: 20)
                    Text(total > 0 ? "\(Int(Double(b.count)/Double(total)*100))%" : "—")
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(PM.base.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Inventory Aging Bar

struct InventoryAgingBar: View {
    let total: Int; let under90: Int; let mid: Int
    let over180: Int; let over365: Int; let noDate: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Age Since Purchase").font(.caption).foregroundStyle(.secondary)
                if noDate > 0 { Text("(\(noDate) items have no purchase date)").font(.caption2).foregroundStyle(.secondary) }
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if total > 0 {
                        RoundedRectangle(cornerRadius: 4).fill(Color.green)
                            .frame(width: geo.size.width * CGFloat(under90)/CGFloat(total))
                        RoundedRectangle(cornerRadius: 4).fill(Color.yellow)
                            .frame(width: geo.size.width * CGFloat(mid)/CGFloat(total))
                        RoundedRectangle(cornerRadius: 4).fill(Color.red)
                            .frame(width: max(2, geo.size.width * CGFloat(over180)/CGFloat(total)))
                    }
                }
            }
            .frame(height: 12)
            HStack(spacing: 14) {
                AgingLegend(color: .green,  label: "< 90 days",   count: under90)
                AgingLegend(color: .yellow, label: "90-180 days", count: mid)
                AgingLegend(color: .red,    label: "> 180 days",  count: over180)
                Spacer()
                if over365 > 0 { Text("\(over365) items over 1 year").font(.caption2).foregroundStyle(.red).fontWeight(.medium) }
            }
        }
    }
}

// MARK: - Supporting Views

struct AgingLegend: View {
    let color: Color; let label: String; let count: Int
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label): \(count)").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.pmDisplay(size: 17))
            .foregroundStyle(PM.textPrimary)
            .textCase(.uppercase)
            .tracking(1.0)
    }
}

struct AnalyticCard: View {
    let label: String; let value: String; let icon: String; let color: Color
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                        .strokeBorder(color.opacity(0.25), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.pmDisplay(size: 19))
                    .foregroundStyle(PM.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(label)
                    .font(.pmBody(size: 11, weight: .medium))
                    .foregroundStyle(PM.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer()
        }
        .padding(12)
        .background(PM.card, in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                .strokeBorder(color.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - YoY Chart

struct YoYChart: View {
    let data: [AnalyticsView.YoYMonth]
    let year1: Int; let year2: Int
    var maxVal: Double { data.flatMap { [$0.gross1, $0.gross2] }.max() ?? 1 }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(data) { d in
                VStack(spacing: 2) {
                    HStack(alignment: .bottom, spacing: 2) {
                        // Year 1 bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(PM.cyan.opacity(0.5))
                            .frame(maxWidth: .infinity,
                                   minHeight: 3,
                                   maxHeight: d.gross1 > 0 ? max(3, CGFloat(d.gross1/maxVal)*120) : 3)
                        // Year 2 bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.mint)
                            .frame(maxWidth: .infinity,
                                   minHeight: 3,
                                   maxHeight: d.gross2 > 0 ? max(3, CGFloat(d.gross2/maxVal)*120) : 3)
                    }
                    Text(d.abbrev)
                        .font(.system(size: 8)).foregroundStyle(.secondary)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(PM.cyan.opacity(0.6)).frame(width: 10, height: 10)
                    Text(String(year1)).font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.mint).frame(width: 10, height: 10)
                    Text(String(year2)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Price Bracket Chart

struct PriceBracketChart: View {
    let brackets: [AnalyticsView.PriceBracket]
    var maxMargin: Double { brackets.map(\.avgMargin).max() ?? 1 }
    var maxDays: Double   { brackets.map(\.avgDays).max() ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Text("Range").font(.caption2).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                Text("# Sales").font(.caption2).foregroundStyle(.secondary).frame(width: 50, alignment: .center)
                Text("Avg Margin").font(.caption2).foregroundStyle(.mint).frame(maxWidth: .infinity)
                Text("Avg Days").font(.caption2).foregroundStyle(.orange).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 10).padding(.bottom, 6)

            ForEach(brackets) { b in
                HStack(spacing: 8) {
                    Text(b.label).font(.caption).frame(width: 90, alignment: .leading)
                    Text("\(b.count)").font(.caption).monospacedDigit().frame(width: 50, alignment: .center).foregroundStyle(.secondary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 16)
                            RoundedRectangle(cornerRadius: 3).fill(Color.mint.gradient)
                                .frame(width: max(4, geo.size.width*CGFloat(b.avgMargin/max(maxMargin,1))), height: 16)
                            Text(b.avgMargin.asPercent)
                                .font(.caption2).fontWeight(.semibold).foregroundStyle(.white).padding(.leading, 6)
                        }
                    }.frame(height: 16)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 16)
                            RoundedRectangle(cornerRadius: 3).fill(Color.orange.gradient)
                                .frame(width: max(4, geo.size.width*CGFloat(b.avgDays/max(maxDays,1))), height: 16)
                            Text("\(Int(b.avgDays))d")
                                .font(.caption2).fontWeight(.semibold).foregroundStyle(.white).padding(.leading, 6)
                        }
                    }.frame(height: 16)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
            }
        }
        .padding(.vertical, 8)
        .background(PM.base.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Gallery ROI Chart

struct GalleryROIChart: View {
    let stats: [AnalyticsView.GalleryStat]
    var maxROI: Double { stats.map(\.roi).max() ?? 1 }

    var body: some View {
        VStack(spacing: 5) {
            ForEach(stats.prefix(10)) { stat in
                HStack(spacing: 8) {
                    Text(stat.name).font(.caption).lineLimit(1).frame(width: 130, alignment: .trailing)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 18)
                            RoundedRectangle(cornerRadius: 3).fill(Color.purple.gradient)
                                .frame(width: max(4, geo.size.width*CGFloat(min(stat.roi/max(maxROI,1),1))), height: 18)
                        }
                    }.frame(height: 18)
                    Text(stat.roi.asPercent).font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 55, alignment: .trailing)
                    Text("\(Int(stat.avgDays))d").font(.caption2).foregroundStyle(.secondary).frame(width: 35, alignment: .trailing)
                }
            }
            HStack {
                Spacer()
                Text("ROI %  |  Avg days to sell").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Restock Chart

struct RestockChart: View {
    let stats: [AnalyticsView.RestockStat]
    let maxValue: Double
    let valueForStat: (AnalyticsView.RestockStat) -> Double
    let labelForStat: (AnalyticsView.RestockStat) -> String

    var body: some View {
        VStack(spacing: 5) {
            ForEach(stats) { stat in
                HStack(spacing: 8) {
                    Text(stat.name).font(.caption).lineLimit(1).frame(width: 130, alignment: .trailing)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 18)
                            RoundedRectangle(cornerRadius: 3).fill(Color.indigo.gradient)
                                .frame(width: max(4, geo.size.width*CGFloat(min(valueForStat(stat)/max(maxValue,1),1))), height: 18)
                        }
                    }.frame(height: 18)
                    Text(labelForStat(stat)).font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 55, alignment: .trailing)
                    Text("\(stat.count) sold").font(.caption2).foregroundStyle(.secondary).frame(width: 45, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Day of Week Chart

struct DayOfWeekChart: View {
    let stats: [AnalyticsView.DayStat]
    var maxCount: Int { stats.map(\.count).max() ?? 1 }
    var maxGross: Double { stats.map(\.gross).max() ?? 1 }

    func barColor(_ stat: AnalyticsView.DayStat) -> Color {
        stat.name == "Saturday" || stat.name == "Sunday" ? .mint : .cyan.opacity(0.7)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(stats) { d in
                VStack(spacing: 3) {
                    Text("\(d.count)")
                        .font(.system(size: 9)).foregroundStyle(.secondary).monospacedDigit()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(d).gradient)
                        .frame(maxWidth: .infinity,
                               minHeight: 4,
                               maxHeight: max(4, CGFloat(d.count)/CGFloat(maxCount)*80))
                    Text(d.short)
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    Text(d.gross > 999 ? "$\(Int(d.gross/1000))k" : "$\(Int(d.gross))")
                        .font(.system(size: 8)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Concentration Chart

struct ConcentrationChart: View {
    let stats: [AnalyticsView.ConcentrationStat]
    let total: Double
    var top5Value: Double { stats.prefix(5).reduce(0){$0+$1.value} }
    var top5Pct: Double { total > 0 ? top5Value/total*100 : 0 }

    var top5PctString: String { String(format: "%.1f", top5Pct) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Summary bar showing top 5 vs rest
            VStack(alignment: .leading, spacing: 4) {
                Text("Top 5 artists = \(top5PctString)% of inventory value")
                    .font(.caption).foregroundStyle(.secondary)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(stats.prefix(5)) { stat in
                            let idx = stats.firstIndex(where: { $0.id == stat.id }) ?? 0
                            let barW = total > 0 ? max(4.0, geo.size.width * CGFloat(stat.pct / 100)) : 4.0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(concentrationColor(idx).gradient)
                                .frame(width: barW)
                        }
                        RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.2))
                            .frame(maxWidth: .infinity)
                    }
                }.frame(height: 10)
            }

            // Individual bars
            let maxPct = stats.map(\.pct).max() ?? 1
            ForEach(Array(stats.prefix(10).enumerated()), id: \.element.id) { idx, stat in
                HStack(spacing: 8) {
                    Text(stat.name).font(.caption).lineLimit(1).frame(width: 130, alignment: .trailing)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 16)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(concentrationColor(idx).gradient)
                                .frame(width: max(4, geo.size.width * CGFloat(min(stat.pct / max(maxPct, 1), 1))), height: 16)
                        }
                    }.frame(height: 16)
                    Text(String(format: "%.1f%%", stat.pct))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
                    Text(stat.value.asCurrency)
                        .font(.caption2).foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
                }
            }
        }
    }

    func concentrationColor(_ idx: Int) -> Color {
        let colors: [Color] = [.mint, .cyan, .blue, .indigo, .purple, .teal, .orange, .yellow, .pink, .red]
        return colors[idx % colors.count]
    }
}
// MARK: - Break-Even View

struct BreakEvenView: View {
    let store: InventoryStore

    // Rolling 90-day sell-through stats
    private var recentSales: [SaleRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        return store.sales.filter { $0.dateSold >= cutoff }
    }

    private var salesPer30Days: Double {
        guard !recentSales.isEmpty else { return 0 }
        return Double(recentSales.count) / 3.0   // 90 days / 3 = per 30 days
    }

    private var avgProfitPerSale: Double {
        guard !recentSales.isEmpty else { return 0 }
        // Net sales per sale = gross - taxes - fees (cash actually received)
        // This is what's available to recover COGS, so use it for the projection
        return recentSales.reduce(0) { $0 + $1.netSales } / Double(recentSales.count)
    }

    private var totalCostBasis: Double {
        store.items.reduce(0) { $0 + $1.totalCostComputed }
    }

    private var totalInventoryItems: Int { store.items.count }

    // How many items need to sell to cover cost basis (at avg profit per sale)
    private var itemsNeededToBreakEven: Int {
        guard avgProfitPerSale > 0 else { return 0 }
        return Int(ceil(totalCostBasis / avgProfitPerSale))
    }

    // Months to break even at current rate
    private var monthsToBreakEven: Double? {
        guard salesPer30Days > 0, avgProfitPerSale > 0 else { return nil }
        let monthsNeeded = totalCostBasis / (salesPer30Days * avgProfitPerSale)
        return monthsNeeded
    }

    private var breakEvenDate: Date? {
        guard let months = monthsToBreakEven else { return nil }
        return Calendar.current.date(byAdding: .day, value: Int(months * 30), to: Date())
    }

    private var profitGeneratedLast90: Double {
        recentSales.reduce(0) { $0 + $1.netSales }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Key metrics row
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                BreakEvenCard(
                    label: "Cost Basis Remaining",
                    value: totalCostBasis.asCurrency,
                    icon: "cart.fill",
                    color: .orange
                )
                BreakEvenCard(
                    label: "Items to Sell",
                    value: avgProfitPerSale > 0 ? "~\(itemsNeededToBreakEven)" : "—",
                    icon: "tag.fill",
                    color: .blue,
                    sub: "at avg \(avgProfitPerSale.asCurrency) net sales/item"
                )
                BreakEvenCard(
                    label: "Estimated Date",
                    value: breakEvenDate.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .none) } ?? "—",
                    icon: "calendar",
                    color: .mint,
                    sub: monthsToBreakEven.map { String(format: "~%.0f months away", $0) }
                )
            }

            Divider()

            // Sell-through rate stats
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sell-Through Rate").font(.caption).foregroundStyle(.secondary)
                    Text(salesPer30Days > 0 ? String(format: "%.1f items/month", salesPer30Days) : "No recent data")
                        .font(.subheadline).fontWeight(.semibold)
                    Text("Based on last 90 days (\(recentSales.count) sales)")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Divider().frame(height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Net Sales Last 90 Days").font(.caption).foregroundStyle(.secondary)
                    Text(profitGeneratedLast90.asCurrency)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(profitGeneratedLast90 >= 0 ? .green : .red)
                    Text(String(format: "%.0f%% of remaining cost basis", totalCostBasis > 0 ? profitGeneratedLast90 / totalCostBasis * 100 : 0))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Divider().frame(height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Current Inventory").font(.caption).foregroundStyle(.secondary)
                    Text("\(totalInventoryItems) items")
                        .font(.subheadline).fontWeight(.semibold)
                    Text(totalCostBasis.asCurrency + " total cost")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            // Progress bar: Net Sales (Gross - Taxes - Fees) vs Total COGS (sold + unsold)
            // This answers "have I gotten my money back?" — cash in vs cash out, excluding profit margin
            let allTimeNetSales  = store.sales.reduce(0) { $0 + $1.netSales }   // Gross - Taxes - Fees
            let allTimeCOGSSold  = store.sales.reduce(0) { $0 + $1.totalCost }  // COGS on sold items
            let allTimeCOGSTotal = allTimeCOGSSold + totalCostBasis              // + unsold inventory cost
            let recoveredPct     = allTimeCOGSTotal > 0 ? min(allTimeNetSales / allTimeCOGSTotal, 1.0) : 0.0
            let stillNeeded      = max(0, allTimeCOGSTotal - allTimeNetSales)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("All-Time Cost Recovery")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", recoveredPct * 100))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(recoveredPct >= 1.0 ? .green : .orange)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(PM.raised).frame(height: 10)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(recoveredPct >= 1.0 ? Color.green.gradient : Color.orange.gradient)
                            .frame(width: max(4, geo.size.width * CGFloat(recoveredPct)), height: 10)
                    }
                }.frame(height: 10)
                Text(recoveredPct >= 1.0
                    ? "✓ Net sales have fully recovered your total cost basis"
                    : String(format: "%@ more in net sales needed to recover all COGS", stillNeeded.asCurrency))
                    .font(.caption2).foregroundStyle(.tertiary)
                Text("Net Sales ÷ Total COGS (sold + unsold inventory)")
                    .font(.caption2).foregroundStyle(PM.textTertiary)
            }

            if recentSales.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
                    Text("No sales in the last 90 days — projections unavailable. Sell-through rate will appear once recent sales are recorded.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct BreakEvenCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    var sub: String? = nil

    init(label: String, value: String, icon: String, color: Color, sub: String? = nil) {
        self.label = label; self.value = value; self.icon = icon; self.color = color; self.sub = sub
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundStyle(color)
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(value)
                .font(.title3).fontWeight(.bold)
                .foregroundStyle(color)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if let sub {
                Text(sub).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - CCP Section (standalone view so @Observable array changes re-render counts correctly)

struct CCPSection: View {
    let items: [InventoryItem]
    let sales: [SaleRecord]

    private var inv:  [InventoryItem] { items.filter { $0.tags.uppercased().contains("CCP") } }
    private var sold: [SaleRecord]    { sales.filter { $0.tags.uppercased().contains("CCP") } }

    private var totalPurchased: Int    { inv.count + sold.count }
    private var totalSpent: Double     { inv.reduce(0){$0+$1.totalCostComputed} + sold.reduce(0){$0+$1.totalCost} }
    private var outstandingCost: Double{ inv.reduce(0){$0+$1.totalCostComputed} }
    private var netSales: Double       { sold.reduce(0){$0+$1.netSales} }
    private var profit: Double         { sold.reduce(0){$0+$1.profit} }
    private var outstandingValue: Double{ inv.reduce(0){$0+$1.shopifyPrice} }
    private var unrealizedProfit: Double{ outstandingValue - outstandingCost }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle("Cult Classic Prints (CCP)")
                Text("Private commission tracking — cost & return analysis")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                AnalyticCard(label: "Total Purchased",  value: "\(totalPurchased)",          icon: "shippingbox.fill",            color: .blue)
                AnalyticCard(label: "Sold",             value: "\(sold.count)",              icon: "checkmark.circle.fill",       color: .green)
                AnalyticCard(label: "In Inventory",     value: "\(inv.count)",               icon: "archivebox.fill",             color: .orange)
                AnalyticCard(label: "Total Spent",      value: totalSpent.asCurrency,        icon: "cart.badge.minus",            color: .red)
                AnalyticCard(label: "Net Sales",        value: netSales.asCurrency,          icon: "dollarsign.circle.fill",      color: .mint)
                AnalyticCard(label: "Profit on Sold",   value: profit.asCurrency,            icon: "chart.line.uptrend.xyaxis",   color: .green)
                AnalyticCard(label: "Outstanding Cost", value: outstandingCost.asCurrency,   icon: "exclamationmark.circle.fill", color: .yellow)
                AnalyticCard(label: "Outstanding Value",value: outstandingValue.asCurrency,  icon: "tag.fill",                   color: .teal)
                AnalyticCard(label: "Unrealised Profit",value: unrealizedProfit.asCurrency,  icon: "chart.bar.fill",             color: .purple)
            }
        }
        .padding(16)
        .pmCard(fill: PM.card, radius: PM.Radius.lg)
    }
}

// MARK: - Rolling Actual Chart

struct RollingActualChart: View {
    let windows: [AnalyticsView.RollingWindow]
    let maxValue: Double
    let valueForWindow: (AnalyticsView.RollingWindow) -> Double
    let labelForValue: (Double) -> String
    let metric: AnalyticsView.RollingMetric

    var body: some View {
        VStack(spacing: 5) {
            ForEach(windows) { w in
                let v = valueForWindow(w)
                HStack(spacing: 8) {
                    Text(w.label)
                        .font(.caption).monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 20)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(PM.cyan.gradient)
                                .frame(width: max(4, geo.size.width * CGFloat(v / max(maxValue, 1))), height: 20)
                        }
                    }.frame(height: 20)
                    Text(labelForValue(v))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.primary)
                        .frame(width: 80, alignment: .trailing)
                    // Prints count alongside $$ for context when in $$ mode
                    if metric != .prints {
                        Text("\(w.count) sold")
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Rolling Forecast Chart

struct RollingForecastChart: View {
    let windows: [AnalyticsView.ForecastWindow]
    let maxValue: Double
    let valueForWindow: (AnalyticsView.ForecastWindow) -> Double
    let labelForValue: (Double) -> String
    let metric: AnalyticsView.RollingMetric

    var body: some View {
        VStack(spacing: 5) {
            ForEach(windows) { w in
                let v = valueForWindow(w)
                HStack(spacing: 8) {
                    Text(w.label)
                        .font(.caption).monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(PM.raised).frame(height: 20)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.purple.opacity(0.85), Color.indigo.opacity(0.7)],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * CGFloat(v / max(maxValue, 1))), height: 20)
                        }
                    }.frame(height: 20)
                    Text("~\(labelForValue(v))")
                        .font(.caption).monospacedDigit().italic()
                        .foregroundStyle(.purple)
                        .frame(width: 88, alignment: .trailing)
                    if metric != .prints {
                        Text("~\(String(format: "%.0f", w.count)) sold")
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
            HStack {
                Spacer()
                Text("~ = projected estimate")
                    .font(.caption2).foregroundStyle(PM.textTertiary).italic()
            }
        }
    }
}
