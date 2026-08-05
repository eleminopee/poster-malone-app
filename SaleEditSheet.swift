import SwiftUI

struct SaleEditSheet: View {
    @Environment(InventoryStore.self) var store
    @Environment(\.dismiss) var dismiss

    let saleId: UUID

    // All editable fields
    @State private var marketplace: Marketplace
    @State private var dateSold: Date
    @State private var datePurchased: Date
    @State private var dateListed: Date?
    @State private var grossSales: Double
    @State private var taxes: Double
    @State private var feesAndShipping: Double
    @State private var ebayPrice: Double
    @State private var shopifyPrice: Double

    // Item detail overrides (rarely changed after sale but editable for corrections)
    @State private var artist: String
    @State private var title: String
    @State private var size: String
    @State private var edition: String
    @State private var printType: String
    @State private var productionTechnique: String
    @State private var gallery: String
    @State private var franchise: String
    @State private var theme: String
    @State private var condition: String
    @State private var signed: Bool
    @State private var imperfect: Bool
    @State private var netCost: Double
    @State private var taxAndShipping: Double
    @State private var weight: Double
    @State private var ebayTitle: String

    // MARK: Computed (mirrors spreadsheet formulas)
    // Net Sales  = Gross - Taxes - Fees+Shipping
    // Profit     = Net Sales - Total Cost
    // P/L%       = (Profit / Total Cost) × 100   ← cost-based, matches sheet
    // Days Sold  = Date Sold - Date Purchased

    var totalCost: Double      { netCost + taxAndShipping }
    var netSales: Double       { grossSales - taxes - feesAndShipping }
    var profit: Double         { netSales - totalCost }
    var plPercent: Double      { totalCost > 0 ? (profit / totalCost) * 100 : 0 }
    var daysToSell: Int        { max(0, Calendar.current.dateComponents([.day], from: datePurchased, to: dateSold).day ?? 0) }
    var daysInInventory: Int   {
        guard let listed = dateListed else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: listed, to: dateSold).day ?? 0)
    }

    init(sale: SaleRecord) {
        saleId = sale.id
        _marketplace        = State(initialValue: sale.marketplace)
        _dateSold           = State(initialValue: sale.dateSold)
        _datePurchased      = State(initialValue: sale.datePurchased ?? sale.dateSold.addingTimeInterval(-Double(max(sale.daysToSell, 0)) * 86400))
        _dateListed         = State(initialValue: sale.dateListed)
        _grossSales         = State(initialValue: sale.grossSales)
        _taxes              = State(initialValue: sale.taxes)
        _feesAndShipping    = State(initialValue: sale.feesAndShipping)
        _ebayPrice          = State(initialValue: sale.ebayPrice)
        _shopifyPrice       = State(initialValue: sale.shopifyPrice)
        _artist             = State(initialValue: sale.artist)
        _title              = State(initialValue: sale.title)
        _size               = State(initialValue: sale.size)
        _edition            = State(initialValue: sale.edition)
        _printType          = State(initialValue: sale.printType)
        _productionTechnique = State(initialValue: sale.productionTechnique)
        _gallery            = State(initialValue: sale.gallery)
        _franchise          = State(initialValue: sale.franchise)
        _theme              = State(initialValue: sale.theme)
        _condition          = State(initialValue: sale.condition)
        _signed             = State(initialValue: sale.signed)
        _imperfect          = State(initialValue: sale.imperfect)
        _netCost            = State(initialValue: sale.netCost)
        _taxAndShipping     = State(initialValue: sale.taxAndShipping)
        _weight             = State(initialValue: sale.weight)
        _ebayTitle          = State(initialValue: sale.ebayTitle)
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Sale Details
                Section("Sale Details") {
                    Picker("Marketplace", selection: $marketplace) {
                        ForEach(Marketplace.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    DatePicker("Date Sold", selection: $dateSold,
                               displayedComponents: .date)
                }

                // MARK: Financials (the main edit section)
                Section("Financials — Enter These") {
                    TextField("Gross Sales", value: $grossSales,
                              format: .currency(code: "USD"))
                        .help("Total amount the buyer paid including all fees")
                    TextField("Taxes Collected", value: $taxes,
                              format: .currency(code: "USD"))
                        .help("Sales tax collected and remitted by the marketplace")
                    TextField("Fees + Shipping", value: $feesAndShipping,
                              format: .currency(code: "USD"))
                        .help("Platform final value fees plus any shipping label cost")
                }

                // MARK: Auto-calculated (read-only)
                Section("Calculated — Auto-Updated") {
                    LabeledContent("Net Sales") {
                        Text(netSales.asCurrency)
                            .foregroundStyle(.secondary)
                    }
                    .help("Gross - Taxes - Fees+Shipping")

                    LabeledContent("Total Cost") {
                        Text(totalCost.asCurrency)
                            .foregroundStyle(.secondary)
                    }
                    .help("Net Cost + Tax & Shipping paid when acquired")

                    LabeledContent("Profit / Loss") {
                        Text(profit.asCurrency)
                            .foregroundStyle(profit >= 0 ? Color.green : Color.red)
                            .fontWeight(.semibold)
                    }
                    .help("Net Sales - Total Cost")

                    LabeledContent("P/L %") {
                        Text(plPercent.asPercent)
                            .foregroundStyle(plPercent >= 0 ? Color.green : Color.red)
                            .fontWeight(.semibold)
                    }
                    .help("Profit ÷ Cost of Goods × 100 — matches spreadsheet formula")

                    LabeledContent("Days to Sell") {
                        Text("\(daysToSell) days")
                            .foregroundStyle(daysToSell > 365 ? Color.orange : Color.primary)
                    }
                    .help("Date Sold − Date Purchased")

                    LabeledContent("Days in Inventory") {
                        Text(dateListed != nil ? "\(daysInInventory) days" : "—")
                            .foregroundStyle(.secondary)
                    }
                    .help("Date Sold − Date Listed")
                }

                // MARK: Acquisition
                Section("Acquisition") {
                    DatePicker("Date Purchased", selection: $datePurchased,
                               displayedComponents: .date)
                    TextField("Net Cost", value: $netCost,
                              format: .currency(code: "USD"))
                    TextField("Tax & Shipping (acquired)", value: $taxAndShipping,
                              format: .currency(code: "USD"))
                }

                // MARK: Listing Info
                Section("Listing Info") {
                    if let listed = dateListed {
                        LabeledContent("Date Listed", value: listed.shortDate)
                    }
                    TextField("eBay Price", value: $ebayPrice,
                              format: .currency(code: "USD"))
                    TextField("Shopify Price", value: $shopifyPrice,
                              format: .currency(code: "USD"))
                    TextField("eBay Title", text: $ebayTitle)
                    TextField("Weight (lbs)", value: $weight,
                              format: .number)
                }

                // MARK: Item Details
                Section("Item Details") {
                    TextField("Artist", text: $artist)
                    TextField("Title", text: $title)
                    TextField("Size", text: $size)
                    TextField("Edition", text: $edition)
                    TextField("Print Type", text: $printType)
                    TextField("Production Technique", text: $productionTechnique)
                    TextField("Gallery", text: $gallery)
                    TextField("Franchise", text: $franchise)
                    TextField("Theme", text: $theme)
                    TextField("Condition", text: $condition)
                    Toggle("Signed", isOn: $signed)
                    Toggle("Imperfect", isOn: $imperfect)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Edit Sale")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .help("Discard changes")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveSale()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Save changes to this sale record")
                }
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(minWidth: 460, minHeight: 620)
    }

    // MARK: - Save

    private func saveSale() {
        guard let idx = store.sales.firstIndex(where: { $0.id == saleId }) else { return }

        store.sales[idx].marketplace        = marketplace
        store.sales[idx].dateSold           = dateSold
        store.sales[idx].datePurchased      = datePurchased
        store.sales[idx].grossSales         = grossSales
        store.sales[idx].taxes              = taxes
        store.sales[idx].feesAndShipping    = feesAndShipping
        store.sales[idx].netSales           = netSales
        store.sales[idx].totalCost          = totalCost
        store.sales[idx].profit             = profit
        store.sales[idx].profitLossPercent  = plPercent
        store.sales[idx].daysToSell         = daysToSell
        store.sales[idx].daysInInventory    = daysInInventory
        store.sales[idx].ebayPrice          = ebayPrice
        store.sales[idx].shopifyPrice       = shopifyPrice
        store.sales[idx].ebayTitle          = ebayTitle
        store.sales[idx].weight             = weight
        store.sales[idx].artist             = artist
        store.sales[idx].title              = title
        store.sales[idx].size               = size
        store.sales[idx].edition            = edition
        store.sales[idx].printType          = printType
        store.sales[idx].productionTechnique = productionTechnique
        store.sales[idx].gallery            = gallery
        store.sales[idx].franchise          = franchise
        store.sales[idx].theme              = theme
        store.sales[idx].condition          = condition
        store.sales[idx].signed             = signed
        store.sales[idx].imperfect          = imperfect
        store.sales[idx].netCost            = netCost
        store.sales[idx].taxAndShipping     = taxAndShipping

        store.save()
    }
}
