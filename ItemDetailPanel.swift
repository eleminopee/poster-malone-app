import SwiftUI

// ============================================================================
// ItemDetailPanel.swift — the spotlight panel
// Hero image with a soft vignette, big Bebas-cyan price, two-column metadata
// chips, and full-width gradient action buttons pinned to the bottom.
// Every button, sheet, confirmation, and field from the original is intact.
// ============================================================================

struct ItemDetailPanel: View {
    let item: InventoryItem
    @Binding var searchText: String
    @Binding var selectedItem: InventoryItem?
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @Environment(PMRouter.self) var router
    @State private var selectedImageIndex = 0
    @State private var showingEditSheet = false
    @State private var showingSoldSheet = false
    @State private var showingPhotoManager = false
    @State private var showingDeleteConfirm = false
    @State private var showingDuplicateSheet = false

    private var closeButton: some View {
        Button {
            selectedItem = nil
        } label: {
            Image(systemName: "xmark")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(PM.borderStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(8)
        .help("Close detail panel")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Photo gallery — hero with soft vignette
                if !item.images.isEmpty {
                    PhotoGalleryView(images: item.images, selectedIndex: $selectedImageIndex)
                        .frame(height: 260)
                        .overlay {
                            // Soft vignette so the art glows out of the dark
                            LinearGradient(
                                stops: [
                                    .init(color: .black.opacity(0.35), location: 0.0),
                                    .init(color: .clear,               location: 0.25),
                                    .init(color: .clear,               location: 0.75),
                                    .init(color: .black.opacity(0.45), location: 1.0)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                            .allowsHitTesting(false)
                        }
                        .overlay(alignment: .topTrailing) {
                            closeButton
                        }
                } else {
                    RoundedRectangle(cornerRadius: 0)
                        .fill(PM.surface)
                        .frame(height: 200)
                        .overlay { PM.heroWash.allowsHitTesting(false) }
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.stack")
                                    .font(.largeTitle)
                                    .foregroundStyle(PM.textTertiary)
                                Text("No photos synced")
                                    .font(.pmBody(size: 12))
                                    .foregroundStyle(PM.textTertiary)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            closeButton
                        }
                }

                VStack(alignment: .leading, spacing: 20) {

                    // MARK: Header
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            searchText = item.artist
                        } label: {
                            Text(item.artist)
                                .font(.pmBody(size: 12, weight: .semibold))
                                .foregroundStyle(PM.pink)
                                .textCase(.uppercase)
                                .tracking(1.4)
                                .underline(color: PM.pink.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                        .help("Filter inventory to show all prints by \(item.artist)")

                        Text(item.title)
                            .font(.pmDisplay(size: 26))
                            .foregroundStyle(PM.textPrimary)
                            .lineLimit(3)
                            .minimumScaleFactor(0.7)

                        HStack(spacing: 6) {
                            Text(item.gallery)
                            if !item.size.isEmpty {
                                Text("·")
                                Text(item.size)
                            }
                            if !item.edition.isEmpty {
                                Text("·")
                                Text(item.edition)
                            }
                        }
                        .font(.pmBody(size: 13))
                        .foregroundStyle(PM.textSecondary)
                    }

                    // MARK: Price hero — big Bebas cyan
                    ItemPriceHero(
                        ebayPrice: item.ebayPrice,
                        shopifyPrice: item.shopifyPrice,
                        margin: item.margin,
                        status: item.status
                    )

                    // MARK: Metadata chips — two-column pill layout
                    ItemMetaChips(item: item)

                    PMNeonDivider(color: PM.pink).opacity(0.5)

                    // MARK: Details — matches Edit Item section order exactly

                    // Core Details
                    DetailSection(title: "Core Details") {
                        DetailRow(label: "SKU",                 value: item.sku)
                        DetailRow(label: "Artist",              value: item.artist)
                        DetailRow(label: "Title",               value: item.title)
                        DetailRow(label: "Size",                value: item.size)
                        DetailRow(label: "Edition",             value: item.edition)
                        DetailRow(label: "Print Type",          value: item.printType)
                        DetailRow(label: "Production Technique",value: item.productionTechnique)
                        DetailRow(label: "Gallery",             value: item.gallery)
                    }

                    // Storage
                    DetailSection(title: "Storage") {
                        DetailRow(label: "Drawer",   value: item.drawer)
                        DetailRow(label: "Sleeve #", value: item.sleeveNumber)
                    }

                    // Classification
                    DetailSection(title: "Classification") {
                        DetailRow(label: "Franchise", value: item.franchise)
                        DetailRow(label: "Character", value: item.character)
                        DetailRow(label: "Theme",     value: item.theme)
                        DetailRow(label: "Tags",      value: item.tags)
                        DetailRow(label: "Condition", value: item.condition)
                        DetailRow(label: "Signed",    value: item.signed ? "Yes" : "No")
                        DetailRow(label: "Imperfect", value: item.imperfect ? "Yes" : "No")
                    }

                    // Acquisition
                    DetailSection(title: "Acquisition") {
                        DetailRow(label: "Date Purchased", value: item.datePurchased?.shortDate ?? "—")
                        DetailRow(label: "Net Cost",       value: item.netCost.asCurrency)
                        DetailRow(label: "Tax & Shipping", value: item.taxAndShipping.asCurrency)
                        DetailRow(label: "Total Cost",     value: item.totalCostComputed.asCurrency)
                    }

                    // Pricing & Listing Status
                    DetailSection(title: "Pricing & Listing Status") {
                        DetailRow(label: "eBay Price",    value: item.ebayPrice.asCurrency)
                        DetailRow(label: "Shopify Price", value: item.shopifyPrice.asCurrency)
                        DetailRow(label: "Est. Profit",   value: item.estimatedProfit.asCurrency)
                        DetailRow(label: "Margin",        value: item.margin.asPercent)

                        // Suggested sale price for aging inventory
                        if let suggested = item.suggestedSalePrice {
                            Divider().padding(.leading, 10)
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "tag.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        Text("Suggested Sale Price")
                                            .font(.pmBody(size: 13, weight: .medium))
                                            .foregroundStyle(PM.textSecondary)
                                    }
                                    let discount = item.agingTier == .aging ? "15%" : item.agingTier == .old ? "25%" : "30%"
                                    Text("\(discount) off — \(item.daysSincePurchase) days since purchase")
                                        .font(.pmBody(size: 11))
                                        .foregroundStyle(PM.textTertiary)
                                }
                                .frame(width: 110, alignment: .leading)
                                Text(suggested.asCurrency)
                                    .font(.pmDisplay(size: 16))
                                    .foregroundStyle(.orange)
                                    .pmGlow(.orange, radius: 4, opacity: 0.35)
                                Spacer()
                                Button {
                                    var updated = item
                                    updated.ebayPrice    = suggested
                                    updated.shopifyPrice = (suggested * 0.80 * 100).rounded() / 100
                                    updated.priceUpdatedAt = Date()
                                    store.update(updated)
                                } label: {
                                    Text("Apply Price")
                                }
                                .buttonStyle(PMTintButtonStyle(tint: .orange))
                                .help("Set eBay price to \(suggested.asCurrency) and Shopify to \((suggested * 0.80).asCurrency)")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            Divider().padding(.leading, 10)
                        }

                        // Price updated timestamp
                        if let updated = item.priceUpdatedAt {
                            let formatter: DateFormatter = {
                                let f = DateFormatter()
                                f.dateStyle = .medium
                                f.timeStyle = .short
                                return f
                            }()
                            let daysSince = Calendar.current.dateComponents([.day], from: updated, to: Date()).day ?? 0
                            HStack(alignment: .top) {
                                Text("Price Updated")
                                    .font(.pmBody(size: 13, weight: .medium))
                                    .foregroundStyle(PM.textTertiary)
                                    .textCase(.uppercase)
                                    .tracking(0.4)
                                    .frame(width: 110, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(formatter.string(from: updated))
                                        .font(.pmBody(size: 13))
                                        .foregroundStyle(PM.textPrimary)
                                    Text("\(daysSince) day\(daysSince == 1 ? "" : "s") ago")
                                        .font(.pmBody(size: 11))
                                        .foregroundStyle(PM.textTertiary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            Divider().padding(.leading, 10)
                        }

                        DetailRow(label: "Inventory Status", value: item.status.rawValue)
                        DetailRow(label: "Listed On",        value: item.listingMarketplace.rawValue)
                        DetailRow(label: "Listed Date",      value: item.dateListed?.shortDate ?? "—")
                        DetailRow(label: "Days Listed",      value: "\(item.daysInInventory)")
                    }

                    // eBay
                    DetailSection(title: "eBay") {
                        DetailRow(label: "Title",          value: item.ebayTitle)
                        // Title length indicator
                        let titleLen = item.ebayTitle.count
                        HStack(alignment: .center) {
                            Text("Title Length")
                                .font(.pmBody(size: 13, weight: .medium))
                                .foregroundStyle(PM.textTertiary)
                                .textCase(.uppercase)
                                .tracking(0.4)
                                .frame(width: 110, alignment: .leading)
                            ProgressView(value: Double(min(titleLen, 80)), total: 80)
                                .tint(titleLen > 80 ? .red : titleLen > 70 ? .orange : PM.cyan)
                                .frame(maxWidth: .infinity)
                            Text("\(titleLen) / 80")
                                .font(.pmBody(size: 11, weight: .semibold))
                                .foregroundStyle(titleLen > 80 ? .red : titleLen > 70 ? .orange : PM.textSecondary)
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        Divider().padding(.leading, 10)
                        DetailRow(label: "Category ID",    value: item.ebayCategoryId)
                        DetailRow(label: "Item ID",        value: item.ebayItemId)
                        DetailRow(label: "eBay Status",    value: item.ebayListingStatus.isEmpty ? "—" : item.ebayListingStatus)
                        DetailRow(label: "Store Cat 1",    value: EbayStoreCategoryMap.label(for: item.storeCategory1) ?? item.storeCategory1)
                        DetailRow(label: "Store Cat 2",    value: EbayStoreCategoryMap.label(for: item.storeCategory2) ?? item.storeCategory2)
                        DetailRow(label: "Pay Profile",    value: item.paymentProfileName)
                        DetailRow(label: "Ship Profile",   value: item.shippingProfileName)
                        DetailRow(label: "Return Profile", value: item.returnProfileName)
                        DescriptionPreview(
                            label: "eBay Description",
                            html: item.description,
                            emptyMessage: "No eBay description — tap Edit to generate one"
                        )
                    }

                    // Shopify
                    DetailSection(title: "Shopify") {
                        DetailRow(label: "Title",          value: item.shopifyTitle)
                        DetailRow(label: "Handle",         value: item.shopifyHandle)
                        DetailRow(label: "Shopify Status", value: shopifyStatusLabel(item.shopifyStatus))
                        DetailRow(label: "Last Push",      value: item.shopifyAPIUpdates?.shortDate ?? "—")
                        DescriptionPreview(
                            label: "Shopify Description",
                            html: item.shopifyDescription,
                            emptyMessage: "No Shopify description — tap Edit → Generate to create one"
                        )
                    }

                    // Instagram
                    DetailSection(title: "Instagram") {
                        DetailRow(label: "Queue for IG", value: item.igPost ? "Yes" : "No")
                        DetailRow(label: "Status",       value: item.igStatus.isEmpty ? "—" : item.igStatus)
                        if !item.igCaption.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Caption")
                                    .font(.pmBody(size: 12, weight: .medium))
                                    .foregroundStyle(PM.textTertiary)
                                Text(item.igCaption)
                                    .font(.pmBody(size: 12))
                                    .foregroundStyle(PM.textSecondary)
                                    .padding(8)
                                    .background(PM.base)
                                    .clipShape(RoundedRectangle(cornerRadius: PM.Radius.sm))
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                    }

                    // Photo Links
                    if !item.images.isEmpty {
                        DetailSection(title: "Photo Links") {
                            ForEach(Array(item.images.enumerated()), id: \.offset) { i, url in
                                HStack(alignment: .top) {
                                    Text(i == 0 ? "Cover" : "Photo \(i + 1)")
                                        .font(.pmBody(size: 13, weight: .medium))
                                        .foregroundStyle(PM.textTertiary)
                                        .textCase(.uppercase)
                                        .tracking(0.4)
                                        .frame(width: 110, alignment: .leading)
                                    Text(url)
                                        .font(.pmBody(size: 11))
                                        .foregroundStyle(PM.textSecondary)
                                        .textSelection(.enabled)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(url, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.caption)
                                            .foregroundStyle(PM.cyan)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy URL to clipboard")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                Divider().padding(.leading, 10)
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 8)   // breathing room above pinned actions
            }
        }
        .pmScreen()
        // MARK: Pinned action dock — full-width gradient buttons at the bottom
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ItemActionDock(
                onEdit:      { showingEditSheet = true },
                onPhotos:    { showingPhotoManager = true },
                onMarkSold:  { showingSoldSheet = true },
                onDuplicate: { showingDuplicateSheet = true },
                onDelete:    { showingDeleteConfirm = true }
            )
            .confirmationDialog(
                "Delete \"\(item.title)\"?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    let sku = item.sku
                    selectedItem = nil
                    store.delete(item)
                    router.showToast(.warning, "Moved \(sku) to Trash — restorable for 30 days")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("\(item.sku) will move to Trash and can be restored for 30 days.")
            }
        }
        .sheet(isPresented: $showingDuplicateSheet) {
            DuplicateItemSheet(item: item)
                .environment(store)
        }
        .sheet(isPresented: $showingEditSheet) {
            ItemEditSheet(item: item, selectedItem: $selectedItem)
                .environment(store)
                .environment(credentials)
        }
        .sheet(isPresented: $showingSoldSheet) {
            MarkSoldSheet(item: item)
                .environment(store)
        }
        .sheet(isPresented: $showingPhotoManager) {
            PhotoManagerView(item: item)
                .environment(store)
                .environment(credentials)
        }
    }

    private func shopifyStatusLabel(_ status: String) -> String {
        switch status.uppercased() {
        case "ACTIVE":   return "Active"
        case "DRAFT":    return "Draft"
        case "ARCHIVED": return "Archived"
        case "":         return "Not Listed"
        default:         return status
        }
    }
}

// MARK: - Price Hero
// Big Bebas Neue cyan price with margin readout. Plain lets — re-render safe.

struct ItemPriceHero: View {
    let ebayPrice: Double
    let shopifyPrice: Double
    let margin: Double
    let status: ItemStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PM.Space.md) {
            VStack(alignment: .leading, spacing: 0) {
                Text("EBAY PRICE")
                    .font(.pmBody(size: 10, weight: .semibold))
                    .foregroundStyle(PM.textTertiary)
                    .tracking(1.2)
                Text(ebayPrice > 0 ? ebayPrice.asCurrency : "—")
                    .font(.pmDisplay(size: 38))
                    .foregroundStyle(PM.cyan)
                    .monospacedDigit()
                    .pmCyanGlow(radius: 10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(status: status)
                if shopifyPrice > 0 {
                    Text("Shopify \(shopifyPrice.asCurrency)")
                        .font(.pmBody(size: 12, weight: .medium))
                        .foregroundStyle(PM.textSecondary)
                        .monospacedDigit()
                }
                if margin != 0 {
                    Text("\(margin.asPercent) margin")
                        .font(.pmBody(size: 11))
                        .foregroundStyle(margin >= 0 ? Color.green : Color.red)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, PM.Space.lg)
        .padding(.vertical, PM.Space.md)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: PM.Radius.lg, style: .continuous).fill(PM.card)
                PM.heroWash
                    .clipShape(RoundedRectangle(cornerRadius: PM.Radius.lg, style: .continuous))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PM.Radius.lg, style: .continuous)
                .strokeBorder(PM.cyan.opacity(0.20), lineWidth: 1)
        )
    }
}

// MARK: - Metadata Chips
// Two-column pill/chip layout for quick-scan facts.

struct ItemMetaChips: View {
    let item: InventoryItem

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        let chips: [(icon: String, label: String, value: String)] = [
            ("ruler",              "Size",      item.size),
            ("number",             "Edition",   item.edition),
            ("signature",          "Signed",    item.signed ? "Yes" : "No"),
            ("sparkles",           "Condition", item.condition),
            ("tray.full",          "Drawer",    item.drawer),
            ("doc.plaintext",      "Sleeve",    item.sleeveNumber)
        ].filter { !$0.value.isEmpty }

        if !chips.isEmpty {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(chips, id: \.label) { chip in
                    HStack(spacing: 6) {
                        Image(systemName: chip.icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(PM.pink.opacity(0.85))
                        Text(chip.label)
                            .font(.pmBody(size: 11, weight: .medium))
                            .foregroundStyle(PM.textTertiary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        Spacer(minLength: 4)
                        Text(chip.value)
                            .font(.pmBody(size: 12, weight: .semibold))
                            .foregroundStyle(PM.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(PM.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(PM.borderSubtle, lineWidth: 1))
                }
            }
        }
    }
}

// MARK: - Pinned Action Dock
// Full-width gradient/tinted actions. All five original actions preserved.

struct ItemActionDock: View {
    let onEdit: () -> Void
    let onPhotos: () -> Void
    let onMarkSold: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PMPrimaryButtonStyle())
                .help("Edit this item's details, pricing, and metadata")

                Button(action: onMarkSold) {
                    Label("Mark Sold", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PMTintButtonStyle(tint: .green))
                .help("Record this item as sold — moves it from Inventory to Sales")
            }

            HStack(spacing: 8) {
                Button(action: onPhotos) {
                    Label("Photos", systemImage: "photo.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PMGhostButtonStyle(tint: PM.cyan))
                .help("Manage photos — reorder, rotate, or sync from Google Drive")

                Button(action: onDuplicate) {
                    Label("Duplicate", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PMGhostButtonStyle(tint: PM.cyan))
                .help("Create copies of this item with new SKUs — useful for multiple prints of the same title")

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PMTintButtonStyle(tint: .red, prominent: false))
                .help("Permanently delete this item from your inventory")
            }
        }
        .padding(.horizontal, PM.Space.md)
        .padding(.vertical, PM.Space.md)
        .background {
            ZStack(alignment: .top) {
                PM.surface.opacity(0.97)
                LinearGradient(
                    colors: [.clear, PM.pink.opacity(0.4), PM.cyan.opacity(0.4), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 1)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: -4)
    }
}

// MARK: - Photo Gallery

struct PhotoGalleryView: View {
    let images: [String]
    @Binding var selectedIndex: Int
    @State private var loadedImages: [String: NSImage] = [:]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let img = loadedImages[images[safe: selectedIndex] ?? ""] {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(.black)
                } else {
                    Rectangle()
                        .fill(.black)
                        .overlay { ProgressView().tint(PM.cyan) }
                }
            }
            .frame(maxHeight: 220)

            if images.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(images.enumerated()), id: \.offset) { i, url in
                            Button {
                                selectedIndex = i
                            } label: {
                                Group {
                                    if let img = loadedImages[url] {
                                        Image(nsImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } else {
                                        Rectangle().fill(PM.raised)
                                    }
                                }
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(i == selectedIndex ? PM.pink : .clear, lineWidth: 2)
                                )
                                .pmGlow(PM.pink, radius: i == selectedIndex ? 4 : 0,
                                        opacity: i == selectedIndex ? 0.45 : 0)
                            }
                            .buttonStyle(.plain)
                            .help("View photo \(i + 1)")
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .frame(height: 48)
                .background(PM.surface.opacity(0.92))
            }
        }
        .task { await loadAll() }
    }

    private func loadAll() async {
        await withTaskGroup(of: (String, NSImage?).self) { group in
            for url in images {
                group.addTask {
                    guard let u = URL(string: url) else { return (url, nil) }
                    let img = await ImageCache.shared.fetch(u)
                    return (url, img)
                }
            }
            for await (url, img) in group {
                if let img { await MainActor.run { loadedImages[url] = img } }
            }
        }
    }
}

// MARK: - Description Preview
// Shows a collapsible plain-text preview of an HTML description field.

struct DescriptionPreview: View {
    let label: String
    let html: String
    let emptyMessage: String

    @State private var isExpanded = false

    var plainText: String {
        // Strip HTML tags and decode common entities for readable preview
        var text = html
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse excess blank lines
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(label)
                        .font(.pmBody(size: 12, weight: .medium))
                        .foregroundStyle(PM.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.4)
                    Spacer()
                    if html.isEmpty {
                        Text("None")
                            .font(.pmBody(size: 11))
                            .foregroundStyle(PM.textTertiary)
                    } else {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(PM.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if plainText.isEmpty {
                    Text(emptyMessage)
                        .font(.pmBody(size: 12))
                        .foregroundStyle(PM.textTertiary)
                        .italic()
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PM.base, in: RoundedRectangle(cornerRadius: PM.Radius.sm))
                } else {
                    Text(plainText)
                        .font(.pmBody(size: 12))
                        .foregroundStyle(PM.textSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(PM.base, in: RoundedRectangle(cornerRadius: PM.Radius.sm))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
