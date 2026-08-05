import SwiftUI

struct MarkSoldSheet: View {
    @Environment(InventoryStore.self) var store
    @Environment(CredentialsManager.self) var credentials
    @Environment(PMRouter.self) var router
    @Environment(\.dismiss) var dismiss
    let item: InventoryItem

    @State private var marketplace: Marketplace = .ebay
    @State private var dateSold: Date = Date()

    private let soldFolderId = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    LabeledContent("SKU",    value: item.sku)
                    LabeledContent("Artist", value: item.artist)
                    LabeledContent("Title",  value: item.title)
                    LabeledContent("Cost Basis", value: item.totalCostComputed.asCurrency)
                }

                Section {
                    Picker("Marketplace", selection: $marketplace) {
                        ForEach(Marketplace.allCases, id: \.self) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    DatePicker("Date Sold", selection: $dateSold, displayedComponents: .date)
                } header: {
                    Text("Sale Details")
                } footer: {
                    Text("Financial details (gross, taxes, fees) can be filled in afterwards via Edit Sale in the Sales tab.")
                        .font(.caption)
                }

            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Mark as Sold")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move to Sales") {
                        confirmSale()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(width: 420, height: 440)
    }

    private func confirmSale() {
        let sku = item.sku
        store.markAsSoldQuick(item, marketplace: marketplace, dateSold: dateSold)

        // Move Drive folder Inventory → Sold. The sheet dismisses immediately,
        // so feedback goes to the GLOBAL toast (router) — previously it was set
        // on this dismissed view's @State and never seen, so a failed move was
        // silent. (Tier 2 robustness.)
        dismiss()
        Task {
            do {
                let moved = try await GoogleDriveService.shared.moveFolder(
                    named: sku,
                    fromParent: GoogleDriveService.shared.inventoryFolderId,
                    toParent: soldFolderId,
                    credentials: credentials
                )
                if moved {
                    router.showToast(.success, "Drive folder for \(sku) moved to Sold")
                } else {
                    router.showToast(.warning, "Marked \(sku) sold — Drive folder not found (skipped)")
                }
            } catch {
                router.showToast(.error, "Marked \(sku) sold, but Drive move failed: \(error.localizedDescription)")
            }
        }
    }
}
