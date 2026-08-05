import SwiftUI
import AppKit

// ============================================================================
// ComicSheets.swift — Comics module sheets
//   • ComicEditSheet — add/edit; ISBN lookup fills details; Drive folder
//     creation ("Title - Artist - Format") + photo sync (lh3 URLs, same as
//     posters)
//   • ComicMarkSoldSheet — date + optional price/fees (financials can wait)
//   • ComicSaleEditSheet — enter/adjust sale financials
//   • ComicsExportSheet — eBay File Exchange CSV with scheduling config
// ============================================================================

// MARK: - Edit Sheet

struct ComicEditSheet: View {
    @Environment(ComicsStore.self) var comicsStore
    @Environment(CredentialsManager.self) var credentials
    @Environment(PMRouter.self) var router
    @Environment(\.dismiss) var dismiss

    let isNew: Bool
    @State private var comic: ComicRecord

    @State private var isLookingUp = false
    @State private var lookupMessage: String? = nil
    @State private var isDriveWorking = false
    @State private var driveMessage: String? = nil
    @State private var isbndbKey: String = UserDefaults.standard.string(forKey: "comics_isbndb_key") ?? ""

    init(comic: ComicRecord, isNew: Bool) {
        self.isNew = isNew
        _comic = State(initialValue: comic)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("ISBN Lookup") {
                    HStack {
                        TextField("ISBN (scan the back-cover barcode)", text: $comic.isbn)
                        Button {
                            lookupISBN()
                        } label: {
                            if isLookingUp {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Look Up", systemImage: "sparkle.magnifyingglass")
                            }
                        }
                        .disabled(comic.isbn.trimmingCharacters(in: .whitespaces).isEmpty || isLookingUp)
                    }
                    if let lookupMessage {
                        Text(lookupMessage)
                            .font(.caption)
                            .foregroundStyle(lookupMessage.hasPrefix("✓") ? .green : .orange)
                    }
                    DisclosureGroup("ISBNdb key (optional — reliable for new releases)") {
                        SecureField("ISBNdb API key", text: $isbndbKey)
                            .onChange(of: isbndbKey) { _, new in
                                UserDefaults.standard.set(new, forKey: "comics_isbndb_key")
                            }
                        Text("Free sources (Google Books, Open Library) often lack brand-new or pre-order comic omnibuses. An ISBNdb key (~$15/mo at isbndb.com) covers current releases. Paste once — it's saved.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }

                Section("Book") {
                    TextField("Title", text: $comic.title)
                    TextField("Artist / Writer", text: $comic.artist)
                    TextField("Publisher", text: $comic.publisher)
                    TextField("Year", text: $comic.year)
                    Picker("Format", selection: $comic.format) {
                        ForEach(ComicFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Condition", selection: $comic.condition) {
                        ForEach(ComicCondition.allCases) { Text($0.rawValue).tag($0) }
                    }
                }

                Section("Purchase & Pricing") {
                    DatePicker("Date Purchased",
                               selection: Binding(
                                   get: { comic.datePurchased ?? Date() },
                                   set: { comic.datePurchased = $0 }
                               ),
                               displayedComponents: .date)
                    TextField("Price Paid", value: $comic.pricePaid, format: .currency(code: "USD"))
                    if comic.shelf == .inventory {
                        TextField("Asking Price (eBay)", value: $comic.askingPrice, format: .currency(code: "USD"))
                    }
                }

                Section("Photos") {
                    if comic.images.isEmpty {
                        Text("No photos yet. Create the Drive folder, drop photos in from your phone or Mac, then Sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(comic.images, id: \.self) { url in
                                    ThumbnailView(url: url, flat: true)
                                        .frame(width: 56, height: 80)
                                        .contextMenu {
                                            Button("Remove", role: .destructive) {
                                                comic.images.removeAll { $0 == url }
                                            }
                                        }
                                }
                            }
                        }
                        .frame(height: 88)
                    }

                    HStack(spacing: 8) {
                        if comic.driveFolderId.isEmpty {
                            Button {
                                createDriveFolder()
                            } label: {
                                if isDriveWorking {
                                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Working…") }
                                } else {
                                    Label("Create Drive Folder", systemImage: "folder.badge.plus")
                                }
                            }
                            .disabled(isDriveWorking || comic.title.trimmingCharacters(in: .whitespaces).isEmpty)
                        } else {
                            Button {
                                syncPhotos()
                            } label: {
                                if isDriveWorking {
                                    HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Syncing…") }
                                } else {
                                    Label("Sync Photos from Drive", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            .disabled(isDriveWorking)
                        }
                    }
                    if !comic.driveFolderId.isEmpty {
                        Text("Drive folder: \(comic.driveFolderName)")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let driveMessage {
                        Text(driveMessage)
                            .font(.caption)
                            .foregroundStyle(driveMessage.hasPrefix("✓") ? .green : .orange)
                    }
                }

                Section("eBay Listing") {
                    TextEditor(text: $comic.description)
                        .frame(minHeight: 70)
                        .font(.pmBody(size: 13))
                    Button("Use Standard Description") {
                        comic.description = ComicsEbayExport.defaultDescription(for: comic)
                    }
                    .font(.caption)
                }

                Section("Notes") {
                    TextField("Private notes", text: $comic.notes)
                }

                if !isNew {
                    Section {
                        Button("Delete Book", role: .destructive) {
                            comicsStore.delete(comic)
                            dismiss()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(isNew ? "Add Book" : "Edit Book")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isNew { comicsStore.add(comic) }
                        else     { comicsStore.update(comic) }
                        dismiss()
                    }
                    .disabled(comic.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(minWidth: 520, minHeight: 640)
    }

    // MARK: Actions

    private func lookupISBN() {
        isLookingUp = true
        lookupMessage = nil
        Task { @MainActor in
            if let result = await ComicLookupService.lookup(isbn: comic.isbn) {
                // Fill only empty fields — never clobber manual entries.
                if comic.title.isEmpty     { comic.title = result.title }
                if comic.artist.isEmpty    { comic.artist = result.artist }
                if comic.publisher.isEmpty { comic.publisher = result.publisher }
                if comic.year.isEmpty      { comic.year = result.year }
                if let format = result.formatGuess { comic.format = format }
                if comic.images.isEmpty, let cover = result.coverURL {
                    comic.images = [cover]   // stock cover placeholder; replace with real photos via Drive
                }
                lookupMessage = "✓ Found \"\(result.title)\" — review, adjust, and add your photos."
            } else {
                let hasKey = !(UserDefaults.standard.string(forKey: "comics_isbndb_key") ?? "").isEmpty
                lookupMessage = hasKey
                    ? "No match, even via ISBNdb — this ISBN may be too new or unlisted. Enter details manually."
                    : "No match in the free databases (common for brand-new/pre-order comics). Add an ISBNdb key above for reliable coverage, or enter details manually."
            }
            isLookingUp = false
        }
    }

    private func createDriveFolder() {
        isDriveWorking = true
        driveMessage = nil
        Task { @MainActor in
            do {
                // Find (or remember) the Comics root folder — searched with
                // YOUR account token, so no sharing setup is required.
                var rootId = comicsStore.comicsDriveRootId
                if rootId.isEmpty {
                    guard let found = try await GoogleDriveService.shared
                        .findFolderAnywhere(named: "Comics", credentials: credentials) else {
                        driveMessage = "Couldn't find a folder named \"Comics\" in your Drive — create one at the top level of My Drive, then retry."
                        isDriveWorking = false
                        return
                    }
                    rootId = found
                    comicsStore.comicsDriveRootId = found
                }

                let folderId = try await GoogleDriveService.shared.createFolder(
                    named: comic.driveFolderName,
                    inParent: rootId,
                    credentials: credentials
                )
                comic.driveFolderId = folderId
                driveMessage = "✓ Created \"\(comic.driveFolderName)\" — drop photos in, then Sync."
            } catch {
                driveMessage = "Drive error: \(error.localizedDescription)"
            }
            isDriveWorking = false
        }
    }

    private func syncPhotos() {
        isDriveWorking = true
        driveMessage = nil
        Task { @MainActor in
            do {
                let files = try await GoogleDriveService.shared.listImagesUser(
                    inFolder: comic.driveFolderId,
                    credentials: credentials
                )
                guard !files.isEmpty else {
                    driveMessage = "No images found in the folder yet."
                    isDriveWorking = false
                    return
                }
                // Make each public so lh3 thumbnail URLs render — the exact
                // pattern the poster photo flow uses.
                for file in files {
                    try? await GoogleDriveService.shared.makeFilePublic(
                        fileId: file.id, credentials: credentials)
                }
                comic.images = files.map { "https://lh3.googleusercontent.com/d/\($0.id)=w2000#.jpg" }
                driveMessage = "✓ Synced \(files.count) photo\(files.count == 1 ? "" : "s")."
            } catch {
                driveMessage = "Drive error: \(error.localizedDescription)"
            }
            isDriveWorking = false
        }
    }
}

// MARK: - Mark Sold Sheet

struct ComicMarkSoldSheet: View {
    @Environment(ComicsStore.self) var comicsStore
    @Environment(PMRouter.self) var router
    @Environment(\.dismiss) var dismiss

    let comic: ComicRecord
    @State private var dateSold = Date()
    @State private var soldPrice: Double = 0
    @State private var fees: Double = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Book", value: comic.title)
                    DatePicker("Date Sold", selection: $dateSold, displayedComponents: .date)
                }
                Section("Financials (optional — enter later from Sales)") {
                    TextField("Sold Price", value: $soldPrice, format: .currency(code: "USD"))
                    TextField("Fees + Shipping", value: $fees, format: .currency(code: "USD"))
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Mark Sold")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm Sale") {
                        comicsStore.markSold(comic, dateSold: dateSold,
                                             soldPrice: soldPrice, fees: fees)
                        router.showToast(.success, "\"\(comic.title)\" moved to Comic Sales")
                        dismiss()
                    }
                }
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(width: 420, height: 340)
    }
}

// MARK: - Sale Edit Sheet

struct ComicSaleEditSheet: View {
    @Environment(ComicsStore.self) var comicsStore
    @Environment(\.dismiss) var dismiss

    @State private var sale: ComicSaleRecord

    init(sale: ComicSaleRecord) {
        _sale = State(initialValue: sale)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Book", value: sale.comic.title)
                    LabeledContent("Paid", value: sale.comic.pricePaid.asCurrency)
                    DatePicker("Date Sold", selection: $sale.dateSold, displayedComponents: .date)
                }
                Section("Financials") {
                    TextField("Sold Price (gross)", value: $sale.soldPrice, format: .currency(code: "USD"))
                    TextField("Fees + Shipping", value: $sale.feesAndShipping, format: .currency(code: "USD"))
                    LabeledContent("Profit") {
                        Text(sale.profit.asCurrency)
                            .foregroundStyle(sale.profit >= 0 ? .green : .red)
                            .monospacedDigit()
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit Sale")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        comicsStore.updateSale(sale)
                        dismiss()
                    }
                }
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(width: 420, height: 380)
    }
}

// MARK: - eBay Export Sheet

struct ComicsExportSheet: View {
    @Environment(PMRouter.self) var router
    @Environment(\.dismiss) var dismiss

    let comics: [ComicRecord]
    var onExported: () -> Void = {}

    @State private var config = ComicsExportConfig.loadSaved()
    @State private var resultMessage: String? = nil
    @State private var resultIsError = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Books to export", value: "\(comics.count)")
                }
                Section("Listing Schedule (same workflow as posters)") {
                    DatePicker("First listing goes live", selection: $config.startDate)
                    Stepper("Interval: \(config.intervalMinutes) min between listings",
                            value: $config.intervalMinutes, in: 5...240, step: 5)
                }
                Section("eBay Setup (saved for next time)") {
                    TextField("Category ID", text: $config.categoryId)
                    Text("Books & Magazines → Comics & Graphic Novels. Verify on your first upload; File Exchange will flag an invalid category.")
                        .font(.caption2).foregroundStyle(.tertiary)
                    TextField("Payment Profile Name", text: $config.paymentProfile)
                    TextField("Return Profile Name", text: $config.returnProfile)
                    TextField("Shipping Profile Name", text: $config.shippingProfile)
                    Text("Use your eBay Business Policy names. Tip: create a Media Mail shipping policy for books — much cheaper than poster tubes.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Section {
                    Text("The CSV includes each book's ISBN (Product:ISBN), so eBay matches it to the catalog — the same thing scanning the barcode in the eBay app does.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let resultMessage {
                    Section {
                        Text(resultMessage)
                            .font(.callout)
                            .foregroundStyle(resultIsError ? .red : .green)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Export eBay CSV")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export CSV") { export() }
                        .disabled(comics.isEmpty)
                }
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(width: 520, height: 560)
    }

    private func export() {
        config.persist()
        let result = ComicsEbayExport.csv(for: comics, config: config)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "comics_ebay_upload.csv"
        panel.canCreateDirectories = true
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try result.csv.write(to: url, atomically: true, encoding: .utf8)
            var msg = "✓ Exported \(result.count) book\(result.count == 1 ? "" : "s") — upload via Seller Hub → Reports (File Exchange)."
            if result.hasLeadTimeWarning {
                msg += " ⚠︎ Some schedule times are under 1 hour out — eBay may reject those rows."
            }
            resultIsError = false
            resultMessage = msg
            NSWorkspace.shared.activateFileViewerSelecting([url])
            onExported()
        } catch {
            resultIsError = true
            resultMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}
