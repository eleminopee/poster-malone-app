import SwiftUI

struct BulkMarkListedSheet: View {
    let items: [InventoryItem]
    @Binding var listedDate: Date
    let onConfirm: () -> Void

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This will set **\(items.count) item\(items.count == 1 ? "" : "s")** to **Listed** status and assign the listed date below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Listed Date") {
                    DatePicker("Date Listed", selection: $listedDate, displayedComponents: .date)
                }

                Section("Items to be Updated") {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.sku)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(item.artist) – \(item.title)")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(item.status.rawValue)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(PM.raised, in: Capsule())
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Listed")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .navigationTitle("Mark as Listed")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply to \(items.count) Items") {
                        onConfirm()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(items.isEmpty)
                }
            }
        }
        .pmScreen()
        .tint(PM.pink)
        .frame(minWidth: 480, minHeight: 400)
    }
}
