import Foundation

// MARK: - Shopify Service

actor ShopifyService {
    static let shared = ShopifyService()

    private let apiVersion = "2025-01"

    // MARK: - Core GraphQL

    private func graphql(
        shop: String,
        token: String,
        query: String,
        variables: [String: Any] = [:]
    ) async throws -> [String: Any] {
        let normalizedShop = shop
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: ".myshopify.com", with: "")
            .components(separatedBy: "/").first ?? shop

        let urlStr = "https://\(normalizedShop).myshopify.com/admin/api/\(apiVersion)/graphql.json"
        guard let url = URL(string: urlStr) else {
            throw ShopifyError.invalidCredentials
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Shopify-Access-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query,
            "variables": variables
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ShopifyError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ShopifyError.parseError
        }
        if let errors = json["errors"] {
            throw ShopifyError.graphqlError(String(describing: errors))
        }
        return (json["data"] as? [String: Any]) ?? [:]
    }

    // MARK: - Product Lookup (by SKU)

    func getProductId(shop: String, token: String, sku: String) async throws -> String? {
        let query = """
        query($q: String!) {
          productVariants(first: 1, query: $q) {
            edges {
              node {
                sku
                product { id }
              }
            }
          }
        }
        """
        let data = try await graphql(shop: shop, token: token, query: query,
                                     variables: ["q": "sku:\(sku)"])
        let edges = (data["productVariants"] as? [String: Any])?["edges"] as? [[String: Any]]
        return ((edges?.first?["node"] as? [String: Any])?["product"] as? [String: Any])?["id"] as? String
    }

    func getVariantId(shop: String, token: String, sku: String) async throws -> String? {
        let query = """
        query($q: String!) {
          productVariants(first: 1, query: $q) {
            edges { node { id sku } }
          }
        }
        """
        let data = try await graphql(shop: shop, token: token, query: query,
                                     variables: ["q": "sku:\(sku)"])
        let edges = (data["productVariants"] as? [String: Any])?["edges"] as? [[String: Any]]
        return (edges?.first?["node"] as? [String: Any])?["id"] as? String
    }

    // MARK: - Product Status Check
    // Returns (status, handle) for a given SKU.
    // status is "ACTIVE", "DRAFT", "ARCHIVED", or nil if not found on Shopify.

    struct ProductInfo {
        let status: String   // "ACTIVE", "DRAFT", "ARCHIVED"
        let handle: String
        let productId: String
    }

    func getProductStatus(shop: String, token: String, sku: String) async throws -> ProductInfo? {
        let query = """
        query($q: String!) {
          productVariants(first: 1, query: $q) {
            edges {
              node {
                sku
                product {
                  id
                  handle
                  status
                }
              }
            }
          }
        }
        """
        let data = try await graphql(shop: shop, token: token, query: query,
                                     variables: ["q": "sku:\(sku)"])
        let edges = (data["productVariants"] as? [String: Any])?["edges"] as? [[String: Any]]
        guard let node = edges?.first?["node"] as? [String: Any],
              let product = node["product"] as? [String: Any],
              let status = product["status"] as? String,
              let handle = product["handle"] as? String,
              let productId = product["id"] as? String else {
            return nil
        }
        return ProductInfo(status: status, handle: handle, productId: productId)
    }

    // MARK: - Create Product
    // Shopify API 2025-01+: variants cannot be passed inside ProductInput.
    // Create the product first, then set SKU/price on the default variant.

    func createProduct(shop: String, token: String, item: InventoryItem) async throws -> String {
        let handle = slugify("\(item.artist) \(item.title) \(item.sku)")
        let isPoster = item.size.contains("36") || item.printType.lowercased().contains("poster")
        let productType = isPoster ? "Poster" : "Print"
        let title = item.shopifyTitle.isEmpty ? buildTitle(item) : item.shopifyTitle
        let tags = buildTags(item)

        // Step 1: Create the product (no variants in input)
        let createMutation = """
        mutation productCreate($input: ProductInput!) {
          productCreate(input: $input) {
            product {
              id
              handle
              variants(first: 1) { edges { node { id } } }
            }
            userErrors { field message }
          }
        }
        """

        let input: [String: Any] = [
            "title": title,
            "handle": handle,
            "descriptionHtml": item.shopifyDescription.isEmpty ? item.description : item.shopifyDescription,
            "vendor": item.artist,
            "productType": productType,
            "status": "DRAFT",
            "tags": tags,
            "category": "gid://shopify/TaxonomyCategory/hg-3-4-2-1"
        ]

        let createData = try await graphql(shop: shop, token: token, query: createMutation,
                                           variables: ["input": input])
        let createResult = createData["productCreate"] as? [String: Any]
        if let errors = createResult?["userErrors"] as? [[String: Any]], !errors.isEmpty {
            throw ShopifyError.userErrors(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }
        guard let product = createResult?["product"] as? [String: Any],
              let productId = product["id"] as? String else {
            throw ShopifyError.parseError
        }

        // Step 2: Get the default variant ID that Shopify auto-created
        guard let variantEdges = (product["variants"] as? [String: Any])?["edges"] as? [[String: Any]],
              let variantId = (variantEdges.first?["node"] as? [String: Any])?["id"] as? String else {
            // Product created but couldn't get variant — still return productId
            return productId
        }

        // Step 3: Update the default variant with SKU, price, weight
        let variantMutation = """
        mutation productVariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
          productVariantsBulkUpdate(productId: $productId, variants: $variants) {
            productVariants { id sku price }
            userErrors { field message }
          }
        }
        """

        let variantInput: [String: Any] = [
            "id": variantId,
            "price": String(format: "%.2f", item.shopifyPrice > 0 ? item.shopifyPrice : 0),
            "taxable": true,
            "inventoryItem": [
                "sku": item.sku,
                "requiresShipping": true,
                "measurement": [
                    "weight": ["value": item.weight > 0 ? item.weight : 2.0, "unit": "POUNDS"]
                ]
            ]
        ]

        let variantData = try await graphql(shop: shop, token: token, query: variantMutation,
                                            variables: ["productId": productId, "variants": [variantInput]])
        let variantResult = variantData["productVariantsBulkUpdate"] as? [String: Any]
        if let errors = variantResult?["userErrors"] as? [[String: Any]], !errors.isEmpty {
            print("Variant update warning for \(item.sku): \(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))")
        }

        return productId
    }

    // MARK: - Update Product (title, description, productType, SEO, category)

    func updateProduct(shop: String, token: String, productId: String, item: InventoryItem) async throws {
        let title = item.shopifyTitle.isEmpty ? buildTitle(item) : item.shopifyTitle
        let isPoster = item.size.contains("36") || item.printType.lowercased().contains("poster")
        let productType = isPoster ? "Poster" : "Print"
        let seoTitle = title
        let seoDesc = "\(title) \(item.size) limited edition poster print. Alternative movie poster for collectors."

        // Home & Garden > Decor > Artwork > Posters, Prints & Visual Artwork > Posters
        let categoryGid = "gid://shopify/TaxonomyCategory/hg-3-4-2-1"

        let mutation = """
        mutation productUpdate($input: ProductInput!) {
          productUpdate(input: $input) {
            product { id }
            userErrors { field message }
          }
        }
        """

        let input: [String: Any] = [
            "id": productId,
            "title": title,
            "descriptionHtml": item.shopifyDescription.isEmpty ? item.description : item.shopifyDescription,
            "productType": productType,
            "tags": buildTags(item),
            "seo": ["title": seoTitle, "description": seoDesc],
            "category": categoryGid
        ]

        let data = try await graphql(shop: shop, token: token, query: mutation,
                                     variables: ["input": input])
        let result = data["productUpdate"] as? [String: Any]
        if let errors = result?["userErrors"] as? [[String: Any]], !errors.isEmpty {
            throw ShopifyError.userErrors(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }
    }

    // MARK: - Add to Collections
    // Looks up manual collection IDs by title and adds the product.
    // Only works for manual (custom) collections — automated collections
    // add products via rules and cannot be modified via API.

    func addToCollections(shop: String, token: String, productId: String, item: InventoryItem) async throws {
        var collectionTitles: [String] = []

        // Print type → collection
        let pt = item.printType.lowercased()
        if pt.contains("movie poster") {
            collectionTitles.append("Movie Posters")
        } else if pt.contains("art poster") {
            collectionTitles.append("Art Posters")
        } else if pt.contains("art print") || pt.contains("mini print") {
            collectionTitles.append("Art Prints")
        }

        // Franchise (preferred) or Theme → genre collection
        let themeOrFranchise = item.franchise.isEmpty ? item.theme : item.franchise
        if !themeOrFranchise.isEmpty {
            collectionTitles.append(themeOrFranchise)
        }

        // Artist → artist collection
        if !item.artist.isEmpty {
            collectionTitles.append(item.artist)
        }

        // New Arrivals
        collectionTitles.append("New Arrivals")

        // Fetch all collections at once and match by title client-side
        // (avoids per-title query issues with special characters)
        let fetchQuery = """
        query {
          collections(first: 250) {
            edges { node { id title } }
          }
        }
        """
        let fetchData = try await graphql(shop: shop, token: token, query: fetchQuery)
        let allEdges = (fetchData["collections"] as? [String: Any])?["edges"] as? [[String: Any]] ?? []

        // Build title → id map (case-insensitive)
        var titleToId: [String: String] = [:]
        for edge in allEdges {
            if let node = edge["node"] as? [String: Any],
               let id = node["id"] as? String,
               let title = node["title"] as? String {
                titleToId[title.lowercased()] = id
            }
        }

        // Match our desired collections
        let addMutation = """
        mutation collectionAddProducts($id: ID!, $productIds: [ID!]!) {
          collectionAddProducts(id: $id, productIds: $productIds) {
            collection { id title }
            userErrors { field message }
          }
        }
        """

        for title in collectionTitles {
            guard let collectionId = titleToId[title.lowercased()] else { continue }
            _ = try? await graphql(shop: shop, token: token, query: addMutation,
                                    variables: ["id": collectionId, "productIds": [productId]])
        }
    }

    // MARK: - Publish to Online Store
    // NOTE: Requires write_publications scope which isn't available on standard tokens.
    // Products are created as DRAFT — publish manually in Shopify Admin.
    // This is a no-op to avoid breaking the call site.

    func publishProduct(shop: String, token: String, productId: String) async throws {
        // Cannot publish without write_publications scope.
        // Publish manually: Shopify Admin → Products → select product → Save as Active.
    }

    // MARK: - Enable Inventory Tracking
    // Enables tracking on the inventory item and sets available quantity to 1.

    func enableInventoryTracking(shop: String, token: String, productId: String, sku: String) async throws {
        // Step 1: Get variant ID and inventory item ID
        let variantQuery = """
        query($q: String!) {
          productVariants(first: 1, query: $q) {
            edges {
              node {
                id
                inventoryItem { id }
              }
            }
          }
        }
        """
        let variantData = try await graphql(shop: shop, token: token, query: variantQuery,
                                             variables: ["q": "sku:\(sku)"])
        let edges = (variantData["productVariants"] as? [String: Any])?["edges"] as? [[String: Any]]
        guard let node = edges?.first?["node"] as? [String: Any],
              let variantId = node["id"] as? String,
              let inventoryItem = node["inventoryItem"] as? [String: Any],
              let inventoryItemId = inventoryItem["id"] as? String else { return }

        // Step 2: Enable tracking — must complete before setting qty
        let trackMutation = """
        mutation inventoryItemUpdate($id: ID!, $input: InventoryItemInput!) {
          inventoryItemUpdate(id: $id, input: $input) {
            inventoryItem { id tracked }
            userErrors { field message }
          }
        }
        """
        let trackData = try await graphql(shop: shop, token: token, query: trackMutation,
                                           variables: ["id": inventoryItemId, "input": ["tracked": true]])
        // Verify tracking was enabled before proceeding
        let tracked = ((trackData["inventoryItemUpdate"] as? [String: Any])?["inventoryItem"] as? [String: Any])?["tracked"] as? Bool ?? false
        guard tracked else {
            print("Inventory tracking could not be enabled for \(sku)")
            return
        }

        // Step 3: Set inventory policy to DENY (won't oversell)
        let policyMutation = """
        mutation productVariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
          productVariantsBulkUpdate(productId: $productId, variants: $variants) {
            productVariants { id inventoryPolicy }
            userErrors { field message }
          }
        }
        """
        _ = try? await graphql(shop: shop, token: token, query: policyMutation,
                                variables: ["productId": productId,
                                            "variants": [["id": variantId, "inventoryPolicy": "DENY"]]])

        // Step 4: Get primary location ID
        let locationQuery = """
        query { locations(first: 1) { edges { node { id } } } }
        """
        let locationData = try await graphql(shop: shop, token: token, query: locationQuery)
        guard let locationEdges = (locationData["locations"] as? [String: Any])?["edges"] as? [[String: Any]],
              let locationId = (locationEdges.first?["node"] as? [String: Any])?["id"] as? String else { return }

        // Step 5: Set quantity to 1
        let setQtyMutation = """
        mutation inventorySetOnHandQuantities($input: InventorySetOnHandQuantitiesInput!) {
          inventorySetOnHandQuantities(input: $input) {
            inventoryAdjustmentGroup { reason }
            userErrors { field message }
          }
        }
        """
        let qtyInput: [String: Any] = [
            "reason": "received",
            "setQuantities": [[
                "inventoryItemId": inventoryItemId,
                "locationId": locationId,
                "quantity": 1
            ]]
        ]
        let qtyResult = try? await graphql(shop: shop, token: token, query: setQtyMutation,
                                            variables: ["input": qtyInput])
        if let errors = (qtyResult?["inventorySetOnHandQuantities"] as? [String: Any])?["userErrors"] as? [[String: Any]],
           !errors.isEmpty {
            print("Inventory qty warning for \(sku): \(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))")
        }
    }

    // MARK: - Update Variant Price

    func updatePrice(shop: String, token: String, productId: String, variantId: String, price: Double) async throws {
        let mutation = """
        mutation productVariantsBulkUpdate($productId: ID!, $variants: [ProductVariantsBulkInput!]!) {
          productVariantsBulkUpdate(productId: $productId, variants: $variants) {
            productVariants { id price }
            userErrors { field message }
          }
        }
        """
        let variantInput: [String: Any] = [
            "id": variantId,
            "price": String(format: "%.2f", price)
        ]
        let data = try await graphql(shop: shop, token: token, query: mutation,
                                     variables: ["productId": productId, "variants": [variantInput]])
        let result = data["productVariantsBulkUpdate"] as? [String: Any]
        if let errors = result?["userErrors"] as? [[String: Any]], !errors.isEmpty {
            throw ShopifyError.userErrors(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }
    }

    // MARK: - Push Images

    func pushImages(shop: String, token: String, productId: String, imageURLs: [String]) async throws {
        guard !imageURLs.isEmpty else { return }

        // Convert Google Drive URLs to a format Shopify's servers can fetch.
        // lh3.googleusercontent.com URLs are Google's CDN — use export=view
        // which returns the image directly without auth redirects.
        let convertedURLs = imageURLs.compactMap { url -> String? in
            guard !url.isEmpty else { return nil }

            // Already a working direct image URL
            if url.hasPrefix("https://lh3.googleusercontent.com") {
                // Cap at 2048px longest side — stays well under Shopify's 25MP limit
                // while retaining full quality for web display
                let base = url.components(separatedBy: "=").first ?? url
                return "\(base)=s2048"
            }

            // drive.google.com/file/d/FILE_ID/view → lh3 CDN not available,
            // use export=view which works for publicly shared files
            if url.contains("drive.google.com") {
                if let fileId = extractDriveFileId(from: url) {
                    return "https://drive.google.com/uc?export=view&id=\(fileId)"
                }
            }

            return url
        }

        guard !convertedURLs.isEmpty else { return }

        let mutation = """
        mutation productCreateMedia($productId: ID!, $media: [CreateMediaInput!]!) {
          productCreateMedia(productId: $productId, media: $media) {
            media {
              ... on MediaImage {
                id
                image { url }
              }
            }
            mediaUserErrors { field message }
          }
        }
        """

        let media = convertedURLs.map { url -> [String: Any] in
            ["originalSource": url, "mediaContentType": "IMAGE", "alt": ""]
        }

        let data = try await graphql(shop: shop, token: token, query: mutation,
                                     variables: ["productId": productId, "media": media])
        let result = data["productCreateMedia"] as? [String: Any]
        if let errors = result?["mediaUserErrors"] as? [[String: Any]], !errors.isEmpty {
            print("Image push warning: \(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))")
        }
    }

    private func extractDriveFileId(from url: String) -> String? {
        // Handle /file/d/FILE_ID/view and /d/FILE_ID formats
        for pattern in ["/file/d/", "/d/"] {
            if let range = url.range(of: pattern) {
                let after = String(url[range.upperBound...])
                return after.components(separatedBy: "/").first?.components(separatedBy: "?").first
            }
        }
        // Handle id=FILE_ID query param
        if let range = url.range(of: "id=") {
            let after = String(url[range.upperBound...])
            return after.components(separatedBy: "&").first
        }
        return nil
    }

    // MARK: - Set Metafields

    func setMetafields(shop: String, token: String, productId: String, item: InventoryItem) async throws {
        let size = parseSize(item.size)
        let isPoster = item.size.contains("36") || item.printType.lowercased().contains("poster")
        let productType = isPoster ? "Poster" : "Print"
        let isMoviePoster = item.printType.lowercased().contains("movie") ? "true" : "false"
        let pkg = packageForSize(item.size)

        var serial = ""
        var total = ""
        if let match = item.edition.range(of: #"(\d+)\s*/\s*(\d+)"#, options: .regularExpression) {
            let parts = item.edition[match].components(separatedBy: "/")
            serial = parts[0].trimmingCharacters(in: .whitespaces)
            total  = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        }

        var metafields: [[String: Any]] = []

        func add(_ key: String, _ value: String, _ type: String) {
            guard !value.isEmpty else { return }
            metafields.append([
                "ownerId": productId,
                "namespace": "cin",
                "key": key,
                "type": type,
                "value": value
            ])
        }

        add("edition",         item.edition,          "single_line_text_field")
        add("gallery",         item.gallery,           "single_line_text_field")
        add("theme",           item.theme,             "single_line_text_field")
        add("size",            item.size,              "single_line_text_field")
        add("width",           size.width,             "number_decimal")
        add("height",          size.height,            "number_decimal")
        add("type",            productType,            "single_line_text_field")
        add("is_movie_poster", isMoviePoster,          "boolean")
        add("edition_serial",  serial,                 "number_integer")
        add("edition_total",   total,                  "number_integer")
        add("artist_slug",     slugify(item.artist),   "single_line_text_field")
        add("gallery_slug",    slugify(item.gallery),  "single_line_text_field")
        add("pkg_length",      String(pkg.length),     "number_decimal")
        add("pkg_width",       String(pkg.width),      "number_decimal")
        add("pkg_height",      String(pkg.height),     "number_decimal")
        add("pkg_template",    pkg.template,           "single_line_text_field")

        guard !metafields.isEmpty else { return }

        let mutation = """
        mutation metafieldsSet($metafields: [MetafieldsSetInput!]!) {
          metafieldsSet(metafields: $metafields) {
            metafields { id key }
            userErrors { field message }
          }
        }
        """
        let data = try await graphql(shop: shop, token: token, query: mutation,
                                     variables: ["metafields": metafields])
        let result = data["metafieldsSet"] as? [String: Any]
        if let errors = result?["userErrors"] as? [[String: Any]], !errors.isEmpty {
            throw ShopifyError.userErrors(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }
    }

    // MARK: - Generate Description via Anthropic

    func generateDescription(item: InventoryItem, anthropicKey: String) async throws -> String {
        let prompt = buildDescriptionPrompt(item)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anthropicKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "claude-sonnet-4-6",
            "max_tokens": 1000,
            "messages": [["role": "user", "content": prompt]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ShopifyError.anthropicError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = (json["content"] as? [[String: Any]])?.first,
              var text = content["text"] as? String else {
            throw ShopifyError.anthropicError("Unexpected response format")
        }

        text = text.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "<strong>$1</strong>",
                                          options: .regularExpression)

        let structured = buildStructuredDetails(item)
        let paragraphs = text.components(separatedBy: "\n\n")
            .map { "<p>\($0.trimmingCharacters(in: .whitespacesAndNewlines))</p>" }
            .filter { $0 != "<p></p>" }
            .joined(separator: "\n\n")

        return structured + "\n\n" + paragraphs
    }

    // MARK: - Title Generation

    func generateTitle(_ item: InventoryItem) -> String {
        let isPoster = item.size.contains("36") || item.printType.lowercased().contains("poster")
        let typeLabel = isPoster ? "Limited Edition Poster" : "Limited Edition Print"
        let parts = [item.artist, item.title, item.size, typeLabel]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parts.joined(separator: " - ")
    }

    // MARK: - Helpers

    private func buildTitle(_ item: InventoryItem) -> String { generateTitle(item) }

    private func buildTags(_ item: InventoryItem) -> String {
        // Tags drive automated collection membership (New Arrivals, artist collections, etc.)
        var tags = [item.artist, item.title, item.theme, item.franchise, item.printType,
                    "Alternative Movie Poster", "Movie Poster", "Poster", "new-arrival"]
        // Add artist slug as tag so artist automated collections fire
        if !item.artist.isEmpty {
            tags.append(slugify(item.artist))
        }
        return tags.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    private func buildStructuredDetails(_ item: InventoryItem) -> String {
        var lines = ["<p style=\"font-size: 16px; line-height: 1.6;\">"]
        lines.append("<strong>Title:</strong> \(item.title)<br>")
        lines.append("<strong>Artist:</strong> \(item.artist)<br>")
        lines.append("<strong>Dimensions:</strong> \(item.size) inches<br>")
        lines.append("<strong>Edition Size:</strong> \(item.edition)<br>")
        lines.append("<strong>Production Technique:</strong> \(item.productionTechnique)<br>")
        lines.append("<strong>Gallery:</strong> \(item.gallery)")
        if item.signed { lines.append("<br><strong>Signed:</strong> Yes, signed by the artist") }
        lines.append("</p>")
        return lines.joined(separator: "\n")
    }

    private func buildDescriptionPrompt(_ item: InventoryItem) -> String {
        """
        You are writing a professional product description for a curated alternative movie poster and art print e-commerce store. Write in a knowledgeable, enthusiastic tone that appeals to collectors - professional but passionate about the artwork.

        Write a 150-200 word SEO-optimized description for this print:

        Title: \(item.title)
        Artist: \(item.artist)
        Gallery: \(item.gallery)
        \(item.franchise.isEmpty ? "" : "Franchise: \(item.franchise)")
        \(item.theme.isEmpty ? "" : "Theme: \(item.theme)")
        Size: \(item.size)
        Edition: \(item.edition)
        Technique: \(item.productionTechnique)
        \(item.signed ? "Special Note: This print is signed by the artist" : "")
        Print Type: \(item.printType)

        Requirements:
        - Write 2-3 paragraphs in a professional, knowledgeable tone
        - Separate paragraphs with a blank line between them
        - Use **bold text** (markdown format) for the product title when you first mention it
        - Sound like a curated art gallery describing a collectible piece
        - Focus on what makes this artwork special: the artist's style, the movie/franchise connection, visual composition, and collectible value
        - Naturally include SEO phrases like "limited edition movie poster", "collectible art print", "\(item.franchise) poster", "\(item.artist) art"
        - Highlight the artist's reputation and technique when notable
        - Emphasize the limited edition nature and production quality
        - Appeal to both dedicated collectors and fans discovering alternative movie posters
        \(item.signed ? "- Emphasize that it's artist-signed - this significantly increases collectible value" : "")
        - End with why this piece is valuable for collectors

        Do NOT use casual language, exclamation marks, price info, or generic phrases.

        Write the description now (remember to separate paragraphs with blank lines):
        """
    }

    func slugify(_ str: String) -> String {
        str.lowercased()
            .components(separatedBy: .alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    struct SizeParsed { let width: String; let height: String }

    func parseSize(_ s: String) -> SizeParsed {
        let pattern = #"(\d+(?:\.\d+)?)\s*[xX]\s*(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r1 = Range(match.range(at: 1), in: s),
              let r2 = Range(match.range(at: 2), in: s) else {
            return SizeParsed(width: "", height: "")
        }
        return SizeParsed(width: String(s[r1]), height: String(s[r2]))
    }

    struct PackageDims { let length: Double; let width: Double; let height: Double; let template: String }

    func packageForSize(_ size: String) -> PackageDims {
        if size.contains("36") || size.contains("24x36") {
            return PackageDims(length: 29, width: 3, height: 3, template: "large_tube")
        } else if size.contains("24") || size.contains("18x24") {
            return PackageDims(length: 25, width: 3, height: 3, template: "medium_tube")
        }
        return PackageDims(length: 12, width: 12, height: 2, template: "flat_box")
    }

    // MARK: - Mark Sold Out
    // Mirrors pm_setShopifySoldOut_ in the Google Apps Script.
    // 1) Looks up variant + inventoryItem + product by SKU
    // 2) Sets inventory quantity to 0 at the primary location
    // 3) Sets product status to DRAFT

    func markSoldOut(shop: String, token: String, sku: String) async throws {

        // Step 1: Look up variant, inventoryItem, and product by SKU
        let lookupQuery = """
        query($q: String!) {
          productVariants(first: 1, query: $q) {
            edges {
              node {
                id
                sku
                inventoryItem { id }
                product { id status }
              }
            }
          }
        }
        """
        let lookupData = try await graphql(shop: shop, token: token,
                                           query: lookupQuery,
                                           variables: ["q": "sku:\(sku)"])
        let edges = (lookupData["productVariants"] as? [String: Any])?["edges"] as? [[String: Any]]
        guard let node = edges?.first?["node"] as? [String: Any],
              let inventoryItem = node["inventoryItem"] as? [String: Any],
              let inventoryItemId = inventoryItem["id"] as? String,
              let product = node["product"] as? [String: Any],
              let productId = product["id"] as? String else {
            // SKU not on Shopify — not an error, just skip
            return
        }

        // Step 2: Get primary location ID
        let locationQuery = "query { locations(first: 1) { edges { node { id } } } }"
        let locationData = try await graphql(shop: shop, token: token, query: locationQuery)
        guard let locationEdges = (locationData["locations"] as? [String: Any])?["edges"] as? [[String: Any]],
              let locationId = (locationEdges.first?["node"] as? [String: Any])?["id"] as? String else {
            throw ShopifyError.graphqlError("No Shopify location found")
        }

        // Step 3: Set quantity to 0 (ignoreCompareQuantity avoids stale-qty conflicts)
        let qtyMutation = """
        mutation inventorySetQuantities($input: InventorySetQuantitiesInput!) {
          inventorySetQuantities(input: $input) {
            userErrors { code field message }
          }
        }
        """
        let qtyInput: [String: Any] = [
            "reason": "correction",
            "name": "available",
            "ignoreCompareQuantity": true,
            "quantities": [[
                "inventoryItemId": inventoryItemId,
                "locationId": locationId,
                "quantity": 0
            ]]
        ]
        let qtyData = try await graphql(shop: shop, token: token,
                                        query: qtyMutation,
                                        variables: ["input": qtyInput])
        if let errs = (qtyData["inventorySetQuantities"] as? [String: Any])?["userErrors"] as? [[String: Any]],
           !errs.isEmpty {
            throw ShopifyError.userErrors(errs.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }

        // Step 4: Set product status to DRAFT
        let draftMutation = """
        mutation productUpdate($input: ProductInput!) {
          productUpdate(input: $input) {
            product { id status }
            userErrors { field message }
          }
        }
        """
        let draftData = try await graphql(shop: shop, token: token,
                                          query: draftMutation,
                                          variables: ["input": ["id": productId, "status": "DRAFT"]])
        if let errs = (draftData["productUpdate"] as? [String: Any])?["userErrors"] as? [[String: Any]],
           !errs.isEmpty {
            throw ShopifyError.userErrors(errs.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }
    }

    // MARK: - Errors

    enum ShopifyError: LocalizedError {
        case invalidCredentials
        case httpError(Int)
        case graphqlError(String)
        case userErrors(String)
        case parseError
        case anthropicError(String)

        var errorDescription: String? {
            switch self {
            case .invalidCredentials:    return "Missing Shopify shop or token. Check Admin settings."
            case .httpError(let code):   return "Shopify HTTP error \(code)"
            case .graphqlError(let msg): return "GraphQL error: \(msg)"
            case .userErrors(let msg):   return "Shopify error: \(msg)"
            case .parseError:            return "Failed to parse Shopify response"
            case .anthropicError(let m): return "Anthropic API error: \(m)"
            }
        }
    }
}
