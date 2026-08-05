import SwiftUI

// ============================================================================
// SidebarView.swift — Poster Malone command rail
// Wordmark on top, nav with pink active glow, quick stats as glowing tiles,
// orange "needs listing" badge preserved, pulsing last-saved indicator.
// Native List(selection:) is kept so arrow-key navigation still works.
// ============================================================================

struct SidebarView: View {
    @Environment(InventoryStore.self) var store
    @Environment(PMRouter.self) var router

    // SESSION 3 (audit #7): reads the store's precomputed set.
    var needsListingCount: Int {
        store.needsListingItems.count
    }

    var body: some View {
        List {
            // SESSION 5: Today cockpit entry, above the section menu.
            Section {
                SidebarTodayRow(isSelected: router.isShowingToday) {
                    router.goToday()
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 6, trailing: 8))
            }

            Section {
                ForEach(AppSection.allCases, id: \.self) { section in
                    Button {
                        router.go(section)
                    } label: {
                        SidebarNavRow(
                            section: section,
                            isSelected: !router.isShowingToday && router.section == section,
                            badgeCount: section == .inventory ? needsListingCount : 0
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
            } header: {
                Text("MENU")
                    .font(.pmBody(size: 11, weight: .semibold))
                    .foregroundStyle(PM.textTertiary)
                    .tracking(1.5)
            }

            Section {
                SidebarComicsRow(isSelected: router.isShowingComics) {
                    router.goComics()
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))

                SidebarExpensesRow(isSelected: router.isShowingExpenses) {
                    router.goExpenses()
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))

                SidebarTrashRow(
                    isSelected: router.isShowingTrash,
                    count: store.trash.count
                ) {
                    router.goTrash()
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
            }

            Section {
                SidebarStatsGrid(
                    inInventory: "\(store.items.count)",
                    totalValue: store.totalInventoryValue.asCurrency,
                    totalSold: "\(store.sales.count)",
                    allTimePL: store.totalProfit.asCurrency,
                    plPositive: store.totalProfit >= 0
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            } header: {
                Text("QUICK STATS")
                    .font(.pmBody(size: 11, weight: .semibold))
                    .foregroundStyle(PM.textTertiary)
                    .tracking(1.5)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .tint(PM.pink)
        .safeAreaInset(edge: .top, spacing: 0) {
            PMWordmark(size: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let saved = store.lastSaved {
                LastSavedPulse(saved: saved)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
        .pmScreen()
        .navigationTitle("Poster Malone")
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 270)
    }
}

// MARK: - Nav Row
// Child struct receives plain values — no computed props in a big body.

struct SidebarTodayRow: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PM.Space.sm + 2) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? PM.pink : PM.cyan)
                    .frame(width: 20)
                    .pmGlow(isSelected ? PM.pink : PM.cyan, radius: isSelected ? 6 : 3, opacity: isSelected ? 0.6 : 0.3)
                Text("Today")
                    .font(.pmBody(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? PM.textPrimary : PM.textSecondary)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                isSelected ? PM.pink.opacity(0.12) : (hovering ? PM.raised : Color.clear),
                in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? PM.pink.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isIn in
            withAnimation(PM.Anim.hover) { hovering = isIn }
        }
    }
}

struct SidebarComicsRow: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PM.Space.sm + 2) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? PM.pink : PM.textSecondary)
                    .frame(width: 20)
                    .pmGlow(PM.pink, radius: isSelected ? 6 : 0, opacity: isSelected ? 0.6 : 0)
                Text("Comics")
                    .font(.pmBody(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? PM.textPrimary : PM.textSecondary)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                isSelected ? PM.pink.opacity(0.12) : (hovering ? PM.raised : Color.clear),
                in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? PM.pink.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isIn in
            withAnimation(PM.Anim.hover) { hovering = isIn }
        }
    }
}

struct SidebarExpensesRow: View {
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PM.Space.sm + 2) {
                Image(systemName: "doc.text.below.ecg")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? PM.pink : PM.textSecondary)
                    .frame(width: 20)
                    .pmGlow(PM.pink, radius: isSelected ? 6 : 0, opacity: isSelected ? 0.6 : 0)
                Text("Expenses & Tax")
                    .font(.pmBody(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? PM.textPrimary : PM.textSecondary)
                Spacer()
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                isSelected ? PM.pink.opacity(0.12) : (hovering ? PM.raised : Color.clear),
                in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? PM.pink.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isIn in
            withAnimation(PM.Anim.hover) { hovering = isIn }
        }
    }
}

struct SidebarTrashRow: View {
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: PM.Space.sm + 2) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? PM.pink : PM.textSecondary)
                    .frame(width: 20)
                    .pmGlow(PM.pink, radius: isSelected ? 6 : 0, opacity: isSelected ? 0.6 : 0)
                Text("Trash")
                    .font(.pmBody(size: 15, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? PM.textPrimary : PM.textSecondary)
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.pmBody(size: 11, weight: .semibold))
                        .foregroundStyle(PM.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(PM.raised, in: Capsule())
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                isSelected ? PM.pink.opacity(0.12) : (hovering ? PM.raised : Color.clear),
                in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? PM.pink.opacity(0.4) : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isIn in
            withAnimation(PM.Anim.hover) { hovering = isIn }
        }
    }
}

struct SidebarNavRow: View {
    let section: AppSection
    let isSelected: Bool
    let badgeCount: Int

    @State private var hovering = false

    var body: some View {
        HStack(spacing: PM.Space.sm + 2) {
            Image(systemName: section.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? PM.pink : PM.textSecondary)
                .frame(width: 20)
                .pmGlow(PM.pink, radius: isSelected ? 6 : 0, opacity: isSelected ? 0.6 : 0)

            Text(section.rawValue)
                .font(.pmBody(size: 15, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? PM.textPrimary : PM.textSecondary)

            Spacer()

            // Orange "needs listing" count badge — preserved
            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.pmBody(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: Capsule())
                    .pmGlow(.orange, radius: 4, opacity: 0.45)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .overlay(alignment: .leading) {
            // Cyan active tick on the leading edge
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(PM.cyan)
                    .frame(width: 3, height: 16)
                    .pmCyanGlow(radius: 5)
                    .offset(x: -8)
            }
        }
        .opacity(hovering && !isSelected ? 0.85 : 1.0)
        .onHover { isIn in
            withAnimation(PM.Anim.hover) { hovering = isIn }
        }
    }
}

// MARK: - Quick Stats Grid
// 2×2 glowing micro-tiles. Receives plain values as lets.

struct SidebarStatsGrid: View {
    let inInventory: String
    let totalValue: String
    let totalSold: String
    let allTimePL: String
    let plPositive: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            SidebarStatTile(label: "In Inventory", value: inInventory, accent: PM.cyan)
            SidebarStatTile(label: "Total Value",  value: totalValue,  accent: PM.cyan)
            SidebarStatTile(label: "Total Sold",   value: totalSold,   accent: PM.pink)
            SidebarStatTile(label: "All-Time P/L", value: allTimePL,
                            accent: plPositive ? .green : .red)
        }
    }
}

struct SidebarStatTile: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.pmDisplay(size: 16))
                .foregroundStyle(accent)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .pmGlow(accent, radius: 5, opacity: 0.30)
            Text(label)
                .font(.pmBody(size: 10, weight: .medium))
                .foregroundStyle(PM.textTertiary)
                .textCase(.uppercase)
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .pmCard(fill: PM.card, radius: PM.Radius.md, border: accent.opacity(0.18))
    }
}

// MARK: - Last Saved Pulse

struct LastSavedPulse: View {
    let saved: Date
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.35))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulsing ? 1.5 : 0.9)
                    .opacity(pulsing ? 0.0 : 0.8)
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .pmGlow(.green, radius: 4, opacity: 0.6)
            }
            Text("Saved \(saved.formatted(.relative(presentation: .named)))")
                .font(.pmBody(size: 11, weight: .medium))
                .foregroundStyle(PM.textTertiary)
                .lineLimit(1)
            Spacer()
        }
        .onAppear {
            withAnimation(PM.Anim.pulse) { pulsing = true }
        }
    }
}
