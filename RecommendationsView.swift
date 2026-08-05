import SwiftUI

// MARK: - Recommendations View

struct RecommendationsView: View {
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials

    private var recStore: RecommendationsStore { RecommendationsStore.shared }

    // Convenience accessors
    var recommendations: [Recommendation] { recStore.recommendations }
    var isLoading: Bool                   { recStore.isLoading }
    var errorMessage: String?             { recStore.errorMessage }
    var lastGenerated: Date?              { recStore.lastGenerated }

    struct Recommendation: Identifiable {
        let id = UUID()
        let category: Category
        let title: String
        let insight: String
        let action: String
        let priority: Priority

        enum Category: String {
            case buying      = "Buying"
            case pricing     = "Pricing"
            case inventory   = "Inventory"
            case performance = "Performance"
            case risk        = "Risk"
            case timing      = "Timing"

            var icon: String {
                switch self {
                case .buying:      return "cart.badge.plus"
                case .pricing:     return "tag.fill"
                case .inventory:   return "archivebox.fill"
                case .performance: return "chart.line.uptrend.xyaxis"
                case .risk:        return "exclamationmark.triangle.fill"
                case .timing:      return "clock.fill"
                }
            }

            var color: Color {
                switch self {
                case .buying:      return .mint
                case .pricing:     return .orange
                case .inventory:   return .blue
                case .performance: return .green
                case .risk:        return .red
                case .timing:      return .purple
                }
            }
        }

        enum Priority: String {
            case high   = "High"
            case medium = "Medium"
            case low    = "Low"

            var color: Color {
                switch self {
                case .high:   return .red
                case .medium: return .orange
                case .low:    return .secondary
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Business Insights")
                        .font(.headline).fontWeight(.semibold)
                    if let last = lastGenerated {
                        Text("Generated \(last.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Powered by Claude — analyzes your real inventory & sales data")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    Task { await generateRecommendations() }
                } label: {
                    if isLoading {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Analyzing...").font(.subheadline)
                        }
                    } else {
                        Label(recommendations.isEmpty ? "Generate Insights" : "Refresh",
                              systemImage: recommendations.isEmpty ? "sparkles" : "arrow.clockwise")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || credentials.anthropicKey.isEmpty)
            }
            .padding(16)
            .background(.bar)

            Divider()

            if credentials.anthropicKey.isEmpty {
                ContentUnavailableView {
                    Label("Anthropic API Key Required", systemImage: "key.fill")
                } description: {
                    Text("Add your Anthropic API key in Admin → Credentials to enable AI insights.")
                }
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle).foregroundStyle(.orange)
                    Text(error)
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") { Task { await generateRecommendations() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else if recommendations.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No Insights Yet", systemImage: "sparkles")
                } description: {
                    Text("Tap Generate Insights to get personalized business recommendations based on your inventory and sales history.")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Priority summary bar
                        if !recommendations.isEmpty {
                            prioritySummaryBar
                        }

                        ForEach(recommendations) { rec in
                            RecommendationCard(rec: rec)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Recommendations")
    }

    // MARK: - Priority Summary

    var prioritySummaryBar: some View {
        let high   = recommendations.filter { $0.priority == .high   }.count
        let medium = recommendations.filter { $0.priority == .medium }.count
        let low    = recommendations.filter { $0.priority == .low    }.count

        return HStack(spacing: 12) {
            PriorityStat(count: high,   label: "High Priority",   color: .red)
            PriorityStat(count: medium, label: "Medium Priority", color: .orange)
            PriorityStat(count: low,    label: "Low Priority",    color: .secondary)
            Spacer()
            Text("\(recommendations.count) total insights")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Data Snapshot Builder

    private func buildDataSnapshot() -> String {
        // All-time financials
        let totalSales   = store.sales.count
        let totalGross   = store.sales.reduce(0.0) { $0 + $1.grossSales }
        let totalProfit  = store.sales.reduce(0.0) { $0 + $1.profit }
        let avgMargin    = store.sales.isEmpty ? 0 : store.sales.reduce(0.0){$0+$1.profitLossPercent}/Double(store.sales.count)
        let avgDays      = { () -> Double in
            let v = store.sales.filter { $0.daysToSell > 0 }
            return v.isEmpty ? 0 : Double(v.reduce(0){$0+$1.daysToSell})/Double(v.count)
        }()

        // Inventory
        let invCount  = store.items.count
        let invValue  = store.items.reduce(0.0){$0+$1.shopifyPrice}
        let invCost   = store.items.reduce(0.0){$0+$1.totalCostComputed}

        // Age buckets
        let cal = Calendar.current
        func daysHeld(_ item: InventoryItem) -> Int {
            guard let p = item.datePurchased else { return 0 }
            return max(0, cal.dateComponents([.day], from: p, to: Date()).day ?? 0)
        }
        let over180  = store.items.filter { daysHeld($0) > 180 }.count
        let over365  = store.items.filter { daysHeld($0) > 365 }.count

        // Top artists by profit
        var artistData: [String: (profit: Double, cost: Double, count: Int, days: [Int])] = [:]
        for s in store.sales where !s.artist.isEmpty && s.totalCost > 0 {
            let ex = artistData[s.artist] ?? (0,0,0,[])
            artistData[s.artist] = (ex.profit+s.profit, ex.cost+s.totalCost, ex.count+1,
                                    s.daysToSell > 0 ? ex.days+[s.daysToSell] : ex.days)
        }
        // Top artists by profit — explicit loop to help compiler
        struct ArtistEntry {
            let name: String; let profit: Double; let roi: Double; let count: Int; let avgDays: Double
        }
        var artistEntries: [ArtistEntry] = []
        for (name, d) in artistData where d.count >= 3 && d.cost > 0 {
            let roi     = d.profit / d.cost * 100
            let avgDays = d.days.isEmpty ? 0.0 : Double(d.days.reduce(0, +)) / Double(d.days.count)
            artistEntries.append(ArtistEntry(name: name, profit: d.profit, roi: roi, count: d.count, avgDays: avgDays))
        }
        let topArtists = artistEntries.sorted { $0.profit > $1.profit }.prefix(10)

        // Restock score (roi / avg days) — broken into loop to help compiler
        struct RestockEntry {
            let name: String; let roi: Double; let avgDays: Double; let count: Int; let score: Double
        }
        var restockEntries: [RestockEntry] = []
        for (name, d) in artistData where d.count >= 5 && d.cost > 0 {
            let roi     = d.profit / d.cost * 100
            let avgDays = d.days.isEmpty ? 999.0 : Double(d.days.reduce(0, +)) / Double(d.days.count)
            let score   = roi / max(avgDays, 1) * 100
            restockEntries.append(RestockEntry(name: name, roi: roi, avgDays: avgDays, count: d.count, score: score))
        }
        let restockTop = restockEntries.sorted { $0.score > $1.score }.prefix(8)

        // Gallery ROI
        var galleryData: [String: (profit: Double, cost: Double, count: Int)] = [:]
        for s in store.sales where !s.gallery.isEmpty && s.totalCost > 0 {
            let ex = galleryData[s.gallery] ?? (0,0,0)
            galleryData[s.gallery] = (ex.profit+s.profit, ex.cost+s.totalCost, ex.count+1)
        }
        let topGalleries = galleryData.filter { $0.value.count >= 3 }
            .map { (name: $0.key, roi: $0.value.cost > 0 ? $0.value.profit/$0.value.cost*100 : 0, count: $0.value.count) }
            .sorted { $0.roi > $1.roi }.prefix(8)

        // Price brackets
        let brackets: [(String, Double, Double)] = [("Under $50",0,50),("$50-100",50,100),("$100-200",100,200),("$200+",200,99999)]
        let bracketStats = brackets.map { label, lo, hi -> String in
            let b = store.sales.filter { $0.grossSales >= lo && $0.grossSales < hi && $0.daysToSell > 0 }
            let avgD = b.isEmpty ? 0 : Double(b.reduce(0){$0+$1.daysToSell})/Double(b.count)
            let avgM = b.isEmpty ? 0 : b.compactMap { $0.totalCost > 0 ? $0.profitLossPercent : nil }.reduce(0,+)/Double(b.count)
            return "\(label): \(b.count) sales, avg \(Int(avgD)) days to sell, avg \(String(format:"%.0f",avgM))% margin"
        }

        // Theme performance
        var themeData: [String: (gross: Double, count: Int)] = [:]
        for s in store.sales where !s.theme.isEmpty {
            let ex = themeData[s.theme] ?? (0,0)
            themeData[s.theme] = (ex.gross+s.grossSales, ex.count+1)
        }
        let topThemes = themeData.sorted { $0.value.count > $1.value.count }.prefix(8)

        // Print type in inventory vs sold
        var ptSold: [String: Int] = [:]
        var ptInv: [String: Int] = [:]
        for s in store.sales where !s.printType.isEmpty { ptSold[s.printType, default: 0] += 1 }
        for i in store.items  where !i.printType.isEmpty { ptInv[i.printType,  default: 0] += 1 }

        // Day of week
        let dowFmt = DateFormatter(); dowFmt.dateFormat = "EEEE"
        var dowData: [String: Int] = [:]
        for s in store.sales { dowData[dowFmt.string(from: s.dateSold), default: 0] += 1 }

        // CCP
        let ccpInv  = store.items.filter { $0.tags.uppercased().contains("CCP") }
        let ccpSold = store.sales.filter { $0.tags.uppercased().contains("CCP") }
        let ccpROI  = ccpSold.reduce(0.0){$0+$1.totalCost} > 0 ?
            ccpSold.reduce(0.0){$0+$1.profit} / ccpSold.reduce(0.0){$0+$1.totalCost} * 100 : 0

        // YoY
        let thisYear = cal.component(.year, from: Date())
        let lastYear = thisYear - 1
        let thisYrGross = store.sales.filter { cal.component(.year, from: $0.dateSold) == thisYear }.reduce(0.0){$0+$1.grossSales}
        let lastYrGross = store.sales.filter { cal.component(.year, from: $0.dateSold) == lastYear }.reduce(0.0){$0+$1.grossSales}

        // Stale inventory (expensive items over 365 days)
        let staleExpensive = store.items
            .filter { daysHeld($0) > 365 && $0.shopifyPrice > 100 }
            .sorted { $0.shopifyPrice > $1.shopifyPrice }
            .prefix(5)
            .map { "\($0.artist) - \($0.title) (\($0.size), \($0.shopifyPrice.asCurrency), \(daysHeld($0)) days)" }

        return """
        POSTER MALONE BUSINESS DATA SNAPSHOT
        =====================================

        ALL-TIME PERFORMANCE:
        - Total sales: \(totalSales)
        - Gross revenue: \(totalGross.asCurrency)
        - Total profit: \(totalProfit.asCurrency)
        - Avg margin: \(String(format:"%.1f",avgMargin))%
        - Avg days to sell: \(Int(avgDays))

        CURRENT INVENTORY:
        - Items in stock: \(invCount)
        - Total listed value: \(invValue.asCurrency)
        - Total cost basis: \(invCost.asCurrency)
        - Potential profit if all sold: \((invValue-invCost).asCurrency)
        - Items over 180 days old: \(over180) (\(invCount > 0 ? Int(Double(over180)/Double(invCount)*100) : 0)%)
        - Items over 365 days old: \(over365)

        YEAR-OVER-YEAR:
        - \(lastYear) gross: \(lastYrGross.asCurrency)
        - \(thisYear) gross to date: \(thisYrGross.asCurrency)

        TOP 10 ARTISTS BY TOTAL PROFIT:
        \(topArtists.map { "- \($0.name): \($0.profit.asCurrency) profit, ROI \(String(format:"%.0f",$0.roi))%, \($0.count) sold, avg \(Int($0.avgDays)) days" }.joined(separator: "\n"))

        BEST ARTISTS TO RESTOCK (score = ROI / avg days held):
        \(restockTop.map { "- \($0.name): score \(String(format:"%.0f",$0.score)), ROI \(String(format:"%.0f",$0.roi))%, avg \(Int($0.avgDays)) days, \($0.count) sold" }.joined(separator: "\n"))

        GALLERY ROI (min 3 sales):
        \(topGalleries.map { "- \($0.name): \(String(format:"%.0f",$0.roi))% ROI, \($0.count) sales" }.joined(separator: "\n"))

        PRICE vs VELOCITY:
        \(bracketStats.joined(separator: "\n"))

        TOP THEMES BY VOLUME:
        \(topThemes.map { "- \($0.key): \($0.value.count) sales, \($0.value.gross.asCurrency) gross" }.joined(separator: "\n"))

        PRINT TYPE (sold vs in inventory):
        \(Set(Array(ptSold.keys)+Array(ptInv.keys)).map { "- \($0): \(ptSold[$0] ?? 0) sold, \(ptInv[$0] ?? 0) in stock" }.sorted().joined(separator: "\n"))

        SALES BY DAY OF WEEK:
        \(["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"].compactMap { d in dowData[d].map { "- \(d): \($0) sales" } }.joined(separator: "\n"))

        CCP (CULT CLASSIC PRINTS):
        - In inventory: \(ccpInv.count), outstanding cost: \(ccpInv.reduce(0.0){$0+$1.totalCostComputed}.asCurrency)
        - Sold: \(ccpSold.count), ROI on sold: \(String(format:"%.0f",ccpROI))%

        STALE HIGH-VALUE INVENTORY (>1yr, >$100):
        \(staleExpensive.isEmpty ? "None" : staleExpensive.joined(separator: "\n"))
        """
    }

    // MARK: - Generate Recommendations

    private func generateRecommendations() async {
        recStore.isLoading = true
        recStore.errorMessage = nil
        recStore.recommendations = []

        let snapshot = buildDataSnapshot()

        let prompt = """
        You are a business analyst for Poster Malone, an alternative movie poster reselling business on eBay and Shopify. Analyze this real business data and provide 8-12 specific, actionable recommendations.

        \(snapshot)

        Return ONLY a JSON array with this exact structure, no other text:
        [
          {
            "category": "Buying|Pricing|Inventory|Performance|Risk|Timing",
            "priority": "High|Medium|Low",
            "title": "Short title (max 8 words)",
            "insight": "2-3 sentences explaining what the data shows and why it matters.",
            "action": "1-2 sentences of the specific action to take."
          }
        ]

        Guidelines:
        - Reference specific artists, numbers, and percentages from the data — never be generic
        - Buying: which artists/galleries to prioritize at next drop based on ROI and velocity
        - Pricing: are items under/overpriced based on bracket analysis and stale inventory
        - Inventory: which specific items to discount or promote to clear stale stock
        - Timing: when to list based on day-of-week data
        - Risk: any concerning patterns like concentration or slow movers
        - Performance: what's working well and should be doubled down on
        - Be direct and numerical — "KWow has 125% ROI at 59 days" not "some artists perform well"
        """

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json",    forHTTPHeaderField: "Content-Type")
        request.setValue(credentials.anthropicKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",          forHTTPHeaderField: "anthropic-version")

        guard let body = try? JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-4-6",
            "max_tokens": 3000,
            "messages": [["role": "user", "content": prompt]]
        ]) else {
            recStore.errorMessage = "Failed to build request"
            recStore.isLoading = false
            return
        }
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                recStore.errorMessage = "API error (HTTP \(status)) — check your Anthropic API key in Admin"
                recStore.isLoading = false
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = (json["content"] as? [[String: Any]])?.first,
                  let text = content["text"] as? String else {
                recStore.errorMessage = "Unexpected API response format"
                recStore.isLoading = false
                return
            }

            let cleaned = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let jsonData = cleaned.data(using: .utf8),
                  let array = try JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                recStore.errorMessage = "Could not parse AI response. Try again."
                recStore.isLoading = false
                return
            }

            recStore.recommendations = array.compactMap { parseRecommendation($0) }
                .sorted { priorityOrder($0.priority) < priorityOrder($1.priority) }
            recStore.lastGenerated = Date()

        } catch {
            recStore.errorMessage = "Network error: \(error.localizedDescription)"
        }

        recStore.isLoading = false
    }

    private func parseRecommendation(_ dict: [String: Any]) -> Recommendation? {
        guard let title   = dict["title"]   as? String,
              let insight = dict["insight"] as? String,
              let action  = dict["action"]  as? String else { return nil }

        let categoryStr = dict["category"] as? String ?? "Performance"
        let priorityStr = dict["priority"] as? String ?? "Medium"

        let category: Recommendation.Category = switch categoryStr {
            case "Buying":      .buying
            case "Pricing":     .pricing
            case "Inventory":   .inventory
            case "Risk":        .risk
            case "Timing":      .timing
            default:            .performance
        }
        let priority: Recommendation.Priority = switch priorityStr {
            case "High": .high
            case "Low":  .low
            default:     .medium
        }

        return Recommendation(category: category, title: title,
                              insight: insight, action: action, priority: priority)
    }

    private func priorityOrder(_ p: Recommendation.Priority) -> Int {
        switch p { case .high: return 0; case .medium: return 1; case .low: return 2 }
    }
}

// MARK: - Recommendation Card

struct RecommendationCard: View {
    let rec: RecommendationsView.Recommendation
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    // Category icon
                    Image(systemName: rec.category.icon)
                        .font(.subheadline)
                        .foregroundStyle(rec.category.color)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(rec.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 6) {
                            Text(rec.category.rawValue)
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(rec.category.color.opacity(0.15))
                                .foregroundStyle(rec.category.color)
                                .clipShape(Capsule())
                            Text(rec.priority.rawValue + " Priority")
                                .font(.caption2)
                                .foregroundStyle(rec.priority.color)
                        }
                    }

                    Spacer()

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // Expanded content
            if expanded {
                Divider().padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 10) {
                    // Insight
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Insight", systemImage: "lightbulb.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.yellow)
                        Text(rec.insight)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    // Action
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Recommended Action", systemImage: "arrow.right.circle.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.mint)
                        Text(rec.action)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .padding(.top, 4)
            }
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(expanded ? rec.category.color.opacity(0.3) : .clear, lineWidth: 1)
        )
    }
}

// MARK: - Supporting Views

struct PriorityStat: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count) \(label)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
