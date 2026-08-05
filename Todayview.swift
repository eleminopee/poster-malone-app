import SwiftUI

// ============================================================================
// TodayView.swift — SESSION 5
// The morning cockpit. Opens by default (PMRouter.isShowingToday = true).
// Action cards show live counts and deep-link into filtered destinations;
// a week snapshot and the recent paper trail give an at-a-glance pulse.
//
// All counts read the store's precomputed derived sets (Session 3) or cheap
// local reductions — nothing heavy runs in this body.
// ============================================================================

struct TodayView: View {
    @Environment(InventoryStore.self) var store
    @Environment(PMRouter.self) var router

    // MARK: Derived counts (cheap — store sets are precomputed)

    private var needsListing: Int { store.needsListingItems.count }
    private var noDescription: Int { store.noDescriptionItems.count }
    private var longTitle: Int { store.longTitleItems.count }
    private var notOnShopify: Int { store.ebayNotShopifyItems.count }
    private var notOnShopifyValue: Double { store.ebayNotShopifyValue }
    private var needsPhotos: Int { store.needsPhotosItems.count }
    private var needsShopifyCopy: Int { store.needsShopifyCopyItems.count }

    /// Sold records with no financials entered yet (gross == 0).
    private var missingFinancials: Int {
        store.sales.lazy.filter { $0.grossSales == 0 }.count
    }

    /// IG posts due today or earlier, still pending.
    private var igDueToday: Int {
        let endOfToday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        return store.igQueue.lazy.filter {
            $0.status == .pending && $0.scheduledDate < endOfToday
        }.count
    }

    /// Items held 365+ days (deep stale) for the alert card.
    private var deepStale: Int {
        store.items.lazy.filter {
            $0.status != .sold && $0.datePurchased != nil && $0.daysSincePurchase >= 365
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PM.Space.xl) {

                header

                // ── Action cards ─────────────────────────────────────────
                Text("NEEDS ATTENTION")
                    .font(.pmBody(size: 11, weight: .semibold))
                    .foregroundStyle(PM.textTertiary)
                    .tracking(1.5)

                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 14)
                ], spacing: 14) {
                    if needsListing > 0 {
                        TodayActionCard(
                            icon: "tray.and.arrow.up.fill", tint: .orange,
                            count: needsListing, title: "Needs Listing",
                            subtitle: "Processed, no active eBay listing"
                        ) { router.openInventory(.needsListing) }
                    }
                    if notOnShopify > 0 {
                        TodayActionCard(
                            icon: "bag.badge.plus", tint: PM.cyan,
                            count: notOnShopify, title: "Not on Shopify",
                            subtitle: "On eBay only · \(notOnShopifyValue.asCurrency) to add"
                        ) { router.openInventory(.notOnShopify) }
                    }
                    if needsPhotos > 0 {
                        TodayActionCard(
                            icon: "photo.badge.plus", tint: .yellow,
                            count: needsPhotos, title: "Needs Photos",
                            subtitle: "Blocks listing, Shopify, and IG"
                        ) { router.openInventory(.needsPhotos) }
                    }
                    if needsShopifyCopy > 0 {
                        TodayActionCard(
                            icon: "text.badge.plus", tint: PM.pink,
                            count: needsShopifyCopy, title: "Needs Shopify Copy",
                            subtitle: "Missing Shopify title or description"
                        ) { router.openInventory(.needsShopifyCopy) }
                    }
                    if missingFinancials > 0 {
                        TodayActionCard(
                            icon: "dollarsign.circle.fill", tint: PM.cyan,
                            count: missingFinancials, title: "Missing Financials",
                            subtitle: "Sold items with no sale price entered"
                        ) { router.openSales(.missingFinancials) }
                    }
                    if noDescription > 0 {
                        TodayActionCard(
                            icon: "text.append", tint: .purple,
                            count: noDescription, title: "No Description",
                            subtitle: "Items missing an eBay description"
                        ) { router.openInventory(.noDescription) }
                    }
                    if igDueToday > 0 {
                        TodayActionCard(
                            icon: "camera.badge.clock", tint: PM.pink,
                            count: igDueToday, title: "Instagram Due",
                            subtitle: "Queued posts ready to publish"
                        ) { router.go(.instagramAutomation) }
                    }
                    if longTitle > 0 {
                        TodayActionCard(
                            icon: "textformat.size", tint: .red,
                            count: longTitle, title: "Long eBay Titles",
                            subtitle: "Over the 80-character limit"
                        ) { router.openInventory(.longTitle) }
                    }
                    if deepStale > 0 {
                        TodayActionCard(
                            icon: "clock.badge.exclamationmark.fill", tint: .orange,
                            count: deepStale, title: "Stale 1yr+",
                            subtitle: "Held over a year — review pricing"
                        ) { router.openInventory(.oldest) }
                    }
                }

                // All-clear state
                if needsListing == 0 && missingFinancials == 0 && noDescription == 0
                    && igDueToday == 0 && longTitle == 0 && deepStale == 0
                    && notOnShopify == 0 && needsPhotos == 0 && needsShopifyCopy == 0 {
                    allClear
                }

                weekSnapshot

                recentActivity

                // Quick link to the books — Tier 2
                Button {
                    router.goExpenses()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.below.ecg")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PM.cyan)
                        Text("Expenses & Tax Summary")
                            .font(.pmBody(size: 14, weight: .medium))
                            .foregroundStyle(PM.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(PM.textTertiary)
                    }
                    .padding(PM.Space.md)
                    .pmCard(fill: PM.card, radius: PM.Radius.lg)
                }
                .buttonStyle(.plain)
            }
            .padding(PM.Space.xl)
        }
        .pmScreen()
        .navigationTitle("Today")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.pmDisplay(size: 30))
                .foregroundStyle(PM.textPrimary)
            Text(Date().formatted(date: .complete, time: .omitted))
                .font(.pmBody(size: 14))
                .foregroundStyle(PM.textSecondary)
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 0..<12:  return "GOOD MORNING"
        case 12..<17: return "GOOD AFTERNOON"
        default:      return "GOOD EVENING"
        }
    }

    // MARK: - All-clear

    private var allClear: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22))
                .foregroundStyle(.green)
                .pmGlow(.green, radius: 6, opacity: 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text("All caught up")
                    .font(.pmDisplay(size: 18))
                    .foregroundStyle(PM.textPrimary)
                Text("Nothing needs attention right now.")
                    .font(.pmBody(size: 13))
                    .foregroundStyle(PM.textSecondary)
            }
            Spacer()
        }
        .padding(PM.Space.lg)
        .pmCard(fill: PM.card, radius: PM.Radius.lg, border: Color.green.opacity(0.25))
    }

    // MARK: - Week Snapshot

    private var weekSnapshot: some View {
        let cal = Calendar.current
        let now = Date()
        let weekStart  = cal.date(byAdding: .day, value: -7,  to: now)!
        let prevStart  = cal.date(byAdding: .day, value: -14, to: now)!
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!

        let thisWeek = store.sales.filter { $0.dateSold >= weekStart }
        let prevWeek = store.sales.filter { $0.dateSold >= prevStart && $0.dateSold < weekStart }
        let monthSales = store.sales.filter { $0.dateSold >= monthStart }

        let thisWeekGross = thisWeek.reduce(0) { $0 + $1.grossSales }
        let prevWeekGross = prevWeek.reduce(0) { $0 + $1.grossSales }
        let monthGross    = monthSales.reduce(0) { $0 + $1.grossSales }
        let monthProfit   = monthSales.reduce(0) { $0 + $1.profit }

        let delta: Double = prevWeekGross > 0
            ? (thisWeekGross - prevWeekGross) / prevWeekGross * 100
            : (thisWeekGross > 0 ? 100 : 0)

        return VStack(alignment: .leading, spacing: PM.Space.sm) {
            Text("THIS WEEK")
                .font(.pmBody(size: 11, weight: .semibold))
                .foregroundStyle(PM.textTertiary)
                .tracking(1.5)

            HStack(spacing: 14) {
                TodayStat(label: "Sales (7d)", value: "\(thisWeek.count)", tint: PM.cyan)
                TodayStat(label: "Gross (7d)", value: thisWeekGross.asCurrency, tint: PM.cyan)
                TodayStat(
                    label: "vs Prev Week",
                    value: (delta >= 0 ? "+" : "") + String(format: "%.0f%%", delta),
                    tint: delta >= 0 ? .green : .red
                )
                TodayStat(label: "Month Gross", value: monthGross.asCurrency, tint: PM.cyan)
                TodayStat(
                    label: "Month Profit", value: monthProfit.asCurrency,
                    tint: monthProfit >= 0 ? .green : .red
                )
            }
        }
    }

    // MARK: - Recent Activity

    private var recentActivity: some View {
        let recent = Array(store.paperTrail.prefix(8))
        return VStack(alignment: .leading, spacing: PM.Space.sm) {
            HStack {
                Text("RECENT ACTIVITY")
                    .font(.pmBody(size: 11, weight: .semibold))
                    .foregroundStyle(PM.textTertiary)
                    .tracking(1.5)
                Spacer()
                Button("View All") { router.go(.paperTrail) }
                    .buttonStyle(.plain)
                    .font(.pmBody(size: 12, weight: .medium))
                    .foregroundStyle(PM.cyan)
            }

            if recent.isEmpty {
                Text("No activity logged yet.")
                    .font(.pmBody(size: 13))
                    .foregroundStyle(PM.textTertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(recent) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: entry.action.icon)
                                .font(.system(size: 12))
                                .foregroundStyle(entry.action.color)
                                .frame(width: 18)
                            Text(entry.action.rawValue)
                                .font(.pmBody(size: 12, weight: .medium))
                                .foregroundStyle(PM.textSecondary)
                                .frame(width: 120, alignment: .leading)
                            Text(entry.title)
                                .font(.pmBody(size: 13))
                                .foregroundStyle(PM.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(entry.date.formatted(.relative(presentation: .named)))
                                .font(.pmBody(size: 11))
                                .foregroundStyle(PM.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        if entry.id != recent.last?.id {
                            Rectangle().fill(PM.borderSubtle).frame(height: 1).padding(.leading, 12)
                        }
                    }
                }
                .pmCard(fill: PM.card, radius: PM.Radius.lg)
            }
        }
    }
}

// MARK: - Action Card

struct TodayActionCard: View {
    let icon: String
    let tint: Color
    let count: Int
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                            .strokeBorder(tint.opacity(0.30), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(count)")
                            .font(.pmDisplay(size: 24))
                            .foregroundStyle(PM.textPrimary)
                            .monospacedDigit()
                        Text(title)
                            .font(.pmBody(size: 14, weight: .semibold))
                            .foregroundStyle(PM.textPrimary)
                    }
                    Text(subtitle)
                        .font(.pmBody(size: 12))
                        .foregroundStyle(PM.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(hovering ? tint : PM.textTertiary)
            }
            .padding(PM.Space.md)
            .pmCard(
                fill: hovering ? PM.raised : PM.card,
                radius: PM.Radius.lg,
                border: hovering ? tint.opacity(0.35) : PM.borderSubtle
            )
            .pmGlow(tint, radius: hovering ? 8 : 0, opacity: hovering ? 0.18 : 0)
        }
        .buttonStyle(.plain)
        .onHover { isIn in
            withAnimation(PM.Anim.hover) { hovering = isIn }
        }
        .help("\(count) \(title) — tap to open")
    }
}

// MARK: - Stat pill

struct TodayStat: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.pmDisplay(size: 20))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
                .pmGlow(tint, radius: 5, opacity: 0.25)
            Text(label)
                .font(.pmBody(size: 11, weight: .medium))
                .foregroundStyle(PM.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PM.Space.md)
        .padding(.vertical, PM.Space.sm + 2)
        .pmCard(fill: PM.card, radius: PM.Radius.md)
    }
}
