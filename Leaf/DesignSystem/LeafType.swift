import SwiftUI

/// PostScript names of the bundled display face (registered through `UIAppFonts`).
enum LeafFontName {
    static let regular = "InstrumentSerif-Regular"
    static let italic = "InstrumentSerif-Italic"
}

/// Typography tokens (DESIGN.md §3) as plain `Font`s.
///
/// A `Font` can't carry tracking, line spacing, case or colour, so prefer
/// `.leafStyle(.eyebrow)` (everything) or `.leafFont(.eyebrow)` (no colour) on views.
/// Instrument Serif is display-only and never appears below 24 pt.
enum LeafType {
    /// 120 pt, fixed. Tracking −3, one line, scales down to 50%.
    static let heroNumeral = Font.custom(LeafFontName.regular, fixedSize: 120)
    /// 160 pt, fixed. The speed-test 3·2·1.
    static let countdown = Font.custom(LeafFontName.regular, fixedSize: 160)
    /// Instrument Serif Italic 96 pt, fixed. Tracking −1.
    static let wordmark = Font.custom(LeafFontName.italic, fixedSize: 96)
    /// New York Light 88 pt, monospaced digits, fixed. Tracking −1.
    static let timer = Font.system(size: 88, weight: .light, design: .serif).monospacedDigit()
    /// 56 pt relative to Large Title. Tracking −1.
    static let display = Font.custom(LeafFontName.regular, size: 56, relativeTo: .largeTitle)
    /// 40 pt relative to Large Title. Tracking −0.5.
    static let masthead = Font.custom(LeafFontName.regular, size: 40, relativeTo: .largeTitle)
    /// 34 pt relative to Title. Tracking −0.5.
    static let statNumeral = Font.custom(LeafFontName.regular, size: 34, relativeTo: .title)
    /// 28 pt relative to Title 2. "01" index numerals.
    static let index = Font.custom(LeafFontName.regular, size: 28, relativeTo: .title2)
    /// Instrument Serif Italic 24 pt relative to Title 2. Tracking −0.2.
    static let pullQuote = Font.custom(LeafFontName.italic, size: 24, relativeTo: .title2)
    /// New York Medium, Title 2 (22).
    static let title = Font.system(.title2, design: .serif, weight: .medium)
    /// New York Semibold, Headline (17).
    static let headline = Font.system(.headline, design: .serif, weight: .semibold)
    /// New York, Body. Line spacing 5.
    static let body = Font.system(.body, design: .serif)
    /// New York, Title 3. Line spacing 9, tracking 0.1.
    static let passage = Font.system(.title3, design: .serif)
    /// New York small caps, Subheadline. Tracking 0.6.
    static let author = Font.system(.subheadline, design: .serif).lowercaseSmallCaps()
    /// SF Pro Medium, Subheadline (15).
    static let ui = Font.system(.subheadline, weight: .medium)
    /// SF Pro, Body.
    static let uiBody = Font.body
    /// SF Pro, Caption (12). Usually `inkSecondary`.
    static let caption = Font.caption
    /// SF Pro Semibold, Caption 2 (11). Uppercase, tracking 1.5, `inkTertiary`.
    static let eyebrow = Font.system(.caption2, weight: .semibold)
    /// SF Pro Medium, Subheadline, monospaced digits. Dates and figures in rows.
    static let data = Font.system(.subheadline, weight: .medium).monospacedDigit()
}

/// A complete text style: font plus the tracking, line spacing, case, colour and limits
/// DESIGN.md §3 attaches to it. Apply with `.leafStyle(_:)`.
enum LeafTextStyle: CaseIterable, Hashable, Sendable {
    case heroNumeral, countdown, wordmark, timer, display, masthead, statNumeral, index, pullQuote
    case title, headline, body, passage, author, ui, uiBody, caption, eyebrow, data

    var font: Font {
        switch self {
        case .heroNumeral: LeafType.heroNumeral
        case .countdown: LeafType.countdown
        case .wordmark: LeafType.wordmark
        case .timer: LeafType.timer
        case .display: LeafType.display
        case .masthead: LeafType.masthead
        case .statNumeral: LeafType.statNumeral
        case .index: LeafType.index
        case .pullQuote: LeafType.pullQuote
        case .title: LeafType.title
        case .headline: LeafType.headline
        case .body: LeafType.body
        case .passage: LeafType.passage
        case .author: LeafType.author
        case .ui: LeafType.ui
        case .uiBody: LeafType.uiBody
        case .caption: LeafType.caption
        case .eyebrow: LeafType.eyebrow
        case .data: LeafType.data
        }
    }

    var tracking: CGFloat {
        switch self {
        case .heroNumeral: -3
        case .wordmark, .timer, .display: -1
        case .masthead, .statNumeral: -0.5
        case .pullQuote: -0.2
        case .passage: 0.1
        case .author: 0.6
        case .eyebrow: 1.5
        default: 0
        }
    }

    var lineSpacing: CGFloat? {
        switch self {
        case .body: 5
        case .passage: 9
        default: nil
        }
    }

    var isUppercase: Bool { self == .eyebrow }

    /// The colour the spec pairs with this style.
    var defaultColor: Color {
        switch self {
        case .caption, .author: .inkSecondary
        case .eyebrow, .index: .inkTertiary
        default: .ink
        }
    }

    /// `display`, `masthead` and `statNumeral` stop growing at accessibility2.
    var capsDynamicType: Bool {
        switch self {
        case .display, .masthead, .statNumeral: true
        default: false
        }
    }

    var lineLimit: Int? {
        switch self {
        case .heroNumeral, .countdown, .timer, .wordmark: 1
        default: nil
        }
    }

    var minimumScaleFactor: CGFloat? {
        switch self {
        case .heroNumeral, .timer: 0.5
        default: nil
        }
    }

    var dynamicTypeRange: ClosedRange<DynamicTypeSize> {
        capsDynamicType ? DynamicTypeSize.xSmall...DynamicTypeSize.accessibility2 : DynamicTypeSize.xSmall...DynamicTypeSize.accessibility5
    }
}

/// Applies a `LeafTextStyle`. Only sets line spacing, case, line limit and scale factor when the
/// style defines them, so a caller's own `.lineLimit(2)` outside still wins.
struct LeafTextStyleModifier: ViewModifier {
    let style: LeafTextStyle
    let color: Color?
    let appliesColor: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        let spacing = style.lineSpacing
        let uppercase = style.isUppercase
        let limit = style.lineLimit
        let scale = style.minimumScaleFactor
        let styled = content
            .font(style.font)
            .tracking(style.tracking)
            .transformEnvironment(\.lineSpacing) { value in
                if let spacing { value = spacing }
            }
            .transformEnvironment(\.textCase) { value in
                if uppercase { value = .uppercase }
            }
            .transformEnvironment(\.lineLimit) { value in
                if let limit { value = limit }
            }
            .transformEnvironment(\.minimumScaleFactor) { value in
                if let scale { value = scale }
            }
            .dynamicTypeSize(style.dynamicTypeRange)
        if appliesColor {
            styled.foregroundStyle(color ?? style.defaultColor)
        } else {
            styled
        }
    }
}

extension View {
    /// The full text style: font, tracking, line spacing, case, colour and limits.
    /// Pass `color:` to override the spec colour (an outer `.foregroundStyle` will not override it).
    func leafStyle(_ style: LeafTextStyle, color: Color? = nil) -> some View {
        modifier(LeafTextStyleModifier(style: style, color: color, appliesColor: true))
    }

    /// Like `leafStyle` but leaves the colour alone, so it inherits `.foregroundStyle` from outside.
    func leafFont(_ style: LeafTextStyle) -> some View {
        modifier(LeafTextStyleModifier(style: style, color: nil, appliesColor: false))
    }
}

extension Text {
    /// Font, tracking and colour as a `Text`, for interpolating styled runs:
    /// `Text("of \(Text(title).leafText(.title))")`. No case, spacing or limits; use `leafStyle` for those.
    func leafText(_ style: LeafTextStyle, color: Color? = nil) -> Text {
        font(style.font)
            .tracking(style.tracking)
            .foregroundStyle(color ?? style.defaultColor)
    }
}

#Preview("Type") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text("22").leafStyle(.heroNumeral)
            Text("2026").leafStyle(.display)
            Text("Good evening.").leafStyle(.masthead)
            Text("6 h 22 m").leafStyle(.statNumeral)
            Text("01").leafStyle(.index)
            Text("about pp. 142–158").leafStyle(.pullQuote)
            Text("The Hobbit").leafStyle(.title)
            Text("Project Hail Mary").leafStyle(.headline)
            Text("In a hole in the ground there lived a hobbit. Not a nasty, dirty, wet hole.").leafStyle(.body)
            Text("J. R. R. Tolkien").leafStyle(.author)
            Text("22 min · The Hobbit").leafStyle(.ui)
            Text("p. 142 of 310 · done by Sun 26 Oct").leafStyle(.caption)
            Text("Thursday 16 October").leafStyle(.eyebrow)
            Text("3 Dec").leafStyle(.data)
        }
        .padding(20)
    }
    .paperBackground()
}
