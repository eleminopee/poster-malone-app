import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(InventoryStore.self) var store
    @State private var importType: ImportType = .inventory
    @State private var showingFilePicker = false
    @State private var showingResult = false
    @State private var syncResult: SyncResult? = nil
    @State private var errorMessage: String? = nil
    @State private var isProcessing = false

    enum ImportType { case inventory, sales, both }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Stats
            HStack(spacing: 16) {
                ImportStatCard(
                    label: "Inventory Items",
                    value: "\(store.items.count)",
                    icon: "archivebox.fill",
                    color: .blue
                )
                ImportStatCard(
                    label: "Sales Records",
                    value: "\(store.sales.count)",
                    icon: "dollarsign.circle.fill",
                    color: .green
                )
            }

            Divider()

            Text("Import from CSV")
                .font(.headline)

            Text("Export each sheet from Google Sheets via File → Download → CSV, then import below. Existing items are updated by SKU — nothing is deleted.")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Import buttons
            VStack(spacing: 10) {
                ImportRow(
                    title: "Import Inventory",
                    subtitle: "From Inventory sheet CSV",
                    icon: "archivebox",
                    color: .blue,
                    isProcessing: isProcessing
                ) {
                    importType = .inventory
                    showingFilePicker = true
                }

                ImportRow(
                    title: "Import Sales",
                    subtitle: "From Sales sheet CSV",
                    icon: "dollarsign.circle",
                    color: .green,
                    isProcessing: isProcessing
                ) {
                    importType = .sales
                    showingFilePicker = true
                }
            }

            if let error = errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .sheet(isPresented: $showingResult) {
            if let r = syncResult {
                SyncResultView(result: r)
            }
        }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        errorMessage = nil
        guard case .success(let urls) = result, let url = urls.first else { return }

        isProcessing = true

        Task {
            do {
                // Copy file to temp location we definitely have access to
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(url.lastPathComponent)

                let accessed = url.startAccessingSecurityScopedResource()

                do {
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.copyItem(at: url, to: tempURL)
                } catch {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                    throw error
                }

                if accessed { url.stopAccessingSecurityScopedResource() }

                var result = SyncResult()
                switch importType {
                case .inventory:
                    let items = try CSVImporter.importInventory(from: tempURL)
                    result = await MainActor.run {
                        SyncEngine.syncInventory(incoming: items, into: store)
                    }
                case .sales:
                    let sales = try CSVImporter.importSales(from: tempURL)
                    result = await MainActor.run {
                        SyncEngine.syncSales(incoming: sales, into: store)
                    }
                case .both:
                    break
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)

                await MainActor.run {
                    self.syncResult = result
                    isProcessing = false
                    showingResult = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct ImportRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let isProcessing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.medium)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }

                Spacer()

                if isProcessing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }
}

struct ImportStatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title3).fontWeight(.semibold)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity)
    }
}

struct SyncResultView: View {
    let result: SyncResult
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Import Complete")
                .font(.title2)
                .fontWeight(.semibold)

            Text(result.summary)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            if !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(result.errors.prefix(5), id: \.self) { err in
                        Label(err, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding()
                .background(.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(width: 360)
    }
}
