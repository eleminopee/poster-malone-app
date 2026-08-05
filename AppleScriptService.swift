import Foundation
import AppKit

// MARK: - AppleScript Service
// No sandbox — uses NSAppleScript directly for simplicity.
// This is a personal app distributed via copy-to-Applications, not App Store.

struct AppleScriptService {

    // MARK: - eBay File Exchange Upload

    @discardableResult
    static func uploadToFileExchange(csvURL: URL) throws -> String {
        let filename = csvURL.lastPathComponent
            .replacingOccurrences(of: "\"", with: "\\\"")

        var lines: [String] = []
        lines.append("set fileExchangeURL to \"https://www.ebay.com/sh/reports/uploads\"")
        lines.append("tell application \"Safari\"")
        lines.append("    activate")
        lines.append("    if (count of windows) = 0 then make new document")
        lines.append("    set URL of front document to fileExchangeURL")
        lines.append("    delay 6")
        lines.append("    do JavaScript \"(function(){ var btns = document.querySelectorAll('button'); for(var i=0;i<btns.length;i++){ if(btns[i].textContent.toLowerCase().indexOf('upload')>-1){ btns[i].click(); break; } } })();\" in front document")
        lines.append("    delay 2")
        lines.append("    do JavaScript \"(function(){ var input = document.querySelector('input[type=file]'); if(input){ input.click(); } })();\" in front document")
        lines.append("    delay 4")
        lines.append("end tell")
        // Use do shell script to run a sub-osascript with full UI access
        // This sidesteps the keystroke permission issue
        lines.append("do shell script \"osascript -e 'tell application \\\"System Events\\\"' -e 'keystroke \\\"" + filename + "\\\"' -e 'delay 0.5' -e 'key code 36' -e 'end tell'\"")
        lines.append("delay 2")
        lines.append("return \"Upload triggered\"")

        let script = lines.joined(separator: "\n")
        print("=== Safari Upload AppleScript ===\n\(script)\n=================================")
        return try run(script)
    }

    // MARK: - Daily Recap Email

    static func sendRecapEmail(
        to recipient: String,
        ended: [(sku: String, title: String, price: Double)],
        scheduled: [(sku: String, title: String, price: Double, slot: Date)],
        inventorySnapshot: InventorySnapshot,
        isTestRun: Bool = false
    ) throws {
        let subjectPrefix = isTestRun ? "[TEST RUN] " : ""
        let dateStr = Date().formatted(date: .abbreviated, time: .omitted)
        let subject = "\(subjectPrefix)Poster Malone Daily Recap — \(dateStr)"
            .replacingOccurrences(of: "\"", with: "'")

        let slotFormatter = DateFormatter()
        slotFormatter.dateFormat = "M/d h:mm a"
        slotFormatter.timeZone = TimeZone(identifier: "America/Chicago")

        var bodyLines: [String] = []
        if isTestRun { bodyLines.append("THIS IS A TEST RUN"); bodyLines.append("") }
        bodyLines.append("ENDED & RE-LISTED TODAY (\(ended.count) items)")
        bodyLines.append(String(repeating: "-", count: 40))
        if ended.isEmpty {
            bodyLines.append("None")
        } else {
            ended.forEach { bodyLines.append("- \($0.sku)  \($0.title)  $\(String(format: "%.2f", $0.price))") }
        }
        bodyLines.append("")
        bodyLines.append("SCHEDULED LISTINGS (\(scheduled.count) items)")
        bodyLines.append(String(repeating: "-", count: 40))
        if scheduled.isEmpty {
            bodyLines.append("None")
        } else {
            scheduled.forEach { bodyLines.append("- \($0.sku)  \($0.title)  $\(String(format: "%.2f", $0.price))  \(slotFormatter.string(from: $0.slot)) CST") }
        }
        bodyLines.append("")
        bodyLines.append("INVENTORY SNAPSHOT")
        bodyLines.append(String(repeating: "-", count: 40))
        bodyLines.append("Total Items:   \(inventorySnapshot.totalItems)")
        bodyLines.append("Listed:        \(inventorySnapshot.listedCount)")
        bodyLines.append("Ordered:       \(inventorySnapshot.orderedCount)")
        bodyLines.append("Processed:     \(inventorySnapshot.processedCount)")
        bodyLines.append("Pending:       \(inventorySnapshot.pendingCount)")
        bodyLines.append("Total Value:   $\(String(format: "%.2f", inventorySnapshot.totalValue))")
        bodyLines.append("All-Time P/L:  $\(String(format: "%.2f", inventorySnapshot.totalProfit))")
        bodyLines.append("")
        bodyLines.append("Sent by Poster Malone App")

        let asBodyParts = bodyLines
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "'") + "\"" }
            .joined(separator: " & return & ")

        let escapedTo = recipient.replacingOccurrences(of: "\"", with: "'")

        var lines: [String] = []
        lines.append("tell application \"Mail\"")
        lines.append("    activate")
        lines.append("    delay 1")
        lines.append("    set bodyText to \(asBodyParts)")
        lines.append("    set newMsg to make new outgoing message")
        lines.append("    set subject of newMsg to \"\(subject)\"")
        lines.append("    set content of newMsg to bodyText")
        lines.append("    set visible of newMsg to false")
        lines.append("    tell newMsg")
        lines.append("        make new to recipient with properties {address:\"\(escapedTo)\"}")
        lines.append("    end tell")
        lines.append("    send newMsg")
        lines.append("end tell")
        lines.append("return \"Email sent\"")

        let script = lines.joined(separator: "\n")
        print("=== Mail Recap AppleScript ===\n\(script)\n=================================")
        try run(script)
    }

    // MARK: - Core Runner

    @discardableResult
    static func run(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw AppleScriptError.executionFailed("Could not create NSAppleScript")
        }
        let result = script.executeAndReturnError(&error)
        if let err = error {
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error"
            throw AppleScriptError.executionFailed(msg)
        }
        return result.stringValue ?? ""
    }

    // No-op — kept for call site compatibility
    static func ensureScriptsDirectory() {}

    enum AppleScriptError: LocalizedError {
        case executionFailed(String)
        var errorDescription: String? {
            switch self { case .executionFailed(let m): return "AppleScript failed: \(m)" }
        }
    }
}

// MARK: - Inventory Snapshot

struct InventorySnapshot {
    let totalItems:     Int
    let listedCount:    Int
    let orderedCount:   Int
    let processedCount: Int
    let pendingCount:   Int
    let totalValue:     Double
    let totalProfit:    Double

    init(from store: InventoryStore) {
        totalItems     = store.items.count
        listedCount    = store.items.filter { $0.status == .listed }.count
        orderedCount   = store.items.filter { $0.status == .ordered }.count
        processedCount = store.items.filter { $0.status == .processed }.count
        pendingCount   = store.items.filter { $0.status == .pending }.count
        totalValue     = store.totalInventoryValue
        totalProfit    = store.totalProfit
    }
}
