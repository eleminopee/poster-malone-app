import SwiftUI

// MARK: - eBay Store Category Mapping

struct EbayStoreCategory: Identifiable, Hashable {
    let id: String
    let label: String
}

enum EbayStoreCategoryMap {

    static let moviePosterCat1: [EbayStoreCategory] = [
        EbayStoreCategory(id: "49066240018", label: "Animation & Anime"),
        EbayStoreCategory(id: "49066249018", label: "DC"),
        EbayStoreCategory(id: "49066239018", label: "Horror"),
        EbayStoreCategory(id: "49066242018", label: "Marvel"),
        EbayStoreCategory(id: "49066287018", label: "Other"),
        EbayStoreCategory(id: "49066238018", label: "Sci-Fi & Fantasy"),
        EbayStoreCategory(id: "49066241018", label: "Star Wars"),
    ]

    static let artPosterCat1: [EbayStoreCategory] = [
        EbayStoreCategory(id: "49066272018", label: "Animation & Anime"),
        EbayStoreCategory(id: "49066267018", label: "DC"),
        EbayStoreCategory(id: "49066269018", label: "Horror"),
        EbayStoreCategory(id: "49066266018", label: "Marvel"),
        EbayStoreCategory(id: "49066271018", label: "Other"),
        EbayStoreCategory(id: "49066270018", label: "Sci-Fi & Fantasy"),
        EbayStoreCategory(id: "49066268018", label: "Star Wars"),
    ]

    static let artPrintCat1: [EbayStoreCategory] = artPosterCat1

    static let cat2Options: [EbayStoreCategory] = [
        EbayStoreCategory(id: "",            label: "None"),
        EbayStoreCategory(id: "49066160018", label: "Imperfects/Damaged Deals"),
        EbayStoreCategory(id: "49066159018", label: "Private Commissions"),
    ]

    static func cat1Options(for printType: String) -> [EbayStoreCategory] {
        switch printType.lowercased() {
        case "movie poster":  return moviePosterCat1
        case "art poster":    return artPosterCat1
        case "art print", "mini print": return artPrintCat1
        default:
            return (moviePosterCat1 + artPosterCat1)
                .reduce(into: [EbayStoreCategory]()) { result, cat in
                    if !result.contains(where: { $0.id == cat.id }) { result.append(cat) }
                }
                .sorted { $0.label < $1.label }
        }
    }

    static func label(for id: String) -> String? {
        let all = moviePosterCat1 + artPosterCat1 + cat2Options
        return all.first(where: { $0.id == id })?.label
    }
}

// MARK: - Item Edit Sheet

struct ItemEditSheet: View {
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @Environment(\.dismiss) var dismiss
    @State var item: InventoryItem
    @Binding var selectedItem: InventoryItem?

    var isNewItem: Bool

    // Shopify section state
    @State private var isGenerating = false
    @State private var isCheckingStatus = false
    @State private var shopifyStatusDisplay: ShopifyStatusDisplay = .unknown
    @State private var generateError: String? = nil

    // eBay Item ID fetch state
    @State private var isFetchingItemId = false
    @State private var itemIdFetchMessage: String? = nil

    enum ShopifyStatusDisplay {
        case unknown
        case checking
        case notListed
        case active
        case draft
        case archived
        case error(String)

        var label: String {
            switch self {
            case .unknown:        return "—"
            case .checking:       return "Checking..."
            case .notListed:      return "Not Listed"
            case .active:         return "Active"
            case .draft:          return "Draft"
            case .archived:       return "Archived"
            case .error:          return "Error"
            }
        }

        var color: Color {
            switch self {
            case .active:         return .green
            case .draft:          return .orange
            case .archived:       return .secondary
            case .notListed:      return .secondary
            case .error:          return .red
            default:              return .secondary
            }
        }

        var icon: String {
            switch self {
            case .active:         return "checkmark.circle.fill"
            case .draft:          return "pencil.circle.fill"
            case .archived:       return "archivebox.fill"
            case .notListed:      return "minus.circle"
            case .error:          return "exclamationmark.circle.fill"
            default:              return "questionmark.circle"
            }
        }
    }

    init(item: InventoryItem, selectedItem: Binding<InventoryItem?> = .constant(nil)) {
        _item = State(initialValue: item)
        _selectedItem = selectedItem
        isNewItem = item.sku.isEmpty
    }

    var cat1Options: [EbayStoreCategory] {
        EbayStoreCategoryMap.cat1Options(for: item.printType)
    }

    var canGenerate: Bool {
        !credentials.anthropicKey.isEmpty && !item.title.isEmpty && !item.artist.isEmpty
    }

    var canCheckStatus: Bool {
        !credentials.shopifyShop.isEmpty && !credentials.shopifyToken.isEmpty && !item.sku.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Core Details
                Section("Core Details") {
                    HStack {
                        TextField("SKU", text: $item.sku)
                        if isNewItem {
                            Text("Auto-assigned")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PM.raised, in: Capsule())
                        }
                    }
                    TextField("Artist", text: $item.artist)
                    TextField("Title", text: $item.title)
                    TextField("Size", text: $item.size)
                    TextField("Edition", text: $item.edition)
                    Picker("Print Type", selection: $item.printType) {
                        Text("— Select —").tag("")
                        Text("Movie Poster").tag("Movie Poster")
                        Text("Art Poster").tag("Art Poster")
                        Text("Art Print").tag("Art Print")
                        Text("Mini Print").tag("Mini Print")
                    }
                    .onChange(of: item.printType) { _, newType in
                        switch newType.lowercased() {
                        case "movie poster":                          item.ebayCategoryId = "28009"
                        case "art poster", "art print", "mini print": item.ebayCategoryId = "20081"
                        default: break
                        }
                    }
                    Picker("Production Technique", selection: $item.productionTechnique) {
                        Text("— Select —").tag("")
                        Text("Screen Print").tag("Screen Print")
                        Text("Giclée").tag("Giclée")
                        Text("Lithograph").tag("Lithograph")
                        Text("Offset Print").tag("Offset Print")
                        Text("Digital Print").tag("Digital Print")
                    }
                    TextField("Gallery", text: $item.gallery)
                }

                // MARK: Storage
                Section("Storage") {
                    TextField("Drawer", text: $item.drawer)
                    TextField("Sleeve #", text: $item.sleeveNumber)
                }

                // MARK: Classification
                Section("Classification") {
                    TextField("Franchise", text: $item.franchise)
                    TextField("Character", text: $item.character)
                    TextField("Theme", text: $item.theme)
                    TextField("Tags", text: $item.tags)
                    TextField("Condition", text: $item.condition)
                    Toggle("Signed", isOn: $item.signed)
                    Toggle("Imperfect", isOn: $item.imperfect)
                }

                // MARK: Acquisition
                Section("Acquisition") {
                    DatePicker("Date Purchased", selection: Binding(
                        get: { item.datePurchased ?? Date() },
                        set: { item.datePurchased = $0 }
                    ), displayedComponents: .date)
                    TextField("Net Cost", value: $item.netCost, format: .currency(code: "USD"))
                    TextField("Tax & Shipping", value: $item.taxAndShipping, format: .currency(code: "USD"))
                }

                // MARK: Pricing & Listing Status
                Section("Pricing & Listing Status") {
                    TextField("eBay Price", value: $item.ebayPrice, format: .currency(code: "USD"))
                        .onChange(of: item.ebayPrice) { _, newPrice in
                            if newPrice > 0 {
                                let raw = newPrice * 0.80
                                item.shopifyPrice = (raw * 100).rounded() / 100
                            }
                            item.priceUpdatedAt = Date()
                        }
                        .help("Setting eBay price automatically calculates Shopify price at 80%")

                    HStack {
                        TextField("Shopify Price", value: $item.shopifyPrice, format: .currency(code: "USD"))
                        if item.ebayPrice > 0 {
                            Text("80% of eBay")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PM.raised, in: Capsule())
                        }
                    }
                    .help("Shopify price is auto-set to 80% of eBay price. You can override manually.")

                    Picker("Inventory Status", selection: $item.status) {
                        ForEach(ItemStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .help("Your internal inventory status")

                    Picker("Listed On", selection: $item.listingMarketplace) {
                        ForEach(ListingMarketplace.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .help("Where this item is currently listed for sale")

                    // Listed Date — optional, blank by default until actually listed
                    HStack {
                        if let listed = item.dateListed {
                            DatePicker("Listed Date", selection: Binding(
                                get: { listed },
                                set: { item.dateListed = $0 }
                            ), displayedComponents: .date)
                            Button {
                                item.dateListed = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear listed date")
                        } else {
                            Text("Listed Date")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Set Date") {
                                item.dateListed = Date()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                // MARK: eBay
                Section("eBay") {

                    // eBay Description generate / clear / edit
                    HStack(spacing: 8) {
                        Button {
                            item.description = item.generatedEbayDescription()
                        } label: {
                            Label(item.description.isEmpty ? "Generate Description" : "Regenerate",
                                  systemImage: "doc.text")
                        }
                        .buttonStyle(.bordered)
                        .help("Builds a structured eBay HTML description from item details")

                        if !item.description.isEmpty {
                            Button(role: .destructive) {
                                item.description = ""
                            } label: {
                                Label("Clear", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .help("Clear so you can regenerate from scratch")
                        }
                    }

                    if !item.description.isEmpty {
                        TextEditor(text: $item.description)
                            .font(.caption)
                            .frame(minHeight: 120, maxHeight: 200)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PM.borderStrong))
                            .help("Edit the eBay description directly")
                    }

                    TextField("eBay Title", text: $item.ebayTitle)

                    // Generate eBay Title button
                    HStack(spacing: 8) {
                        Button {
                            item.ebayTitle = item.generatedEbayTitle()
                        } label: {
                            Label(item.ebayTitle.isEmpty ? "Generate eBay Title" : "Regenerate Title",
                                  systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.bordered)
                        .disabled(item.title.isEmpty || item.artist.isEmpty)
                        .help("Generates: Title Mondo Size Poster Artist Limited Edition Print")

                        if !item.ebayTitle.isEmpty {
                            Button(role: .destructive) {
                                item.ebayTitle = ""
                            } label: {
                                Label("Clear", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .help("Clear the eBay title")
                        }
                    }

                    // Title length counter — eBay limit is 80 characters
                    let titleLen = item.ebayTitle.count
                    HStack(spacing: 6) {
                        ProgressView(value: Double(min(titleLen, 80)), total: 80)
                            .tint(titleLen > 80 ? .red : titleLen > 70 ? .orange : .green)
                            .frame(maxWidth: .infinity)
                        Text("\(titleLen) / 80")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(titleLen > 80 ? .red : titleLen > 70 ? .orange : .secondary)
                            .monospacedDigit()
                    }
                    if titleLen > 80 {
                        Text("Title exceeds 80 characters — eBay will reject this listing")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    TextField("Category ID", text: $item.ebayCategoryId)

                    if cat1Options.isEmpty {
                        TextField("Store Category 1 ID", text: $item.storeCategory1)
                    } else {
                        Picker("Store Category 1", selection: $item.storeCategory1) {
                            Text("— Select —").tag("")
                            ForEach(cat1Options) { cat in
                                Text(cat.label).tag(cat.id)
                            }
                        }
                        .onChange(of: item.printType) { _, _ in
                            let validIDs = cat1Options.map(\.id)
                            if !validIDs.contains(item.storeCategory1) {
                                item.storeCategory1 = ""
                            }
                        }
                        .help("Filtered by Print Type")
                    }

                    Picker("Store Category 2", selection: $item.storeCategory2) {
                        ForEach(EbayStoreCategoryMap.cat2Options) { cat in
                            Text(cat.label).tag(cat.id)
                        }
                    }
                    .help("Use for Imperfects/Damaged Deals or Private Commissions")

                    TextField("Payment Profile", text: $item.paymentProfileName)
                    TextField("Shipping Profile", text: $item.shippingProfileName)
                    TextField("Return Profile", text: $item.returnProfileName)

                    // eBay Item ID — at bottom of eBay section
                    Divider()
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("eBay Item ID")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if item.ebayItemId.isEmpty {
                                Text("Not set")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            } else {
                                Text(item.ebayItemId)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                        if isFetchingItemId {
                            ProgressView().controlSize(.small)
                        } else {
                            Button {
                                Task { await fetchEbayItemId() }
                            } label: {
                                Label(item.ebayItemId.isEmpty ? "Fetch from eBay" : "Refresh",
                                      systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(item.sku.isEmpty)
                            .help(item.sku.isEmpty
                                  ? "SKU required to look up eBay Item ID"
                                  : "Looks up this SKU in your active eBay listings and stores the Item ID")
                        }
                    }
                    if let msg = itemIdFetchMessage {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(msg.hasPrefix("✓") ? Color.green : Color.red)
                    }
                    if !item.ebayItemId.isEmpty {
                        Link("View on eBay ↗",
                             destination: URL(string: "https://www.ebay.com/itm/\(item.ebayItemId)")!)
                            .font(.caption)
                    }
                }

                // MARK: Shopify
                Section("Shopify") {

                    // Generate Title + Description
                    Button {
                        Task { await generateShopifyContent() }
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView().controlSize(.small)
                                Text("Generating...")
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(canGenerate ? Color.accentColor : .secondary)
                                Text(item.shopifyTitle.isEmpty && item.shopifyDescription.isEmpty
                                     ? "Generate Title & Description"
                                     : "Regenerate Title & Description")
                                    .foregroundStyle(canGenerate ? .primary : .secondary)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isGenerating || !canGenerate)
                    .help(canGenerate
                          ? "Uses Claude AI to write a Shopify title and SEO description"
                          : "Requires Artist, Title, and Anthropic API key in Admin → Credentials")

                    if let err = generateError {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }

                    TextField("Shopify Title", text: $item.shopifyTitle)
                        .help("Format: Artist - Title - Size - Limited Edition Print/Poster")

                    // Shopify Description — editable + clear
                    if !item.shopifyDescription.isEmpty {
                        HStack {
                            Text("Shopify Description")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button(role: .destructive) {
                                item.shopifyDescription = ""
                            } label: {
                                Label("Clear", systemImage: "trash").font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Clear so you can regenerate")
                        }
                        TextEditor(text: $item.shopifyDescription)
                            .font(.caption)
                            .frame(minHeight: 100, maxHeight: 180)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(PM.borderStrong))
                            .help("Edit the Shopify description directly")
                    }

                    // Shopify Handle — read-only
                    HStack {
                        Text("URL Handle").foregroundStyle(.secondary)
                        Spacer()
                        if item.shopifyHandle.isEmpty {
                            Text("Assigned when created on Shopify")
                                .font(.caption).foregroundStyle(.tertiary)
                        } else {
                            Text(item.shopifyHandle)
                                .font(.caption).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .help("URL slug — set automatically by Shopify on product creation")

                    // Shopify live status check
                    HStack {
                        Button {
                            Task { await checkShopifyStatus() }
                        } label: {
                            HStack(spacing: 6) {
                                if isCheckingStatus {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise.circle")
                                }
                                Text("Check Shopify Status")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isCheckingStatus || !canCheckStatus)
                        .help(canCheckStatus
                              ? "Check the live Shopify status of this product"
                              : "Requires Shopify credentials in Admin → Credentials")

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: shopifyStatusDisplay.icon)
                            Text(shopifyStatusDisplay.label)
                        }
                        .font(.caption).fontWeight(.medium)
                        .foregroundStyle(shopifyStatusDisplay.color)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(shopifyStatusDisplay.color.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 6))
                    }

                    if case .error(let msg) = shopifyStatusDisplay {
                        Text(msg).font(.caption).foregroundStyle(.red)
                    }
                }

                // MARK: Instagram
                Section("Instagram") {
                    Toggle("Queue for Instagram", isOn: $item.igPost)

                    // Generate caption
                    HStack(spacing: 8) {
                        Button {
                            item.igCaption = buildIGCaption(item)
                        } label: {
                            Label(item.igCaption.isEmpty ? "Generate Caption" : "Regenerate",
                                  systemImage: "camera")
                        }
                        .buttonStyle(.bordered)
                        .help("Builds an Instagram caption from this item's details")

                        if !item.igCaption.isEmpty {
                            Button(role: .destructive) {
                                item.igCaption = ""
                            } label: {
                                Label("Clear", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .help("Clear the caption so you can regenerate")
                        }
                    }

                    TextField("Caption", text: $item.igCaption, axis: .vertical)
                        .lineLimit(3...8)
                        .help("Edit the caption directly")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(isNewItem ? "New Item" : "Edit Item")
            .onAppear {
                if isNewItem {
                    item.sku = store.nextSKU
                    item.datePurchased = Date()
                    // Default eBay profiles
                    item.paymentProfileName  = "eBay_Payments"
                    item.shippingProfileName = "Free_USPS_Ground"
                    item.returnProfileName   = "30_Day_Return"
                    item.weight             = 2.0
                    item.status             = .processed
                }
                // Initialise the status badge from stored value
                shopifyStatusDisplay = displayFromStored(item.shopifyStatus)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .help("Discard changes and close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isNewItem { store.add(item) } else { store.update(item) }
                        // Immediately refresh the detail panel with the saved data
                        selectedItem = item
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Save changes to inventory")
                }
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(minWidth: 500, minHeight: 600)
    }

    // MARK: - eBay Item ID Fetch

    private func fetchEbayItemId() async {
        guard !item.sku.isEmpty else { return }
        isFetchingItemId = true
        itemIdFetchMessage = nil
        do {
            let listings = try await EbayService.shared.getAllActiveListings(credentials: credentials)
            if let match = listings.first(where: { $0.sku == item.sku }) {
                item.ebayItemId = match.itemId
                itemIdFetchMessage = "✓ Found: \(match.itemId)"
            } else {
                itemIdFetchMessage = "No active eBay listing found for SKU \(item.sku)"
            }
        } catch {
            itemIdFetchMessage = "Error: \(error.localizedDescription)"
        }
        isFetchingItemId = false
    }

    // MARK: - Instagram Caption Builder

    private func buildIGCaption(_ item: InventoryItem) -> String {
        var lines: [String] = []

        // Line 1: Artist. Title.
        let artistLine = [item.artist, item.title]
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        if !artistLine.isEmpty { lines.append(artistLine + ".") }

        // Line 2: Edition info
        if !item.edition.isEmpty {
            lines.append("Edition: \(item.edition)")
        }

        // Line 3: Gallery
        if !item.gallery.isEmpty {
            lines.append(item.gallery)
        }

        // Line 4: Size + technique
        let details = [item.size, item.productionTechnique]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        if !details.isEmpty { lines.append(details) }

        // Blank line before call to action
        lines.append("")
        lines.append("Available now. Link in bio.")

        // Hashtags
        var tags: [String] = ["#postermalone", "#alternativemovieposters",
                              "#limitededitionprint", "#screenprint"]
        if !item.artist.isEmpty {
            let slug = item.artist
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
            tags.append("#\(slug)")
        }
        if !item.gallery.isEmpty {
            let slug = item.gallery
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
            tags.append("#\(slug)")
        }
        if !item.franchise.isEmpty {
            let slug = item.franchise
                .lowercased()
                .replacingOccurrences(of: " ", with: "")
            tags.append("#\(slug)")
        }
        lines.append(tags.joined(separator: " "))

        return lines.joined(separator: "\n")
    }

    // MARK: - Generate Title & Description

    private func generateShopifyContent() async {
        isGenerating = true
        generateError = nil
        do {
            let desc  = try await ShopifyService.shared.generateDescription(
                item: item, anthropicKey: credentials.anthropicKey)
            let title = await ShopifyService.shared.generateTitle(item)
            item.shopifyDescription = desc
            item.shopifyTitle = title
        } catch {
            generateError = error.localizedDescription
        }
        isGenerating = false
    }

    // MARK: - Check Shopify Status

    private func checkShopifyStatus() async {
        isCheckingStatus = true
        shopifyStatusDisplay = .checking
        do {
            let info = try await ShopifyService.shared.getProductStatus(
                shop: credentials.shopifyShop,
                token: credentials.shopifyToken,
                sku: item.sku
            )
            if let info {
                // Save handle back to item
                item.shopifyHandle = info.handle
                item.shopifyStatus = info.status
                shopifyStatusDisplay = displayFromAPI(info.status)
            } else {
                item.shopifyStatus = ""
                shopifyStatusDisplay = .notListed
            }
        } catch {
            shopifyStatusDisplay = .error(error.localizedDescription)
        }
        isCheckingStatus = false
    }

    // MARK: - Status Helpers

    private func displayFromAPI(_ status: String) -> ShopifyStatusDisplay {
        switch status.uppercased() {
        case "ACTIVE":   return .active
        case "DRAFT":    return .draft
        case "ARCHIVED": return .archived
        default:         return .notListed
        }
    }

    private func displayFromStored(_ stored: String) -> ShopifyStatusDisplay {
        switch stored.uppercased() {
        case "ACTIVE":   return .active
        case "DRAFT":    return .draft
        case "ARCHIVED": return .archived
        case "":         return .unknown
        default:         return .unknown
        }
    }
}
