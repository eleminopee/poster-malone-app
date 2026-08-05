import Foundation
import SwiftUI

// ============================================================================
// ComicsStore.swift — the Comics module engine
//
// A COMPLETELY SEPARATE subsystem from the poster inventory: its own models,
// its own store singleton, its own JSON files (comics_inventory.json /
// comics_sales.json). Nothing here touches InventoryStore, poster automation,
// eBay/Shopify services, or any existing behavior.
//
// Contents:
//   • ComicRecord / ComicSaleRecord + enums (format, condition, shelf, status)
//   • ComicsStore — @Observable singleton, CRUD, mark-sold/restore, persistence
//   • ComicLookupService — ISBN → title/author/publisher/year (Google Books,
//     Open Library fallback; both free, no API key)
//   • ComicsEbayExport — File Exchange CSV mirroring the poster template's
//     structure (ScheduleTime scheduling, business-policy columns, BestOffer),
//     with book-specific columns (Product:ISBN for eBay catalog matching —
//     the CSV equivalent of scanning the barcode in the eBay app).
// ============================================================================

// MARK: - Enums

enum ComicFormat: String, Codable, CaseIterable, Identifiable {
    case omnibus        = "Omnibus"
    case hardcover      = "Hardcover"
    case tradePaperback = "Trade Paperback"
    case paperback      = "Paperback"
    case deluxeEdition  = "Deluxe Edition"
    case absoluteEdition = "Absolute Edition"
    case boxSet         = "Box Set"
    case singleIssue    = "Single Issue"
    case other          = "Other"
    var id: String { rawValue }
}

enum ComicCondition: String, Codable, CaseIterable, Identifiable {
    case brandNew  = "Brand New"
    case likeNew   = "Like New"
    case veryGood  = "Very Good"
    case good      = "Good"
    case acceptable = "Acceptable"
    var id: String { rawValue }

    /// eBay numeric Condition IDs for book categories.
    var ebayConditionId: String {
        switch self {
        case .brandNew:   return "1000"
        case .likeNew:    return "2750"
        case .veryGood:   return "4000"
        case .good:       return "5000"
        case .acceptable: return "6000"
        }
    }
}

/// Which shelf the book lives on. Personal Collection uses the identical
/// record shape — moving between shelves is a one-field change.
enum ComicShelf: String, Codable {
    case inventory
    case collection
}

enum ComicStatus: String, Codable, CaseIterable {
    case inStock = "In Stock"
    case listed  = "Listed"

    var color: Color {
        switch self {
        case .inStock: return .orange
        case .listed:  return .green
        }
    }
}

// MARK: - Records

struct ComicRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var isbn: String = ""
    var title: String = ""
    var artist: String = ""          // writer/artist as one field per workflow
    var publisher: String = ""
    var year: String = ""
    var format: ComicFormat = .hardcover
    var condition: ComicCondition = .likeNew
    var shelf: ComicShelf = .inventory
    var status: ComicStatus = .inStock

    var datePurchased: Date? = nil
    var pricePaid: Double = 0
    var askingPrice: Double = 0      // eBay price
    var dateListed: Date? = nil
    var dateAdded: Date = Date()

    var description: String = ""     // eBay description
    var notes: String = ""
    var images: [String] = []        // lh3 URLs, same pattern as posters
    var driveFolderId: String = ""

    /// Drive folder name: "Title - Artist - Format" (no SKUs — no duplicates
    /// in the comics world, per workflow decision).
    var driveFolderName: String {
        let parts = [title, artist, format.rawValue]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        // Drive disallows "/" in names
        return parts.joined(separator: " - ").replacingOccurrences(of: "/", with: "-")
    }

    var daysOwned: Int {
        guard let purchased = datePurchased else { return 0 }
        return Calendar.current.dateComponents([.day], from: purchased, to: Date()).day ?? 0
    }
}

struct ComicSaleRecord: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Full snapshot of the book at sale time — makes "return to inventory"
    /// a lossless restore.
    var comic: ComicRecord
    var dateSold: Date = Date()
    var soldPrice: Double = 0        // gross
    var feesAndShipping: Double = 0

    var profit: Double { soldPrice - feesAndShipping - comic.pricePaid }
}

// MARK: - Store

@MainActor
@Observable
final class ComicsStore {
    static let shared = ComicsStore()

    var comics: [ComicRecord] = []       // both shelves; filter by .shelf
    var sales: [ComicSaleRecord] = []
    var lastSaved: Date? = nil

    /// The Google Drive "Comics" root folder ID (detected or pasted once,
    /// persisted). Item folders are created inside it.
    var comicsDriveRootId: String {
        get { UserDefaults.standard.string(forKey: "comics_drive_root_id") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "comics_drive_root_id") }
    }

    private let comicsURL: URL
    private let salesURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first!
            .appendingPathComponent("PosterMalone", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        comicsURL = support.appendingPathComponent("comics_inventory.json")
        salesURL  = support.appendingPathComponent("comics_sales.json")
        load()
    }

    // MARK: Derived

    var inventory: [ComicRecord]  { comics.filter { $0.shelf == .inventory } }
    var collection: [ComicRecord] { comics.filter { $0.shelf == .collection } }

    var inventoryCostBasis: Double { inventory.reduce(0) { $0 + $1.pricePaid } }
    var inventoryAskingValue: Double { inventory.reduce(0) { $0 + $1.askingPrice } }
    var totalSalesGross: Double { sales.reduce(0) { $0 + $1.soldPrice } }
    var totalSalesProfit: Double { sales.reduce(0) { $0 + $1.profit } }

    // MARK: CRUD

    func add(_ comic: ComicRecord) {
        comics.append(comic)
        save()
    }

    func update(_ comic: ComicRecord) {
        guard let i = comics.firstIndex(where: { $0.id == comic.id }) else { return }
        comics[i] = comic
        save()
    }

    func delete(_ comic: ComicRecord) {
        comics.removeAll { $0.id == comic.id }
        save()
    }

    /// Sell a book: snapshot into a sale record, remove from the shelf.
    /// Financials can be entered now or later via the sale edit sheet.
    func markSold(_ comic: ComicRecord, dateSold: Date, soldPrice: Double, fees: Double) {
        var snapshot = comic
        snapshot.status = .listed   // preserved for the record
        let sale = ComicSaleRecord(comic: snapshot, dateSold: dateSold,
                                   soldPrice: soldPrice, feesAndShipping: fees)
        sales.insert(sale, at: 0)
        comics.removeAll { $0.id == comic.id }
        save()
    }

    func updateSale(_ sale: ComicSaleRecord) {
        guard let i = sales.firstIndex(where: { $0.id == sale.id }) else { return }
        sales[i] = sale
        save()
    }

    func deleteSale(_ sale: ComicSaleRecord) {
        sales.removeAll { $0.id == sale.id }
        save()
    }

    /// Undo a sale — restores the snapshot back to inventory.
    func returnToInventory(_ sale: ComicSaleRecord) {
        var restored = sale.comic
        restored.shelf = .inventory
        restored.status = .inStock
        comics.append(restored)
        sales.removeAll { $0.id == sale.id }
        save()
    }

    func moveToShelf(_ comic: ComicRecord, shelf: ComicShelf) {
        guard let i = comics.firstIndex(where: { $0.id == comic.id }) else { return }
        comics[i].shelf = shelf
        save()
    }

    // MARK: Persistence (simple immediate save — comic volumes are small)

    func save() {
        encode(comics, to: comicsURL)
        encode(sales, to: salesURL)
        lastSaved = Date()
    }

    private func load() {
        comics = decode(from: comicsURL) ?? []
        sales  = decode(from: salesURL) ?? []
        print("ComicsStore: loaded \(comics.count) comics, \(sales.count) sales")
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }
}

// MARK: - ISBN Lookup
// Google Books first (best metadata coverage, no key needed), Open Library
// as fallback + for physical format. Both free/public APIs.

struct ComicLookupResult {
    var title = ""
    var artist = ""
    var publisher = ""
    var year = ""
    var formatGuess: ComicFormat? = nil
    var coverURL: String? = nil
}

enum ComicLookupService {

    /// Optional ISBNdb API key. If set (in Comics settings), it's tried FIRST —
    /// it's the only source with reliable coverage of current/pre-order comic
    /// omnibuses. Without it, the free sources (Google Books, Open Library) are
    /// used, which often lack brand-new releases.
    static var isbndbKey: String {
        UserDefaults.standard.string(forKey: "comics_isbndb_key") ?? ""
    }

    static func lookup(isbn rawIsbn: String) async -> ComicLookupResult? {
        // Normalize: keep digits and X (ISBN-10 check digit)
        let isbn = rawIsbn.uppercased().filter { $0.isNumber || $0 == "X" }
        guard isbn.count == 10 || isbn.count == 13 else { return nil }

        // 1) ISBNdb first if a key is configured — best coverage for new comics.
        if !isbndbKey.isEmpty, let r = await isbndb(isbn: isbn) {
            return r
        }

        // 2) Google Books — exact isbn: index, then a looser general query.
        var result = await googleBooks(isbn: isbn, exact: true)
        if result == nil { result = await googleBooks(isbn: isbn, exact: false) }

        // 3) Open Library — the books endpoint, then the search endpoint.
        if let ol = await openLibrary(isbn: isbn) {
            if result == nil { result = ol }
            else { merge(&result!, ol) }
        }
        if result == nil, let ols = await openLibrarySearch(isbn: isbn) {
            result = ols
        }
        return result
    }

    private static func merge(_ base: inout ComicLookupResult, _ other: ComicLookupResult) {
        if base.formatGuess == nil { base.formatGuess = other.formatGuess }
        if base.coverURL == nil    { base.coverURL = other.coverURL }
        if base.publisher.isEmpty  { base.publisher = other.publisher }
        if base.artist.isEmpty     { base.artist = other.artist }
        if base.year.isEmpty       { base.year = other.year }
    }

    // MARK: ISBNdb (paid, optional — reliable for current comics)

    private static func isbndb(isbn: String) async -> ComicLookupResult? {
        guard var req = URLRequest(url: URL(string: "https://api2.isbndb.com/book/\(isbn)")!) as URLRequest? else { return nil }
        req.setValue(isbndbKey, forHTTPHeaderField: "Authorization")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let book = json["book"] as? [String: Any] else { return nil }

        var r = ComicLookupResult()
        r.title = book["title"] as? String ?? book["title_long"] as? String ?? ""
        if let authors = book["authors"] as? [String] {
            r.artist = authors.joined(separator: ", ")
        }
        r.publisher = book["publisher"] as? String ?? ""
        if let date = book["date_published"] as? String {
            r.year = String(date.prefix(4))
        }
        r.coverURL = book["image"] as? String
        let binding = book["binding"] as? String ?? ""
        r.formatGuess = guessFormat(from: binding.isEmpty ? r.title : binding)
        return r.title.isEmpty ? nil : r
    }

    // MARK: Google Books

    private static func googleBooks(isbn: String, exact: Bool) async -> ComicLookupResult? {
        // exact=true → "isbn:####" structured; exact=false → raw ISBN query.
        let q = exact ? "isbn:\(isbn)" : isbn
        guard let encoded = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.googleapis.com/books/v1/volumes?q=\(encoded)&maxResults=5") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else { return nil }

        // For the loose query, prefer an item whose industryIdentifiers match.
        let chosen: [String: Any]? = exact
            ? items.first?["volumeInfo"] as? [String: Any]
            : (items.first { item in
                guard let vi = item["volumeInfo"] as? [String: Any],
                      let ids = vi["industryIdentifiers"] as? [[String: Any]] else { return false }
                return ids.contains { ($0["identifier"] as? String)?.filter(\.isNumber) == isbn }
              }?["volumeInfo"] as? [String: Any]) ?? (items.first?["volumeInfo"] as? [String: Any])

        guard let info = chosen else { return nil }

        var r = ComicLookupResult()
        var title = info["title"] as? String ?? ""
        if let subtitle = info["subtitle"] as? String, !subtitle.isEmpty {
            title += ": \(subtitle)"
        }
        r.title = title
        r.artist = (info["authors"] as? [String])?.joined(separator: ", ") ?? ""
        r.publisher = info["publisher"] as? String ?? ""
        r.year = String((info["publishedDate"] as? String ?? "").prefix(4))
        if let links = info["imageLinks"] as? [String: Any],
           let thumb = (links["thumbnail"] ?? links["smallThumbnail"]) as? String {
            r.coverURL = thumb.replacingOccurrences(of: "http://", with: "https://")
        }
        r.formatGuess = guessFormat(from: title)
        return r.title.isEmpty ? nil : r
    }

    // MARK: Open Library

    private static func openLibrary(isbn: String) async -> ComicLookupResult? {
        guard let url = URL(string: "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&jscmd=data&format=json") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let book = json["ISBN:\(isbn)"] as? [String: Any] else { return nil }

        var r = ComicLookupResult()
        r.title = book["title"] as? String ?? ""
        if let authors = book["authors"] as? [[String: Any]] {
            r.artist = authors.compactMap { $0["name"] as? String }.joined(separator: ", ")
        }
        if let pubs = book["publishers"] as? [[String: Any]] {
            r.publisher = pubs.compactMap { $0["name"] as? String }.joined(separator: ", ")
        }
        if let dateStr = book["publish_date"] as? String {
            r.year = String(dateStr.suffix(4))
        }
        if let covers = book["cover"] as? [String: Any],
           let large = (covers["large"] ?? covers["medium"]) as? String {
            r.coverURL = large
        }
        if let format = book["physical_format"] as? String {
            r.formatGuess = guessFormat(from: format)
        } else {
            r.formatGuess = guessFormat(from: r.title)
        }
        return r.title.isEmpty ? nil : r
    }

    /// Open Library search endpoint — sometimes finds items the books API misses.
    private static func openLibrarySearch(isbn: String) async -> ComicLookupResult? {
        guard let url = URL(string: "https://openlibrary.org/search.json?isbn=\(isbn)&limit=1") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let docs = json["docs"] as? [[String: Any]],
              let doc = docs.first else { return nil }

        var r = ComicLookupResult()
        r.title = doc["title"] as? String ?? ""
        if let authors = doc["author_name"] as? [String] {
            r.artist = authors.joined(separator: ", ")
        }
        if let pubs = doc["publisher"] as? [String] {
            r.publisher = pubs.first ?? ""
        }
        if let year = doc["first_publish_year"] as? Int {
            r.year = String(year)
        }
        if let coverId = doc["cover_i"] as? Int {
            r.coverURL = "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg"
        }
        r.formatGuess = guessFormat(from: r.title)
        return r.title.isEmpty ? nil : r
    }

    private static func guessFormat(from text: String) -> ComicFormat? {
        let t = text.lowercased()
        if t.contains("omnibus") { return .omnibus }
        if t.contains("absolute") { return .absoluteEdition }
        if t.contains("deluxe") { return .deluxeEdition }
        if t.contains("box set") || t.contains("boxed set") { return .boxSet }
        if t.contains("hardcover") || t.contains("hardback") { return .hardcover }
        if t.contains("trade paperback") || t.contains("tpb") { return .tradePaperback }
        if t.contains("paperback") { return .paperback }
        return nil
    }
}

// MARK: - eBay File Exchange Export (Comics)
// Mirrors the poster CSV's structure — ScheduleTime scheduling, business
// policies, BestOffer — with book columns. `Product:ISBN` triggers eBay's
// catalog match (the CSV equivalent of scanning the barcode in the eBay app).

struct ComicsExportConfig {
    var startDate: Date
    var intervalMinutes: Int
    var categoryId: String
    var paymentProfile: String
    var returnProfile: String
    var shippingProfile: String
    var location: String = "Your City, State"
    var postalCode: String = "00000"

    // Persisted so setup is a one-time task.
    static func loadSaved() -> ComicsExportConfig {
        let d = UserDefaults.standard
        return ComicsExportConfig(
            startDate: Date().addingTimeInterval(2 * 3600),
            intervalMinutes: d.object(forKey: "comics_export_interval") as? Int ?? 20,
            // eBay: Books & Magazines > Comics & Graphic Novels.
            // VERIFY on your first upload — adjust here or in the export sheet
            // if File Exchange reports an invalid category.
            categoryId: d.string(forKey: "comics_export_category") ?? "259061",
            paymentProfile: d.string(forKey: "comics_export_payment") ?? "",
            returnProfile: d.string(forKey: "comics_export_return") ?? "",
            shippingProfile: d.string(forKey: "comics_export_shipping") ?? ""
        )
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(intervalMinutes, forKey: "comics_export_interval")
        d.set(categoryId, forKey: "comics_export_category")
        d.set(paymentProfile, forKey: "comics_export_payment")
        d.set(returnProfile, forKey: "comics_export_return")
        d.set(shippingProfile, forKey: "comics_export_shipping")
    }
}

enum ComicsEbayExport {

    /// Approximate shipping weight by format (lb, oz) + box dims — editable
    /// defaults; omnibuses are heavy, singles are light.
    static func package(for format: ComicFormat) -> (major: Int, minor: Int, l: Int, w: Int, d: Int) {
        switch format {
        case .omnibus, .absoluteEdition, .boxSet: return (5, 0, 14, 10, 4)
        case .hardcover, .deluxeEdition:          return (3, 0, 13, 9, 3)
        case .tradePaperback, .paperback:         return (1, 8, 12, 9, 2)
        case .singleIssue:                        return (0, 8, 12, 9, 1)
        case .other:                              return (2, 0, 13, 9, 3)
        }
    }

    static func csv(for comics: [ComicRecord], config: ComicsExportConfig)
        -> (csv: String, count: Int, hasLeadTimeWarning: Bool) {

        let header = [
            "Action(SiteID=US|Country=US|Currency=USD|Version=1193|CC=UTF-8)",
            "Custom label (SKU)", "Category ID", "Title", "Product:ISBN",
            "Price", "Quantity", "Item photo URL", "Condition ID",
            "Description", "Format", "Duration",
            "C:Publisher", "C:Format", "C:Author", "C:Publication Year",
            "C:Language", "C:Genre",
            "Location", "PostalCode",
            "PaymentProfileName", "ReturnProfileName", "ShippingProfileName",
            "WeightMajor", "WeightMinor", "PackageLength", "PackageWidth", "PackageDepth",
            "BestOfferEnabled", "MinimumBestOfferPrice", "BestOfferAutoAcceptPrice",
            "ScheduleTime"
        ]

        let now = Date()
        let oneHourFromNow = now.addingTimeInterval(3600)
        var hasLeadTimeWarning = false
        var scheduleTime = config.startDate
        var rows: [[String]] = []

        for comic in comics {
            if scheduleTime < oneHourFromNow { hasLeadTimeWarning = true }

            let pkg = package(for: comic.format)
            let listingTitle = ebayTitle(for: comic)
            let minOffer   = comic.askingPrice > 0 ? String(format: "%.2f", comic.askingPrice * 0.80) : ""
            let autoAccept = comic.askingPrice > 0 ? String(format: "%.2f", comic.askingPrice * 0.90) : ""

            rows.append([
                "Add",
                "COMIC-\(comic.id.uuidString.prefix(8))",
                config.categoryId,
                listingTitle,
                comic.isbn,
                comic.askingPrice > 0 ? String(format: "%.2f", comic.askingPrice) : "",
                "1",
                comic.images.joined(separator: "|"),
                comic.condition.ebayConditionId,
                comic.description.isEmpty ? defaultDescription(for: comic) : comic.description,
                "FixedPrice",
                "GTC",
                comic.publisher,
                comic.format.rawValue,
                comic.artist,
                comic.year,
                "English",
                "Comics & Graphic Novels",
                config.location,
                config.postalCode,
                config.paymentProfile,
                config.returnProfile,
                config.shippingProfile,
                String(pkg.major),
                String(pkg.minor),
                String(pkg.l),
                String(pkg.w),
                String(pkg.d),
                "true",
                minOffer,
                autoAccept,
                ebayDateTime(scheduleTime)
            ])

            scheduleTime = scheduleTime.addingTimeInterval(Double(config.intervalMinutes) * 60)
        }

        var lines = [csvRow(header)]
        rows.forEach { lines.append(csvRow($0)) }
        return (lines.joined(separator: "\n"), rows.count, hasLeadTimeWarning)
    }

    /// eBay title: "Title - Artist - Format Publisher" trimmed to 80 chars.
    static func ebayTitle(for comic: ComicRecord) -> String {
        var t = comic.title
        for extra in [comic.format.rawValue, comic.publisher] {
            let candidate = t + " " + extra
            if !extra.isEmpty && candidate.count <= 80 { t = candidate }
        }
        return String(t.prefix(80))
    }

    static func defaultDescription(for comic: ComicRecord) -> String {
        var parts: [String] = []
        parts.append("\(comic.title)")
        if !comic.artist.isEmpty    { parts.append("By \(comic.artist).") }
        if !comic.publisher.isEmpty { parts.append("Published by \(comic.publisher)\(comic.year.isEmpty ? "" : " (\(comic.year))").") }
        parts.append("Format: \(comic.format.rawValue). Condition: \(comic.condition.rawValue).")
        parts.append("From a smoke-free home. Carefully packed and shipped with tracking.")
        return parts.joined(separator: " ")
    }

    // CSV helpers (self-contained; EbayExportService's are private)

    private static func csvRow(_ fields: [String]) -> String {
        fields.map { f in
            if f.contains(",") || f.contains("\"") || f.contains("\n") {
                return "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return f
        }.joined(separator: ",")
    }

    private static func ebayDateTime(_ date: Date) -> String {
        // Matches EbayExportService.formatEbayDateTime exactly (UTC) — the
        // format already proven working in the poster File Exchange flow.
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        let y  = comps.year ?? 2026
        let mo = String(format: "%02d", comps.month ?? 1)
        let d  = String(format: "%02d", comps.day ?? 1)
        let h  = String(format: "%02d", comps.hour ?? 0)
        let mi = String(format: "%02d", comps.minute ?? 0)
        return "\(y)-\(mo)-\(d) \(h):\(mi):00"
    }
}
