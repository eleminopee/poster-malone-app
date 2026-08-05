import SwiftUI

struct EbayAutomationView: View {
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @Environment(\.dismiss) var dismiss

    // Passed in directly from InventoryTableView — guaranteed non-empty when sheet opens
    var preselectedIDs: Set<InventoryItem.ID> = []

    // Google Drive folder IDs (from project config)
    private let soldFolderId = ""

    @State private var selectedTab: EbayTab = .drafts
    @State private var isWorking = false
    @State private var pendingListedIDs: Set<InventoryItem.ID> = []


    @State private var resultMessage: String? = nil
    @State private var resultIsError = false

    // Scheduled export config
    @State private var scheduleDate = Date()
    @State private var scheduleTime = defaultEveningTime()
    @State private var intervalMinutes = 30
    @State private var useCustomTime = false

    // Process sold
    @State private var soldDays = 30
    @State private var soldOrders: [EbayService.EbayOrder] = []
    @State private var auditResults: [EbayService.EbayListing] = []
    /// Duplicate detection: SKUs with more than one live eBay listing.
    @State private var duplicateGroups: [DuplicateGroup] = []
    /// Silent auto-check on open: count of duplicated SKUs, shown as a banner
    /// above the tabs so the user is alerted without running anything.
    @State private var autoDuplicateCount: Int = 0
    @State private var didRunAutoCheck = false
    @State private var syncStatusResult: String? = nil
    @State private var isSyncingStatus = false

    // Mark Listed state
    @State private var markListedDate = Date()
    @State private var markListedResult: String? = nil

    // Bulk Fill state
    @State private var bulkFillTitles = true
    @State private var bulkFillDescriptions = true
    @State private var bulkFillIGCaptions = true
    @State private var isBulkFilling = false
    @State private var bulkFillResult: String? = nil

    enum EbayTab: String, CaseIterable {
        case drafts        = "Export Drafts"
        case scheduled     = "Scheduled"
        case processSold   = "Process Sold"
        case checkListings = "Check Listings"
        case syncStatus    = "Sync Status"
        case markListed    = "Mark Listed"
        case bulkFill      = "Bulk Fill"
        case audit         = "Audit SKUs"
    }

    var activeItems: [InventoryItem] {
        store.items.filter { $0.action.uppercased() == "Y" && !$0.sku.isEmpty }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Auto-check alert banner — shown on any tab when the silent
                // on-open check found duplicates. Tapping jumps to the Audit tab.
                if autoDuplicateCount > 0 {
                    Button {
                        selectedTab = .audit
                        if duplicateGroups.isEmpty { Task { await auditSKUs() } }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("\(autoDuplicateCount) duplicated SKU\(autoDuplicateCount == 1 ? "" : "s") live on eBay — same item listed more than once")
                                .font(.pmBody(size: 13, weight: .semibold))
                                .foregroundStyle(PM.textPrimary)
                            Spacer()
                            Text("Review in Audit")
                                .font(.pmBody(size: 12, weight: .medium))
                                .foregroundStyle(.red)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background(Color.red.opacity(0.12))
                        .overlay(Rectangle().fill(Color.red.opacity(0.4)).frame(height: 1), alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Tab bar — pink underline tabs
                HStack(spacing: 0) {
                    ForEach(EbayTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                            resultMessage = nil
                        } label: {
                            VStack(spacing: 0) {
                                Text(tab.rawValue)
                                    .font(.pmBody(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(
                                        selectedTab == tab
                                            ? PM.pink
                                            : PM.textSecondary
                                    )
                                Rectangle()
                                    .fill(selectedTab == tab ? PM.pink : Color.clear)
                                    .frame(height: 2)
                                    .pmGlow(PM.pink, radius: selectedTab == tab ? 4 : 0,
                                            opacity: selectedTab == tab ? 0.5 : 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .animation(PM.Anim.hover, value: selectedTab)
                    }
                    Spacer()
                }
                .background(PM.surface)

                PMNeonDivider(color: PM.pink).opacity(0.4)

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .drafts:        draftsPanel
                        case .scheduled:     scheduledPanel
                        case .processSold:   processSoldPanel
                        case .checkListings: checkListingsPanel
                        case .syncStatus:    syncStatusPanel
                        case .markListed:    markListedPanel
                        case .bulkFill:      bulkFillPanel
                        case .audit:         auditPanel
                        }
                    }
                    .padding(20)
                }

                // Result banner
                if let msg = resultMessage {
                    Divider()
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: resultIsError
                              ? "exclamationmark.triangle.fill"
                              : "checkmark.circle.fill")
                            .foregroundStyle(resultIsError ? .red : .green)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(msg.components(separatedBy: "\n"), id: \.self) { line in
                                Text(line)
                                    .font(.subheadline)
                                    .foregroundStyle(line.lowercased().contains("error") ? .red : .primary)
                            }
                        }
                        Spacer()
                        Button("Dismiss") { resultMessage = nil }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        resultIsError
                            ? Color.red.opacity(0.08)
                            : Color.green.opacity(0.08)
                    )
                }
            }
            .navigationTitle("eBay Automation")
            .onAppear {
                pendingListedIDs = preselectedIDs
                if !pendingListedIDs.isEmpty {
                    selectedTab = .markListed
                }
            }
            .task {
                // Silent duplicate check once per open — populates the banner
                // without the user running anything. Detect + alert only.
                guard !didRunAutoCheck else { return }
                didRunAutoCheck = true
                if let listings = try? await EbayService.shared.getAllActiveListings(credentials: credentials) {
                    var bySku: [String: Int] = [:]
                    for l in listings where !l.sku.isEmpty { bySku[l.sku, default: 0] += 1 }
                    autoDuplicateCount = bySku.values.filter { $0 > 1 }.count
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .pmScreen()
        .frame(minWidth: 680, minHeight: 500)
    }

    // MARK: - Drafts Panel

    var draftsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Export eBay Drafts",
                subtitle: "Generates a CSV for eBay bulk draft upload. Exports all items with Action = Y.",
                icon: "square.and.arrow.up"
            )

            ItemCountBadge(count: activeItems.count, label: "items flagged Action = Y")

            Button {
                Task { await exportDrafts() }
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Export Draft CSV", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || activeItems.isEmpty)

            InfoBox(text: "File saves to your Downloads folder. Import into eBay Seller Hub via File Exchange → Upload.")
        }
    }

    // MARK: - Scheduled Panel

    var scheduledPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Export Scheduled Listings",
                subtitle: "Generates a CSV for eBay scheduled listing upload with staggered times.",
                icon: "calendar.badge.clock"
            )

            ItemCountBadge(count: activeItems.count, label: "items will be scheduled")

            // Date picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Start Date").font(.caption).foregroundStyle(.secondary)
                DatePicker("", selection: $scheduleDate, displayedComponents: .date)
                    .labelsHidden()
            }

            // Time picker
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Start Time (CST)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Toggle("Custom", isOn: $useCustomTime)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                if useCustomTime {
                    DatePicker("", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                } else {
                    Picker("", selection: $scheduleTime) {
                        ForEach(eveningTimeSlots(), id: \.self) { slot in
                            Text(formatTime(slot)).tag(slot)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
            }

            // Interval
            VStack(alignment: .leading, spacing: 8) {
                Text("Interval Between Listings").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $intervalMinutes) {
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 160)
            }

            // Preview
            if !activeItems.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Schedule Preview").font(.caption).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(schedulePreview().prefix(8).enumerated()), id: \.offset) { i, preview in
                            HStack {
                                Text(preview.sku)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(width: 90, alignment: .leading)
                                Text(preview.timeStr)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            if i < min(7, activeItems.count - 1) {
                                Divider().padding(.leading, 10)
                            }
                        }
                        if activeItems.count > 8 {
                            Text("+ \(activeItems.count - 8) more...")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                        }
                    }
                    .background(PM.card, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            Button {
                Task { await exportScheduled() }
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Export Scheduled CSV", systemImage: "calendar.badge.clock")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || activeItems.isEmpty)

            InfoBox(text: "File saves to Downloads. Import via eBay Seller Hub → File Exchange. eBay requires at least 1 hour lead time.")
        }
    }

    // MARK: - Process Sold Panel

    var processSoldPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Process Sold Listings",
                subtitle: "Fetches recent eBay orders, matches SKUs to inventory, and moves them to Sales.",
                icon: "checkmark.circle"
            )

            // eBay account connection status
            ebayAuthStatusRow

            if credentials.isEbayConnected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Look back period").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $soldDays) {
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                        Text("60 days").tag(60)
                        Text("90 days").tag(90)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }

                Button {
                    Task { await processSold() }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Fetch & Process Sold Orders", systemImage: "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)

                if !soldOrders.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Found Orders").font(.caption).foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            ForEach(soldOrders, id: \.orderId) { order in
                                ForEach(order.lineItems, id: \.sku) { lineItem in
                                    HStack {
                                        Text(lineItem.sku.isEmpty ? "No SKU" : lineItem.sku)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .frame(width: 90, alignment: .leading)
                                        Text(lineItem.price.asCurrency)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Text(order.creationDate.shortDate)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    Divider().padding(.leading, 10)
                                }
                            }
                        }
                        .background(PM.card, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            InfoBox(text: "Items found in eBay orders that match your inventory SKUs will be moved to Sales automatically.")
        }
    }

    // MARK: - eBay Auth Status Row

    var ebayAuthStatusRow: some View {
        HStack(spacing: 10) {
            if credentials.isEbayConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Refresh token set — ready to fetch orders")
                    .font(.subheadline)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No refresh token")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Paste your eBay refresh token in Admin -> eBay credentials")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(
            credentials.isEbayConnected
                ? Color.green.opacity(0.06)
                : Color.orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    credentials.isEbayConnected
                        ? Color.green.opacity(0.2)
                        : Color.orange.opacity(0.25),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Check Listings Panel

    var checkListingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Check eBay Listings",
                subtitle: "Compares your active eBay listings against inventory to find discrepancies.",
                icon: "magnifyingglass"
            )

            Button {
                Task { await checkListings() }
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Check Active Listings", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)

            if !auditResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(auditResults.count) listings not found in inventory")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    VStack(spacing: 0) {
                        ForEach(auditResults, id: \.itemId) { listing in
                            HStack {
                                Text(listing.sku)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(width: 100, alignment: .leading)
                                Text(listing.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(listing.itemId)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            Divider().padding(.leading, 10)
                        }
                    }
                    .background(PM.card, in: RoundedRectangle(cornerRadius: 8))
                }
            }

            InfoBox(text: "Fetches all active eBay listings and checks them against your inventory. Results show items listed on eBay but not in your inventory.")
        }
    }

    // MARK: - Sync Status Panel

    var syncStatusPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Sync eBay Listing Status",
                subtitle: "Fetches all active eBay listings, updates each item's eBay Status field, and auto-corrects inventory status to Listed for anything active on eBay.",
                icon: "arrow.triangle.2.circlepath"
            )

            Button {
                Task { await syncEbayListingStatus() }
            } label: {
                if isSyncingStatus {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Sync eBay Status", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSyncingStatus)

            if let result = syncStatusResult {
                HStack(spacing: 6) {
                    Image(systemName: result.contains("failed") ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(result.contains("failed") ? Color.red : Color.green)
                    Text(result).font(.caption)
                }
            }

            // Legend
            VStack(alignment: .leading, spacing: 8) {
                Text("What this does:").font(.caption).fontWeight(.medium).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Label("Sets eBay Status → Active for every SKU found in your live eBay listings", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("Sets eBay Status → Unlisted for everything else", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                    Label("Auto-corrects Inventory Status → Listed if eBay is Active but item is Pending, Processed, Ordered, etc.", systemImage: "wand.and.stars")
                        .foregroundStyle(.orange)
                    Label("Flags Inventory Status → Research if eBay is Unlisted but item was Listed — needs investigation", systemImage: "exclamationmark.magnifyingglass")
                        .foregroundStyle(Color(red: 1.0, green: 0.2, blue: 0.6))
                }
                .font(.caption2)
            }
            .padding(10)
            .background(PM.card, in: RoundedRectangle(cornerRadius: 8))

            InfoBox(text: "Items already Listed or Sold are never silently downgraded — mismatches become Research so you can investigate. Filter your inventory by Status = Research to see everything flagged.")
        }
    }


    // MARK: - Mark Listed Panel

    var markListedPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Mark Items as Listed",
                subtitle: "Updates status to Listed and sets the listed date for all items you checked in the inventory table.",
                icon: "checkmark.circle"
            )

            let selectedItems = store.items.filter { pendingListedIDs.contains($0.id) }

            if selectedItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No items selected")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Check items in the Inventory table first, then come back here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            } else {
                // Date picker
                HStack {
                    Text("Listed Date")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    DatePicker("", selection: $markListedDate, displayedComponents: .date)
                        .labelsHidden()
                }

                // Item list — read only, shows what will be updated
                VStack(spacing: 0) {
                    ForEach(selectedItems) { item in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .font(.body)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(item.artist) — \(item.title)")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text("\(item.sku) · \(item.size) · \(item.status.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            // Arrow showing status change
                            HStack(spacing: 4) {
                                Text(item.status.rawValue)
                                    .font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(PM.raised, in: Capsule())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Listed")
                                    .font(.caption2)
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        Divider().padding(.leading, 42)
                    }
                }
                .background(PM.base.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

                // Apply button
                Button {
                    for item in selectedItems {
                        var updated = item
                        updated.status = .listed
                        updated.dateListed = markListedDate
                        updated.action = ""   // uncheck the action checkbox
                        store.update(updated)
                        store.addPaperTrailEntry(action: .listedEbay, item: updated)
                    }
                    markListedResult = "✓ Marked \(selectedItems.count) item\(selectedItems.count == 1 ? "" : "s") as Listed on \(markListedDate.formatted(date: .abbreviated, time: .omitted))"
                } label: {
                    Label("Apply to \(selectedItems.count) Item\(selectedItems.count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                if let result = markListedResult {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(result).font(.caption)
                    }
                }

                InfoBox(text: "Close this sheet and check items in the Inventory table to update the list above.")
            }
        }
    }

    // MARK: - Bulk Fill Panel

    var bulkFillPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Bulk Fill Titles & Descriptions",
                subtitle: "Auto-generates missing eBay titles and descriptions for all eligible inventory items.",
                icon: "wand.and.stars"
            )

            // Live counts
            let missingTitles = store.items.filter {
                $0.status != .sold && $0.status != .theVault &&
                !$0.artist.isEmpty && !$0.title.isEmpty &&
                $0.ebayTitle.trimmingCharacters(in: .whitespaces).isEmpty
            }
            let missingDescs = store.items.filter {
                $0.status != .sold && $0.status != .theVault &&
                !$0.artist.isEmpty && !$0.title.isEmpty &&
                $0.description.trimmingCharacters(in: .whitespaces).isEmpty
            }

            // Live counts
            let missingIGCaptions = store.items.filter {
                $0.status != .sold && $0.status != .theVault &&
                !$0.artist.isEmpty &&
                $0.igCaption.trimmingCharacters(in: .whitespaces).isEmpty
            }

            // What will be filled
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Toggle(isOn: $bulkFillTitles) {
                        HStack(spacing: 6) {
                            Text("eBay Titles")
                                .font(.subheadline).fontWeight(.medium)
                            Text("\(missingTitles.count) missing")
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(missingTitles.isEmpty ? Color.secondary.opacity(0.15) : Color.red.opacity(0.15), in: Capsule())
                                .foregroundStyle(missingTitles.isEmpty ? Color.secondary : Color.red)
                        }
                    }
                    .disabled(missingTitles.isEmpty)
                }
                HStack(spacing: 12) {
                    Toggle(isOn: $bulkFillDescriptions) {
                        HStack(spacing: 6) {
                            Text("eBay Descriptions")
                                .font(.subheadline).fontWeight(.medium)
                            Text("\(missingDescs.count) missing")
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(missingDescs.isEmpty ? Color.secondary.opacity(0.15) : Color.purple.opacity(0.15), in: Capsule())
                                .foregroundStyle(missingDescs.isEmpty ? Color.secondary : Color.purple)
                        }
                    }
                    .disabled(missingDescs.isEmpty)
                }
                HStack(spacing: 12) {
                    Toggle(isOn: $bulkFillIGCaptions) {
                        HStack(spacing: 6) {
                            Text("Instagram Captions")
                                .font(.subheadline).fontWeight(.medium)
                            Text("\(missingIGCaptions.count) missing")
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(missingIGCaptions.isEmpty ? Color.secondary.opacity(0.15) : Color.pink.opacity(0.15), in: Capsule())
                                .foregroundStyle(missingIGCaptions.isEmpty ? Color.secondary : Color.pink)
                        }
                    }
                    .disabled(missingIGCaptions.isEmpty)
                }
            }
            .padding(12)
            .background(PM.card, in: RoundedRectangle(cornerRadius: 8))

            let totalToFill = (bulkFillTitles ? missingTitles.count : 0) + (bulkFillDescriptions ? missingDescs.count : 0) + (bulkFillIGCaptions ? missingIGCaptions.count : 0)

            Button {
                Task { await runBulkFill(titles: missingTitles, descs: missingDescs, igCaptions: missingIGCaptions) }
            } label: {
                if isBulkFilling {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Fill \(totalToFill) Item\(totalToFill == 1 ? "" : "s")", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBulkFilling || totalToFill == 0)

            if let result = bulkFillResult {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(result).font(.caption)
                }
            }

            InfoBox(text: "Only fills items where the field is currently empty. Existing titles and descriptions are never overwritten.")
        }
    }

    // MARK: - Audit Panel

    var auditPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Audit eBay Listings",
                subtitle: "Finds duplicate SKUs (same item listed twice) and listings whose SKU isn't in your inventory. Run after any reschedule batch.",
                icon: "exclamationmark.triangle"
            )

            Button {
                Task { await auditSKUs() }
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Run Audit", systemImage: "exclamationmark.triangle")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)

            // Duplicate SKUs — the higher-priority finding, shown first.
            if !duplicateGroups.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(duplicateGroups.count) duplicated SKU\(duplicateGroups.count == 1 ? "" : "s") — same item live more than once")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                    Text("Review each on eBay and end the extra listing — keep whichever has watchers or offers. Don't end anything showing a sale.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(duplicateGroups) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.sku)
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(PM.pink)
                                ForEach(group.listings, id: \.itemId) { listing in
                                    HStack {
                                        Text(listing.title)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("item \(listing.itemId)")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            Divider().padding(.leading, 10)
                        }
                    }
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.red.opacity(0.3), lineWidth: 1))
                }
            }

            if !auditResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(auditResults.count) listings missing from inventory")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    VStack(spacing: 0) {
                        ForEach(auditResults, id: \.itemId) { listing in
                            HStack {
                                Text(listing.sku)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(width: 100, alignment: .leading)
                                Text(listing.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(listing.itemId)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            Divider().padding(.leading, 10)
                        }
                    }
                    .background(PM.card, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Actions

    private func exportDrafts() async {
        isWorking = true
        resultMessage = nil
        do {
            let csv = try EbayExportService.buildDraftCSV(items: activeItems)
            let ts = timestamp()
            let url = try await MainActor.run {
                try EbayExportService.saveToDownloads(csv, filename: "ebay_drafts_\(ts).csv")
            }
            resultIsError = false
            resultMessage = "✓ Exported \(activeItems.count) items → \(url.lastPathComponent)"
            NSWorkspace.shared.selectFile(
                url.path,
                inFileViewerRootedAtPath: url.deletingLastPathComponent().path
            )
        } catch {
            resultIsError = true
            resultMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func exportScheduled() async {
        isWorking = true
        resultMessage = nil

        let calendar = Calendar.current
        let dateComps = calendar.dateComponents([.year, .month, .day], from: scheduleDate)
        let timeComps = calendar.dateComponents([.hour, .minute], from: scheduleTime)
        var combined = DateComponents()
        combined.year   = dateComps.year
        combined.month  = dateComps.month
        combined.day    = dateComps.day
        combined.hour   = timeComps.hour
        combined.minute = timeComps.minute
        combined.timeZone = TimeZone(identifier: "America/Chicago")
        let startDateTime = calendar.date(from: combined) ?? scheduleDate

        do {
            let config = EbayExportService.ScheduleConfig(
                startDate: startDateTime,
                intervalMinutes: intervalMinutes
            )
            let result = try EbayExportService.buildScheduledCSV(items: activeItems, config: config)
            let ts = timestamp()
            let url = try await MainActor.run {
                try EbayExportService.saveToDownloads(
                    result.csv,
                    filename: "ebay_scheduled_\(ts).csv"
                )
            }
            resultIsError = false
            var msg = "✓ Exported \(result.count) items → \(url.lastPathComponent)"
            if result.hasLeadTimeWarning {
                msg += "\n⚠️ Some listings are less than 1 hour from now"
            }
            resultMessage = msg
            NSWorkspace.shared.selectFile(
                url.path,
                inFileViewerRootedAtPath: url.deletingLastPathComponent().path
            )
        } catch {
            resultIsError = true
            resultMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func processSold() async {
        isWorking = true
        resultMessage = nil

        let shop  = credentials.shopifyShop
        let token = credentials.shopifyToken

        do {
            let orders = try await EbayService.shared.getSoldOrders(days: soldDays, credentials: credentials)
            soldOrders = orders

            var movedCount    = 0
            var shopifyOK     = 0
            var shopifySkipped = 0
            var shopifyErrors: [String] = []
            var folderOK      = 0
            var folderMissing = 0
            var folderErrors: [String] = []

            for order in orders {
                for lineItem in order.lineItems {
                    guard !lineItem.sku.isEmpty else { continue }
                    guard let item = store.items.first(where: { $0.sku == lineItem.sku }) else { continue }

                    let estimatedFees  = lineItem.price * 0.129
                    let feesAndShipping = estimatedFees + order.shippingCost
                    store.markAsSold(
                        item,
                        marketplace: .ebay,
                        grossSales: lineItem.price,
                        taxes: lineItem.tax,
                        feesAndShipping: feesAndShipping,
                        dateSold: order.creationDate
                    )
                    movedCount += 1

                    let sku = item.sku

                    // Shopify: set qty=0 and status=DRAFT
                    if !shop.isEmpty && !token.isEmpty {
                        do {
                            try await ShopifyService.shared.markSoldOut(shop: shop, token: token, sku: sku)
                            shopifyOK += 1
                        } catch ShopifyService.ShopifyError.graphqlError(let msg) where msg.contains("No Shopify location") {
                            // Product exists but location lookup failed — count separately
                            shopifyErrors.append("\(sku): \(msg)")
                        } catch {
                            // Product may simply not exist on Shopify yet — treat as skip, not hard failure
                            let msg = error.localizedDescription
                            if msg.lowercased().contains("not found") || msg.lowercased().contains("no variant") {
                                shopifySkipped += 1
                            } else {
                                shopifyErrors.append("\(sku): \(msg)")
                            }
                        }
                    } else {
                        shopifySkipped += 1
                    }

                    // Google Drive: move folder Inventory → Sold
                    do {
                        let moved = try await GoogleDriveService.shared.moveFolder(
                            named: sku,
                            fromParent: GoogleDriveService.shared.inventoryFolderId,
                            toParent: soldFolderId,
                            credentials: credentials
                        )
                        if moved {
                            folderOK += 1
                        } else {
                            folderMissing += 1
                        }
                    } catch {
                        folderErrors.append("\(sku): \(error.localizedDescription)")
                    }
                }
            }

            // Build result message
            var parts: [String] = []
            parts.append("✓ \(movedCount) item\(movedCount == 1 ? "" : "s") moved to Sales")

            if !shop.isEmpty && !token.isEmpty {
                var shopifyLine = "Shopify: \(shopifyOK) set to Draft/qty 0"
                if shopifySkipped > 0 { shopifyLine += ", \(shopifySkipped) not on Shopify" }
                if !shopifyErrors.isEmpty { shopifyLine += ", \(shopifyErrors.count) error\(shopifyErrors.count == 1 ? "" : "s")" }
                parts.append(shopifyLine)
            }

            var folderLine = "Drive: \(folderOK) folder\(folderOK == 1 ? "" : "s") moved to Sold"
            if folderMissing > 0 { folderLine += ", \(folderMissing) not found" }
            if !folderErrors.isEmpty { folderLine += ", \(folderErrors.count) error\(folderErrors.count == 1 ? "" : "s")" }
            parts.append(folderLine)

            if !shopifyErrors.isEmpty {
                parts.append("Shopify errors: " + shopifyErrors.joined(separator: "; "))
            }
            if !folderErrors.isEmpty {
                parts.append("Drive errors: " + folderErrors.joined(separator: "; "))
            }

            resultIsError = !shopifyErrors.isEmpty || !folderErrors.isEmpty
            resultMessage = parts.joined(separator: "\n")

        } catch {
            resultIsError = true
            resultMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func syncEbayListingStatus() async {
        isSyncingStatus = true
        syncStatusResult = nil
        do {
            // Fetch all active eBay listings — simple SKU lookup
            let activeListings = try await EbayService.shared.getAllActiveListings(credentials: credentials)
            let activeSkus = Set(activeListings.map { $0.sku })

            var activeCount   = 0
            var unlistedCount = 0
            var fixedCount    = 0   // items whose inventory status was auto-corrected to Listed
            var researchCount = 0   // items flagged Research: Unlisted on eBay but status was Listed

            // Active = SKU found in eBay active listings. Unlisted = not found.
            // Bonus: if eBay says Active but inventory status isn't .listed, auto-correct it.
            // Also: if eBay says Unlisted but inventory status IS .listed, flag as Research.
            let updatedItems = store.items.map { item -> InventoryItem in
                var updated = item
                guard !item.sku.isEmpty else { return updated }
                if activeSkus.contains(item.sku) {
                    updated.ebayListingStatus = "Active"
                    activeCount += 1
                    // Auto-correct status to .listed if it's anything other than .listed or .sold
                    if item.status != .listed && item.status != .sold {
                        updated.status = .listed
                        fixedCount += 1
                    }
                } else {
                    updated.ebayListingStatus = "Unlisted"
                    unlistedCount += 1
                    // Flag for investigation: item thinks it's Listed but eBay has no active listing
                    if item.status == .listed {
                        updated.status = .research
                        researchCount += 1
                    }
                }
                return updated
            }

            await MainActor.run {
                for item in updatedItems {
                    store.update(item)
                }
                var msg = "✓ Synced — \(activeCount) Active, \(unlistedCount) Unlisted"
                if fixedCount > 0 {
                    msg += " · \(fixedCount) → Listed"
                }
                if researchCount > 0 {
                    msg += " · \(researchCount) → Research"
                }
                syncStatusResult = msg
                isSyncingStatus = false
            }
        } catch {
            await MainActor.run {
                syncStatusResult = "Sync failed: \(error.localizedDescription)"
                isSyncingStatus = false
            }
        }
    }

    private func checkListings() async {
        isWorking = true
        resultMessage = nil
        auditResults = []
        do {
            let listings = try await EbayService.shared.getAllActiveListings(credentials: credentials)
            let inventorySKUs = Set(store.items.map { $0.sku })
            let missing = listings.filter { !inventorySKUs.contains($0.sku) }
            auditResults = missing
            resultIsError = !missing.isEmpty
            resultMessage = "Found \(listings.count) active listings. \(missing.count) not in inventory."
        } catch {
            resultIsError = true
            resultMessage = error.localizedDescription
        }
        isWorking = false
    }

    struct DuplicateGroup: Identifiable {
        let sku: String
        let listings: [EbayService.EbayListing]
        var id: String { sku }
    }

    private func auditSKUs() async {
        isWorking = true
        resultMessage = nil
        auditResults = []
        duplicateGroups = []
        do {
            let listings = try await EbayService.shared.getAllActiveListings(credentials: credentials)
            let inventorySKUs = Set(store.items.map { $0.sku })
            let missing = listings.filter { !inventorySKUs.contains($0.sku) }
            auditResults = missing

            // Duplicate detection — group live listings by SKU; any SKU with
            // 2+ live listings is a duplicate (the exact problem from the
            // reschedule batch where old listings weren't ended).
            var bySku: [String: [EbayService.EbayListing]] = [:]
            for l in listings where !l.sku.isEmpty {
                bySku[l.sku, default: []].append(l)
            }
            duplicateGroups = bySku
                .filter { $0.value.count > 1 }
                .map { DuplicateGroup(sku: $0.key, listings: $0.value) }
                .sorted { $0.sku < $1.sku }

            resultIsError = !missing.isEmpty || !duplicateGroups.isEmpty
            var parts: [String] = []
            if !duplicateGroups.isEmpty {
                let extra = duplicateGroups.reduce(0) { $0 + ($1.listings.count - 1) }
                parts.append("⚠️ \(duplicateGroups.count) duplicated SKU\(duplicateGroups.count == 1 ? "" : "s") (\(extra) extra listing\(extra == 1 ? "" : "s"))")
            }
            if !missing.isEmpty {
                parts.append("⚠️ \(missing.count) eBay SKUs missing from inventory")
            }
            resultMessage = parts.isEmpty
                ? "✓ All \(listings.count) eBay listings clean — no duplicates, all SKUs in inventory"
                : parts.joined(separator: "  •  ")
        } catch {
            resultIsError = true
            resultMessage = error.localizedDescription
        }
        isWorking = false
    }

    // MARK: - Schedule Helpers

    struct SchedulePreviewItem {
        let sku: String
        let timeStr: String
    }

    private func schedulePreview() -> [SchedulePreviewItem] {
        let calendar = Calendar.current
        let dateComps = calendar.dateComponents([.year, .month, .day], from: scheduleDate)
        let timeComps = calendar.dateComponents([.hour, .minute], from: scheduleTime)
        var combined = DateComponents()
        combined.year   = dateComps.year
        combined.month  = dateComps.month
        combined.day    = dateComps.day
        combined.hour   = timeComps.hour
        combined.minute = timeComps.minute
        combined.timeZone = TimeZone(identifier: "America/Chicago")
        var current = calendar.date(from: combined) ?? scheduleDate

        let formatter = DateFormatter()
        formatter.dateFormat = "M/d h:mm a"
        formatter.timeZone = TimeZone(identifier: "America/Chicago")

        return activeItems.map { item in
            let str = formatter.string(from: current)
            current = current.addingTimeInterval(Double(intervalMinutes) * 60)
            return SchedulePreviewItem(sku: item.sku, timeStr: str)
        }
    }

    private func eveningTimeSlots() -> [Date] {
        var slots: [Date] = []
        let calendar = Calendar.current
        var comps = calendar.dateComponents([.year, .month, .day], from: Date())
        comps.timeZone = TimeZone(identifier: "America/Chicago")
        for hour in 18...23 {
            for minute in [0, 30] {
                comps.hour = hour
                comps.minute = minute
                if let date = calendar.date(from: comps) {
                    slots.append(date)
                }
            }
        }
        return slots
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone(identifier: "America/Chicago")
        return f.string(from: date)
    }

    private static func defaultEveningTime() -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 18
        comps.minute = 0
        comps.timeZone = TimeZone(identifier: "America/Chicago")
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: Date())
    }

    // MARK: - Bulk Fill

    private func runBulkFill(titles: [InventoryItem], descs: [InventoryItem], igCaptions: [InventoryItem] = []) async {
        isBulkFilling = true
        bulkFillResult = nil

        var titlesFilledCount = 0
        var descsFilledCount = 0
        var igFilledCount = 0

        // Fill eBay titles
        if bulkFillTitles {
            for item in titles {
                var updated = item
                updated.ebayTitle = item.generatedEbayTitle()
                store.update(updated)
                titlesFilledCount += 1
            }
        }

        // Fill eBay descriptions
        if bulkFillDescriptions {
            for item in descs {
                var updated = item
                updated.description = item.generatedEbayDescription()
                store.update(updated)
                descsFilledCount += 1
            }
        }

        // Fill Instagram captions
        if bulkFillIGCaptions {
            for item in igCaptions {
                var updated = item
                updated.igCaption = buildIGCaption(item)
                store.update(updated)
                igFilledCount += 1
            }
        }

        var parts: [String] = []
        if titlesFilledCount > 0 { parts.append("\(titlesFilledCount) title\(titlesFilledCount == 1 ? "" : "s")") }
        if descsFilledCount  > 0 { parts.append("\(descsFilledCount) description\(descsFilledCount == 1 ? "" : "s")") }
        if igFilledCount     > 0 { parts.append("\(igFilledCount) IG caption\(igFilledCount == 1 ? "" : "s")") }
        bulkFillResult = parts.isEmpty ? "Nothing to fill." : "✓ Filled \(parts.joined(separator: ", "))"

        isBulkFilling = false
    }

    // MARK: - Instagram Caption Builder (mirrors ItemEditSheet.buildIGCaption)

    private func buildIGCaption(_ item: InventoryItem) -> String {
        var lines: [String] = []
        let artistLine = [item.artist, item.title].filter { !$0.isEmpty }.joined(separator: ". ")
        if !artistLine.isEmpty { lines.append(artistLine + ".") }
        if !item.edition.isEmpty { lines.append("Edition: \(item.edition)") }
        if !item.gallery.isEmpty { lines.append(item.gallery) }
        let details = [item.size, item.productionTechnique].filter { !$0.isEmpty }.joined(separator: " · ")
        if !details.isEmpty { lines.append(details) }
        lines.append("")
        lines.append("Available now. Link in bio.")
        var tags: [String] = ["#postermalone", "#alternativemovieposters", "#limitededitionprint", "#screenprint"]
        if !item.artist.isEmpty { tags.append("#\(item.artist.lowercased().replacingOccurrences(of: " ", with: ""))") }
        if !item.gallery.isEmpty { tags.append("#\(item.gallery.lowercased().replacingOccurrences(of: " ", with: ""))") }
        if !item.franchise.isEmpty { tags.append("#\(item.franchise.lowercased().replacingOccurrences(of: " ", with: ""))") }
        lines.append(tags.joined(separator: " "))
        return lines.joined(separator: "\n")
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(PM.pink)
                .frame(width: 36, height: 36)
                .background(PM.pink.opacity(0.10), in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                        .strokeBorder(PM.pink.opacity(0.25), lineWidth: 1)
                )
                .pmGlow(PM.pink, radius: 5, opacity: 0.20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.pmDisplay(size: 18))
                    .foregroundStyle(PM.textPrimary)
                    .tracking(0.8)
                Text(subtitle)
                    .font(.pmBody(size: 13))
                    .foregroundStyle(PM.textSecondary)
            }
        }
    }
}

struct ItemCountBadge: View {
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Text("\(count)")
                .font(.pmDisplay(size: 16))
                .foregroundStyle(PM.pink)
                .monospacedDigit()
                .pmGlow(PM.pink, radius: 4, opacity: 0.35)
            Text(label)
                .font(.pmBody(size: 13))
                .foregroundStyle(PM.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(PM.card, in: RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                .strokeBorder(PM.pink.opacity(0.25), lineWidth: 1)
        )
    }
}

struct InfoBox: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(PM.cyan)
                .font(.caption)
            Text(text)
                .font(.pmBody(size: 12))
                .foregroundStyle(PM.textSecondary)
        }
        .padding(10)
        .background(PM.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(PM.borderSubtle, lineWidth: 1)
        )
    }
}
