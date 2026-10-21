import SwiftUI
import UIKit

/// Canopy, Leaf's design system (docs/design/DESIGN_SYSTEM.md): minimal, clean, cozy. Deep forest green on a clean
/// cream, three supporting accents with one job each, Liquid Glass on everything you touch. Every screen reads its colours, type, space and motion
/// from here.
enum Canopy {
    // MARK: Neutrals (§3)

    /// Every screen's base, under the backdrop glow.
    static let canvas = dynamic(light: 0xF5F1E8, dark: 0x0E1813)
    /// The opaque stand-in for glass under Reduce Transparency, and list cells.
    static let surface = dynamic(light: 0xFCFAF5, dark: 0x172520)
    /// Titles, body and numerals.
    static let text = dynamic(light: 0x16211B, dark: 0xF3EEE2)
    /// Authors, captions, meta.
    static let textSecondary = dynamic(light: 0x5B675F, dark: 0xAEB9B0)
    /// Large or non-text only: placeholders, units beside big numerals.
    static let textTertiary = dynamic(light: 0x7A847D, dark: 0x7C8A81)
    /// Hairlines and progress tracks.
    static let separator = dynamic(light: 0xE4DED1, dark: 0x22332A)
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
    var color: Color { CanopyAccentCache.color[self]! }
    /// Fills and glass tints behind accent content.
    var soft: Color { CanopyAccentCache.soft[self]! }
    /// The backdrop glow: the accent itself, used at low opacity.
    var glow: Color { CanopyAccentCache.glow[self]! }

    fileprivate var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .forest: return (0x1F4D36, 0x93CFA9)
        case .dusk: return (0x46559A, 0xA9B5F2)
        case .clay: return (0xA44A28, 0xEB9C74)
        case .bloom: return (0x963B62, 0xE79BBB)
        }
    }
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

/// The type ramp. New York for books and words worth savouring, SF Pro Rounded for numbers, SF Pro for the rest.
/// Every style is built on a text style, so it follows Dynamic Type.
enum CanopyType: CaseIterable {
    case display, title, bookTitle, headline, body, callout, caption, label, timer, stat, statSmall, quote

    var font: Font {
        switch self {
        case .display: return .system(.largeTitle, design: .serif, weight: .semibold)
        case .title: return .system(.title, weight: .bold)
        case .bookTitle: return .system(.title2, design: .serif, weight: .semibold)
        case .headline: return .system(.headline, weight: .semibold)
        case .body: return .system(.body)
        case .callout: return .system(.callout)
        case .caption: return .system(.footnote, weight: .medium)
        case .label: return .system(.footnote, weight: .semibold)
        case .timer: return .system(size: 76, weight: .semibold, design: .rounded).monospacedDigit()
        case .stat: return .system(.largeTitle, design: .rounded, weight: .semibold).monospacedDigit()
        case .statSmall: return .system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
        case .quote: return .system(.title3, design: .serif).italic()
        }
    }

    /// The colour a style takes unless the caller gives one.
    var defaultColor: Color {
        switch self {
        case .caption: return Canopy.textSecondary
        case .label: return CanopyAccent.forest.color
        default: return Canopy.text
        }
    }

    var name: String {
        switch self {
        case .display: return "display"
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
        font(style.font).foregroundStyle(color ?? style.defaultColor)
    }
}
