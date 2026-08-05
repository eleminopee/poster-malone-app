import Foundation

// MARK: - Instagram Graph API Service
//
// Uses the Instagram Content Publishing API (Graph API v21.0) to post
// single images or carousels directly from inventory items.
//
// Flow:
//   1. For each image URL → POST /media  (creates a container, returns container_id)
//   2. POST /media with children=[container_ids] → carousel container
//   3. POST /media_publish with creation_id → publishes the post
//
// Auth:
//   Long-lived User Access Token stored in UserDefaults key "instagram_token_v1"
//   Instagram Business Account ID stored in UserDefaults key "instagram_account_id"
//   Token lasts 60 days — refresh endpoint built in.
//
// Image URLs:
//   lh3.googleusercontent.com/d/FILE_ID=s2048 — already public, works directly.
//   Single image: use image_url param on /media endpoint.
//   Carousel: first create individual IMAGE containers, then a CAROUSEL_ALBUM container.

@Observable
class InstagramService {
    static let shared = InstagramService()

    private let graphBase = "https://graph.facebook.com/v21.0"

    // MARK: - Credential accessors (UserDefaults — same pattern as eBay refresh token)

    var accessToken: String {
        get { UserDefaults.standard.string(forKey: "instagram_token_v1") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "instagram_token_v1") }
    }

    var accountId: String {
        get { UserDefaults.standard.string(forKey: "instagram_account_id") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "instagram_account_id") }
    }

    var isConnected: Bool { !accessToken.isEmpty && !accountId.isEmpty }

    // MARK: - Errors

    enum IGError: LocalizedError {
        case notConfigured
        case noImages
        case tooManyImages
        case containerFailed(String)
        case publishFailed(String)
        case tokenExpired
        case networkError(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:          return "Instagram not configured. Add token + account ID in Admin → Credentials."
            case .noImages:               return "This item has no photos. Add photos via Photo Manager first."
            case .tooManyImages:          return "Instagram carousels support up to 10 images."
            case .containerFailed(let m): return "Failed to create media container: \(m)"
            case .publishFailed(let m):   return "Failed to publish post: \(m)"
            case .tokenExpired:           return "Instagram token has expired. Re-authenticate in Admin → Credentials."
            case .networkError(let m):    return "Network error: \(m)"
            }
        }
    }

    // MARK: - Post Result

    struct PostResult {
        let postId: String
        let permalink: String
        let imageCount: Int
    }

    // MARK: - Main Post Entry Point

    /// Posts an inventory item to Instagram.
    /// Uses item.images (lh3 URLs) for photos and item.igCaption for the caption.
    /// Automatically picks single vs carousel based on image count.
    func post(item: InventoryItem) async throws -> PostResult {
        guard isConnected else { throw IGError.notConfigured }
        guard !item.images.isEmpty else { throw IGError.noImages }

        // Convert lh3 URLs to s2048 size for best quality within IG limits
        let imageURLs = item.images.prefix(10).map { convertToIGURL($0) }
        guard !imageURLs.isEmpty else { throw IGError.noImages }
        if imageURLs.count > 10 { throw IGError.tooManyImages }

        let caption = item.igCaption.isEmpty ? buildFallbackCaption(item) : item.igCaption

        let postId: String
        if imageURLs.count == 1 {
            postId = try await postSingleImage(url: imageURLs[0], caption: caption)
        } else {
            postId = try await postCarousel(urls: Array(imageURLs), caption: caption)
        }

        // Fetch permalink
        let permalink = try await fetchPermalink(mediaId: postId)

        return PostResult(postId: postId, permalink: permalink, imageCount: imageURLs.count)
    }

    // MARK: - Single Image Post

    private func postSingleImage(url: String, caption: String) async throws -> String {
        // Step 1: Create container
        let containerId = try await createImageContainer(url: url, caption: caption, isCarouselItem: false)

        // Step 2: Publish
        return try await publishContainer(containerId: containerId)
    }

    // MARK: - Carousel Post

    private func postCarousel(urls: [String], caption: String) async throws -> String {
        // Step 1: Create individual image containers (no caption — caption goes on carousel)
        var childIds: [String] = []
        for url in urls {
            let childId = try await createImageContainer(url: url, caption: nil, isCarouselItem: true)
            childIds.append(childId)
            // Small delay to avoid rate limiting
            try await Task.sleep(for: .milliseconds(300))
        }

        // Step 2: Create carousel container
        let carouselId = try await createCarouselContainer(childIds: childIds, caption: caption)

        // Step 3: Publish
        return try await publishContainer(containerId: carouselId)
    }

    // MARK: - API: Create Image Container

    private func createImageContainer(url: String, caption: String?, isCarouselItem: Bool) async throws -> String {
        let endpoint = "\(graphBase)/\(accountId)/media"
        var params: [String: String] = [
            "image_url":    url,
            "access_token": accessToken
        ]
        if isCarouselItem {
            params["is_carousel_item"] = "true"
        } else if let caption {
            params["caption"] = caption
        }

        let data = try await postForm(endpoint: endpoint, params: params)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IGError.containerFailed("Invalid JSON response")
        }

        // Check for token expiry
        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? 0
            let msg = error["message"] as? String ?? "Unknown error"
            if code == 190 { throw IGError.tokenExpired }
            throw IGError.containerFailed(msg)
        }

        guard let id = json["id"] as? String else {
            throw IGError.containerFailed("No container ID in response")
        }
        return id
    }

    // MARK: - API: Create Carousel Container

    private func createCarouselContainer(childIds: [String], caption: String) async throws -> String {
        let endpoint = "\(graphBase)/\(accountId)/media"
        let params: [String: String] = [
            "media_type":   "CAROUSEL_ALBUM",
            "children":     childIds.joined(separator: ","),
            "caption":      caption,
            "access_token": accessToken
        ]

        let data = try await postForm(endpoint: endpoint, params: params)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IGError.containerFailed("Invalid JSON response for carousel")
        }
        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? 0
            let msg = error["message"] as? String ?? "Unknown error"
            if code == 190 { throw IGError.tokenExpired }
            throw IGError.containerFailed(msg)
        }
        guard let id = json["id"] as? String else {
            throw IGError.containerFailed("No carousel container ID in response")
        }
        return id
    }

    // MARK: - API: Publish Container

    private func publishContainer(containerId: String) async throws -> String {
        let endpoint = "\(graphBase)/\(accountId)/media_publish"
        let params: [String: String] = [
            "creation_id":  containerId,
            "access_token": accessToken
        ]

        let data = try await postForm(endpoint: endpoint, params: params)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IGError.publishFailed("Invalid JSON response")
        }
        if let error = json["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? 0
            let msg = error["message"] as? String ?? "Unknown error"
            if code == 190 { throw IGError.tokenExpired }
            throw IGError.publishFailed(msg)
        }
        guard let id = json["id"] as? String else {
            throw IGError.publishFailed("No media ID in response")
        }
        return id
    }

    // MARK: - API: Fetch Permalink

    private func fetchPermalink(mediaId: String) async throws -> String {
        let endpoint = "\(graphBase)/\(mediaId)?fields=permalink&access_token=\(accessToken)"
        guard let url = URL(string: endpoint) else { return "" }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let permalink = json["permalink"] as? String else {
            return "https://www.instagram.com/therealpostermalone/"
        }
        return permalink
    }

    // MARK: - Token Validation

    /// Validates the current token and returns the associated Instagram account info.
    /// Call this from Admin to verify credentials are correct.
    func validateToken() async throws -> (userId: String, name: String, igAccountId: String) {
        guard !accessToken.isEmpty else { throw IGError.notConfigured }

        // 1. Get the Facebook User ID from the token
        let meURL = "\(graphBase)/me?fields=id,name&access_token=\(accessToken)"
        guard let url = URL(string: meURL) else { throw IGError.networkError("Bad URL") }
        let (meData, _) = try await URLSession.shared.data(from: url)

        guard let meJson = try? JSONSerialization.jsonObject(with: meData) as? [String: Any] else {
            throw IGError.networkError("Invalid /me response")
        }
        if let error = meJson["error"] as? [String: Any] {
            let code = error["code"] as? Int ?? 0
            if code == 190 { throw IGError.tokenExpired }
            throw IGError.networkError(error["message"] as? String ?? "Unknown")
        }
        let userId = meJson["id"] as? String ?? ""
        let name   = meJson["name"] as? String ?? ""

        // 2. Get linked Instagram Business Accounts
        let accsURL = "\(graphBase)/\(userId)/accounts?fields=instagram_business_account&access_token=\(accessToken)"
        guard let accsUrl = URL(string: accsURL) else { throw IGError.networkError("Bad accounts URL") }
        let (accsData, _) = try await URLSession.shared.data(from: accsUrl)

        guard let accsJson = try? JSONSerialization.jsonObject(with: accsData) as? [String: Any],
              let pages = accsJson["data"] as? [[String: Any]],
              let firstPage = pages.first,
              let igBiz = firstPage["instagram_business_account"] as? [String: Any],
              let igId = igBiz["id"] as? String else {
            throw IGError.networkError("No Instagram Business Account found. Make sure your IG account is a Professional account connected to a Facebook Page.")
        }

        return (userId: userId, name: name, igAccountId: igId)
    }

    // MARK: - Token Refresh
    // Long-lived tokens last 60 days. This extends them by another 60 days.
    // Call periodically from Admin (show a "Refresh Token" button when < 10 days remain).

    func refreshLongLivedToken(appId: String, appSecret: String) async throws -> String {
        let endpoint = "\(graphBase)/oauth/access_token?grant_type=fb_exchange_token&client_id=\(appId)&client_secret=\(appSecret)&fb_exchange_token=\(accessToken)"
        guard let url = URL(string: endpoint) else { throw IGError.networkError("Bad refresh URL") }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = json["access_token"] as? String else {
            throw IGError.networkError("Token refresh failed")
        }
        accessToken = newToken
        return newToken
    }

    // MARK: - Helpers

    /// Converts an lh3 Google Drive URL to =s2048 for Instagram-safe sizing.
    /// Instagram requires images to be at least 320px and recommends square/portrait crops.
    private func convertToIGURL(_ raw: String) -> String {
        // Strip any existing size suffix (=w2000#.jpg or =s1600 etc.)
        let stripped: String
        if let base = raw.components(separatedBy: "=").first {
            stripped = base
        } else {
            stripped = raw
        }
        return "\(stripped)=s2048"
    }

    /// Builds a minimal fallback caption when igCaption is empty.
    private func buildFallbackCaption(_ item: InventoryItem) -> String {
        var parts: [String] = []
        if !item.artist.isEmpty { parts.append(item.artist) }
        if !item.title.isEmpty  { parts.append(item.title) }
        if !item.size.isEmpty   { parts.append(item.size) }
        parts.append("#postermalone #alternativemovieposters #mondoposter #limitededition #movieposter #popart #filmcollector")
        return parts.joined(separator: "\n")
    }

    /// POST application/x-www-form-urlencoded helper
    private func postForm(endpoint: String, params: [String: String]) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw IGError.networkError("Invalid URL: \(endpoint)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = params.map { k, v in
            "\(k.urlEncoded)=\(v.urlEncoded)"
        }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 401 { throw IGError.tokenExpired }
            return data
        } catch let error as IGError {
            throw error
        } catch {
            throw IGError.networkError(error.localizedDescription)
        }
    }
}

// MARK: - String URL encoding helper

private extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "+", with: "%2B") ?? self
    }
}
