import SwiftUI

struct DuplicateItemSheet: View {
    @Environment(InventoryStore.self) var store
    @Environment(\.dismiss) var dismiss

    let item: InventoryItem

    @State private var quantity: Int = 1
    @State private var resetStatus: Bool = true
    @State private var clearImages: Bool = true
    @State private var createdSkus: [String] = []
    @State private var isDone = false

    private var previewSkus: [String] {
        // Simulate what SKUs would be assigned (for preview only)
        let allSKUs = store.items.map(\.sku) + store.sales.map(\.sku)
        let highest = allSKUs.compactMap { sku -> Int? in
            guard sku.uppercased().hasPrefix("PM-") else { return nil }
            return Int(sku.dropFirst(3))
        }.max() ?? 0
        return (1...quantity).map { i in
            String(format: "PM-%04d", highest + i)
        }
    }

    var body: some View {
        NavigationStack {
            if isDone {
                doneView
            } else {
                configView
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(width: 460, height: isDone ? 320 : 480)
    }

    // MARK: - Config View

    private var configView: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.cyan)
                Text("Duplicate Item")
                    .font(.title2).fontWeight(.bold)
                Text(item.title)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.sku).font(.caption).foregroundStyle(.tertiary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(item.artist).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            Divider()

            Form {
                // Quantity
                Section {
                    HStack {
                        Text("Number of copies")
                        Spacer()
                        Stepper("\(quantity)", value: $quantity, in: 1...19)
                            .fixedSize()
                    }
                    Text("Will create \(quantity) new item\(quantity == 1 ? "" : "s") with sequential SKUs.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("Quantity")
                }

                // Options
                Section {
                    Toggle("Reset status to Pending", isOn: $resetStatus)
                    Toggle("Clear photos (each copy gets its own Drive folder)", isOn: $clearImages)
                } header: {
                    Text("Options")
                } footer: {
                    Text("All other fields — artist, title, size, edition, pricing, descriptions, tags — are copied exactly.")
                        .font(.caption)
                }

                // SKU Preview
                Section {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(previewSkus, id: \.self) { sku in
                                HStack(spacing: 8) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                    Text(sku)
                                        .font(.caption).monospacedDigit()
                                    Text("— \(item.title)")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 90)
                } header: {
                    Text("New SKUs (preview)")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            // Bottom buttons
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)

                Spacer()

                Button {
                    performDuplicate()
                } label: {
                    Label(
                        "Create \(quantity) \(quantity == 1 ? "Copy" : "Copies")",
                        systemImage: "doc.on.doc.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Done View

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("\(createdSkus.count) \(createdSkus.count == 1 ? "Copy" : "Copies") Created")
                    .font(.title2).fontWeight(.bold)
                Text("Find them in your inventory — edit each one to assign drawer, sleeve, and any per-copy details.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // SKU list
            VStack(spacing: 4) {
                ForEach(createdSkus, id: \.self) { sku in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2).foregroundStyle(.green)
                        Text(sku).font(.caption).monospacedDigit()
                        Text("— \(item.title)")
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .padding(.bottom, 20)
        }
    }

    // MARK: - Action

    private func performDuplicate() {
        createdSkus = store.duplicateItem(
            item,
            count: quantity,
            resetStatus: resetStatus,
            clearImages: clearImages
        )
        withAnimation { isDone = true }
    }
}
