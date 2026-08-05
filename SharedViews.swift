import SwiftUI

// ============================================================================
// SharedViews.swift — cascade layer
// ThumbnailView, StatusBadge, DetailSection, DetailRow.
// PUBLIC APIs ARE UNCHANGED — only the visual treatment is new (PMTheme).
// ============================================================================

// MARK: - Thumbnail View
// Rounded cover art. Same init: ThumbnailView(url:) — `flat: true` drops the
// cyan halo for table rows (Session 2: shadows are expensive at row scale).
// Fetches at 160px — a 36pt cell never needs more (was 1600px before).

struct ThumbnailView: View {
    let url: String?
    var flat: Bool = false
    var maxPixel: Int = 160
    @State private var image: NSImage? = nil
    @State private var failed = false

    /// Synchronous cache peek done at init — a cached thumbnail renders on the
    /// first pass with NO async task. Only genuine misses spawn .task. This is
    /// what keeps swapping the table back to ~920 rows smooth (was: 920
    /// concurrent actor hops → beach ball).
    private var cachedImage: NSImage? {
        guard let urlStr = url, let u = URL(string: urlStr) else { return nil }
        return ImageCache.cached(u, maxPixel: maxPixel)
    }

    var body: some View {
        let shown = image ?? cachedImage
        Group {
            if let img = shown {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                            .strokeBorder(PM.borderStrong, lineWidth: 1)
                    )
                    .pmGlow(PM.cyan, radius: flat ? 0 : 4, opacity: flat ? 0 : 0.22)
            } else if failed {
                RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                    .fill(PM.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                            .strokeBorder(PM.borderSubtle, lineWidth: 1)
                    )
                    .overlay {
                        Image(systemName: "photo.slash")
                            .foregroundStyle(PM.textTertiary)
                            .font(.caption2)
                    }
            } else {
                RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                    .fill(PM.raised)
                    .overlay(
                        RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                            .strokeBorder(PM.borderSubtle, lineWidth: 1)
                    )
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(PM.textTertiary)
                            .font(.caption2)
                    }
            }
        }
        .task(id: url) {
            // Already have it synchronously? Don't touch the actor at all.
            if cachedImage != nil { return }
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let urlStr = url, let url = URL(string: urlStr) else { return }
        if let img = await ImageCache.shared.fetch(url, maxPixel: maxPixel) {
            await MainActor.run { image = img }
        } else {
            await MainActor.run { failed = true }
        }
    }
}

// MARK: - Status Badge
// Same init: StatusBadge(status:). Semantic colors preserved exactly —
// now rendered with the unified glow-capsule treatment.

struct StatusBadge: View {
    let status: ItemStatus
    var flat: Bool = false   // true in table rows — same colors, no shadow

    var color: Color { PM.statusColor(status) }

    var body: some View {
        PMGlowBadge(text: status.rawValue, color: color, flat: flat)
    }
}

// MARK: - Detail Section
// Same init: DetailSection(title:) { ... }. Now a PM card with a glowing
// display-face header and a neon hairline under the title.

struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: PM.Space.sm) {
            HStack(spacing: PM.Space.sm) {
                Text(title)
                    .font(.pmDisplay(size: 15))
                    .foregroundStyle(PM.textSecondary)
                    .tracking(1.2)
                PMNeonDivider(color: PM.pink)
            }
            VStack(spacing: 0) {
                content()
            }
            .padding(.vertical, 2)
            .pmCard(fill: PM.card, radius: PM.Radius.md)
        }
    }
}

// MARK: - Detail Row
// Same init: DetailRow(label:value:). Condensed body face, hairline divider.

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        if !value.isEmpty && value != "—" && value != "$0.00" {
            HStack(alignment: .top) {
                Text(label)
                    .font(.pmBody(size: 13, weight: .medium))
                    .foregroundStyle(PM.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .frame(width: 110, alignment: .leading)
                Text(value)
                    .font(.pmBody(size: 13))
                    .foregroundStyle(PM.textPrimary)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Rectangle()
                .fill(PM.borderSubtle)
                .frame(height: 1)
                .padding(.leading, 10)
        }
    }
}

// MARK: - Safe array subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
