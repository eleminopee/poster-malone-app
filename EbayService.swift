import Foundation
import AppKit

@Observable
class EbayService {
    static let shared = EbayService()

    private let clientId     = ""   // supplied via CredentialsManager / Keychain
    private let clientSecret = ""   // supplied via CredentialsManager / Keychain
    private let baseURL      = "https://api.ebay.com"

    // Client credentials token (app-level — Trading API only)
    private var appToken: String? = nil
    private var appTokenExpiry: Date = .distantPast

    var isLoading = false
    var lastError: String? = nil

    // MARK: - App-Level Token (client credentials — Trading API / GetMyeBaySelling)

    func ensureAppToken() async throws -> String {
        if let token = appToken, Date() < appTokenExpiry { return token }
        return try await fetchClientCredentialsToken()
    }

    private func fetchClientCredentialsToken() async throws -> String {
        let credentials = "\(clientId):\(clientSecret)"
        guard let credData = credentials.data(using: .utf8) else {
            throw EbayError.authFailed("Cannot encode credentials")
        }
        let b64 = credData.base64EncodedString()

        var request = URLRequest(url: URL(string: "\(baseURL)/identity/v1/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials&scope=https%3A%2F%2Fapi.ebay.com%2Foauth%2Fapi_scope".data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["access_token"] as? String else {
            throw EbayError.authFailed(json?["error_description"] as? String ?? "No token returned")
        }
        let expiresIn = json?["expires_in"] as? Double ?? 7200
        appToken = token
        appTokenExpiry = Date().addingTimeInterval(expiresIn - 60)
        return token
    }

    // MARK: - User Token (refresh token grant — Fulfillment API)
    // The refresh token is pasted once into Admin > eBay credentials.
    // It lasts 18 months and silently exchanges for a short-lived access token here.

    func ensureUserToken(credentials: CredentialsManager) async throws -> String {
        if !credentials.ebayUserToken.isEmpty, Date() < credentials.ebayUserTokenExpiry {
            return credentials.ebayUserToken
        }
        guard !credentials.ebayRefreshToken.isEmpty else {
            throw EbayError.authFailed(
                "No eBay refresh token. Paste your refresh token in Admin > eBay credentials."
            )
        }
        return try await refreshUserToken(credentials: credentials)
    }

    func refreshUserToken(credentials: CredentialsManager) async throws -> String {
        let creds = "\(clientId):\(clientSecret)"
        guard let credData = creds.data(using: .utf8) else {
            throw EbayError.authFailed("Cannot encode credentials")
        }
        let b64 = credData.base64EncodedString()

        let scopeStr = [
            "https://api.ebay.com/oauth/api_scope/sell.fulfillment",
            "https://api.ebay.com/oauth/api_scope/sell.finances",
            "https://api.ebay.com/oauth/api_scope/sell.inventory"
        ].joined(separator: " ")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        let body = "grant_type=refresh_token&refresh_token=\(credentials.ebayRefreshToken)&scope=\(scopeStr)"

        var request = URLRequest(url: URL(string: "\(baseURL)/identity/v1/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let token = json?["access_token"] as? String else {
            let desc = json?["error_description"] as? String
                ?? json?["error"] as? String
                ?? "HTTP \(statusCode)"
            if statusCode == 400 || statusCode == 401 {
                await MainActor.run { credentials.clearEbayTokens() }
            }
            throw EbayError.authFailed("Token refresh failed: \(desc)")
        }

        let expiresIn = json?["expires_in"] as? Double ?? 7200
        let newRefresh = json?["refresh_token"] as? String ?? credentials.ebayRefreshToken
        await MainActor.run {
            credentials.saveEbayTokens(userToken: token, refreshToken: newRefresh, expiresIn: expiresIn)
        }
        return token
    }

    // MARK: - eBay OAuth Authorization Flow
    // Generates a fresh refresh token via the full OAuth authorization code flow.
    // Uses the RuName registered in the eBay developer portal.
    private let ruName = ""

    // Step 1: Build the eBay OAuth authorization URL and open it in the browser
    func buildEbayAuthURL() -> URL? {
        let scopes = [
            "https://api.ebay.com/oauth/api_scope",
            "https://api.ebay.com/oauth/api_scope/sell.fulfillment",
            "https://api.ebay.com/oauth/api_scope/sell.finances",
            "https://api.ebay.com/oauth/api_scope/sell.inventory"
        ].joined(separator: "%20")

        let urlStr = "https://auth.ebay.com/oauth2/authorize"
            + "?client_id=\(clientId)"
            + "&redirect_uri=\(ruName)"
            + "&response_type=code"
            + "&scope=\(scopes)"
        return URL(string: urlStr)
    }

    // Step 2: Exchange the authorization code for tokens
    func exchangeEbayCodeForTokens(code: String, credentials: CredentialsManager) async throws {
        let creds = "\(clientId):\(clientSecret)"
        let b64 = Data(creds.utf8).base64EncodedString()

        let body = "grant_type=authorization_code"
            + "&code=\(code)"
            + "&redirect_uri=\(ruName)"

        var req = URLRequest(url: URL(string: "\(baseURL)/identity/v1/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let accessToken  = json?["access_token"]  as? String,
              let refreshToken = json?["refresh_token"] as? String else {
            let msg = json?["error_description"] as? String
                   ?? json?["error"] as? String
                   ?? "No tokens returned"
            throw EbayError.authFailed("Code exchange failed: \(msg)")
        }

        let expiresIn = json?["expires_in"] as? Double ?? 7200
        await MainActor.run {
            credentials.saveEbayTokens(userToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
        }
        print("eBay OAuth: new refresh token obtained successfully")
    }

    // MARK: - Active Listings (Trading API)

    struct EbayListing {
        let itemId: String
        let sku: String
        let title: String
    }

    // Mirrors Google Apps Script getAllEbayActiveListings_ exactly:
    // OAuth access token in <eBayAuthToken> XML body, compat level 967, OutputSelectors
    func getAllActiveListings(credentials: CredentialsManager) async throws -> [EbayListing] {
        let accessToken = try await ensureUserToken(credentials: credentials)
        var listings: [EbayListing] = []
        var page = 1
        var totalPages = 1
        repeat {
            let (items, pages) = try await fetchListingsPage(page: page, accessToken: accessToken)
            listings.append(contentsOf: items)
            totalPages = pages
            page += 1
        } while page <= totalPages
        print("eBay getAllActiveListings: \(listings.count) listings with SKUs across \(totalPages) pages")
        return listings
    }

    private func fetchListingsPage(page: Int, accessToken: String) async throws -> ([EbayListing], Int) {
        let xmlBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <GetMyeBaySellingRequest xmlns="urn:ebay:apis:eBLBaseComponents">
          <RequesterCredentials>
            <eBayAuthToken>\(accessToken)</eBayAuthToken>
          </RequesterCredentials>
          <ActiveList>
            <Include>true</Include>
            <Pagination>
              <EntriesPerPage>200</EntriesPerPage>
              <PageNumber>\(page)</PageNumber>
            </Pagination>
          </ActiveList>
          <OutputSelector>ActiveList.ItemArray.Item.ItemID</OutputSelector>
          <OutputSelector>ActiveList.ItemArray.Item.SKU</OutputSelector>
          <OutputSelector>ActiveList.ItemArray.Item.Title</OutputSelector>
          <OutputSelector>ActiveList.PaginationResult</OutputSelector>
        </GetMyeBaySellingRequest>
        """
        var request = URLRequest(url: URL(string: "\(baseURL)/ws/api.dll")!)
        request.httpMethod = "POST"
        request.setValue("text/xml",         forHTTPHeaderField: "Content-Type")
        request.setValue("GetMyeBaySelling", forHTTPHeaderField: "X-EBAY-API-CALL-NAME")
        request.setValue("967",              forHTTPHeaderField: "X-EBAY-API-COMPATIBILITY-LEVEL")
        request.setValue("0",                forHTTPHeaderField: "X-EBAY-API-SITEID")
        request.httpBody = xmlBody.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let xml = String(data: data, encoding: .utf8) ?? ""
        print("eBay p\(page): \(xml.prefix(300))")
        return (parseActiveListings(xml), parseTotalPages(xml))
    }

    private func parseActiveListings(_ xml: String) -> [EbayListing] {
        var listings: [EbayListing] = []
        guard let regex = try? NSRegularExpression(pattern: "<Item>(.*?)</Item>",
                                                   options: [.dotMatchesLineSeparators]) else { return [] }
        let range = NSRange(xml.startIndex..., in: xml)
        for match in regex.matches(in: xml, range: range) {
            guard let r = Range(match.range(at: 1), in: xml) else { continue }
            let block = String(xml[r])
            let sku   = block.range(of: "(?<=<SKU>)[^<]+",    options: .regularExpression).map { String(block[$0]) } ?? ""
            guard !sku.isEmpty else { continue }
            let id    = block.range(of: "(?<=<ItemID>)[^<]+", options: .regularExpression).map { String(block[$0]) } ?? ""
            let title = block.range(of: "(?<=<Title>)[^<]+",  options: .regularExpression).map { String(block[$0]) } ?? ""
            listings.append(EbayListing(itemId: id, sku: sku, title: title))
        }
        return listings
    }

    private func parseTotalPages(_ xml: String) -> Int {
        guard let m = xml.range(of: "(?<=<TotalNumberOfPages>)[^<]+", options: .regularExpression),
              let n = Int(xml[m]) else { return 1 }
        return n
    }

    // MARK: - Sold Orders (Fulfillment API)

    struct EbayOrder {
        let orderId: String
        let creationDate: Date
        let lineItems: [OrderLineItem]
        let totalAmount: Double
        let tax: Double
        let shippingCost: Double
    }

    struct OrderLineItem {
        let sku: String
        let title: String
        let price: Double
        let tax: Double
    }

    func getSoldOrders(days: Int = 30, credentials: CredentialsManager) async throws -> [EbayOrder] {
        let token = try await ensureUserToken(credentials: credentials)
        let formatter = ISO8601DateFormatter()
        let since = formatter.string(from: Date().addingTimeInterval(-Double(days) * 86400))
        let urlStr = "\(baseURL)/sell/fulfillment/v1/order?filter=creationdate:%5B\(since)..%5D&limit=200"
        var request = URLRequest(url: URL(string: urlStr)!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            if statusCode == 401 || statusCode == 403 {
                await MainActor.run { credentials.clearEbayTokens() }
                throw EbayError.authFailed(
                    "eBay token rejected (\(statusCode)). Paste a fresh refresh token in Admin > eBay credentials."
                )
            }
            throw EbayError.apiFailed("Fulfillment API HTTP \(statusCode)")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["orders"] as? [[String: Any]] ?? []).compactMap { parseOrder($0) }
    }

    private func parseOrder(_ o: [String: Any]) -> EbayOrder? {
        guard let orderId = o["orderId"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        let date = formatter.date(from: o["creationDate"] as? String ?? "") ?? Date()
        let pricing  = o["pricingSummary"] as? [String: Any] ?? [:]
        let total    = (pricing["total"]        as? [String: Any])?["value"] as? Double ?? 0
        let tax      = (pricing["tax"]          as? [String: Any])?["value"] as? Double ?? 0
        let shipping = (pricing["deliveryCost"] as? [String: Any])?["value"] as? Double ?? 0
        let lineItems = (o["lineItems"] as? [[String: Any]] ?? []).compactMap { li -> OrderLineItem? in
            OrderLineItem(
                sku:   li["sku"]   as? String ?? "",
                title: li["title"] as? String ?? "",
                price: (li["lineItemCost"] as? [String: Any])?["value"] as? Double ?? 0,
                tax:   ((li["taxes"] as? [[String: Any]])?.first?["amount"] as? [String: Any])?["value"] as? Double ?? 0
            )
        }
        return EbayOrder(orderId: orderId, creationDate: date, lineItems: lineItems,
                         totalAmount: total, tax: tax, shippingCost: shipping)
    }

    // MARK: - Sync Item IDs (bulk — writes ItemID back to all matching inventory items)

    /// Fetches all active listings, matches by SKU, returns a [sku: itemId] dictionary.
    func fetchSkuToItemIdMap(credentials: CredentialsManager) async throws -> [String: String] {
        let listings = try await getAllActiveListings(credentials: credentials)
        var map: [String: String] = [:]
        for listing in listings where !listing.sku.isEmpty && !listing.itemId.isEmpty {
            map[listing.sku] = listing.itemId
        }
        return map
    }

    /// Fetches the eBay ItemID for a single SKU. Returns nil if not found in active listings.
    func fetchItemId(forSKU sku: String, credentials: CredentialsManager) async throws -> String? {
        let map = try await fetchSkuToItemIdMap(credentials: credentials)
        return map[sku]
    }

    // MARK: - End Item (Trading API)

    /// Ends a single active eBay listing immediately.
    /// endingReason: "NotAvailable" (sold/removed), "LostOrBroken", "Incorrect", "OtherListingError"
    func endItem(itemId: String, credentials: CredentialsManager, reason: String = "NotAvailable") async throws {
        let accessToken = try await ensureUserToken(credentials: credentials)
        let xmlBody = """
        <?xml version="1.0" encoding="utf-8"?>
        <EndItemRequest xmlns="urn:ebay:apis:eBLBaseComponents">
          <RequesterCredentials>
            <eBayAuthToken>\(accessToken)</eBayAuthToken>
          </RequesterCredentials>
          <ItemID>\(itemId)</ItemID>
          <EndingReason>\(reason)</EndingReason>
        </EndItemRequest>
        """
        var request = URLRequest(url: URL(string: "\(baseURL)/ws/api.dll")!)
        request.httpMethod = "POST"
        request.setValue("text/xml",    forHTTPHeaderField: "Content-Type")
        request.setValue("EndItem",     forHTTPHeaderField: "X-EBAY-API-CALL-NAME")
        request.setValue("967",         forHTTPHeaderField: "X-EBAY-API-COMPATIBILITY-LEVEL")
        request.setValue("0",           forHTTPHeaderField: "X-EBAY-API-SITEID")
        request.httpBody = xmlBody.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let xml = String(data: data, encoding: .utf8) ?? ""

        // Check for API-level failure
        if xml.contains("<Ack>Failure</Ack>") {
            let msg = xml.range(of: "(?<=<LongMessage>)[^<]+", options: .regularExpression)
                .map { String(xml[$0]) } ?? "EndItem failed"
            throw EbayError.apiFailed(msg)
        }
        print("eBay EndItem \(itemId): success")
    }

    /// Ends multiple listings concurrently (max 5 at a time to avoid rate limits).
    func endItems(itemIds: [String], credentials: CredentialsManager) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, itemId) in itemIds.enumerated() {
                // Stagger by 200ms per item to avoid hammering the API
                let delay = UInt64(index) * 200_000_000
                group.addTask {
                    try await Task.sleep(nanoseconds: delay)
                    try await self.endItem(itemId: itemId, credentials: credentials)
                }
            }
            try await group.waitForAll()
        }
    }

    // MARK: - Feed API — Upload Scheduled Listings CSV
    // Uses eBay's Feed API to upload a File Exchange CSV directly via REST.
    // Requires sell.feed scope — re-auth needed if upgrading from older token.
    // Returns the feed task ID for tracking.

    func uploadScheduledListingsCSV(csvURL: URL, credentials: CredentialsManager) async throws -> String {
        let token = try await ensureUserToken(credentials: credentials)

        // Step 1 — Create upload task
        var createReq = URLRequest(url: URL(string: "\(baseURL)/sell/feed/v1/task")!)
        createReq.httpMethod = "POST"
        createReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createReq.setValue("EBAY_US", forHTTPHeaderField: "X-EBAY-C-MARKETPLACE-ID")

        let taskBody: [String: Any] = [
            "feedType": "LMS_ADD_FIXED_PRICE_ITEM",
            "schemaVersion": "1.0"
        ]
        createReq.httpBody = try JSONSerialization.data(withJSONObject: taskBody)

        let (createData, createResp) = try await URLSession.shared.data(for: createReq)
        let createStatus = (createResp as? HTTPURLResponse)?.statusCode ?? 0

        // Task ID comes back in Location header
        guard let location = (createResp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
              let taskId = location.split(separator: "/").last.map(String.init) else {
            let msg = String(data: createData, encoding: .utf8) ?? "HTTP \(createStatus)"
            throw EbayError.apiFailed("Feed task creation failed: \(msg)")
        }

        print("eBay Feed: created task \(taskId)")

        // Step 2 — Upload CSV file to the task
        let csvData = try Data(contentsOf: csvURL)
        let boundary = "PosterMaloneBoundary\(Int(Date().timeIntervalSince1970))"

        var uploadReq = URLRequest(url: URL(string: "\(baseURL)/sell/feed/v1/task/\(taskId)/upload_file")!)
        uploadReq.httpMethod = "POST"
        uploadReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        uploadReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        uploadReq.setValue("EBAY_US", forHTTPHeaderField: "X-EBAY-C-MARKETPLACE-ID")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(csvURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(csvData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        uploadReq.httpBody = body

        let (uploadData, uploadResp) = try await URLSession.shared.data(for: uploadReq)
        let uploadStatus = (uploadResp as? HTTPURLResponse)?.statusCode ?? 0

        guard uploadStatus == 204 || uploadStatus == 200 else {
            let msg = String(data: uploadData, encoding: .utf8) ?? "HTTP \(uploadStatus)"
            throw EbayError.apiFailed("Feed upload failed: \(msg)")
        }

        print("eBay Feed: uploaded CSV to task \(taskId) — status \(uploadStatus)")
        return taskId
    }

    // MARK: - Add Fixed Price Item (Trading API)
    // Schedules a listing using AddFixedPriceItem — same auth as EndItem.
    // ScheduleTime must be at least 1 hour in the future.
    // Returns the new eBay ItemID.

    func addFixedPriceItem(item: InventoryItem, scheduleTime: Date, credentials: CredentialsManager) async throws -> String {
        let token = try await ensureUserToken(credentials: credentials)
        let size  = EbayExportService.parseSize(item.size)
        let pkg   = EbayExportService.packageForWeight(item.weight)

        let schedISO = isoDateTime(scheduleTime)
        let price    = String(format: "%.2f", item.ebayPrice)
        let minOffer = String(format: "%.2f", item.ebayPrice * 0.80)
        let autoAcc  = String(format: "%.2f", item.ebayPrice * 0.90)
        let conditionId = item.condition.lowercased().contains("used") ? "3000" : "1000"

        // Build item specifics
        var specificsXML = ""
        let specifics: [(String, String)] = [
            ("Artist", item.artist),
            ("Production Technique", item.productionTechnique),
            ("Features", "Limited Edition"),
            ("Theme", "Movies|Art"),
            ("Item Length", size.height),
            ("Item Width", size.width)
        ].filter { !$0.1.isEmpty }
        for (name, value) in specifics {
            specificsXML += "<NameValueList><Name>\(escXML(name))</Name><Value>\(escXML(value))</Value></NameValueList>"
        }

        // Build photo URLs
        let photoXML = item.images.prefix(12).map {
            "<PictureURL>\(escXML($0))</PictureURL>"
        }.joined()

        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <AddFixedPriceItemRequest xmlns="urn:ebay:apis:eBLBaseComponents">
          <RequesterCredentials><eBayAuthToken>\(token)</eBayAuthToken></RequesterCredentials>
          <ErrorLanguage>en_US</ErrorLanguage>
          <WarningLevel>Low</WarningLevel>
          <Item>
            <Title>\(escXML(item.ebayTitle))</Title>
            <Description><![CDATA[\(item.description)]]></Description>
            <PrimaryCategory><CategoryID>\(item.ebayCategoryId)</CategoryID></PrimaryCategory>
            <StartPrice>\(price)</StartPrice>
            <ConditionID>\(conditionId)</ConditionID>
            <Country>US</Country>
            <Currency>USD</Currency>
            <DispatchTimeMax>3</DispatchTimeMax>
            <ListingDuration>GTC</ListingDuration>
            <ListingType>FixedPriceItem</ListingType>
            <Location>Your City, State</Location>
            <PostalCode>00000</PostalCode>
            <Quantity>1</Quantity>
            <SKU>\(escXML(item.sku))</SKU>
            <ScheduleTime>\(schedISO)</ScheduleTime>
            <BestOfferDetails>
              <BestOfferEnabled>true</BestOfferEnabled>
            </BestOfferDetails>
            <ListingDetails>
              <MinimumBestOfferPrice>\(minOffer)</MinimumBestOfferPrice>
              <BestOfferAutoAcceptPrice>\(autoAcc)</BestOfferAutoAcceptPrice>
            </ListingDetails>
            <PictureDetails>\(photoXML)</PictureDetails>
            <ItemSpecifics>\(specificsXML)</ItemSpecifics>
            <ShippingPackageDetails>
              <WeightMajor unit="lbs">\(pkg.weightMajor)</WeightMajor>
              <WeightMinor unit="oz">\(pkg.weightMinor)</WeightMinor>
              <PackageDepth unit="in">\(pkg.depth)</PackageDepth>
              <PackageLength unit="in">\(pkg.length)</PackageLength>
              <PackageWidth unit="in">\(pkg.width)</PackageWidth>
            </ShippingPackageDetails>
            <SellerProfiles>
              <SellerPaymentProfile>
                <PaymentProfileName>\(escXML(item.paymentProfileName))</PaymentProfileName>
              </SellerPaymentProfile>
              <SellerReturnProfile>
                <ReturnProfileName>\(escXML(item.returnProfileName))</ReturnProfileName>
              </SellerReturnProfile>
              <SellerShippingProfile>
                <ShippingProfileName>\(escXML(item.shippingProfileName))</ShippingProfileName>
              </SellerShippingProfile>
            </SellerProfiles>
          </Item>
        </AddFixedPriceItemRequest>
        """

        var request = URLRequest(url: URL(string: "https://api.ebay.com/ws/api.dll")!)
        request.httpMethod = "POST"
        request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.setValue("967", forHTTPHeaderField: "X-EBAY-API-COMPATIBILITY-LEVEL")
        request.setValue("AddFixedPriceItem", forHTTPHeaderField: "X-EBAY-API-CALL-NAME")
        request.setValue("0", forHTTPHeaderField: "X-EBAY-API-SITEID")
        request.setValue(clientId, forHTTPHeaderField: "X-EBAY-API-APP-NAME")
        request.httpBody = xml.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let responseStr = String(data: data, encoding: .utf8) ?? ""

        // Check for errors
        if responseStr.contains("<Ack>Failure</Ack>") || responseStr.contains("<Ack>PartialFailure</Ack>") {
            let msg = extractXML(responseStr, tag: "LongMessage")
                   ?? extractXML(responseStr, tag: "ShortMessage")
                   ?? "Unknown error"
            throw EbayError.apiFailed(msg)
        }

        let itemId = extractXML(responseStr, tag: "ItemID") ?? ""
        print("eBay AddFixedPriceItem \(item.sku): scheduled, ItemID=\(itemId)")
        return itemId
    }

    // MARK: - XML Helpers

    private func escXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func extractXML(_ xml: String, tag: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"),
              let end   = xml.range(of: "</\(tag)>") else { return nil }
        return String(xml[start.upperBound..<end.lowerBound])
    }

    private func isoDateTime(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    // MARK: - Errors

    enum EbayError: LocalizedError {
        case authFailed(String)
        case apiFailed(String)
        case exportFailed(String)
        var errorDescription: String? {
            switch self {
            case .authFailed(let m):   return "eBay auth failed: \(m)"
            case .apiFailed(let m):    return "eBay API error: \(m)"
            case .exportFailed(let m): return "Export failed: \(m)"
            }
        }
    }
}
