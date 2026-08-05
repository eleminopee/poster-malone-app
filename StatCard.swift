import SwiftUI

// ============================================================================
// StatCard.swift — glowing terminal stat tile
// Same init: StatCard(label:value:icon:) — used by InventoryView & SalesView.
// Value in Bebas Neue cyan; icon in a tinted well; hover lift.
// ============================================================================

struct StatCard: View {
    let label: String
    let value: String
    let icon: String

    @State private var hovering = false

    var body: some View {
        HStack(spacing: PM.Space.sm + 2) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PM.cyan)
                .frame(width: 28, height: 28)
                .background(PM.cyan.opacity(0.10), in: RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: PM.Radius.sm, style: .continuous)
                        .strokeBorder(PM.cyan.opacity(0.25), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.pmDisplay(size: 19))
                    .foregroundStyle(PM.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label)
                    .font(.pmBody(size: 11, weight: .medium))
                    .foregroundStyle(PM.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, PM.Space.md + 2)
        .padding(.vertical, PM.Space.sm + 2)
        .pmCard(
            fill: hovering ? PM.raised : PM.card,
            radius: PM.Radius.lg,
            border: hovering ? PM.cyan.opacity(0.30) : PM.borderSubtle
        )
        .pmGlow(PM.cyan, radius: hovering ? 8 : 0, opacity: hovering ? 0.18 : 0)
        .onHover { isIn in
            withAnimation(PM.Anim.hover) { hovering = isIn }
        }
    }
}
