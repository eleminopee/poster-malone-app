import Foundation
import AppKit
import Security

@Observable
class GoogleDriveService {
    static let shared = GoogleDriveService()

    let inventoryFolderId = ""   // your Drive folder ID
    let soldFolderId      = ""   // your Drive folder ID

    // MARK: - Service Account (reads: list, find, download, rename, move)

    private let clientEmail  = ""   // service-account email
    private let privateKeyId = "dda33ebd9869df8c0e7034c571a62c6ea44858a5"
    private let rsaKeyB64    = "MIIEogIBAAKCAQEApxLKlrUH728P3ssT5umVJ45B9sHJ4WqoY3JlpF+/KCFujonk14KPT2n4HeaACNb74iHTYhpl54xcD3/2QFkXY3olPyxDMjAD5xxXxeoxbumWZfT4ay3UxTnlQfEr3dKslwoz5IfgbNDLfz3JQsCCbvYB4oioool4TMgbOD9uBhdHDVbB2gtZWbgNxVtnl2n6tryuypdtDbGmvyozMTiYbk9EFzV+FHQAlWTYg6XE7hD0pSUBxfnXNkiaxgXdk+uaOfkNm74wIS2e3mi+qlc5qpJlGz445CPiU82c1j64KibZj6mgW+H8tk7fu5Zy82ofyiWlZRtUQGLhVRaEviz/DwIDAQABAoIBACqktbfMwhc/cj4L+Gr2UL81ZKnOYbBa8FrdrorLc3eTPOw9zv6g0OJUqmM7W4+mC8l2l8UQ9tSoczDzmM9ozfryiMI8knQjZEOfbNnTwkVMcrpYUfXNT2L9uYHgxDEMnke473DTq5kqm95Az3dtun0G5olDF0PRMbbrVmM/cV41Ne6B8iDPHndMEq1ZD0Lvihxuhu1COBarN8NMAmhivJFtdqQSnkss1hOEmRKsxWMx0x0Lkh4TWRqoh/NW8KK9dhT5tZrSCfxga+fuE0IzVpwpnKih6NDoaNRIoMvnmhDYb+BavFqM64b8KYZbqD3UJ+vbgOeSsDCxeWGxOJcpwxkCgYEA3opyTYjCg3nfRG2gHesv6ScvB/hUeuLXLqGlzRCXLfmz1a+hIYh/0KXBKW5hauRw2amHx9YG5UO00NdVEB6oQsgQNyUEToieNOA90ITTAkUqwJCl0YkhZpPCuvNIfP5arwOGxVQfrUMHP4TKEZq7Bus/PZMIUdYUecev6uljX8cCgYEAwDFqP6zOoK+nSxWywQmXwI5vG1PPDsXFw4TBNuaGsg2ryF6TpO5H7Xrnhpl1eh+NkT9ivyhYZLx1tPPPwW0eqQhEq0RzJgG5WcfG7hyZru/N8Dd0XP9VnphAnS2aCCPmihwR40Rnt1/g/wHxVpZ70RoLROsYWLeU/mMs0s15dnkCgYBaYBExaaPM7xZ73KVU4SlQ32fbLb9pNGw89Mq3r9AljK26zxt52cxGeLosUDZhyaoGyzFoN4QPYWKyGXDjHgApNsRXEMJh/lt5j8OqxfZHir1k/JlKsg0Ncl53u8spb8Z2ItF9m79NhtYPtqa1ZYgktC63m9maGn2wQycvGF8SCwKBgCmcSUGh+1aE0TaLaxkqJ4XUELAc9A5huVB8dIybWnxAQ3ntKBAkWsRKwMe+f9XB8ReKXqm+ZWzh9KYJx2g8ZM/570wZVMjcxLFwdFxnKsraNn8UsofT7Eia9BpTni62/xnVu/W1gLMN+hub4xF5ITODbP8t2yaSEJsHA9RcEjkZAoGAWAftqe317cYZcOr2PtTh5dlln9OygtT+CDBTw8T8EMa228E3KQBgJbaa0G4PhpQD++CX6/bfFlzFyHKTEROHmLgu+Tn7L0RGXpyKswg+NsdpdchpelDey6uu3aJz2vw58Xm8kgkooU+UxvQOFVg3OBY7OapeCG3DkolfG7+26g0="

    private let saTokenURL = "https://oauth2.googleapis.com/token"
    private let saScope     = "https://www.googleapis.com/auth/drive"
    private var saToken: String? = nil
    private var saTokenExpiry: Date = .distantPast
    private var cachedKey: SecKey? = nil

    // MARK: - Google OAuth User Tokens (writes/uploads)
    // Personal Gmail accounts can't use service account delegation.
    // Writes use a standard OAuth2 user token instead.

    private let oauthTokenURL    = "https://oauth2.googleapis.com/token"
    private let oauthScope       = "https://www.googleapis.com/auth/drive"

    private let oauthClientId     = ""   // Google Cloud Console → OAuth client
    private let oauthClientSecret = ""   // Google Cloud Console → OAuth client

    // Keep these settable for legacy compatibility but they default to the hardcoded values
    var googleClientId: String = "653966807069-r9f8voksf6b1649047f7pp6ilugfv7qa.apps.googleusercontent.com"
    var googleClientSecret: String = ""

    var isAuthenticated = false
    var errorMessage: String? = nil

    // MARK: - Drive File Model

    struct DriveFile: Identifiable {
        let id: String
        let name: String
        let mimeType: String
    }

    // MARK: - Service Account Token (reads only)

    func ensureSAToken() async throws -> String {
        if let t = saToken, Date() < saTokenExpiry { return t }
        return try await fetchSAToken()
    }

    private func fetchSAToken() async throws -> String {
        let jwt = try makeJWT()
        var req = URLRequest(url: URL(string: saTokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)".data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["access_token"] as? String else {
            throw DriveError.authFailed(json?["error_description"] as? String ?? "SA token failed")
        }
        saToken = token
        saTokenExpiry = Date().addingTimeInterval((json?["expires_in"] as? Double ?? 3600) - 60)
        await MainActor.run { isAuthenticated = true }
        return token
    }

    private func makeJWT() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header: [String: Any] = ["alg": "RS256", "typ": "JWT", "kid": privateKeyId]
        let claims: [String: Any] = [
            "iss": clientEmail, "scope": saScope,
            "aud": saTokenURL, "exp": now + 3600, "iat": now
        ]
        let h = try jsonBase64URL(header)
        let c = try jsonBase64URL(claims)
        let input = "\(h).\(c)"
        guard let inputData = input.data(using: .utf8) else {
            throw DriveError.jwtFailed("Cannot encode signing input")
        }
        let key = try getPrivateKey()
        var cfErr: Unmanaged<CFError>?
        guard let sig = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256,
                                               inputData as CFData, &cfErr) as Data? else {
            throw DriveError.jwtFailed(cfErr?.takeRetainedValue().localizedDescription ?? "Signing failed")
        }
        return "\(input).\(base64URLEncode(sig))"
    }

    private func getPrivateKey() throws -> SecKey {
        if let k = cachedKey { return k }
        guard let keyData = Data(base64Encoded: rsaKeyB64) else {
            throw DriveError.jwtFailed("Cannot decode RSA key")
        }
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 2048
        ]
        var cfErr: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, &cfErr) else {
            throw DriveError.jwtFailed(cfErr?.takeRetainedValue().localizedDescription ?? "Key creation failed")
        }
        cachedKey = key
        return key
    }

    private func jsonBase64URL(_ obj: [String: Any]) throws -> String {
        base64URLEncode(try JSONSerialization.data(withJSONObject: obj))
    }

    private func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Google OAuth User Token (writes)

    func ensureUserToken(credentials: CredentialsManager) async throws -> String {
        // Return cached access token if still valid
        if !credentials.googleUserToken.isEmpty, Date() < credentials.googleUserTokenExpiry {
            return credentials.googleUserToken
        }
        guard !credentials.googleRefreshToken.isEmpty else {
            throw DriveError.authFailed(
                "Google Drive not connected. Tap 'Connect Google Account' in Admin -> Google."
            )
        }
        return try await refreshUserToken(credentials: credentials)
    }

    func refreshUserToken(credentials: CredentialsManager) async throws -> String {
        guard !googleClientId.isEmpty, !googleClientSecret.isEmpty else {
            throw DriveError.authFailed("Google Client ID/Secret not set in Admin -> Google.")
        }
        let body = [
            "client_id":     googleClientId,
            "client_secret": googleClientSecret,
            "refresh_token": credentials.googleRefreshToken,
            "grant_type":    "refresh_token"
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
         .joined(separator: "&")

        var req = URLRequest(url: URL(string: oauthTokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["access_token"] as? String else {
            let msg = json?["error_description"] as? String ?? json?["error"] as? String ?? "HTTP \(code)"
            if code == 400 || code == 401 { await MainActor.run { credentials.clearGoogleTokens() } }
            throw DriveError.authFailed("Google token refresh failed: \(msg)")
        }
        let expiresIn = json?["expires_in"] as? Double ?? 3600
        let newRefresh = json?["refresh_token"] as? String ?? credentials.googleRefreshToken
        await MainActor.run {
            credentials.saveGoogleTokens(userToken: token, refreshToken: newRefresh, expiresIn: expiresIn)
        }
        return token
    }

    // MARK: - Authorization Flow (one-time browser login)

    // localhost redirect — the correct approach for Google Desktop app OAuth clients.
    // Requires com.apple.security.network.server entitlement.
    // After fixing entitlements: Product > Clean Build Folder, then rebuild.
    private let callbackPorts: [UInt16] = [9482, 9483, 9484, 9485, 9876]

    var isAuthorizing = false
    var lastAuthResult: String? = nil
    var lastAuthWasError = false
    private var callbackServer: GoogleCallbackServer? = nil

    func startAuthorization(credentials: CredentialsManager) async throws {
        guard !googleClientId.isEmpty else {
            throw DriveError.authFailed("Enter your Google Client ID in Admin -> Google first.")
        }
        callbackServer?.stop()
        callbackServer = nil

        var server: GoogleCallbackServer?
        var chosenPort: UInt16 = callbackPorts[0]
        for port in callbackPorts {
            let candidate = GoogleCallbackServer(port: port)
            do { try candidate.start(); server = candidate; chosenPort = port; break }
            catch { continue }
        }
        guard let server else {
            throw DriveError.authFailed("Could not bind to any local port. In Xcode: open PosterMalone.entitlements as Source Code, ensure com.apple.security.network.server is a top-level key (not nested), then Product > Clean Build Folder and rebuild.")
        }
        self.callbackServer = server
        await MainActor.run { isAuthorizing = true }

        let activeRedirect = "http://localhost:\(chosenPort)/google_callback"
        let redirectEncoded = activeRedirect.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let scope = oauthScope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let authURLStr = "https://accounts.google.com/o/oauth2/v2/auth"
            + "?client_id=\(googleClientId)"
            + "&redirect_uri=\(redirectEncoded)"
            + "&response_type=code"
            + "&scope=\(scope)"
            + "&access_type=offline"
            + "&prompt=consent"

        guard let authURL = URL(string: authURLStr) else {
            server.stop(); self.callbackServer = nil
            await MainActor.run { isAuthorizing = false }
            throw DriveError.authFailed("Cannot build authorization URL")
        }

        _ = await MainActor.run { NSWorkspace.shared.open(authURL) }

        do {
            let code = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await server.waitForCode() }
                group.addTask {
                    try await Task.sleep(for: .seconds(120))
                    throw DriveError.authFailed("Authorization timed out after 2 minutes.")
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
            try await exchangeCodeForTokens(code: code, redirectURI: activeRedirect, credentials: credentials)
            await MainActor.run {
                isAuthorizing = false
                lastAuthResult = "Google Drive connected — uploads will use your account"
                lastAuthWasError = false
            }
        } catch {
            await MainActor.run {
                isAuthorizing = false
                lastAuthResult = error.localizedDescription
                lastAuthWasError = true
            }
            server.stop(); self.callbackServer = nil
            throw error
        }
        server.stop(); self.callbackServer = nil
    }

    func exchangeCodeForTokens(code: String, redirectURI: String, credentials: CredentialsManager) async throws {
        guard !googleClientId.isEmpty, !googleClientSecret.isEmpty else {
            throw DriveError.authFailed("Google Client ID/Secret not set.")
        }
        let redirectEncoded = redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let body = "code=\(code)&client_id=\(googleClientId)&client_secret=\(googleClientSecret)"
            + "&redirect_uri=\(redirectEncoded)&grant_type=authorization_code"

        var req = URLRequest(url: URL(string: oauthTokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let accessToken  = json?["access_token"]  as? String,
              let refreshToken = json?["refresh_token"] as? String else {
            let msg = json?["error_description"] as? String ?? json?["error"] as? String ?? "No tokens"
            throw DriveError.authFailed("Token exchange failed: \(msg)")
        }
        let expiresIn = json?["expires_in"] as? Double ?? 3600
        await MainActor.run {
            credentials.saveGoogleTokens(userToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn)
        }
    }

    // MARK: - Drive Read Operations (service account token)

    func listFiles(inFolder folderId: String) async throws -> [DriveFile] {
        let token = try await ensureSAToken()
        let q = "'\(folderId)' in parents and trashed=false and mimeType contains 'image/'"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://www.googleapis.com/drive/v3/files?q=\(q)&fields=files(id,name,mimeType)&orderBy=name&pageSize=50"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return [] }
        return files.compactMap { f -> DriveFile? in
            guard let id = f["id"] as? String, let name = f["name"] as? String,
                  let mime = f["mimeType"] as? String else { return nil }
            return DriveFile(id: id, name: name, mimeType: mime)
        }
    }

    /// Lists all SUBFOLDERS in a parent folder (paginated). Used by the
    /// Drive reconciliation pass — folder names are SKUs (PM-XXXX).
    func listFolders(inParent parentId: String) async throws -> [DriveFile] {
        let token = try await ensureSAToken()
        var results: [DriveFile] = []
        var pageToken: String? = nil

        repeat {
            let q = "'\(parentId)' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            var urlStr = "https://www.googleapis.com/drive/v3/files?q=\(q)&fields=nextPageToken,files(id,name,mimeType)&orderBy=name&pageSize=1000"
            if let pageToken {
                urlStr += "&pageToken=\(pageToken)"
            }
            var req = URLRequest(url: URL(string: urlStr)!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }
            if let files = json["files"] as? [[String: Any]] {
                results.append(contentsOf: files.compactMap { f -> DriveFile? in
                    guard let id = f["id"] as? String, let name = f["name"] as? String,
                          let mime = f["mimeType"] as? String else { return nil }
                    return DriveFile(id: id, name: name, mimeType: mime)
                })
            }
            pageToken = json["nextPageToken"] as? String
        } while pageToken != nil

        return results
    }

    /// Move a folder by its known ID (avoids a redundant findFolder lookup
    /// when the caller already listed it). User OAuth token for the write.
    func moveFolder(id folderId: String, fromParent: String, toParent: String,
                    credentials: CredentialsManager) async throws {
        let token = try await ensureUserToken(credentials: credentials)
        let url = "https://www.googleapis.com/drive/v3/files/\(folderId)?addParents=\(toParent)&removeParents=\(fromParent)&fields=id,parents"
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{}".data(using: .utf8)
        let (respData, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let body = String(data: respData, encoding: .utf8) ?? ""
            throw DriveError.uploadFailed("Move failed for folder \(folderId): HTTP \(code) \(body)")
        }
    }

    // MARK: - Comics module support (additive — user-token variants)
    // These search/list with the USER's OAuth token, so the Comics folder
    // needs no service-account sharing setup: your own token sees your Drive.

    /// Find a folder by exact name anywhere in the user's Drive.
    func findFolderAnywhere(named name: String, credentials: CredentialsManager) async throws -> String? {
        let token = try await ensureUserToken(credentials: credentials)
        let q = "name = '\(name)' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://www.googleapis.com/drive/v3/files?q=\(q)&fields=files(id,name)&pageSize=5"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return nil }
        return files.first?["id"] as? String
    }

    /// List image files in a folder using the user's token.
    func listImagesUser(inFolder folderId: String, credentials: CredentialsManager) async throws -> [DriveFile] {
        let token = try await ensureUserToken(credentials: credentials)
        let q = "'\(folderId)' in parents and trashed=false and mimeType contains 'image/'"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://www.googleapis.com/drive/v3/files?q=\(q)&fields=files(id,name,mimeType)&orderBy=name&pageSize=100"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return [] }
        return files.compactMap { f -> DriveFile? in
            guard let id = f["id"] as? String, let name = f["name"] as? String,
                  let mime = f["mimeType"] as? String else { return nil }
            return DriveFile(id: id, name: name, mimeType: mime)
        }
    }

    func findFolder(named name: String, inParent parentId: String) async throws -> String? {
        let token = try await ensureSAToken()
        let q = "'\(parentId)' in parents and name='\(name)' and mimeType='application/vnd.google-apps.folder' and trashed=false"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://www.googleapis.com/drive/v3/files?q=\(q)&fields=files(id,name)&pageSize=1"
        var req = URLRequest(url: URL(string: urlStr)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else { return nil }
        return files.first?["id"] as? String
    }

    func downloadFile(fileId: String) async throws -> Data {
        let token = try await ensureSAToken()
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)?alt=media")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw DriveError.downloadFailed("HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        return data
    }

    // MARK: - Drive Write Operations (user OAuth token)

    func createFolder(named name: String, inParent parentId: String, credentials: CredentialsManager) async throws -> String {
        let token = try await ensureUserToken(credentials: credentials)
        let metadata: [String: Any] = ["name": name, "mimeType": "application/vnd.google-apps.folder", "parents": [parentId]]
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: metadata)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw DriveError.uploadFailed("Could not create folder '\(name)'")
        }
        return id
    }

    func uploadFile(data fileData: Data, name: String, mimeType: String,
                    parentId: String, existingFileId: String? = nil,
                    credentials: CredentialsManager) async throws -> String {
        let token = try await ensureUserToken(credentials: credentials)

        if let existingId = existingFileId {
            // Update existing file content
            var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(existingId)?uploadType=media")!)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            req.httpBody = fileData
            let (resp, _) = try await URLSession.shared.data(for: req)
            let json = try JSONSerialization.jsonObject(with: resp) as? [String: Any]
            return json?["id"] as? String ?? existingId
        } else {
            // Step 1: create metadata → get file ID
            let metadata: [String: Any] = ["name": name, "parents": [parentId]]
            var metaReq = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
            metaReq.httpMethod = "POST"
            metaReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            metaReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            metaReq.httpBody = try JSONSerialization.data(withJSONObject: metadata)
            let (metaResp, metaHTTP) = try await URLSession.shared.data(for: metaReq)
            guard let metaJson = try JSONSerialization.jsonObject(with: metaResp) as? [String: Any],
                  let fileId = metaJson["id"] as? String else {
                let body = String(data: metaResp, encoding: .utf8) ?? ""
                throw DriveError.uploadFailed("Metadata create failed (HTTP \((metaHTTP as? HTTPURLResponse)?.statusCode ?? 0)): \(body)")
            }

            // Step 2: upload content
            var uploadReq = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileId)?uploadType=media&fields=id")!)
            uploadReq.httpMethod = "PATCH"
            uploadReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            uploadReq.setValue(mimeType, forHTTPHeaderField: "Content-Type")
            uploadReq.httpBody = fileData
            let (_, uploadResp) = try await URLSession.shared.data(for: uploadReq)
            let uploadCode = (uploadResp as? HTTPURLResponse)?.statusCode ?? 0
            guard uploadCode == 200 else {
                throw DriveError.uploadFailed("Content upload failed (HTTP \(uploadCode))")
            }
            return fileId
        }
    }

    func renameFile(fileId: String, newName: String, credentials: CredentialsManager) async throws {
        let token = try await ensureUserToken(credentials: credentials)
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["name": newName])
        _ = try await URLSession.shared.data(for: req)
    }

    func deleteFile(fileId: String, credentials: CredentialsManager) async throws {
        let token = try await ensureUserToken(credentials: credentials)
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: req)
    }

    // Makes a file publicly readable via link so lh3.googleusercontent.com thumbnails work.
    // Mirrors ensurePublicFile_() in the Google Apps Script.
    func makeFilePublic(fileId: String, credentials: CredentialsManager) async throws {
        let token = try await ensureUserToken(credentials: credentials)
        let url = URL(string: "https://www.googleapis.com/drive/v3/files/\(fileId)/permissions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["type": "anyone", "role": "reader"])
        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        // 200 = created, 409 = already exists — both are fine
        guard code == 200 || code == 409 else {
            throw DriveError.uploadFailed("Could not set file permissions (HTTP \(code))")
        }
    }

    @discardableResult
    func moveFolder(named name: String, fromParent: String, toParent: String,
                    credentials: CredentialsManager) async throws -> Bool {
        let token = try await ensureUserToken(credentials: credentials)

        // Find the folder using service account (read)
        guard let folderId = try await findFolder(named: name, inParent: fromParent) else {
            return false
        }

        // Move using user token (write)
        let url = "https://www.googleapis.com/drive/v3/files/\(folderId)?addParents=\(toParent)&removeParents=\(fromParent)&fields=id,parents"
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{}".data(using: .utf8)
        let (respData, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            let body = String(data: respData, encoding: .utf8) ?? ""
            throw DriveError.uploadFailed("Move failed for '\(name)': HTTP \(code) \(body)")
        }
        return true
    }

    // MARK: - Reconciliation
    // Finds folders in the Inventory folder whose SKU is no longer in the
    // app's inventory because the item SOLD (SKU present in sales), and moves
    // them to the Sold folder. Catches folders left behind when a Mark-Sold
    // happened while signed out of the Google account in Admin.

    struct ReconcileResult {
        var candidates: [String] = []        // SKUs that should move (sold, still in Inventory folder)
        var moved: [String] = []
        var failed: [(sku: String, error: String)] = []
        var scannedFolders: Int = 0
        var skippedNotSold: Int = 0          // folders not in inventory AND not in sales — left alone
    }

    /// Scan only — returns what WOULD move, without moving anything.
    /// `liveSkus` = current in-app inventory SKUs; `soldSkus` = sale-record SKUs.
    func reconcilePreview(liveSkus: Set<String>, soldSkus: Set<String>) async throws -> ReconcileResult {
        let folders = try await listFolders(inParent: inventoryFolderId)
        var result = ReconcileResult()
        result.scannedFolders = folders.count
        for folder in folders {
            let sku = folder.name.trimmingCharacters(in: .whitespaces).uppercased()
            guard sku.hasPrefix("PM-") else { continue }
            if liveSkus.contains(sku) { continue }          // still in inventory — correct
            if soldSkus.contains(sku) {
                result.candidates.append(sku)               // sold but folder still in Inventory
            } else {
                result.skippedNotSold += 1                  // unknown — don't touch
            }
        }
        result.candidates.sort()
        return result
    }

    /// Execute the moves for the given SKUs (typically the preview's candidates).
    /// Re-lists folders to get fresh IDs, moves each Inventory→Sold.
    func reconcileMove(skus: [String], credentials: CredentialsManager) async throws -> ReconcileResult {
        var result = ReconcileResult()
        guard !skus.isEmpty else { return result }
        let target = Set(skus.map { $0.uppercased() })

        let folders = try await listFolders(inParent: inventoryFolderId)
        result.scannedFolders = folders.count
        for folder in folders {
            let sku = folder.name.trimmingCharacters(in: .whitespaces).uppercased()
            guard target.contains(sku) else { continue }
            result.candidates.append(sku)
            do {
                try await moveFolder(id: folder.id, fromParent: inventoryFolderId,
                                     toParent: soldFolderId, credentials: credentials)
                result.moved.append(sku)
            } catch {
                result.failed.append((sku, error.localizedDescription))
            }
        }
        result.moved.sort()
        return result
    }

    // MARK: - Errors

    enum DriveError: LocalizedError {
        case authFailed(String)
        case jwtFailed(String)
        case downloadFailed(String)
        case uploadFailed(String)
        case folderNotFound(String)

        var errorDescription: String? {
            switch self {
            case .authFailed(let m):    return "Auth failed: \(m)"
            case .jwtFailed(let m):     return "JWT error: \(m)"
            case .downloadFailed(let m): return "Download failed: \(m)"
            case .uploadFailed(let m):  return "Upload failed: \(m)"
            case .folderNotFound(let m): return "Folder not found: \(m)"
            }
        }
    }
}

// MARK: - Google OAuth Callback Server

final class GoogleCallbackServer: @unchecked Sendable {
    private let port: UInt16
    private var serverSocket: Int32 = -1
    private var codeContinuation: CheckedContinuation<String, Error>?

    init(port: UInt16) { self.port = port }

    func start() throws {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw GoogleDriveService.DriveError.authFailed("Cannot create socket") }
        var yes: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(sock, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len    = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = port.bigEndian
        addr.sin_addr.s_addr = UInt32(0x7f000001).bigEndian
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(sock)
            throw GoogleDriveService.DriveError.authFailed("Port \(port) in use (errno \(errno))")
        }
        listen(sock, 1)
        serverSocket = sock
    }

    func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.codeContinuation = continuation
            Task.detached { await self.acceptLoop() }
        }
    }

    private func acceptLoop() async {
        let sock = serverSocket
        guard sock >= 0 else {
            codeContinuation?.resume(throwing: GoogleDriveService.DriveError.authFailed("Server not started"))
            codeContinuation = nil; return
        }
        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        while serverSocket >= 0 {
            var clientAddr = sockaddr_in()
            var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(sock, $0, &addrLen) }
            }
            if client < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    try? await Task.sleep(for: .milliseconds(250)); continue
                }
                break
            }
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = recv(client, &buf, buf.count - 1, 0)
            let req = n > 0 ? String(bytes: buf.prefix(n), encoding: .utf8) ?? "" : ""
            let html = "<html><body style='font-family:system-ui;text-align:center;padding-top:80px'><h2>&#10003; Google Drive Connected</h2><p>You can close this tab and return to Poster Malone.</p></body></html>"
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            resp.withCString { _ = send(client, $0, strlen($0), 0) }
            close(client)

            if let r = req.range(of: "code=") {
                let after = req[r.upperBound...]
                let end = after.firstIndex(where: { $0 == "&" || $0 == " " || $0 == "\r" }) ?? after.endIndex
                let code = String(after[after.startIndex..<end])
                if !code.isEmpty {
                    codeContinuation?.resume(returning: code); codeContinuation = nil; return
                }
            }
            codeContinuation?.resume(throwing: GoogleDriveService.DriveError.authFailed("No auth code in callback"))
            codeContinuation = nil; return
        }
        if codeContinuation != nil {
            codeContinuation?.resume(throwing: GoogleDriveService.DriveError.authFailed("Authorization cancelled"))
            codeContinuation = nil
        }
    }

    func stop() {
        if serverSocket >= 0 { close(serverSocket); serverSocket = -1 }
    }
}
