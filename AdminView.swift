import SwiftUI
import UniformTypeIdentifiers

struct AdminView: View {
    @Environment(CredentialsManager.self) var credentials
    @Environment(InventoryStore.self) var store
    @Environment(ColumnSettings.self) var columnSettings
    @State private var saved = false

    // Restore state
    @State private var isRestoring = false
    @State private var restoreResult: String? = nil
    @State private var restoreIsError = false

    // CSV export state
    @State private var isExportingCSV = false
    @State private var csvExportResult: String? = nil
    @State private var csvExportIsError = false

    // eBay auth state
    @State private var isConnectingEbay = false
    @State private var ebayConnectResult: String? = nil
    @State private var ebayConnectIsError = false
    @State private var ebayAuthCode = ""
    @State private var ebayPollTimer: Timer? = nil
    @State private var ebayPollCount = 0

    // Google auth state
    @State private var isConnectingGoogle = false
    @State private var googleConnectResult: String? = nil
    @State private var googleConnectIsError = false

    // Drive reconcile (find sold-but-unmoved folders)
    @State private var isReconciling = false
    @State private var reconcilePreview: GoogleDriveService.ReconcileResult? = nil
    @State private var reconcileResultText: String? = nil
    @State private var reconcileIsError = false

    // Status sync state
    @State private var isSyncingStatus = false
    @State private var syncStatusResult: String? = nil
    @State private var syncStatusIsError = false

    // Smart merge state
    @State private var isMerging = false
    @State private var mergeResult: String? = nil
    @State private var mergeIsError = false
    @State private var pendingRemovals: [InventoryItem] = []
    @State private var showRemovalConfirm = false

    // Image debug state
    @State private var isTestingImage = false
    @State private var imageTestResult: String? = nil
    @State private var imageURLTested: String? = nil

    var body: some View {
        @Bindable var credentials = credentials

        Form {
            // One-time banner shown after keychain format upgrade
            if credentials.needsCredentialReentry {
                Section {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.orange)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Please re-enter your credentials")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Your saved credentials were moved to a more secure keychain format. This is a one-time step — you won't be asked again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Shopify") {
                LabeledContent("Store")         { Text("bcf3c1-5").foregroundStyle(.secondary).font(.subheadline) }
                LabeledContent("Access Token")  { Text("••••••••••••••••").foregroundStyle(.secondary).font(.subheadline) }
            }

            Section("eBay") {
                LabeledContent("Client ID") { Text(credentials.ebayClientId.isEmpty ? "Not set" : "Configured").foregroundStyle(.secondary).font(.subheadline) }

                // Re-authorize eBay (needed when refresh token expires or is revoked)
                VStack(alignment: .leading, spacing: 8) {
                    Text("eBay Authorization")
                        .font(.subheadline).fontWeight(.medium)
                    Text("If eBay auth fails, click below to sign in and get a fresh token.")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button("Open eBay Sign-In") {
                            if let url = EbayService.shared.buildEbayAuthURL() {
                                NSWorkspace.shared.open(url)
                                startEbayAuthPolling()
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        if isConnectingEbay {
                            ProgressView().controlSize(.small)
                            Text("Waiting for sign-in...")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Button("Test Connection") {
                                Task { await testEbayToken() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Manual fallback
                    DisclosureGroup("Manual code entry (fallback)") {
                        HStack(spacing: 8) {
                            TextField("Paste auth code from eBay redirect URL...", text: $ebayAuthCode)
                                .textFieldStyle(.roundedBorder)
                            Button("Submit") {
                                Task { await submitEbayAuthCode() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(ebayAuthCode.trimmingCharacters(in: .whitespaces).isEmpty || isConnectingEbay)
                        }
                        Text("After signing in, eBay redirects to a URL containing ?code=... — copy just the code value and paste above.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                }

                if let result = ebayConnectResult {
                    HStack(spacing: 6) {
                        Image(systemName: ebayConnectIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(ebayConnectIsError ? .red : .green)
                        Text(result).font(.caption)
                            .foregroundStyle(ebayConnectIsError ? .red : .primary)
                    }
                }
            }

            Section("Anthropic") {
                LabeledContent("API Key") { Text("Hardcoded").foregroundStyle(.secondary).font(.subheadline) }
            }

            Section("Google") {
                LabeledContent("Drive Account") {
                    HStack(spacing: 8) {
                        if GoogleDriveService.shared.isAuthorizing {
                            ProgressView().controlSize(.small)
                            Text("Waiting for Google sign-in...")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if credentials.isGoogleConnected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Connected")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Reconnect") { connectGoogle() }
                                .buttonStyle(.bordered).controlSize(.small)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            Text("Not connected")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Connect Google Drive") { connectGoogle() }
                                .buttonStyle(.borderedProminent).controlSize(.small)
                        }
                    }
                }

                // Show result from URL callback or local state
                let authResult = GoogleDriveService.shared.lastAuthResult ?? googleConnectResult
                let authIsError = GoogleDriveService.shared.lastAuthResult != nil
                    ? GoogleDriveService.shared.lastAuthWasError
                    : googleConnectIsError
                if let result = authResult {
                    HStack(spacing: 6) {
                        Image(systemName: authIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(authIsError ? .red : .green)
                        Text(result).font(.caption)
                            .foregroundStyle(authIsError ? .red : .primary)
                    }
                }

                if !credentials.isGoogleConnected {
                    Text("After connecting, Google redirects back to the app automatically.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                // Drive reconciliation — move sold items' folders that were
                // left behind in Inventory (e.g. Mark-Sold while signed out).
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync Sold Folders")
                        .font(.subheadline).fontWeight(.medium)
                    Text("Finds folders in your Drive Inventory whose item has sold (SKU is in Sales) and moves them to the Sold folder. Folders for items still in inventory — or with unknown SKUs — are left untouched.")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            scanDriveFolders()
                        } label: {
                            if isReconciling {
                                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Scanning…") }
                            } else {
                                Label("Scan Drive", systemImage: "magnifyingglass")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isReconciling || !credentials.isGoogleConnected)

                        if let preview = reconcilePreview, !preview.candidates.isEmpty {
                            Button {
                                moveDriveFolders(preview.candidates)
                            } label: {
                                Label("Move \(preview.candidates.count) to Sold", systemImage: "arrow.right.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.green)
                            .disabled(isReconciling)
                        }
                    }

                    if let preview = reconcilePreview {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scanned \(preview.scannedFolders) folders · \(preview.candidates.count) to move · \(preview.skippedNotSold) unknown left alone")
                                .font(.caption2).foregroundStyle(.secondary)
                            if !preview.candidates.isEmpty {
                                Text(preview.candidates.prefix(40).joined(separator: ", ")
                                     + (preview.candidates.count > 40 ? "…" : ""))
                                    .font(.caption2).foregroundStyle(.tertiary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    }

                    if let result = reconcileResultText {
                        HStack(spacing: 6) {
                            Image(systemName: reconcileIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(reconcileIsError ? .red : .green)
                            Text(result).font(.caption)
                                .foregroundStyle(reconcileIsError ? .red : .primary)
                        }
                    }
                }
            }

            Section("Instagram") {
                LabeledContent("Account") {
                    HStack(spacing: 8) {
                        if credentials.isInstagramConnected {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("@therealpostermalone · Connected")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                            Text("Not configured")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Access Token")
                        .font(.subheadline).fontWeight(.medium)
                    Text("Long-lived token from Meta Developer → PM Poster → Use Cases → Customize → API setup with Instagram login → Generate token. Expires every ~60 days.")
                        .font(.caption).foregroundStyle(.secondary)

                    @Bindable var creds = credentials
                    SecureField("Paste Instagram access token...", text: $creds.instagramToken)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Text("Instagram Account ID")
                        .font(.subheadline).fontWeight(.medium)
                        .padding(.top, 4)
                    TextField("e.g. YOUR_IG_ACCOUNT_ID", text: $creds.instagramAccountId)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    Text("Account ID: YOUR_IG_ACCOUNT_ID · App ID: YOUR_FB_APP_ID")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                if credentials.isInstagramConnected {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Text("Token expires every 60 days. Regenerate at developers.facebook.com → PM Poster → Use Cases → Customize → API setup with Instagram login → Generate token.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Clear Instagram Credentials") {
                    credentials.clearInstagramTokens()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.red)
                .disabled(!credentials.isInstagramConnected)
            }

            Section {
                Button(saved ? "Saved!" : "Save Credentials") {
                    credentials.saveAll()
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                }
                .buttonStyle(.borderedProminent)
                .disabled(saved)
            }

            Section("Inventory Table Columns") {
                Text("Choose which columns appear in the inventory table. Drag to reorder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ColumnVisibilityManager()
                    .environment(columnSettings)
            }

            Section("Import & Sync") {
                Text("Import your Google Sheets CSV exports to populate the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ImportView()
                    .environment(store)

                Divider()
                    .padding(.vertical, 4)

                // Status sync — targeted patch, no data loss
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sync Status from CSV")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Patches only the Status column for matching SKUs from your Inventory CSV. No other data is changed. Use this to fix status values without re-importing everything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await syncStatusFromCSV() }
                    } label: {
                        if isSyncingStatus {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Sync Status from Inventory CSV", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSyncingStatus)
                    .help("Reads only SKU + Status from your exported Inventory CSV and updates the status on matching items — all other fields stay unchanged")

                    if let result = syncStatusResult {
                        HStack(spacing: 6) {
                            Image(systemName: syncStatusIsError
                                  ? "exclamationmark.circle.fill"
                                  : "checkmark.circle.fill")
                                .foregroundStyle(syncStatusIsError ? .red : .green)
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(syncStatusIsError ? .red : .primary)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 4)

                // Smart merge — updates status + removes sold/deleted items
                VStack(alignment: .leading, spacing: 6) {
                    Text("Smart Merge from CSV")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("Updates status on all matching SKUs AND removes items that are no longer in your inventory CSV (sold or deleted). All other fields (prices, descriptions, etc.) stay unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await smartMergeFromCSV() }
                    } label: {
                        if isMerging {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Smart Merge from Inventory CSV", systemImage: "arrow.triangle.merge")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isMerging)
                    .help("Updates status on matching SKUs and removes items no longer in the CSV — safe for regular use after selling items in Google Sheets")

                    if let result = mergeResult {
                        HStack(spacing: 6) {
                            Image(systemName: mergeIsError
                                  ? "exclamationmark.circle.fill"
                                  : "checkmark.circle.fill")
                                .foregroundStyle(mergeIsError ? .red : .green)
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(mergeIsError ? .red : .primary)
                        }
                    }
                }
                .confirmationDialog(
                    "Remove \(pendingRemovals.count) items from inventory?",
                    isPresented: $showRemovalConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Remove \(pendingRemovals.count) Items", role: .destructive) {
                        for item in pendingRemovals {
                            store.delete(item)
                        }
                        store.save()
                        mergeIsError = false
                        mergeResult = "✓ Removed \(pendingRemovals.count) items no longer in CSV"
                        pendingRemovals = []
                    }
                    Button("Cancel", role: .cancel) {
                        pendingRemovals = []
                        mergeResult = "Cancelled — no items removed"
                    }
                } message: {
                    let skus = pendingRemovals.prefix(5).map(\.sku).joined(separator: ", ")
                    let more = pendingRemovals.count > 5 ? " and \(pendingRemovals.count - 5) more..." : ""
                    Text("These SKUs are not in your CSV and will be removed:\n\(skus)\(more)")
                }
            }

            Section("Data") {
                LabeledContent("Inventory Items", value: "\(store.items.count)")
                LabeledContent("Sales Records",   value: "\(store.sales.count)")

                LabeledContent("Backups Folder") {
                    Button("Open in Finder") {
                        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                        let backupDir = docs.appendingPathComponent("PosterMalone Backups")
                        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(backupDir)
                    }
                    .buttonStyle(.link)
                }

                // CSV Export
                VStack(alignment: .leading, spacing: 6) {
                    Text("Export to CSV")
                        .font(.subheadline).fontWeight(.medium)
                    Text("Exports inventory and sales as CSV files matching your spreadsheet format. Saved to the Backups folder.")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            Task { await exportCSV() }
                        } label: {
                            if isExportingCSV {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Export CSVs Now", systemImage: "arrow.down.doc")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isExportingCSV)
                    }

                    if let result = csvExportResult {
                        HStack(spacing: 6) {
                            Image(systemName: csvExportIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(csvExportIsError ? .red : .green)
                            Text(result).font(.caption)
                                .foregroundStyle(csvExportIsError ? .red : .primary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Restore from Backup")
                        .font(.subheadline).fontWeight(.medium)
                    Text("Select any inventory backup JSON file to load it directly — no renaming or relaunching needed.")
                        .font(.caption).foregroundStyle(.secondary)

                    Button {
                        restoreFromBackup()
                    } label: {
                        if isRestoring {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Choose Backup File...", systemImage: "clock.arrow.circlepath")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRestoring)

                    if let result = restoreResult {
                        HStack(spacing: 6) {
                            Image(systemName: restoreIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(restoreIsError ? .red : .green)
                            Text(result).font(.caption)
                                .foregroundStyle(restoreIsError ? .red : .primary)
                        }
                    }
                }

                LabeledContent("App Support Folder") {
                    Button("Open in Finder") {
                        let url = FileManager.default.urls(
                            for: .applicationSupportDirectory, in: .userDomainMask
                        ).first!.appendingPathComponent("PosterMalone")
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                }
            }

            Section("Image Debug") {
                Text("Tests the first image URL from your inventory to diagnose loading issues.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task { await testImageLoad() }
                } label: {
                    if isTestingImage {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Test First Image URL", systemImage: "photo.badge.magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isTestingImage)

                if let result = imageTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.hasPrefix("✓") ? Color.green : Color.red)
                        .textSelection(.enabled)
                }

                if let urlTested = imageURLTested {
                    Text("URL: \(urlTested)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Admin")

    }

    // MARK: - CSV Export

    private func exportCSV() async {
        isExportingCSV = true
        csvExportResult = nil
        do {
            let invCSV   = CSVExportService.inventoryCSV(from: store.items)
            let salesCSV = CSVExportService.salesCSV(from: store.sales)
            let urls     = try CSVExportService.writeCSVBackup(inventoryCSV: invCSV, salesCSV: salesCSV)
            csvExportIsError = false
            csvExportResult  = "✓ Exported \(store.items.count) inventory + \(store.sales.count) sales rows to Backups folder"
            // Open the folder so user can see the files
            NSWorkspace.shared.activateFileViewerSelecting([urls.inventory, urls.sales])
        } catch {
            csvExportIsError = true
            csvExportResult  = "Export failed: \(error.localizedDescription)"
        }
        isExportingCSV = false
    }

    // MARK: - Google Connect (localhost callback flow)

    private func connectGoogle() {
        googleConnectResult = nil
        Task { @MainActor in
            do {
                try await GoogleDriveService.shared.startAuthorization(credentials: credentials)
                googleConnectIsError = false
                googleConnectResult  = GoogleDriveService.shared.lastAuthResult
            } catch {
                googleConnectIsError = true
                googleConnectResult  = error.localizedDescription
            }
        }
    }

    /// Scan the Drive Inventory folder for sold-but-unmoved folders (preview).
    private func scanDriveFolders() {
        isReconciling = true
        reconcileResultText = nil
        reconcilePreview = nil
        let liveSkus = Set(store.items.map { $0.sku.uppercased() })
        let soldSkus = Set(store.sales.map { $0.sku.uppercased() })
        Task { @MainActor in
            do {
                let preview = try await GoogleDriveService.shared.reconcilePreview(
                    liveSkus: liveSkus, soldSkus: soldSkus)
                reconcilePreview = preview
                reconcileIsError = false
                if preview.candidates.isEmpty {
                    reconcileResultText = "✓ Nothing to move — all sold folders are already in Sold."
                }
            } catch {
                reconcileIsError = true
                reconcileResultText = "Scan failed: \(error.localizedDescription)"
            }
            isReconciling = false
        }
    }

    /// Move the previewed candidate folders Inventory → Sold.
    private func moveDriveFolders(_ skus: [String]) {
        isReconciling = true
        reconcileResultText = nil
        Task { @MainActor in
            do {
                let result = try await GoogleDriveService.shared.reconcileMove(
                    skus: skus, credentials: credentials)
                reconcileIsError = !result.failed.isEmpty
                var msg = "✓ Moved \(result.moved.count) folder\(result.moved.count == 1 ? "" : "s") to Sold."
                if !result.failed.isEmpty {
                    msg += " \(result.failed.count) failed: \(result.failed.map(\.sku).joined(separator: ", "))."
                }
                reconcileResultText = msg
                reconcilePreview = nil   // clear the preview after acting
            } catch {
                reconcileIsError = true
                reconcileResultText = "Move failed: \(error.localizedDescription)"
            }
            isReconciling = false
        }
    }

    // MARK: - Restore from Backup

    private func restoreFromBackup() {
        isRestoring = true
        restoreResult = nil

        let panel = NSOpenPanel()
        panel.title = "Select Inventory Backup"
        panel.message = "Choose an inventory backup JSON file from PosterMalone Backups"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        // Default to the Documents backup folder
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let backupDir = docs.appendingPathComponent("PosterMalone Backups")
        if FileManager.default.fileExists(atPath: backupDir.path) {
            panel.directoryURL = backupDir
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            isRestoring = false
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let items = try decoder.decode([InventoryItem].self, from: data)

            // Write to the live inventory.json and reload
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!.appendingPathComponent("PosterMalone", isDirectory: true)
            let inventoryURL = support.appendingPathComponent("inventory.json")
            try data.write(to: inventoryURL, options: .atomic)

            store.load()

            restoreIsError = false
            restoreResult = "✓ Restored \(items.count) items from \(url.lastPathComponent)"
        } catch {
            restoreIsError = true
            restoreResult = "Restore failed: \(error.localizedDescription)"
        }

        isRestoring = false
    }

    // MARK: - eBay Auth Code Exchange

    private func submitEbayAuthCode() async {
        let code = ebayAuthCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return }
        isConnectingEbay = true
        ebayConnectResult = nil
        do {
            try await EbayService.shared.exchangeEbayCodeForTokens(code: code, credentials: credentials)
            ebayConnectIsError = false
            ebayConnectResult = "✓ eBay connected — fresh refresh token saved"
            ebayAuthCode = ""
        } catch {
            ebayConnectIsError = true
            ebayConnectResult = error.localizedDescription
        }
        isConnectingEbay = false
    }

    // MARK: - eBay Safari Auto-Polling

    private func startEbayAuthPolling() {
        isConnectingEbay = true
        ebayConnectResult = nil
        ebayPollCount = 0
        ebayPollTimer?.invalidate()

        ebayPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [self] _ in
            ebayPollCount += 1
            // Timeout after 3 minutes (90 polls x 2s)
            if ebayPollCount > 90 {
                ebayPollTimer?.invalidate()
                ebayPollTimer = nil
                isConnectingEbay = false
                ebayConnectIsError = true
                ebayConnectResult = "Sign-in timed out. Use manual code entry below."
                return
            }

            // Poll Safari URL via AppleScript
            let script = NSAppleScript(source: """
                tell application "Safari"
                    if (count of windows) > 0 then
                        return URL of front document
                    end if
                    return ""
                end tell
            """)
            var error: NSDictionary?
            let result = script?.executeAndReturnError(&error)
            let urlString = result?.stringValue ?? ""

            // Check for eBay redirect with code
            if urlString.contains("code=") && (urlString.contains("example.com") || urlString.contains("localhost")) {
                ebayPollTimer?.invalidate()
                ebayPollTimer = nil

                // Extract code from URL
                if let components = URLComponents(string: urlString),
                   let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
                    Task { @MainActor in
                        await submitCode(code)
                    }
                } else {
                    isConnectingEbay = false
                    ebayConnectIsError = true
                    ebayConnectResult = "Could not extract code from URL. Use manual entry."
                }
            }
        }
    }

    @MainActor
    private func submitCode(_ code: String) async {
        do {
            try await EbayService.shared.exchangeEbayCodeForTokens(code: code, credentials: credentials)
            ebayConnectIsError = false
            ebayConnectResult = "✓ eBay connected — fresh refresh token saved"
        } catch {
            ebayConnectIsError = true
            ebayConnectResult = error.localizedDescription
        }
        isConnectingEbay = false
    }

    // MARK: - eBay Token Test

    private func testEbayToken() async {
        isConnectingEbay = true
        ebayConnectResult = nil
        do {
            _ = try await EbayService.shared.refreshUserToken(credentials: credentials)
            ebayConnectIsError = false
            ebayConnectResult = "✓ Refresh token is valid — Fulfillment API ready"
        } catch {
            ebayConnectIsError = true
            ebayConnectResult = error.localizedDescription
        }
        isConnectingEbay = false
    }

    // MARK: - Image Debug

    @MainActor
    private func testImageLoad() async {
        isTestingImage = true
        imageTestResult = nil
        imageURLTested = nil

        guard let item = store.items.first(where: { !$0.images.isEmpty }),
              let rawURL = item.images.first else {
            imageTestResult = "✗ No items with image URLs found in inventory"
            isTestingImage = false
            return
        }

        imageURLTested = rawURL

        let fileId: String
        if rawURL.contains("lh3.googleusercontent.com/d/") {
            let after = rawURL.components(separatedBy: "/d/").last ?? ""
            fileId = after.components(separatedBy: CharacterSet(charactersIn: "=#/?"))[0]
        } else if rawURL.contains("id=") {
            fileId = rawURL.components(separatedBy: "id=").last?.components(separatedBy: "&").first ?? ""
        } else {
            fileId = ""
        }

        var results: [String] = []

        let urlsToTest: [(String, String)] = [
            ("lh3 s800",       "https://lh3.googleusercontent.com/d/\(fileId)=s800"),
            ("lh3 s1600",      "https://lh3.googleusercontent.com/d/\(fileId)=s1600"),
            ("lh3 w2000",      "https://lh3.googleusercontent.com/d/\(fileId)=w2000"),
            ("export=view",    "https://drive.google.com/uc?export=view&id=\(fileId)"),
            ("export=download","https://drive.google.com/uc?export=download&id=\(fileId)"),
            ("raw url",        rawURL)
        ]

        for (label, urlStr) in urlsToTest {
            guard !fileId.isEmpty, let url = URL(string: urlStr) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 10)
            req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
                         forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "?"
                let isImage = contentType.contains("image")
                let isHTML = data.prefix(5).elementsEqual("<!DOC".utf8) || data.prefix(5).elementsEqual("<html".utf8)
                results.append("\(isImage && !isHTML ? "✓" : "✗") \(label): HTTP \(status), \(contentType), \(data.count) bytes\(isHTML ? " [HTML]" : "")")
            } catch {
                results.append("✗ \(label): \(error.localizedDescription)")
            }
        }

        imageTestResult = results.joined(separator: "\n")
        isTestingImage = false
    }

    @MainActor
    private func smartMergeFromCSV() async {
        isMerging = true
        mergeResult = nil

        let panel = NSOpenPanel()
        panel.title = "Select your Inventory CSV"
        panel.message = "Choose the exported Inventory CSV from your Poster Malone Google Sheet"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            isMerging = false
            return
        }

        do {
            let statusMap = try CSVImporter.syncStatusFromCSV(from: url)
            let csvSKUs = Set(statusMap.keys)

            var statusUpdated = 0
            for i in store.items.indices {
                if let newStatus = statusMap[store.items[i].sku] {
                    if store.items[i].status != newStatus {
                        store.items[i].status = newStatus
                        statusUpdated += 1
                    }
                }
            }

            let toRemove = store.items.filter { !csvSKUs.contains($0.sku) }

            if toRemove.isEmpty {
                store.save()
                mergeIsError = false
                mergeResult = "✓ Updated \(statusUpdated) statuses. No items to remove — everything matches."
                isMerging = false
                return
            }

            pendingRemovals = toRemove
            isMerging = false
            showRemovalConfirm = true

            if statusUpdated > 0 {
                store.save()
            }

        } catch {
            mergeIsError = true
            mergeResult = error.localizedDescription
            isMerging = false
        }
    }

    // MARK: - Status Sync

    @MainActor
    private func syncStatusFromCSV() async {
        isSyncingStatus = true
        syncStatusResult = nil

        let panel = NSOpenPanel()
        panel.title = "Select your Inventory CSV"
        panel.message = "Choose the exported Inventory CSV from your Poster Malone Google Sheet"
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            isSyncingStatus = false
            return
        }

        do {
            let statusMap = try CSVImporter.syncStatusFromCSV(from: url)
            var updated = 0
            var skipped = 0

            for i in store.items.indices {
                let sku = store.items[i].sku
                if let newStatus = statusMap[sku] {
                    if store.items[i].status != newStatus {
                        store.items[i].status = newStatus
                        updated += 1
                    } else {
                        skipped += 1
                    }
                }
            }

            store.save()

            syncStatusIsError = false
            syncStatusResult = "✓ Updated \(updated) items, \(skipped) already correct, \(statusMap.count - updated - skipped) SKUs not found in app"
        } catch {
            syncStatusIsError = true
            syncStatusResult = error.localizedDescription
        }

        isSyncingStatus = false
    }
}
