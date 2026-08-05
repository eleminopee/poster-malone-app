import SwiftUI
import AuthenticationServices

// ============================================================================
// PosterMaloneApp.swift
// SESSION 3 (audit #5): the store's saves are now debounced/coalesced, so the
// app MUST flush pending changes synchronously before the process can exit.
// Three guarantees added here:
//   1. PMAppDelegate.applicationWillTerminate → flushNow() — normal quit.
//   2. PMAppDelegate.applicationWillResignActive → flushNow() — switching
//      away from the app makes data durable immediately (cheap no-op when
//      nothing is dirty).
//   3. runAutomatedRelist calls flushNow() before BOTH NSApp.terminate sites —
//      the headless relist path can never exit with unwritten inventory,
//      paper-trail, or IG-queue data (flushNow drains the serial write queue,
//      so even the direct paper-trail writes are guaranteed on disk).
// URL-scheme behavior, batch sizes, hasRunToday gating, and timing unchanged.
// ============================================================================

@MainActor
final class PMAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        InventoryStore.shared.flushNow()
    }

    func applicationWillResignActive(_ notification: Notification) {
        InventoryStore.shared.flushNow()
    }
}

@main
struct PosterMaloneApp: App {
    @NSApplicationDelegateAdaptor(PMAppDelegate.self) var appDelegate

    private let store = InventoryStore.shared
    @State private var credentials = CredentialsManager()
    @State private var columnSettings = ColumnSettings()
    @State private var router = PMRouter()

    // Track if app was already open before URL was received
    @State private var wasAlreadyOpen = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(credentials)
                .environment(columnSettings)
                .environment(router)
                .frame(minWidth: 1100, minHeight: 700)
                .onAppear {
                    AppleScriptService.ensureScriptsDirectory()
                    wasAlreadyOpen = true
                    store.refreshIGStatuses()
                }
                .onOpenURL { url in
                    handleURL(url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1400, height: 900)

        Settings {
            AdminView()
                .environment(credentials)
                .environment(store)
        }
    }

    // MARK: - URL Scheme Handler

    private func handleURL(_ url: URL) {
        guard let host = url.host else { return }

        switch host {

        case "relist":
            // Full run — checkAlreadyRan only for automatic launches (not manual from PM Automation)
            // PM Automation passes ?source=manual to bypass the guard
            let isManual = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "source" })?.value == "manual"
            Task { await runAutomatedRelist(batchSize: credentials.automationBatchSize, isTest: false, checkAlreadyRan: !isManual) }

        case "relist-test":
            // Test run — never skip, always run, never writes last_relist.txt
            Task { await runAutomatedRelist(batchSize: 1, isTest: true, checkAlreadyRan: false) }

        case "auth":
            if let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value {
                Task {
                    try? await EbayService.shared.exchangeEbayCodeForTokens(code: code, credentials: credentials)
                }
            }

        default:
            break
        }
    }

    // MARK: - Automated Relist (headless)

    @MainActor
    private func runAutomatedRelist(batchSize: Int, isTest: Bool, checkAlreadyRan: Bool) async {
        if checkAlreadyRan && store.hasRunToday() {
            print("Automation: already ran today, skipping")
            if !wasAlreadyOpen {
                store.flushNow()   // SESSION 3: drain any pending writes before exit
                NSApp.terminate(nil)
            }
            return
        }

        // Hide from dock only if we launched specifically for automation
        if !wasAlreadyOpen {
            NSApp.setActivationPolicy(.prohibited)
        }

        print("Automation: starting \(isTest ? "TEST" : "FULL") relist — \(batchSize) item(s) — \(Date())")
        let result = await store.relistSilently(credentials: credentials, batchSize: batchSize, isTest: isTest)
        print("Automation: completed — \(result)")

        // Only quit if we launched specifically for this — don't quit if user had app open
        if !wasAlreadyOpen {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            // SESSION 3: guarantee every mutation from the relist run —
            // inventory updates, paper-trail entries, IG queue — is on disk
            // before the process exits. flushNow() encodes pending changes
            // and synchronously drains the serial write queue.
            store.flushNow()
            NSApp.terminate(nil)
        }
    }
}
