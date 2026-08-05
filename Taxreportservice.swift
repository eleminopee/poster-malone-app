import AppKit
import Foundation

// ============================================================================
// TaxReportService.swift — Tier 2
// Builds a Schedule C–shaped annual summary combining sales revenue/COGS with
// business expenses, then exports CSV. Not tax advice — a worksheet that maps
// the data Poster Malone already tracks onto the lines a sole proprietor's
// Schedule C uses, so filing (or handing to a CPA) is a copy job, not a
// reconstruction.
//
// Mapping:
//   Gross receipts        = Σ sale.grossSales            (Sch C line 1)
//   Returns/allowances    = (not tracked — 0)
//   COGS                  = Σ sale.totalCost             (line 4 / Part III)
//   Gross profit          = receipts − COGS
//   Expenses by category  = Σ expense.amount per category (Part II lines)
//   Net profit            = gross profit − total expenses (line 31)
// Sales taxes collected/remitted are shown separately (pass-through, not income).
// ============================================================================

struct TaxReportService {

    struct MonthRow {
        let month: Int
        let salesCount: Int
        let grossReceipts: Double
        let cogs: Double
        let salesTax: Double
        let fees: Double
    }

    struct AnnualReport {
        let year: Int
        let months: [MonthRow]
        let expenseByCategory: [(category: ExpenseCategory, total: Double)]

        var grossReceipts: Double { months.reduce(0) { $0 + $1.grossReceipts } }
        var cogs: Double          { months.reduce(0) { $0 + $1.cogs } }
        var salesCount: Int       { months.reduce(0) { $0 + $1.salesCount } }
        var salesTax: Double      { months.reduce(0) { $0 + $1.salesTax } }
        var grossProfit: Double   { grossReceipts - cogs }
        var totalExpenses: Double { expenseByCategory.reduce(0) { $0 + $1.total } }
        var netProfit: Double     { grossProfit - totalExpenses }

        func quarter(_ q: Int) -> (receipts: Double, cogs: Double) {
            let range = ((q - 1) * 3 + 1)...((q - 1) * 3 + 3)
            let qm = months.filter { range.contains($0.month) }
            return (qm.reduce(0) { $0 + $1.grossReceipts }, qm.reduce(0) { $0 + $1.cogs })
        }
    }

    // MARK: - Build

    static func build(year: Int, sales: [SaleRecord], expenses: [ExpenseRecord]) -> AnnualReport {
        let cal = Calendar.current
        let yearSales = sales.filter { cal.component(.year, from: $0.dateSold) == year }
        let yearExpenses = expenses.filter { cal.component(.year, from: $0.date) == year }

        var byMonth: [Int: (count: Int, gross: Double, cogs: Double, tax: Double, fees: Double)] = [:]
        for s in yearSales {
            let m = cal.component(.month, from: s.dateSold)
            var e = byMonth[m] ?? (0, 0, 0, 0, 0)
            e.count += 1
            e.gross += s.grossSales
            e.cogs  += s.totalCost
            e.tax   += s.taxes
            e.fees  += s.feesAndShipping
            byMonth[m] = e
        }
        let months = (1...12).map { m -> MonthRow in
            let e = byMonth[m] ?? (0, 0, 0, 0, 0)
            return MonthRow(month: m, salesCount: e.count, grossReceipts: e.gross,
                            cogs: e.cogs, salesTax: e.tax, fees: e.fees)
        }

        var catTotals: [ExpenseCategory: Double] = [:]
        for ex in yearExpenses { catTotals[ex.category, default: 0] += ex.amount }
        // Platform fees from sales (fees+shipping) are a real cost — surface
        // them as a derived expense line so the CPA sees the full picture,
        // without double-counting against any manually-entered platformFees.
        let salesFees = months.reduce(0) { $0 + $1.fees }
        if salesFees > 0 {
            catTotals[.platformFees, default: 0] += salesFees
        }
        let expenseByCategory = ExpenseCategory.allCases.compactMap { cat -> (ExpenseCategory, Double)? in
            let total = catTotals[cat] ?? 0
            return total > 0 ? (cat, total) : nil
        }

        return AnnualReport(year: year, months: months, expenseByCategory: expenseByCategory)
    }

    // MARK: - CSV

    private static func esc(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
    private static func cur(_ v: Double) -> String { String(format: "%.2f", v) }
    private static let monthNames = ["", "Jan","Feb","Mar","Apr","May","Jun",
                                     "Jul","Aug","Sep","Oct","Nov","Dec"]

    static func csv(_ r: AnnualReport) -> String {
        var lines: [String] = []
        lines.append("Poster Malone — \(r.year) Tax Summary (Schedule C worksheet)")
        lines.append("Generated \(Date().formatted(date: .abbreviated, time: .shortened)) — not tax advice")
        lines.append("")

        lines.append("MONTHLY BREAKDOWN")
        lines.append(["Month","Sales","Gross Receipts","COGS","Gross Profit","Sales Tax Collected","Platform Fees+Shipping"].map(esc).joined(separator: ","))
        for m in r.months {
            lines.append([
                monthNames[m.month],
                "\(m.salesCount)",
                cur(m.grossReceipts),
                cur(m.cogs),
                cur(m.grossReceipts - m.cogs),
                cur(m.salesTax),
                cur(m.fees)
            ].map(esc).joined(separator: ","))
        }
        lines.append(["TOTAL","\(r.salesCount)",cur(r.grossReceipts),cur(r.cogs),
                      cur(r.grossProfit),cur(r.salesTax),cur(r.months.reduce(0){$0+$1.fees})]
                        .map(esc).joined(separator: ","))
        lines.append("")

        lines.append("QUARTERLY GROSS RECEIPTS")
        lines.append(["Quarter","Gross Receipts","COGS"].map(esc).joined(separator: ","))
        for q in 1...4 {
            let qd = r.quarter(q)
            lines.append(["Q\(q)", cur(qd.receipts), cur(qd.cogs)].map(esc).joined(separator: ","))
        }
        lines.append("")

        lines.append("EXPENSES BY CATEGORY (Schedule C Part II)")
        lines.append(["Category","Amount"].map(esc).joined(separator: ","))
        for e in r.expenseByCategory {
            lines.append([e.category.rawValue, cur(e.total)].map(esc).joined(separator: ","))
        }
        lines.append(["TOTAL EXPENSES", cur(r.totalExpenses)].map(esc).joined(separator: ","))
        lines.append("")

        lines.append("SUMMARY")
        lines.append(["Gross Receipts (Line 1)", cur(r.grossReceipts)].map(esc).joined(separator: ","))
        lines.append(["Cost of Goods Sold (Line 4)", cur(r.cogs)].map(esc).joined(separator: ","))
        lines.append(["Gross Profit", cur(r.grossProfit)].map(esc).joined(separator: ","))
        lines.append(["Total Expenses (Line 28)", cur(r.totalExpenses)].map(esc).joined(separator: ","))
        lines.append(["NET PROFIT (Line 31)", cur(r.netProfit)].map(esc).joined(separator: ","))
        lines.append("")
        lines.append(esc("Note: Sales tax collected (\(cur(r.salesTax))) is a pass-through liability, not income, and is excluded from net profit. Verify all figures with your CPA."))

        return lines.joined(separator: "\n")
    }

    // MARK: - Save via NSSavePanel (sandbox-safe, matches other export services)

    @MainActor
    static func saveCSV(_ content: String, year: Int) throws -> URL {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "poster_malone_tax_\(year).csv"
        panel.canCreateDirectories = true
        panel.message = "Save your \(year) tax summary"
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        guard panel.runModal() == .OK, let url = panel.url else {
            throw NSError(domain: "TaxReport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Save cancelled"])
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
