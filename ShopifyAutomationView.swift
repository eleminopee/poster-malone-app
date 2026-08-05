import SwiftUI

struct ShopifyAutomationView: View {
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @Environment(\.dismiss) var dismiss

    var initialTab: ShopifyTab = .generate
    @State private var selectedTab: ShopifyTab = .generate
    @State private var isWorking = false
    @State private var resultMessage: String? = nil
    @State private var resultIsError = false
    @State private var progress: (current: Int, total: Int)? = nil
    @State private var pushErrorLog: [(sku: String, error: String)] = []

    // Generate tab
    @State private var generatedPreviews: [GeneratedPreview] = []
    @State private var showingPreview = false

    enum ShopifyTab: String, CaseIterable {
        case generate = "Generate"
        case push     = "Push to Shopify"
        case export   = "Export CSV"
    }

    struct GeneratedPreview: Identifiable {
        let id = UUID()
        let sku: String
        let title: String
        let description: String
        var approved: Bool = true
    }

    var activeItems: [InventoryItem] {
        store.items.filter { $0.action.uppercased() == "Y" && !$0.sku.isEmpty }
    }

    var itemsMissingContent: [InventoryItem] {
        activeItems.filter { $0.shopifyDescription.isEmpty || $0.shopifyTitle.isEmpty }
    }

    var credentialsOK: Bool {
        !credentials.shopifyShop.isEmpty && !credentials.shopifyToken.isEmpty
    }

    /// Shopify brand green — used for the tab underline and accents in this sheet
    private let shopifyGreen = Color(red: 0.22, green: 0.67, blue: 0.33)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Tab bar — Shopify-green underline tabs
                HStack(spacing: 0) {
                    ForEach(ShopifyTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                            resultMessage = nil
                            generatedPreviews = []
                            pushErrorLog = []
                        } label: {
                            VStack(spacing: 0) {
                                Text(tab.rawValue)
                                    .font(.pmBody(size: 14, weight: selectedTab == tab ? .semibold : .medium))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(selectedTab == tab ? shopifyGreen : PM.textSecondary)
                                Rectangle()
                                    .fill(selectedTab == tab ? shopifyGreen : Color.clear)
                                    .frame(height: 2)
                                    .pmGlow(shopifyGreen, radius: selectedTab == tab ? 4 : 0,
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

                PMNeonDivider(color: shopifyGreen).opacity(0.4)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .generate: generatePanel
                        case .push:     pushPanel
                        case .export:   exportPanel
                        }
                    }
                    .padding(20)
                }

                // Progress bar
                if let p = progress {
                    Divider()
                    HStack(spacing: 10) {
                        ProgressView(value: Double(p.current), total: Double(p.total))
                            .frame(maxWidth: .infinity)
                        Text("\(p.current) / \(p.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }

                // Result banner
                if let msg = resultMessage {
                    Divider()
                    HStack(spacing: 10) {
                        Image(systemName: resultIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(resultIsError ? .red : .green)
                        Text(msg)
                            .font(.subheadline)
                        Spacer()
                        Button("Dismiss") { resultMessage = nil }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(resultIsError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
                }
            }
            .navigationTitle("Shopify Automation")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .pmScreen()
        .frame(minWidth: 700, minHeight: 540)
        .onAppear { selectedTab = initialTab }
    }

    // MARK: - Generate Panel

    var generatePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Generate Descriptions & Titles",
                subtitle: "Uses Claude AI to write SEO-optimized Shopify descriptions and titles for your active inventory.",
                icon: "sparkles"
            )

            if credentials.anthropicKey.isEmpty {
                MissingCredentialBox(message: "Anthropic API key not set. Add it in Admin → Credentials.")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ItemCountBadge(count: activeItems.count, label: "active items (Action = Y)")
                    ItemCountBadge(count: itemsMissingContent.count, label: "missing description or title")
                }

                if !generatedPreviews.isEmpty {
                    generatedPreviewList
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await generateContent(onlyMissing: true) }
                    } label: {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Generate Missing Only (\(itemsMissingContent.count))",
                                  systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || itemsMissingContent.isEmpty || credentials.anthropicKey.isEmpty)

                    Button {
                        Task { await generateContent(onlyMissing: false) }
                    } label: {
                        Label("Regenerate All (\(activeItems.count))", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isWorking || activeItems.isEmpty || credentials.anthropicKey.isEmpty)
                }

                if !generatedPreviews.isEmpty {
                    Button {
                        saveGeneratedContent()
                    } label: {
                        Label("Save \(generatedPreviews.filter(\.approved).count) Approved to Inventory",
                              systemImage: "tray.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(generatedPreviews.filter(\.approved).isEmpty)
                }

                InfoBox(text: "Estimated cost: ~$0.02 per item. Titles use format: Artist - Title - Size - Limited Edition Print/Poster.")
            }
        }
    }

    @ViewBuilder
    var generatedPreviewList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview — uncheck to skip saving")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(generatedPreviews.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Toggle("", isOn: $generatedPreviews[i].approved)
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        VStack(alignment: .leading, spacing: 2) {
                            Text(generatedPreviews[i].sku)
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(generatedPreviews[i].title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(generatedPreviews[i].description
                                    .replacingOccurrences(of: "<[^>]+>", with: "",
                                                          options: .regularExpression)
                                    .prefix(120) + "…")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    if i < generatedPreviews.count - 1 {
                        Divider().padding(.leading, 10)
                    }
                }
            }
            .background(PM.card, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Push Panel

    var pushPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Push to Shopify",
                subtitle: "Creates new products or updates existing ones via the Shopify API. Handles title, description, price, metafields, and SEO in one pass.",
                icon: "arrow.up.circle"
            )

            if !credentialsOK {
                MissingCredentialBox(message: "Shopify shop and token required. Add them in Admin → Credentials.")
            } else {
                ItemCountBadge(count: activeItems.count, label: "items will be pushed (Action = Y)")

                VStack(alignment: .leading, spacing: 8) {
                    Text("What gets pushed").font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach([
                            "Title (Shopify format)",
                            "Description / Body HTML",
                            "Price",
                            "Metafields (edition, gallery, size, artist slug, etc.)",
                            "SEO title & description",
                            "Product type & category",
                            "Collections (print type, theme/franchise, artist)",
                            "Inventory tracking enabled, qty set to 1",
                            "Photos from Google Drive"
                        ], id: \.self) { item in
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                                Text(item)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(10)
                .background(PM.card, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    Task { await pushToShopify() }
                } label: {
                    if isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Push \(activeItems.count) Items to Shopify", systemImage: "arrow.up.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking || activeItems.isEmpty)

                InfoBox(text: "New SKUs are created and published to your Online Store + Google/YouTube channels; existing SKUs are updated. Requires read_publications + write_publications on the Shopify token.")

                // Error log — shown after a push with errors
                if !pushErrorLog.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Error Details")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.red)
                            Spacer()
                            Button {
                                let text = pushErrorLog.map { "[\($0.sku)] \($0.error)" }.joined(separator: "\n\n")
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(text, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Copy all error details to clipboard")
                        }
                        VStack(spacing: 0) {
                            ForEach(pushErrorLog, id: \.sku) { entry in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.sku)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text(entry.error)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                Divider().padding(.leading, 10)
                            }
                        }
                        .background(.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.15), lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - Export Panel

    var exportPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(
                title: "Export Shopify CSV",
                subtitle: "Generates a Shopify-formatted CSV for bulk product import via Shopify Admin → Products → Import.",
                icon: "square.and.arrow.up"
            )

            ItemCountBadge(count: activeItems.count, label: "items will be exported (Action = Y)")

            Button {
                Task { await exportCSV() }
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Export Shopify CSV", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || activeItems.isEmpty)

            InfoBox(text: "Import the CSV in Shopify Admin → Products → Import. Products will be created as drafts. Use Push to Shopify for updates to existing products.")
        }
    }

    // MARK: - Actions

    private func generateContent(onlyMissing: Bool) async {
        isWorking = true
        resultMessage = nil
        generatedPreviews = []
        let items = onlyMissing ? itemsMissingContent : activeItems
        var previews: [GeneratedPreview] = []
        var errors = 0

        progress = (0, items.count)

        for (i, item) in items.enumerated() {
            progress = (i, items.count)
            do {
                let desc = try await ShopifyService.shared.generateDescription(
                    item: item, anthropicKey: credentials.anthropicKey)
                let title = await ShopifyService.shared.generateTitle(item)
                previews.append(GeneratedPreview(sku: item.sku, title: title, description: desc))
                // Brief pause to stay within API rate limits
                try? await Task.sleep(for: .milliseconds(1200))
            } catch {
                errors += 1
            }
        }

        progress = nil
        generatedPreviews = previews
        isWorking = false

        if errors > 0 {
            resultIsError = true
            resultMessage = "Generated \(previews.count) items. \(errors) failed — check that your Anthropic API key is valid."
        } else {
            resultIsError = false
            resultMessage = "Generated \(previews.count) items. Review below then tap Save."
        }
    }

    private func saveGeneratedContent() {
        let approved = generatedPreviews.filter(\.approved)
        for preview in approved {
            guard var item = store.items.first(where: { $0.sku == preview.sku }) else { continue }
            item.shopifyTitle = preview.title
            item.shopifyDescription = preview.description
            store.update(item)
        }
        generatedPreviews = []
        resultIsError = false
        resultMessage = "✓ Saved \(approved.count) descriptions & titles to inventory."
    }

    private func pushToShopify() async {
        isWorking = true
        resultMessage = nil
        pushErrorLog = []
        var created = 0; var updated = 0; var errors = 0

        progress = (0, activeItems.count)
        var pushedItems: [InventoryItem] = []   // for uncheck-on-success
        var publishWarning = false              // channel publish failed (e.g. scope)

        for (i, item) in activeItems.enumerated() {
            progress = (i, activeItems.count)
            do {
                let existingId = try await ShopifyService.shared.getProductId(
                    shop: credentials.shopifyShop,
                    token: credentials.shopifyToken,
                    sku: item.sku
                )

                if let productId = existingId {
                    // Update existing
                    try await ShopifyService.shared.updateProduct(
                        shop: credentials.shopifyShop,
                        token: credentials.shopifyToken,
                        productId: productId,
                        item: item
                    )
                    try await ShopifyService.shared.setMetafields(
                        shop: credentials.shopifyShop,
                        token: credentials.shopifyToken,
                        productId: productId,
                        item: item
                    )
                    if item.shopifyPrice > 0,
                       let variantId = try? await ShopifyService.shared.getVariantId(
                           shop: credentials.shopifyShop,
                           token: credentials.shopifyToken,
                           sku: item.sku) {
                        try await ShopifyService.shared.updatePrice(
                            shop: credentials.shopifyShop,
                            token: credentials.shopifyToken,
                            productId: productId,
                            variantId: variantId,
                            price: item.shopifyPrice
                        )
                    }
                    try await ShopifyService.shared.addToCollections(
                        shop: credentials.shopifyShop,
                        token: credentials.shopifyToken,
                        productId: productId,
                        item: item
                    )
                    if !item.images.isEmpty {
                        try await ShopifyService.shared.pushImages(
                            shop: credentials.shopifyShop,
                            token: credentials.shopifyToken,
                            productId: productId,
                            imageURLs: item.images
                        )
                    }
                    // Publish to channels — BEST EFFORT. The product is already
                    // updated; a publish failure (e.g. missing write_publications
                    // scope) must NOT mark the whole push as failed.
                    do {
                        try await ShopifyService.shared.publishProduct(
                            shop: credentials.shopifyShop,
                            token: credentials.shopifyToken,
                            productId: productId
                        )
                    } catch {
                        publishWarning = true
                        pushErrorLog.append((sku: item.sku, error: "Updated, but channel publish failed: \(error.localizedDescription)"))
                    }
                    updated += 1
                    store.markListedOnShopify(item)   // sets shopifyStatus + listingMarketplace
                    store.addPaperTrailEntry(action: .pushedShopify, item: item)
                    pushedItems.append(item)

                } else {
                    // Create new
                    let productId = try await ShopifyService.shared.createProduct(
                        shop: credentials.shopifyShop,
                        token: credentials.shopifyToken,
                        item: item
                    )
                    try await ShopifyService.shared.setMetafields(
                        shop: credentials.shopifyShop,
                        token: credentials.shopifyToken,
                        productId: productId,
                        item: item
                    )
                    try await ShopifyService.shared.addToCollections(
                        shop: credentials.shopifyShop,
                        token: credentials.shopifyToken,
                        productId: productId,
                        item: item
                    )
                    try await ShopifyService.shared.enableInventoryTracking(
                        shop: credentials.shopifyShop,
                        token: credentials.shopifyToken,
                        productId: productId,
                        sku: item.sku
                    )
                    if !item.images.isEmpty {
                        try await ShopifyService.shared.pushImages(
                            shop: credentials.shopifyShop,
                            token: credentials.shopifyToken,
                            productId: productId,
                            imageURLs: item.images
                        )
                    }
                    // Publish to channels — BEST EFFORT (see note above). The
                    // product exists regardless; only channel visibility fails.
                    do {
                        try await ShopifyService.shared.publishProduct(
                            shop: credentials.shopifyShop,
                            token: credentials.shopifyToken,
                            productId: productId
                        )
                    } catch {
                        publishWarning = true
                        pushErrorLog.append((sku: item.sku, error: "Created, but channel publish failed: \(error.localizedDescription)"))
                    }
                    var updated_item = item
                    updated_item.shopifyAPIUpdates = Date()
                    store.update(updated_item)
                    created += 1
                    store.markListedOnShopify(item)   // sets shopifyStatus + listingMarketplace
                    store.addPaperTrailEntry(action: .pushedShopify, item: item)
                    pushedItems.append(item)
                }

            } catch {
                errors += 1
                pushErrorLog.append((sku: item.sku, error: error.localizedDescription))
            }
        }

        // Uncheck (action = "") every item that pushed successfully — one batch
        // = one recompute + one save. They drop out of the NOT ON SHOPIFY view.
        if !pushedItems.isEmpty {
            var batch: [InventoryItem] = []
            for var p in pushedItems {
                // Re-read latest (markListedOnShopify mutated status) before clearing flag.
                if let current = store.items.first(where: { $0.id == p.id }) {
                    p = current
                }
                p.action = ""
                batch.append(p)
            }
            store.updateBatch(batch)
        }

        progress = nil
        isWorking = false
        resultIsError = errors > 0
        var msg = "Created: \(created)  Updated: \(updated)  Errors: \(errors)"
        if publishWarning {
            msg += "  ⚠︎ Products saved but not published to channels — enable read_publications + write_publications on the Shopify token (Admin → credentials)."
        }
        resultMessage = msg
    }

    private func exportCSV() async {
        isWorking = true
        resultMessage = nil
        do {
            let csv = try ShopifyExportService.buildCSV(items: activeItems)
            let ts = timestamp()
            let url = try await MainActor.run {
                try ShopifyExportService.saveToFile(csv, filename: "shopify_products_\(ts).csv")
            }
            resultIsError = false
            resultMessage = "✓ Exported \(activeItems.count) items → \(url.lastPathComponent)"
            NSWorkspace.shared.selectFile(url.path,
                                          inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        } catch {
            resultIsError = true
            resultMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: Date())
    }
}

// MARK: - Supporting Views

struct MissingCredentialBox: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .pmGlow(.orange, radius: 4, opacity: 0.4)
            Text(message)
                .font(.pmBody(size: 12))
                .foregroundStyle(PM.textSecondary)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: PM.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: PM.Radius.sm)
                .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
        )
    }
}
