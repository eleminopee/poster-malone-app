import SwiftUI
import AppKit

// ============================================================================
// PMTheme.swift — Poster Malone design system
// "Trading terminal for poster art."
// Every color, font, radius, shadow, and animation in the app is defined HERE,
// once. Views never hardcode hex values — they reference PM.*.
// ============================================================================

// MARK: - Hex Color Helper

extension Color {
    /// Init from 0xRRGGBB hex literal — e.g. Color(pmHex: 0xff2d78)
    init(pmHex hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - PM Namespace

enum PM {

    // ── Backgrounds (elevation tiers) ───────────────────────────────────────
    /// Window canvas — the deepest layer
    static let base    = Color(pmHex: 0x0a0a12)
    /// Bars, sidebars, panels sitting on the canvas
    static let surface = Color(pmHex: 0x12121c)
    /// Cards, table containers
    static let card    = Color(pmHex: 0x16161f)
    /// Hovered / raised elements, popovers, sheets
    static let raised  = Color(pmHex: 0x1c1c28)

    // ── Borders ─────────────────────────────────────────────────────────────
    static let borderSubtle = Color.white.opacity(0.06)
    static let borderStrong = Color.white.opacity(0.12)

    // ── Text ────────────────────────────────────────────────────────────────
    static let textPrimary   = Color(pmHex: 0xf2f2f5)
    static let textSecondary = Color(pmHex: 0x9a9aab)
    static let textTertiary  = Color(pmHex: 0x5f5f70)

    // ── Accents ─────────────────────────────────────────────────────────────
    static let pink = Color(pmHex: 0xff2d78)
    static let cyan = Color(pmHex: 0x00e5ff)

    /// Pink → cyan signature gradient (primary buttons, wordmark underline)
    static let gradient = LinearGradient(
        colors: [pink, cyan],
        startPoint: .leading, endPoint: .trailing
    )

    /// Subtle diagonal sheen used behind hero areas
    static let heroWash = LinearGradient(
        colors: [pink.opacity(0.16), Color.clear, cyan.opacity(0.10)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // ── Status colors (semantic — DO NOT change meanings) ───────────────────
    static func statusColor(_ status: ItemStatus) -> Color {
        switch status {
        case .listed:    return .green
        case .active:    return .green
        case .ordered:   return .blue
        case .pending:   return .orange
        case .auction:   return .purple
        case .draft:     return Color(.systemGray)
        case .processed: return .teal
        case .research:  return PM.pink          // hot pink — needs attention
        case .theVault:  return .indigo
        case .sold:      return .red
        case .onHold:    return .yellow
        }
    }

    // ── Radii ───────────────────────────────────────────────────────────────
    enum Radius {
        static let xs: CGFloat   = 4
        static let sm: CGFloat   = 6
        static let md: CGFloat   = 8
        static let lg: CGFloat   = 12
        static let xl: CGFloat   = 16
        static let pill: CGFloat = 999
    }

    // ── Spacing scale ───────────────────────────────────────────────────────
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat  = 4
        static let sm: CGFloat  = 8
        static let md: CGFloat  = 12
        static let lg: CGFloat  = 16
        static let xl: CGFloat  = 24
        static let xxl: CGFloat = 32
    }

    // ── Animation curves ────────────────────────────────────────────────────
    enum Anim {
        /// Row / control hover
        static let hover  = Animation.easeOut(duration: 0.15)
        /// Button press
        static let press  = Animation.easeOut(duration: 0.12)
        /// Sheet / dock slide-in
        static let slide  = Animation.spring(response: 0.35, dampingFraction: 0.86)
        /// Ambient pulse (last-saved dot)
        static let pulse  = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
    }
}

// MARK: - Fonts
// Bebas Neue (display) + Barlow Condensed (body), with graceful fallback to
// system faces so nothing ever renders blank if the bundle fonts are missing.

extension Font {

    private static func nsFontExists(_ name: String) -> Bool {
        NSFont(name: name, size: 12) != nil
    }

    /// Display face — Bebas Neue. Wordmark, stat values, section headers, hero price.
    static func pmDisplay(size: CGFloat) -> Font {
        if nsFontExists("BebasNeue-Regular") {
            return .custom("BebasNeue-Regular", size: size)
        }
        if nsFontExists("Bebas Neue") {
            return .custom("Bebas Neue", size: size)
        }
        // Fallback: heavy rounded system face keeps the "poster" weight
        return .system(size: size, weight: .heavy, design: .rounded)
    }

    /// Body face — Barlow Condensed. Labels, chips, dense UI text.
    static func pmBody(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "BarlowCondensed-SemiBold"
        case .medium:                          name = "BarlowCondensed-Medium"
        default:                               name = "BarlowCondensed-Regular"
        }
        if nsFontExists(name) {
            return .custom(name, size: size)
        }
        if nsFontExists("Barlow Condensed") {
            return .custom("Barlow Condensed", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Glow Shadow Modifiers

extension View {
    /// Soft neon bloom in any color. Use sparingly — glow is information.
    func pmGlow(_ color: Color, radius: CGFloat = 8, opacity: Double = 0.45) -> some View {
        self.shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
    }

    /// Brand pink glow
    func pmPinkGlow(radius: CGFloat = 8) -> some View {
        pmGlow(PM.pink, radius: radius)
    }

    /// Data cyan glow
    func pmCyanGlow(radius: CGFloat = 8) -> some View {
        pmGlow(PM.cyan, radius: radius)
    }
}

// MARK: - Card Style

extension View {
    /// Standard elevated card: card fill, hairline border, soft drop.
    func pmCard(
        fill: Color = PM.card,
        radius: CGFloat = PM.Radius.lg,
        border: Color = PM.borderSubtle
    ) -> some View {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Neon Section Divider
// A glowing hairline — replaces plain Divider() in PM-styled screens.

struct PMNeonDivider: View {
    var color: Color = PM.pink
    var body: some View {
        LinearGradient(
            colors: [.clear, color.opacity(0.55), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(height: 1)
        .pmGlow(color, radius: 3, opacity: 0.35)
        .allowsHitTesting(false)
    }
}

// MARK: - Neon-Bordered Input Style
// Wrap any TextField: dark well, hairline border, pink ring when focused.

struct PMNeonFieldModifier: ViewModifier {
    var isFocused: Bool
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.pmBody(size: 13))
            .padding(.horizontal, PM.Space.sm + 2)
            .padding(.vertical, 6)
            .background(PM.base, in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                    .strokeBorder(isFocused ? PM.pink.opacity(0.8) : PM.borderStrong, lineWidth: 1)
            )
            .pmGlow(PM.pink, radius: isFocused ? 6 : 0, opacity: isFocused ? 0.35 : 0)
            .animation(PM.Anim.hover, value: isFocused)
    }
}

extension View {
    func pmNeonField(isFocused: Bool = false) -> some View {
        modifier(PMNeonFieldModifier(isFocused: isFocused))
    }
}

// MARK: - Primary Gradient Button (pink → cyan)

struct PMPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pmBody(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, PM.Space.lg)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(PM.gradient, in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .pmGlow(PM.pink, radius: configuration.isPressed ? 4 : 9, opacity: 0.40)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(PM.Anim.press, value: configuration.isPressed)
    }
}

// MARK: - Tinted Solid Button (one accent color, glow)

struct PMTintButtonStyle: ButtonStyle {
    var tint: Color
    var prominent: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pmBody(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? Color.white : tint)
            .padding(.horizontal, PM.Space.md)
            .padding(.vertical, 7)
            .background(
                prominent ? tint.opacity(0.92) : tint.opacity(0.14),
                in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                    .strokeBorder(tint.opacity(prominent ? 0.0 : 0.45), lineWidth: 1)
            )
            .pmGlow(tint, radius: configuration.isPressed ? 3 : 7, opacity: prominent ? 0.40 : 0.22)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(PM.Anim.press, value: configuration.isPressed)
    }
}

// MARK: - Ghost Button (hairline, dark)

struct PMGhostButtonStyle: ButtonStyle {
    var tint: Color = PM.textSecondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.pmBody(size: 13, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, PM.Space.md)
            .padding(.vertical, 7)
            .background(PM.raised.opacity(configuration.isPressed ? 1.0 : 0.7),
                        in: RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: PM.Radius.md, style: .continuous)
                    .strokeBorder(PM.borderStrong, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(PM.Anim.press, value: configuration.isPressed)
    }
}

// MARK: - Neon Checkbox Toggle Style
// Restyles the bulk-action checkbox column. Same Toggle mechanism — the
// binding still flips item.action between "Y" and "" upstream.

struct PMNeonCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isOn ? PM.pink : PM.base)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(configuration.isOn ? PM.pink : PM.borderStrong, lineWidth: 1.2)
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 15, height: 15)
            .pmGlow(PM.pink, radius: configuration.isOn ? 5 : 0, opacity: configuration.isOn ? 0.5 : 0)
            .contentShape(Rectangle().inset(by: -6))   // generous hit target
            .animation(PM.Anim.hover, value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Noise / Grain Overlay
// 1–2% film grain that makes the dark canvas feel printed, not rendered.

@MainActor
enum PMNoise {
    /// 128×128 tile of random grayscale pixels, generated once.
    static let tile: NSImage = {
        let size = 128
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt8 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return UInt8(truncatingIfNeeded: seed)
        }
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let v = next()
            pixels[i] = v; pixels[i+1] = v; pixels[i+2] = v; pixels[i+3] = 255
        }
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: size * 4, bitsPerPixel: 32
        )!
        pixels.withUnsafeBufferPointer { src in
            rep.bitmapData!.update(from: src.baseAddress!, count: pixels.count)
        }
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        return img
    }()
}

struct PMNoiseOverlay: View {
    var opacity: Double = 0.018
    var body: some View {
        Image(nsImage: PMNoise.tile)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .blendMode(.overlay)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Screen Background
// Apply to every top-level screen: base canvas + grain + forced dark scheme.

extension View {
    func pmScreen() -> some View {
        self
            .background {
                ZStack {
                    PM.base
                    PMNoiseOverlay()
                }
                .ignoresSafeArea()
            }
            .preferredColorScheme(.dark)
    }
}

// MARK: - Glow Capsule Badge
// The unified status-chip treatment: tinted fill + hairline + bloom.
// `flat: true` omits the shadow MODIFIER entirely (not just opacity 0) —
// in a 900-row table, hundreds of live Gaussian shadows are real compositing
// cost while scrolling. Glow stays in the chrome; rows go flat. (Session 2)

struct PMGlowBadge: View {
    let text: String
    let color: Color
    var icon: String? = nil
    var flat: Bool = false

    private var core: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon).font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(.pmBody(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.16), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }

    var body: some View {
        if flat {
            core
        } else {
            core.pmGlow(color, radius: 4, opacity: 0.35)
        }
    }
}

// MARK: - Wordmark

struct PMWordmark: View {
    var size: CGFloat = 26
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("POSTER MALONE")
                .font(.pmDisplay(size: size))
                .foregroundStyle(PM.pink)
                .pmPinkGlow(radius: 10)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Rectangle()
                .fill(PM.gradient)
                .frame(height: 2)
                .frame(maxWidth: 120)
                .pmCyanGlow(radius: 4)
        }
        .accessibilityLabel("Poster Malone")
    }
}
