import Foundation
import AppKit
import ImageIO

// ============================================================================
// ImageCache.swift — size-aware, memory-bounded image cache
//
// SESSION 2 PERFORMANCE FIX (audit item #4):
//   Before: every lh3 URL was forced to =s1600 — so a 36×36 table thumbnail
//   downloaded and decoded a 1600px image (~several MB decoded, each). The
//   cache was an unbounded dictionary of decoded NSImages that was never
//   evicted: browsing the full table could pin gigabytes.
//
//   Now:
//   • fetch(_:maxPixel:) — callers request the size they need. Thumbnails ask
//     for 160px; the detail gallery keeps the old 1600px default, so every
//     existing call site that passes no size behaves exactly as before.
//   • lh3 URLs get a server-side =s{maxPixel} variant (Google resizes for us);
//     all images are additionally decoded AT target size via ImageIO
//     (CGImageSourceCreateThumbnailAtIndex), so we never hold a decode larger
//     than requested.
//   • Storage is NSCache — thread-safe, count- and cost-limited, and evicts
//     automatically under system memory pressure. Cost = decoded byte estimate.
//   • Same dedup of concurrent requests; same nil-on-failure contract; same
//     clear(). Cache keys include the size, so a 160px thumbnail and a 1600px
//     detail image of the same photo coexist correctly.
// ============================================================================

actor ImageCache {
    static let shared = ImageCache()

    /// Decoded-image store. NSCache evicts least-recently-used entries when
    /// limits are exceeded and responds to system memory pressure for free.
    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 400                       // plenty for a 920-item browse
        c.totalCostLimit = 256 * 1024 * 1024     // ~256 MB of decoded pixels
        return c
    }()

    private var inFlight: [String: Task<NSImage?, Never>] = [:]

    // ── Synchronous cache mirror (perf) ─────────────────────────────────
    // NSCache is internally thread-safe, so this nonisolated mirror can be
    // read DIRECTLY during a SwiftUI render pass — no actor hop, no .task.
    // ThumbnailView checks this first: a cached thumbnail renders instantly,
    // so swapping the table back to 920 rows doesn't spawn 920 async tasks
    // (the cause of the beach ball when clearing a search).
    nonisolated(unsafe) private static let syncMirror: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 400
        c.totalCostLimit = 256 * 1024 * 1024
        return c
    }()

    /// Instant, synchronous lookup for an already-decoded image. Safe to call
    /// from the main thread during render. Returns nil if not yet cached.
    nonisolated static func cached(_ url: URL, maxPixel: Int = 1600) -> NSImage? {
        syncMirror.object(forKey: "\(url.absoluteString)#s\(maxPixel)" as NSString)
    }

    /// Fetch an image, decoded at no larger than `maxPixel` on its long edge.
    /// Default 1600 preserves the pre-Session-2 behavior for callers that
    /// don't specify a size (the detail-panel gallery).
    func fetch(_ url: URL, maxPixel: Int = 1600) async -> NSImage? {
        let key = "\(url.absoluteString)#s\(maxPixel)"

        // Return cached image immediately
        if let cached = cache.object(forKey: key as NSString) { return cached }

        // Deduplicate concurrent requests for the same URL+size
        if let existing = inFlight[key] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            let fetchURL = preferredURL(from: url, maxPixel: maxPixel)
            return await download(fetchURL, maxPixel: maxPixel)
        }

        inFlight[key] = task
        let image = await task.value
        inFlight.removeValue(forKey: key)

        if let image {
            cache.setObject(image, forKey: key as NSString, cost: cost(for: image))
            Self.syncMirror.setObject(image, forKey: key as NSString, cost: cost(for: image))
        }

        return image
    }

    // MARK: - URL preference
    // lh3 URLs (any size suffix) → swap to =s{maxPixel}: Google's CDN resizes
    // server-side, so thumbnails transfer ~10–30 KB instead of a megapixel file.

    private func preferredURL(from url: URL, maxPixel: Int) -> URL {
        let str = url.absoluteString

        if str.contains("lh3.googleusercontent.com/d/"),
           let base = str.components(separatedBy: "=").first {
            return URL(string: "\(base)=s\(maxPixel)") ?? url
        }

        return url
    }

    // MARK: - Download

    private func download(_ url: URL, maxPixel: Int) async -> NSImage? {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/webp,image/apng,image/*,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty else { return nil }
            return decoded(data, maxPixel: maxPixel)
        } catch {
            return nil
        }
    }

    // MARK: - Decode at size
    // ImageIO decodes directly at the target dimension — we never materialize
    // a bitmap larger than requested, which is the bulk of the memory and
    // scroll-jank win. Falls back to plain NSImage(data:) if ImageIO balks.

    private func decoded(_ data: Data, maxPixel: Int) -> NSImage? {
        let srcOpts: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithData(data as CFData, srcOpts as CFDictionary) else {
            return NSImage(data: data)
        }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Approximate decoded footprint — drives NSCache cost-based eviction.
    private func cost(for image: NSImage) -> Int {
        let rep = image.representations.first
        let w = rep?.pixelsWide ?? Int(image.size.width)
        let h = rep?.pixelsHigh ?? Int(image.size.height)
        return max(w * h * 4, 1)
    }

    func clear() {
        cache.removeAllObjects()
        Self.syncMirror.removeAllObjects()
    }
}
