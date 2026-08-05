import SwiftUI

// ============================================================================
// TrashView.swift — Tier 2 robustness
// Soft-delete recovery: items deleted from inventory land here for 30 days,
// restorable or permanently removable. Also defines the global toast overlay
// used for Drive-move feedback and restore confirmations.
//
// TrashedItem is defined here (not Models.swift, which is a no-touch file) —
// it's a thin wrapper, not a change to existing models.
// ============================================================================

struct TrashedItem: Identifiable, Codable {
    var id: UUID = UUID()
    var item: InventoryItem
    var deletedAt: Date

    var daysLeft: Int {
        let elapsed = Calendar.current.dateComponents([.day], from: deletedAt, to: Date()).day ?? 0
        return max(0, 30 - elapsed)
    }
}

struct TrashView: View {
    @Environment(InventoryStore.self) var store
    @Environment(PMRouter.self) var router
    @State private var showingEmptyConfirm = false

    private var sorted: [TrashedItem] {
        store.trash.sorted { $0.deletedAt > $1.deletedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("TRASH")
                    .font(.pmDisplay(size: 18))
                    .foregroundStyle(PM.textPrimary)
                    .tracking(0.8)
                Text("Deleted items are kept 30 days, then removed automatically.")
                    .font(.pmBody(size: 12))
                    .foregroundStyle(PM.textTertiary)
                Spacer()
                if !store.trash.isEmpty {
                    Button(role: .destructive) {
                        showingEmptyConfirm = true
                    } label: {
                        Label("Empty Trash", systemImage: "trash")
                            .font(.pmBody(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PM.surface)

            PMNeonDivider(color: PM.pink).opacity(0.5)

            if store.trash.isEmpty {
                ContentUnavailableView {
                    Label("Trash is Empty", systemImage: "trash")
                        .font(.pmDisplay(size: 20))
                        .foregroundStyle(PM.textSecondary)
                } description: {
                    Text("Items you delete from inventory appear here, restorable for 30 days.")
                        .font(.pmBody(size: 13))
                        .foregroundStyle(PM.textTertiary)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sorted) { trashed in
                            TrashRow(
                                trashed: trashed,
                                onRestore: {
                                    store.restoreFromTrash(trashed)
                                    router.showToast(.success, "Restored \(trashed.item.sku) to inventory")
                                },
                                onDelete: {
                                    store.permanentlyDelete(trashed)
                                    router.showToast(.warning, "Permanently deleted \(trashed.item.sku)")
                                }
                            )
                            Rectangle().fill(PM.borderSubtle).frame(height: 1)
                        }
                    }
                }
            }
        }
        .pmScreen()
        .navigationTitle("Trash")
        .confirmationDialog(
            "Empty Trash?",
            isPresented: $showingEmptyConfirm,
            titleVisibility: .visible
        ) {
            Button("Permanently Delete \(store.trash.count) Items", role: .destructive) {
                let n = store.trash.count
                store.emptyTrash()
                router.showToast(.warning, "Emptied trash — \(n) items permanently deleted")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
}

// MARK: - Trash Row

struct TrashRow: View {
    let trashed: TrashedItem
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(url: trashed.item.primaryImage, flat: true)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(trashed.item.title)
                    .font(.pmBody(size: 14, weight: .medium))
                    .foregroundStyle(PM.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(trashed.item.sku)
                        .font(.pmBody(size: 11))
                        .foregroundStyle(PM.textTertiary)
                    Text("·").foregroundStyle(PM.textTertiary)
                    Text(trashed.item.artist)
                        .font(.pmBody(size: 11))
                        .foregroundStyle(PM.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text("\(trashed.daysLeft)d left")
                .font(.pmBody(size: 11, weight: .medium))
                .foregroundStyle(trashed.daysLeft <= 5 ? .orange : PM.textTertiary)
                .monospacedDigit()

            Button(action: onRestore) {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .font(.pmBody(size: 12, weight: .medium))
            }
            .buttonStyle(PMTintButtonStyle(tint: .green, prominent: false))

            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(PMGhostButtonStyle(tint: .red))
            .confirmationDialog(
                "Permanently delete \(trashed.item.sku)?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Forever", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Global Toast Overlay
// Attached once at the app root; shows router.toast and auto-dismisses.

struct PMToastOverlay: View {
    @Environment(PMRouter.self) var router

    var body: some View {
        VStack {
            Spacer()
            if let toast = router.toast {
                HStack(spacing: 10) {
                    Image(systemName: icon(toast.kind))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color(toast.kind))
                    Text(toast.message)
                        .font(.pmBody(size: 13, weight: .medium))
                        .foregroundStyle(PM.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(PM.raised.opacity(0.98),
                            in: RoundedRectangle(cornerRadius: PM.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PM.Radius.lg, style: .continuous)
                        .strokeBorder(color(toast.kind).opacity(0.45), lineWidth: 1)
                )
                .pmGlow(color(toast.kind), radius: 10, opacity: 0.25)
                .shadow(color: .black.opacity(0.5), radius: 14, x: 0, y: 6)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast) {
                    try? await Task.sleep(for: .seconds(3.5))
                    withAnimation(PM.Anim.slide) { router.toast = nil }
                }
            }
        }
        .animation(PM.Anim.slide, value: router.toast)
        .allowsHitTesting(false)
    }

    private func icon(_ k: PMRouter.Toast.Kind) -> String {
        switch k {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }
    private func color(_ k: PMRouter.Toast.Kind) -> Color {
        switch k {
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
