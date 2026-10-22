import SwiftUI
import UIKit

/// Canopy, Leaf's design system (docs/design/DESIGN_SYSTEM.md): the live app's editorial warmth, made cleaner. Cream is
/// the page, green is the ink you act with (text, progress, key controls), black is the one hero button, and glass sits
/// on everything you touch. Every screen reads its colours, type, space and motion from here.
enum Canopy {
    // MARK: Neutrals (§3), from the palette in use

    /// Every screen's base: the cream page.
    static var canvas: Color { CanopyPalette.current.colors.canvas }
    /// Cards under Reduce Transparency, list cells: a brighter cream.
    static var surface: Color { CanopyPalette.current.colors.surface }
    /// Titles, body and numerals: warm ink.
    static var text: Color { CanopyPalette.current.colors.text }
    /// Authors, captions, meta.
    static var textSecondary: Color { CanopyPalette.current.colors.textSecondary }
    /// Large or non-text only: placeholders, units beside big numerals.
    static var textTertiary: Color { CanopyPalette.current.colors.textTertiary }
    /// Hairlines and progress tracks.
    static var separator: Color { CanopyPalette.current.colors.separator }
    /// The Hero button's fill, black in both modes.
    static let hero = Color.black

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor.leafDynamic(light: light, dark: dark))
    }

    // MARK: Space and shape (§5)

    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
        /// Screen side margin.
        static let margin: CGFloat = 20
        /// Inside a card.
        static let cardPadding: CGFloat = 20
        /// Between cards.
        static let cardGap: CGFloat = 16
        /// Between sections.
        static let section: CGFloat = 32
        /// The smallest thing a finger may have to hit.
        static let hitTarget: CGFloat = 44
    }

    enum Radius {
        static let control: CGFloat = 16
        static let card: CGFloat = 28
        static let sheet: CGFloat = 36
        static let cover: CGFloat = 6
    }

    // MARK: Motion (§8)

    enum Motion {
        /// Controls, toggles, chips, selection.
        static let snappy: Animation = .snappy(duration: 0.28)
        /// Layout changes, cards appearing, reorders.
        static let smooth: Animation = .smooth(duration: 0.42)
        /// Celebrations only: goal met, book finished.
        static let bouncy: Animation = .bouncy(duration: 0.5, extraBounce: 0.08)
        /// Focus In: something soft resolves to sharp. Always ends sharp.
        static let focusIn: Animation = .smooth(duration: 0.5)
        static let focusInBlur: CGFloat = 12
        /// The Reduce Motion stand-in for every movement.
        static let fade: Animation = .easeInOut(duration: 0.2)

        static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? fade : animation
        }
    }
}

// MARK: - Accents (§3)

/// The four accents, each with one job. Use the accent of the job, never one for decoration.
enum CanopyAccent: String, CaseIterable, Identifiable, Sendable {
    /// Primary: brand, selection, growth (progress, done, goals, streaks).
    case forest
    /// Reading and time: sessions, reading times, timers, "now".
    case dusk
    /// Tea: steeping, cabinet, caffeine.
    case clay
    /// Memories and insights: journal, quotes, challenges, stamps.
    case bloom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forest: return "Forest"
        case .dusk: return "Dusk"
        case .clay: return "Clay"
        case .bloom: return "Bloom"
        }
    }

    var job: String {
        switch self {
        case .forest: return "Brand, progress, done"
        case .dusk: return "Reading and time"
        case .clay: return "Tea"
        case .bloom: return "Memories and insights"
        }
    }

    /// Text-safe on `canvas` and `surface` in both modes (4.5:1 or better).
    var color: Color { self == .forest ? CanopyPalette.current.colors.forest : CanopyAccentCache.color[self]! }
    /// Fills and glass tints behind accent content.
    var soft: Color { self == .forest ? CanopyPalette.current.colors.forestSoft : CanopyAccentCache.soft[self]! }
    /// The backdrop glow: the accent itself, used at low opacity.
    var glow: Color { self == .forest ? CanopyPalette.current.colors.forest : CanopyAccentCache.glow[self]! }

    fileprivate var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .forest: return (0x3A6A4F, 0x9CC8A9) // stand-in; the palette's green is used
        case .dusk: return (0x46559A, 0xA9B5F2)
        case .clay: return (0xA44A28, 0xEB9C74)
        case .bloom: return (0x963B62, 0xE79BBB)
        }
    }
}

// MARK: - Palettes

/// The cream-and-green palettes on offer . The owner chose Oat (2026-10-22), the default; a launch argument
/// (`-CanopyPalette oat`) picks another for screenshots. Only the neutrals and the green change; Dusk, Clay and Bloom
/// keep their jobs and values.
enum CanopyPalette: String, CaseIterable, Identifiable, Sendable {
    /// A bright, clean cream with the live app's green. Recommended.
    case linen
    /// A warmer oat cream with a soft sage green: the most cream on screen.
    case oat
    /// Near-white ivory with a deep pine green: the cleanest.
    case ivory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .linen: return "Linen"
        case .oat: return "Oat"
        case .ivory: return "Ivory"
        }
    }

    var summary: String {
        switch self {
        case .linen: return "Bright cream, the live app’s green"
        case .oat: return "Warmer cream, soft sage"
        case .ivory: return "Near-white, deep pine"
        }
    }

    /// The palette in use, read once from the launch arguments or defaults.
    static let current: CanopyPalette = CanopyPalette(rawValue: UserDefaults.standard.string(forKey: "CanopyPalette") ?? "") ?? .oat

    var colors: CanopyColors { CanopyColors.cache[self]! }

    /// Light and dark hex values: canvas, surface, text, secondary, tertiary, separator, green.
    fileprivate var hex: [(UInt32, UInt32)] {
        switch self {
        case .linen:
            return [(0xFAF6EE, 0x161513), (0xFFFDF9, 0x211F1C), (0x1F1C17, 0xF4EDDF), (0x625C52, 0xB8AF9F),
                    (0x8B8478, 0x857D70), (0xE8E1D4, 0x34302A), (0x3A6A4F, 0x9CC8A9)]
        case .oat:
            return [(0xF5EFE4, 0x1B1916), (0xFCF8F1, 0x26231F), (0x24201A, 0xF2EADA), (0x665F54, 0xB5AB99),
                    (0x8C8478, 0x847B6E), (0xE5DCCB, 0x3A352E), (0x48705A, 0xA9CDB2)]
        case .ivory:
            return [(0xFCFBF7, 0x121413), (0xFFFFFF, 0x1C1F1D), (0x1A1D1B, 0xF1EEE6), (0x5D625E, 0xAEB2AD),
                    (0x878C88, 0x7E837F), (0xECEAE3, 0x2C302D), (0x2C5A43, 0x8FC2A2)]
        }
    }
}

/// One palette's colours, built once.
struct CanopyColors {
    let canvas: Color
    let surface: Color
    let text: Color
    let textSecondary: Color
    let textTertiary: Color
    let separator: Color
    let forest: Color
    let forestSoft: Color

    fileprivate init(_ palette: CanopyPalette) {
        let h = palette.hex
        canvas = Canopy.dynamic(light: h[0].0, dark: h[0].1)
        surface = Canopy.dynamic(light: h[1].0, dark: h[1].1)
        text = Canopy.dynamic(light: h[2].0, dark: h[2].1)
        textSecondary = Canopy.dynamic(light: h[3].0, dark: h[3].1)
        textTertiary = Canopy.dynamic(light: h[4].0, dark: h[4].1)
        separator = Canopy.dynamic(light: h[5].0, dark: h[5].1)
        forest = Canopy.dynamic(light: h[6].0, dark: h[6].1)
        forestSoft = Color(uiColor: UIColor.leafDynamic(light: h[6].0, dark: h[6].1, lightAlpha: 0.12, darkAlpha: 0.22))
    }

    fileprivate static let cache: [CanopyPalette: CanopyColors] = Dictionary(uniqueKeysWithValues: CanopyPalette.allCases.map { ($0, CanopyColors($0)) })
}

/// Built once: dynamic colours are cheap to keep and costly to rebuild in every body.
private enum CanopyAccentCache {
    static let color: [CanopyAccent: Color] = Dictionary(uniqueKeysWithValues: CanopyAccent.allCases.map { accent in
        (accent, Canopy.dynamic(light: accent.hex.light, dark: accent.hex.dark))
    })
    static let soft: [CanopyAccent: Color] = Dictionary(uniqueKeysWithValues: CanopyAccent.allCases.map { accent in
        (accent, Color(uiColor: UIColor.leafDynamic(light: accent.hex.light, dark: accent.hex.dark, lightAlpha: 0.14, darkAlpha: 0.24)))
    })
    static let glow: [CanopyAccent: Color] = Dictionary(uniqueKeysWithValues: CanopyAccent.allCases.map { accent in
        (accent, Color(uiColor: UIColor.leafDynamic(light: accent.hex.light, dark: accent.hex.dark)))
    })
}

// MARK: - Type (§4)

/// The type ramp, kept from the live app's editorial voice: Instrument Serif for greetings and big numbers, New York for
/// books and quotes, SF Pro for everything you operate. Every style follows Dynamic Type.
enum CanopyType: CaseIterable {
    case display, subline, eyebrow, title, bookTitle, headline, body, callout, caption, label, timer, stat, statSmall, quote

    var font: Font {
        switch self {
        case .display: return .custom(LeafFontName.regular, size: 52, relativeTo: .largeTitle)
        case .subline: return .custom(LeafFontName.italic, size: 24, relativeTo: .title2)
        case .eyebrow: return .system(.caption2, weight: .semibold)
        case .title: return .system(.title, weight: .bold)
        case .bookTitle: return .system(.title2, design: .serif, weight: .semibold)
        case .headline: return .system(.headline, weight: .semibold)
        case .body: return .system(.body)
        case .callout: return .system(.callout)
        case .caption: return .system(.footnote, weight: .medium)
        case .label: return .system(.footnote, weight: .semibold)
        case .timer: return .system(size: 80, weight: .light, design: .serif).monospacedDigit()
        case .stat: return .custom(LeafFontName.regular, size: 36, relativeTo: .title)
        case .statSmall: return .system(.title3, design: .serif, weight: .medium).monospacedDigit()
        case .quote: return .system(.title3, design: .serif).italic()
        }
    }

    /// The colour a style takes unless the caller gives one.
    var defaultColor: Color {
        switch self {
        case .caption, .subline: return Canopy.textSecondary
        case .eyebrow: return Canopy.textTertiary
        case .label: return CanopyAccent.forest.color
        default: return Canopy.text
        }
    }

    var name: String {
        switch self {
        case .display: return "display"
        case .subline: return "subline"
        case .eyebrow: return "eyebrow"
        case .title: return "title"
        case .bookTitle: return "bookTitle"
        case .headline: return "headline"
        case .body: return "body"
        case .callout: return "callout"
        case .caption: return "caption"
        case .label: return "label"
        case .timer: return "timer"
        case .stat: return "stat"
        case .statSmall: return "statSmall"
        case .quote: return "quote"
        }
    }
}

extension View {
    /// Sets a Canopy text style and its default colour (or `color`).
    func canopyText(_ style: CanopyType, color: Color? = nil) -> some View {
        font(style.font)
            .foregroundStyle(color ?? style.defaultColor)
            .tracking(style == .eyebrow ? 1.5 : (style == .display ? -1 : 0))
            .textCase(style == .eyebrow ? .uppercase : nil)
    }
}
