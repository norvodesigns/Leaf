import SwiftUI
import UIKit

// MARK: - Hex helpers

extension Color {
    /// An sRGB colour from a 24-bit hex literal: `Color(hex: 0xF4EFE6)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    /// An sRGB colour from a 24-bit hex literal: `UIColor(hex: 0xF4EFE6)`.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// A colour that follows light and dark mode, and Increase Contrast when given a stronger pair for it.
    static func leafDynamic(
        light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1,
        highContrast: (light: UInt32, dark: UInt32)? = nil
    ) -> UIColor {
        let lightColor = UIColor(hex: light, alpha: lightAlpha)
        let darkColor = UIColor(hex: dark, alpha: darkAlpha)
        let strong = highContrast.map { (light: UIColor(hex: $0.light, alpha: lightAlpha), dark: UIColor(hex: $0.dark, alpha: darkAlpha)) }
        return UIColor { traits in
            let isDark = traits.userInterfaceStyle == .dark
            if let strong, traits.accessibilityContrast == .high { return isDark ? strong.dark : strong.light }
            return isDark ? darkColor : lightColor
        }
    }
}

// MARK: - Tokens (DESIGN.md §2), retuned to Canopy's Oat palette (docs/design/DESIGN_SYSTEM.md §3) so screens not yet
// rebuilt already sit on the chosen cream and green.

/// The palette as dynamic `UIColor`s, for UIKit appearance code. SwiftUI code uses the
/// `Color` tokens below (`.paper`, `.ink`, …).
enum LeafUIColor {
    static let paper = UIColor.leafDynamic(light: 0xF5EFE4, dark: 0x1B1916)
    static let paperRaised = UIColor.leafDynamic(light: 0xFCF8F1, dark: 0x26231F)
    static let paperSunken = UIColor.leafDynamic(light: 0xECE5D7, dark: 0x141210)
    static let ink = UIColor.leafDynamic(light: 0x24201A, dark: 0xF2EADA)
    static let inkSecondary = UIColor.leafDynamic(light: 0x665F54, dark: 0xB5AB99)
    static let inkTertiary = UIColor.leafDynamic(light: 0x6E6457, dark: 0x958B7B)
    static let inkFaint = UIColor.leafDynamic(light: 0xB9B1A3, dark: 0x5A5246)
    static let hairline = UIColor.leafDynamic(light: 0xE5DCCB, dark: 0x3A352E)
    static let hairlineStrong = UIColor.leafDynamic(light: 0xB4AA9A, dark: 0x554D42)
    static let accent = UIColor.leafDynamic(light: 0x48705A, dark: 0xA9CDB2)
    static let accentSoft = UIColor.leafDynamic(light: 0xDFE8DF, dark: 0x2B3A31)
    static let ribbon = UIColor.leafDynamic(light: 0xB23F2C, dark: 0xE0694F)
    static let ribbonSoft = UIColor.leafDynamic(light: 0xF3DDD5, dark: 0x3F2620)
    static let glassTint = UIColor.leafDynamic(light: 0xFCF8F1, dark: 0x1B1916, lightAlpha: 0.22, darkAlpha: 0.30)
    static let lamp = UIColor.leafDynamic(light: 0xFBF6EC, dark: 0x2A2620)
    static let coverShadow = UIColor.leafDynamic(light: 0x2A1F14, dark: 0x000000)

    // Cozy tokens (NEXT.md section 6): warm tints for atmosphere only, never text.
    static let teaPaper = UIColor.leafDynamic(light: 0xEEE6D7, dark: 0x2A2620)
    static let chai = UIColor.leafDynamic(light: 0xB58456, dark: 0xC99A6E)
    static let matcha = UIColor.leafDynamic(light: 0x7F9C5A, dark: 0x9DB97A)
    static let rooibos = UIColor.leafDynamic(light: 0xA9532F, dark: 0xCC714C)
    static let steam = UIColor.leafDynamic(light: 0x9A8F80, dark: 0xE8E1D3)
    static let amber = UIColor.leafDynamic(light: 0xD99A42, dark: 0xE5AA55)
    static let rose = UIColor.leafDynamic(light: 0xB65A6B, dark: 0xD4808F)
}

/// Cached SwiftUI wrappers so each token is built once.
private enum LeafColorCache {
    static let paper = Color(uiColor: LeafUIColor.paper)
    static let paperRaised = Color(uiColor: LeafUIColor.paperRaised)
    static let paperSunken = Color(uiColor: LeafUIColor.paperSunken)
    static let ink = Color(uiColor: LeafUIColor.ink)
    static let inkSecondary = Color(uiColor: LeafUIColor.inkSecondary)
    static let inkTertiary = Color(uiColor: LeafUIColor.inkTertiary)
    static let inkFaint = Color(uiColor: LeafUIColor.inkFaint)
    static let hairline = Color(uiColor: LeafUIColor.hairline)
    static let hairlineStrong = Color(uiColor: LeafUIColor.hairlineStrong)
    static let accent = Color(uiColor: LeafUIColor.accent)
    static let accentSoft = Color(uiColor: LeafUIColor.accentSoft)
    static let ribbon = Color(uiColor: LeafUIColor.ribbon)
    static let ribbonSoft = Color(uiColor: LeafUIColor.ribbonSoft)
    static let glassTint = Color(uiColor: LeafUIColor.glassTint)
    static let lamp = Color(uiColor: LeafUIColor.lamp)
    static let coverShadow = Color(uiColor: LeafUIColor.coverShadow)
    static let teaPaper = Color(uiColor: LeafUIColor.teaPaper)
    static let chai = Color(uiColor: LeafUIColor.chai)
    static let matcha = Color(uiColor: LeafUIColor.matcha)
    static let rooibos = Color(uiColor: LeafUIColor.rooibos)
    static let steam = Color(uiColor: LeafUIColor.steam)
    static let amber = Color(uiColor: LeafUIColor.amber)
    static let rose = Color(uiColor: LeafUIColor.rose)
}

/// Leaf's colour tokens. Declared on `ShapeStyle where Self == Color` so all of these work:
/// `.foregroundStyle(.ink)`, `.tint(.accent)`, `.fill(.hairline)`, `Color.paper`.
extension ShapeStyle where Self == Color {
    /// Every screen background.
    static var paper: Color { LeafColorCache.paper }
    /// Stat tiles, settings rows, a lifted row.
    static var paperRaised: Color { LeafColorCache.paperRaised }
    /// Book-detail stage, wells, chip fills.
    static var paperSunken: Color { LeafColorCache.paperSunken }
    /// Headlines, numerals, body, primary button tint.
    static var ink: Color { LeafColorCache.ink }
    /// Authors, meta, captions.
    static var inkSecondary: Color { LeafColorCache.inkSecondary }
    /// Eyebrows, index numerals, unselected letters.
    static var inkTertiary: Color { LeafColorCache.inkTertiary }
    /// Non-text only: leader dots, future-day dots, missed rings.
    static var inkFaint: Color { LeafColorCache.inkFaint }
    /// 1 px rules and progress tracks.
    static var hairline: Color { LeafColorCache.hairline }
    /// Ruler ticks, the double rule's top line, rest-day dashes.
    static var hairlineStrong: Color { LeafColorCache.hairlineStrong }
    /// "Done" and "sooner": progress fill, toggles, links.
    static var accent: Color { LeafColorCache.accent }
    /// Today's span on the page bar, the "sooner" chip fill.
    static var accentSoft: Color { LeafColorCache.accentSoft }
    /// "Now": today marker, page caret, live dot, dial needle, cover ribbon. Keep it under 3% of a screen.
    static var ribbon: Color { LeafColorCache.ribbon }
    /// The brief flash behind a date that just changed.
    static var ribbonSoft: Color { LeafColorCache.ribbonSoft }
    /// Warm "vellum" glass: `.glassEffect(.regular.tint(.glassTint))`.
    static var glassTint: Color { LeafColorCache.glassTint }
    /// The session mesh's centre point.
    static var lamp: Color { LeafColorCache.lamp }
    /// Base colour for cover shadows; set the alpha per use.
    static var coverShadow: Color { LeafColorCache.coverShadow }

    // Cozy tokens: atmosphere only (tea in the cup, tea rings, the nook's light, scenes). Never text, never a
    // second accent; ink and `accent` still do the work.

    /// Tea-stained paper: the nook's table, quiet wells.
    static var teaPaper: Color { LeafColorCache.teaPaper }
    static var chai: Color { LeafColorCache.chai }
    static var matcha: Color { LeafColorCache.matcha }
    static var rooibos: Color { LeafColorCache.rooibos }
    /// Steam: a warm grey on light paper, near white at night.
    static var steam: Color { LeafColorCache.steam }
    /// Lamp amber.
    static var amber: Color { LeafColorCache.amber }
    static var rose: Color { LeafColorCache.rose }
}

// MARK: - Generated-cover palettes (DESIGN.md §2)

/// One of the ten generated-cover palettes. Covers keep these colours in dark mode.
struct CoverPalette: Hashable, Identifiable {
    let index: Int
    let name: String
    let background: Color
    let foreground: Color
    let rule: Color

    var id: Int { index }

    private init(_ index: Int, _ name: String, background: UInt32, foreground: UInt32, rule: UInt32) {
        self.index = index
        self.name = name
        self.background = Color(hex: background)
        self.foreground = Color(hex: foreground)
        self.rule = Color(hex: rule)
    }

    /// The palette for a book: `Book.paletteSeed % 10`.
    init(book: Book) {
        self = CoverPalette.all[CoverPalette.index(for: book)]
    }

    static func index(for book: Book) -> Int {
        let count = all.count
        return ((book.paletteSeed % count) + count) % count
    }

    static let all: [CoverPalette] = [
        CoverPalette(0, "Oxblood", background: 0x6B2B26, foreground: 0xF3E9D7, rule: 0xD9A866),
        CoverPalette(1, "Ultramarine", background: 0x26375C, foreground: 0xEDE6D8, rule: 0xC9A46A),
        CoverPalette(2, "Bottle", background: 0x2F4A3A, foreground: 0xEADFC8, rule: 0xC8B07A),
        CoverPalette(3, "Slate", background: 0x3D4A52, foreground: 0xE9E4DA, rule: 0xA9B7BE),
        CoverPalette(4, "Plum", background: 0x573247, foreground: 0xF1E4E0, rule: 0xD7A2A0),
        CoverPalette(5, "Teal", background: 0x2D5D5B, foreground: 0xEEE7D9, rule: 0xE0B872),
        CoverPalette(6, "Rust", background: 0x9A4A2C, foreground: 0xF7EBDC, rule: 0xF2C28A),
        CoverPalette(7, "Ochre", background: 0xC48A2C, foreground: 0x1F1A14, rule: 0x6B2B26),
        CoverPalette(8, "Sage", background: 0x9CAE94, foreground: 0x1F2A1E, rule: 0x2A3F2E),
        CoverPalette(9, "Bone", background: 0xE9E0CD, foreground: 0x1C1915, rule: 0xB23F2C),
    ]
}

#Preview("Colour tokens") {
    let tokens: [(String, Color)] = [
        ("paper", .paper), ("paperRaised", .paperRaised), ("paperSunken", .paperSunken),
        ("ink", .ink), ("inkSecondary", .inkSecondary), ("inkTertiary", .inkTertiary), ("inkFaint", .inkFaint),
        ("hairline", .hairline), ("hairlineStrong", .hairlineStrong),
        ("accent", .accent), ("accentSoft", .accentSoft), ("ribbon", .ribbon), ("ribbonSoft", .ribbonSoft),
        ("glassTint", .glassTint), ("lamp", .lamp), ("coverShadow", .coverShadow),
        ("teaPaper", .teaPaper), ("chai", .chai), ("matcha", .matcha), ("rooibos", .rooibos),
        ("steam", .steam), ("amber", .amber), ("rose", .rose),
    ]
    return ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(tokens.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tokens[index].1)
                        .frame(width: 44, height: 28)
                        .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.hairline) }
                    Text(tokens[index].0).leafStyle(.data)
                }
            }
            HStack(spacing: 4) {
                ForEach(CoverPalette.all) { palette in
                    palette.background.frame(width: 24, height: 36)
                }
            }
        }
        .padding(20)
    }
    .paperBackground()
}
