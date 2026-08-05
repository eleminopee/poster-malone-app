import Foundation
import Security

@Observable
class CredentialsManager {

    // MARK: - Credential bootstrap
    //
    // In the private build these were compile-time constants so the app never
    // needed re-entry after an Xcode rebuild. For the public repository they
    // are intentionally empty: every value is supplied at runtime, loaded from
    // the macOS Keychain (see `load(_:)` / `save(_:key:)` below) and entered
    // once through Admin → Credentials.
    //
    // To run this project you will need your own:
    //   • eBay developer keyset (client ID + secret)  — developer.ebay.com
    //   • Shopify custom-app Admin API token           — Shopify Admin → Develop apps
    //   • Anthropic API key                            — console.anthropic.com
    // See README → "Running this project" for setup.
    private let hardcodedEbayClientId     = ""
    private let hardcodedEbayClientSecret = ""
    private let hardcodedShopifyShop      = ""
    private let hardcodedShopifyToken     = ""
    private let hardcodedEbayRefreshToken = ""
    private let hardcodedAnthropicKey     = ""

    var shopifyShop: String = ""
    var shopifyToken: String = ""
    var ebayClientId: String = ""
    var ebayClientSecret: String = ""
    var ebayUserToken: String = ""
    var ebayRefreshToken: String = ""
    var ebayUserTokenExpiry: Date = .distantPast
    var anthropicKey: String = ""
    // Google OAuth user tokens — for Drive uploads from personal Gmail account
    var googleUserToken: String = ""
    var googleRefreshToken: String = ""
    var googleUserTokenExpiry: Date = .distantPast

    private let service = "com.postermalone"

    private var dataDir: URL {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support"))
            .appendingPathComponent("PosterMalone")
    }

    // Set to true after first launch with new keychain format
    var needsCredentialReentry: Bool = false

    init() {
        purgeOldKeychainItemsIfNeeded()
        loadAll()
    }

    // Deletes any items stored in the old login-keychain format (no kSecUseDataProtectionKeychain).
    // Reading old items would trigger the password prompt, so we just delete and ask user to re-enter.
    private func purgeOldKeychainItemsIfNeeded() {
        // Use a Keychain flag (not UserDefaults) so it survives Xcode re-signs
        let flagKey = "keychain_purged_v2_flag"
        let flagQuery: [CFString: Any] = [
            kSecClass:                     kSecClassGenericPassword,
            kSecAttrService:               service,
            kSecAttrAccount:               flagKey,
            kSecReturnData:                true,
            kSecMatchLimit:                kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true as AnyObject
        ]
        var result: AnyObject?
        if SecItemCopyMatching(flagQuery as CFDictionary, &result) == errSecSuccess {
            return  // already purged
        }

        // Only purge credentials that existed BEFORE the data-protection keychain switch.
        // Google tokens were added after, so exclude them to avoid wiping the Drive connection.
        let keys = [
            "shopify_shop", "shopify_token",
            "ebay_client_id", "ebay_client_secret",
            "ebay_user_token", "ebay_refresh_token", "ebay_user_token_expiry",
            "anthropic_key"
        ]

        var hadOldItems = false
        for key in keys {
            let query: [CFString: Any] = [
                kSecClass:       kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: key
            ]
            if SecItemDelete(query as CFDictionary) == errSecSuccess {
                hadOldItems = true
            }
        }

        // Set the flag in the data-protection keychain so it persists across Xcode re-signs
        let flagAdd: [CFString: Any] = [
            kSecClass:                     kSecClassGenericPassword,
            kSecAttrService:               service,
            kSecAttrAccount:               flagKey,
            kSecValueData:                 Data("done".utf8),
            kSecAttrAccessible:            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain: true as AnyObject
        ]
        SecItemAdd(flagAdd as CFDictionary, nil)

        if hadOldItems {
            needsCredentialReentry = true
        }
    }

    var isEbayConnected: Bool { !ebayRefreshToken.isEmpty }
    var isGoogleConnected: Bool { !googleRefreshToken.isEmpty }
    var isInstagramConnected: Bool { !instagramToken.isEmpty && !instagramAccountId.isEmpty }

    // MARK: - Instagram (UserDefaults)

    var instagramToken: String {
        get { UserDefaults.standard.string(forKey: "instagram_token_v1") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "instagram_token_v1") }
    }

    var instagramAccountId: String {
        get { UserDefaults.standard.string(forKey: "instagram_account_id") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "instagram_account_id") }
    }

    // MARK: - Automation Settings (UserDefaults)

    var automationEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "automation_enabled") }
        set { UserDefaults.standard.set(newValue, forKey: "automation_enabled") }
    }

    var automationBatchSize: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "automation_batch_size")
            return v == 0 ? 7 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "automation_batch_size") }
    }

    var automationEmailRecap: Bool {
        get { UserDefaults.standard.object(forKey: "automation_email_recap") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "automation_email_recap") }
    }

    var recapEmail: String {
        get { UserDefaults.standard.string(forKey: "recap_email") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "recap_email") }
    }

    // MARK: - Instagram Token Helpers

    func saveInstagramTokens(token: String, accountId: String) {
        instagramToken     = token
        instagramAccountId = accountId
    }

    func clearInstagramTokens() {
        UserDefaults.standard.removeObject(forKey: "instagram_token_v1")
        UserDefaults.standard.removeObject(forKey: "instagram_account_id")
    }

    // MARK: - Load / Save

    func loadAll() {
        shopifyShop        = load("shopify_shop")         ?? ""
        shopifyToken       = load("shopify_token")        ?? ""
        ebayClientId       = load("ebay_client_id")       ?? ""
        ebayClientSecret   = load("ebay_client_secret")   ?? ""
        ebayUserToken      = load("ebay_user_token")      ?? ""
        ebayRefreshToken   = load("ebay_refresh_token")   ?? ""
        anthropicKey       = load("anthropic_key")        ?? ""
        googleUserToken    = load("google_user_token")    ?? ""
        // Prefer UserDefaults for refresh token (survives Xcode re-signs)
        // Fall back to Keychain for deployed builds that saved it there
        googleRefreshToken = UserDefaults.standard.string(forKey: "google_refresh_token_v2")
                          ?? load("google_refresh_token")
                          ?? ""

        if let s = load("ebay_user_token_expiry"), let ts = Double(s) {
            ebayUserTokenExpiry = Date(timeIntervalSince1970: ts)
        }
        if let ts = UserDefaults.standard.object(forKey: "google_user_token_expiry_v2") as? Double {
            googleUserTokenExpiry = Date(timeIntervalSince1970: ts)
        } else if let s = load("google_user_token_expiry"), let ts = Double(s) {
            googleUserTokenExpiry = Date(timeIntervalSince1970: ts)
        }

        // Try UserDefaults first (written by saveEbayTokens)
        if let udToken = UserDefaults.standard.string(forKey: "ebay_refresh_token_v2"),
           !udToken.isEmpty {
            print("CredentialsManager: Loaded eBay token from UserDefaults")
            ebayRefreshToken = udToken
        }

        // Also try file alongside inventory.json
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                      in: .userDomainMask).first {
            let tokenFile = appSupport.appendingPathComponent("PosterMalone/ebay_token.txt")
            if let fileToken = try? String(contentsOf: tokenFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines), !fileToken.isEmpty {
                print("CredentialsManager: Loaded eBay token from file at \(tokenFile.path)")
                ebayRefreshToken = fileToken
            }
        }

        // Always override with hardcoded values for non-rotating credentials
        ebayClientId     = hardcodedEbayClientId
        ebayClientSecret = hardcodedEbayClientSecret
        shopifyShop      = hardcodedShopifyShop
        shopifyToken     = hardcodedShopifyToken
        anthropicKey     = hardcodedAnthropicKey
        // eBay refresh token: use Keychain value if present (updated via OAuth flow),
        // otherwise fall back to hardcoded value
        if ebayRefreshToken.isEmpty {
            ebayRefreshToken = hardcodedEbayRefreshToken
        }
        // Google tokens are NOT hardcoded — loaded from Keychain only
    }

    func saveAll() {
        save(shopifyShop,        key: "shopify_shop")
        save(shopifyToken,       key: "shopify_token")
        save(ebayClientId,       key: "ebay_client_id")
        save(ebayClientSecret,   key: "ebay_client_secret")
        save(ebayUserToken,      key: "ebay_user_token")
        save(ebayRefreshToken,   key: "ebay_refresh_token")
        save(String(ebayUserTokenExpiry.timeIntervalSince1970), key: "ebay_user_token_expiry")
        save(anthropicKey,       key: "anthropic_key")
        // Google user tokens saved separately via saveGoogleTokens
    }

    // MARK: - eBay Token Helpers

    func saveEbayTokens(userToken: String, refreshToken: String, expiresIn: Double) {
        ebayUserToken       = userToken
        ebayRefreshToken    = refreshToken
        ebayUserTokenExpiry = Date().addingTimeInterval(expiresIn - 120)
        save(userToken,    key: "ebay_user_token")
        save(refreshToken, key: "ebay_refresh_token")
        save(String(ebayUserTokenExpiry.timeIntervalSince1970), key: "ebay_user_token_expiry")
        // UserDefaults
        UserDefaults.standard.set(refreshToken, forKey: "ebay_refresh_token_v2")
        // File — same path as inventory.json, confirmed working
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                      in: .userDomainMask).first {
            let dir = appSupport.appendingPathComponent("PosterMalone")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try refreshToken.write(to: dir.appendingPathComponent("ebay_token.txt"),
                                       atomically: true, encoding: .utf8)
                print("CredentialsManager: eBay token written to \(dir.path)/ebay_token.txt")
            } catch {
                print("CredentialsManager: Failed to write eBay token: \(error)")
            }
        }
    }

    func clearEbayTokens() {
        ebayUserToken = ""; ebayRefreshToken = ""; ebayUserTokenExpiry = .distantPast
        save("", key: "ebay_user_token")
        save("", key: "ebay_refresh_token")
        save("", key: "ebay_user_token_expiry")
    }

    // MARK: - Google Token Helpers

    func saveGoogleTokens(userToken: String, refreshToken: String, expiresIn: Double) {
        googleUserToken       = userToken
        googleRefreshToken    = refreshToken
        googleUserTokenExpiry = Date().addingTimeInterval(expiresIn - 120)
        // Refresh token in UserDefaults — survives Xcode re-signs and rebuilds
        // UserDefaults is tied to the bundle ID, not the code signature
        UserDefaults.standard.set(refreshToken, forKey: "google_refresh_token_v2")
        UserDefaults.standard.set(googleUserTokenExpiry.timeIntervalSince1970,
                                  forKey: "google_user_token_expiry_v2")
        // Keychain backup for deployed archived builds
        save(userToken,    key: "google_user_token")
        save(refreshToken, key: "google_refresh_token")
        save(String(googleUserTokenExpiry.timeIntervalSince1970), key: "google_user_token_expiry")
    }

    func clearGoogleTokens() {
        googleUserToken = ""; googleRefreshToken = ""; googleUserTokenExpiry = .distantPast
        UserDefaults.standard.removeObject(forKey: "google_refresh_token_v2")
        UserDefaults.standard.removeObject(forKey: "google_user_token_expiry_v2")
        save("", key: "google_user_token")
        save("", key: "google_refresh_token")
        save("", key: "google_user_token_expiry")
    }

    // MARK: - Keychain Helpers

    private func save(_ value: String, key: String) {
        let deleteQuery: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        guard !value.isEmpty else { return }
        // kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly: no UI confirmation,
        // survives reboot, stays on device. Combined with kSecUseDataProtectionKeychain
        // this avoids repeated password prompts during Xcode development.
        let addQuery: [CFString: Any] = [
            kSecClass:                         kSecClassGenericPassword,
            kSecAttrService:                   service,
            kSecAttrAccount:                   key,
            kSecValueData:                     Data(value.utf8),
            kSecAttrAccessible:                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain:     true as AnyObject
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func load(_ key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:                     kSecClassGenericPassword,
            kSecAttrService:               service,
            kSecAttrAccount:               key,
            kSecReturnData:                true,
            kSecMatchLimit:                kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true as AnyObject
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
