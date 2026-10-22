import AppIntents
import SwiftUI
import UIKit

// The reading Live Activity's look: Lock Screen (and StandBy), and the Dynamic Island's compact, minimal and expanded
// regions. The views live here, beside the attributes, so the app can draw them too (a debug gallery stages them for
// screenshots, since CI can't show a real Lock Screen). The extension wraps them in its `ActivityConfiguration`.
//
// Hard limits (NEXT.md section 11): nothing animates per second except what the system draws for
// `Text(timerInterval:)` and `ProgressView(timerInterval:)`. The focus pull comes from state changes (pause, resume,
// goal, page logged), which the system animates with the transitions below. In Canopy (docs/design/REDESIGN.md §4.12)
// the timer is Dusk and always sharp, a steep is Clay, and the activity sits on Oat's warm charcoal, not a blurred cover.

/// The fixed colours of the Live Activity: Canopy's Oat palette in its dark form, in both appearances, so it reads the
/// same on the Lock Screen, in StandBy and on the wrist.
enum ReadingActivityPalette {
    /// Oat's cream text.
    static let ink = Color(red: 0xF2 / 255, green: 0xEA / 255, blue: 0xDA / 255)
    static let inkSecondary = Color(red: 0xB5 / 255, green: 0xAB / 255, blue: 0x99 / 255)
    /// Forest: done, the goal met.
    static let accent = Color(red: 0xA9 / 255, green: 0xCD / 255, blue: 0xB2 / 255)
    /// Dusk: reading and time.
    static let dusk = Color(red: 0xA9 / 255, green: 0xB5 / 255, blue: 0xF2 / 255)
    /// Clay: tea.
    static let clay = Color(red: 0xEB / 255, green: 0x9C / 255, blue: 0x74 / 255)
    /// The reading timer's colour (Dusk); the name stays for the places that already use it.
    static let amber = ReadingActivityPalette.dusk
    static let ribbon = ReadingActivityPalette.dusk
    /// Oat's dark canvas, a warm charcoal.
    static let night = Color(red: 0x1B / 255, green: 0x19 / 255, blue: 0x16 / 255)
    static let track = Color.white.opacity(0.16)
}

/// Everything the views need, worked out once from the activity's attributes and state.
struct ReadingActivityModel {
    let title: String
    let author: String
    let totalPages: Int
    let content: ReadingActivityContent
    /// The system marks the activity stale at its stale date, which the app sets to the moment the goal is reached.
    let isStale: Bool

    init(title: String, author: String, totalPages: Int, content: ReadingActivityContent, isStale: Bool) {
        self.title = title
        self.author = author
        self.totalPages = totalPages
        self.content = content
        self.isStale = isStale
    }

    /// The goal is behind us: either the app said so, or the countdown ran out while the app was asleep.
    var goalReached: Bool {
        guard !content.isSteep else { return false }
        return content.state == .goalReached || (isStale && content.countsDown && !content.isPaused)
    }

    /// A pot steeping before the cup.
    var isSteeping: Bool { content.state == .steeping && !isStale }

    /// The tea is ready: the app said so, or the steep ran out while it slept.
    var teaReady: Bool { content.state == .teaReady || (content.state == .steeping && isStale) }

    var isPaused: Bool { content.isPaused }

    var countsDown: Bool { content.countsDown && !goalReached && !teaReady }

    /// Counting down to the goal, or (once it's met, or with no goal) up through the time read.
    var timerRange: ClosedRange<Date> {
        if countsDown { return content.timerRange }
        let start = content.timerStart
        return start...start.addingTimeInterval(ReadingActivityContent.longestTimerSeconds)
    }

    var pauseDate: Date? {
        guard content.isPaused else { return nil }
        let range = timerRange
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        let offset = min(max(TimeInterval(content.pausedElapsedSeconds), 0), span)
        return range.lowerBound.addingTimeInterval(offset)
    }

    var hasGoal: Bool { (content.goalSeconds ?? 0) > 0 }

    /// The share of the goal read while paused (the bar can't run then).
    var pausedFraction: Double {
        guard let goal = content.goalSeconds, goal > 0 else { return 0 }
        return min(1, Double(content.pausedElapsedSeconds) / Double(goal))
    }

    /// "Goal met", "Paused", "Earl Grey · one cup", "Reading", "Earl Grey · steeping", "Earl Grey is ready".
    var eyebrow: String {
        let tea = content.teaName ?? "Your tea"
        if teaReady { return "\(tea) is ready" }
        if isSteeping { return "\(tea) · steeping" }
        if goalReached { return "Goal met" }
        if isPaused { return "Paused" }
        if content.state == .finishing { return "The last pages" }
        if let tea = content.teaName { return "\(tea) · one cup" }
        return "Reading"
    }

    /// The eyebrow when the full one doesn't fit the Lock Screen: just the tea, so it never ends in "STEE…".
    var shortEyebrow: String {
        guard let tea = content.teaName, teaReady || isSteeping || (!goalReached && !isPaused && content.state != .finishing) else {
            return eyebrow
        }
        return tea
    }

    /// The app's line, or plain words for the state.
    var headline: String {
        if teaReady { return "Pour, then read" }
        if isSteeping { return "Find your page and settle in" }
        if goalReached, content.state != .goalReached { return "Goal met. Read on?" }
        if let line = content.line, !line.isEmpty { return line }
        switch content.state {
        case .reading: return "A quiet read"
        case .paused: return "Your place is saved"
        case .goalReached: return "Anything more is a gift"
        case .finishing: return "Nearly done"
        case .steeping: return "Find your page and settle in"
        case .teaReady: return "Pour, then read"
        }
    }

    /// "to your goal", "to the end of the cup", "read", "paused".
    var timerCaption: String {
        if teaReady { return "ready" }
        if isSteeping { return "until it’s ready" }
        if isPaused { return "paused" }
        if countsDown { return content.teaName == nil ? "to your goal" : "left in the cup" }
        return "read"
    }

    /// "p. 142 of 310"
    var pageText: String {
        totalPages > 0 ? "p. \(content.currentPage) of \(totalPages)" : "p. \(content.currentPage)"
    }

    /// Changes whenever the view should rack focus to a new state.
    var phase: String {
        if teaReady { return "ready" }
        return goalReached ? "goal" : (isPaused ? "paused" : content.state.rawValue)
    }

    var timerColor: Color {
        if teaReady || isSteeping { return ReadingActivityPalette.clay }
        if isPaused { return ReadingActivityPalette.inkSecondary }
        return goalReached ? ReadingActivityPalette.accent : ReadingActivityPalette.dusk
    }

    var spokenSummary: String {
        "\(title). \(eyebrow). \(pageText)."
    }
}

/// The small cover and the blurred backdrop the app left in the App Group for this book.
struct ReadingActivityImages {
    var cover: Image?
    var backdrop: Image?

    init(cover: Image? = nil, backdrop: Image? = nil) {
        self.cover = cover
        self.backdrop = backdrop
    }

    /// Reads the pictures for `baseName` from the App Group, if the app wrote them.
    static func load(baseName: String?) -> ReadingActivityImages {
        guard let baseName else { return ReadingActivityImages() }
        let cover = ReadingActivityAssets.coverURL(baseName).flatMap { UIImage(contentsOfFile: $0.path) }
        let backdrop = ReadingActivityAssets.blurredCoverURL(baseName).flatMap { UIImage(contentsOfFile: $0.path) }
        return ReadingActivityImages(cover: cover.map { Image(uiImage: $0) }, backdrop: backdrop.map { Image(uiImage: $0) })
    }
}

// MARK: - Pieces

/// The digits. The system advances them; a paused session is frozen where it stopped.
struct ReadingActivityTimer: View {
    let model: ReadingActivityModel
    var size: CGFloat = 34

    var body: some View {
        Text(timerInterval: model.timerRange, pauseTime: model.pauseDate, countsDown: model.countsDown, showsHours: true)
            .font(.system(size: size, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(model.timerColor)
            .multilineTextAlignment(.trailing)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// How far into the goal: a bar the system fills by itself while reading, still while paused, full once met.
struct ReadingActivityProgress: View {
    let model: ReadingActivityModel

    var body: some View {
        Group {
            if model.goalReached {
                ProgressView(value: 1.0)
            } else if model.countsDown && !model.isPaused {
                ProgressView(timerInterval: model.timerRange, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
            } else if model.hasGoal {
                ProgressView(value: model.pausedFraction)
            } else {
                ProgressView(value: 0.0)
                    .opacity(0)
            }
        }
        .progressViewStyle(.linear)
        .tint(model.goalReached ? ReadingActivityPalette.accent : (model.content.isSteep ? ReadingActivityPalette.clay : ReadingActivityPalette.dusk))
        .accessibilityHidden(true)
    }
}

/// Pause or resume, and a page logged, as intents (they run in the app).
struct ReadingActivityButtons: View {
    let model: ReadingActivityModel
    var compact = false

    var body: some View {
        if !model.content.isSteep {
            sessionButtons
        }
    }

    private var sessionButtons: some View {
        HStack(spacing: 8) {
            if model.isPaused {
                Button(intent: ResumeReadingIntent()) {
                    buttonLabel("Resume", systemImage: "play.fill")
                }
                .accessibilityLabel("Resume reading")
            } else {
                Button(intent: PauseReadingIntent()) {
                    buttonLabel("Pause", systemImage: "pause.fill")
                }
                .accessibilityLabel("Pause reading")
            }
            Button(intent: LogPagesIntent(pages: 1)) {
                buttonLabel("Page", systemImage: "plus")
            }
            .accessibilityLabel("Log a page")
        }
        .buttonStyle(.plain)
    }

    private func buttonLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.system(compact ? .caption2 : .caption, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(ReadingActivityPalette.ink)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 7)
            .background(Color.white.opacity(0.16), in: Capsule())
    }
}

/// A small cover, or a quiet stand-in when the app had none to leave.
struct ReadingActivityCover: View {
    let image: Image?
    var width: CGFloat = 40

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    ReadingActivityPalette.ink.opacity(0.12)
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: width * 0.4))
                        .foregroundStyle(ReadingActivityPalette.inkSecondary)
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// Oat's warm charcoal with a faint lift at the top. Canopy retired the blurred cover backdrop (nothing sits blurred),
/// so `image` is no longer drawn; it stays a parameter so the callers don't change.
struct ReadingActivityBackdrop: View {
    let image: Image?

    var body: some View {
        LinearGradient(
            colors: [Color(red: 0x26 / 255, green: 0x23 / 255, blue: 0x1F / 255), ReadingActivityPalette.night],
            startPoint: .top,
            endPoint: .bottom
        )
        .accessibilityHidden(true)
    }
}

// MARK: - Lock Screen and StandBy

struct ReadingActivityLockScreen: View {
    let model: ReadingActivityModel
    let images: ReadingActivityImages

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption2, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(model.goalReached ? ReadingActivityPalette.accent : ReadingActivityPalette.inkSecondary)
            .lineLimit(1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ReadingActivityCover(image: images.cover, width: 42)
                VStack(alignment: .leading, spacing: 3) {
                    ViewThatFits(in: .horizontal) {
                        eyebrow(model.eyebrow)
                        eyebrow(model.shortEyebrow)
                    }
                    Text(model.title)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(ReadingActivityPalette.ink)
                        .lineLimit(1)
                    Text(model.headline)
                        .font(.system(.subheadline, design: .serif).italic())
                        .foregroundStyle(ReadingActivityPalette.inkSecondary)
                        .lineLimit(1)
                }
                .id(model.phase)
                .transition(.blurReplace)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    ReadingActivityTimer(model: model, size: 34)
                        .frame(maxWidth: 120, alignment: .trailing)
                    Text(model.timerCaption)
                        .font(.caption2)
                        .foregroundStyle(ReadingActivityPalette.inkSecondary)
                }
            }
            ReadingActivityProgress(model: model)
            HStack(alignment: .center, spacing: 8) {
                Text(model.pageText)
                    .font(.system(.caption, weight: .medium).monospacedDigit())
                    .foregroundStyle(ReadingActivityPalette.inkSecondary)
                    .contentTransition(.numericText(value: Double(model.content.currentPage)))
                Spacer(minLength: 4)
                if model.content.state != .finishing {
                    ReadingActivityButtons(model: model)
                }
            }
        }
        .padding(16)
        .background {
            ReadingActivityBackdrop(image: images.backdrop)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.spokenSummary)
    }
}

// MARK: - Dynamic Island

struct ReadingActivityCompactLeading: View {
    let model: ReadingActivityModel
    let images: ReadingActivityImages

    var body: some View {
        if model.content.teaName != nil && !model.goalReached {
            Image(systemName: "cup.and.heat.waves")
                .foregroundStyle(ReadingActivityPalette.clay)
                .accessibilityLabel("Tea and a book")
        } else {
            ReadingActivityCover(image: images.cover, width: 16)
        }
    }
}

struct ReadingActivityCompactTrailing: View {
    let model: ReadingActivityModel

    var body: some View {
        ReadingActivityTimer(model: model, size: 15)
            .frame(maxWidth: 52)
    }
}

/// The smallest form: a ring the system fills while reading, a pause sign, or a check once the goal is met.
struct ReadingActivityMinimal: View {
    let model: ReadingActivityModel

    var body: some View {
        if model.goalReached {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ReadingActivityPalette.accent)
                .accessibilityLabel("Goal met")
        } else if model.isPaused {
            Image(systemName: "pause.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ReadingActivityPalette.inkSecondary)
                .accessibilityLabel("Paused")
        } else if model.countsDown {
            ProgressView(timerInterval: model.timerRange, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                .progressViewStyle(.circular)
                .tint(ReadingActivityPalette.amber)
                .accessibilityLabel("Reading")
        } else {
            Image(systemName: "book.pages")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ReadingActivityPalette.amber)
                .accessibilityLabel("Reading")
        }
    }
}

struct ReadingActivityExpandedLeading: View {
    let images: ReadingActivityImages

    var body: some View {
        ReadingActivityCover(image: images.cover, width: 38)
            .padding(.leading, 4)
    }
}

struct ReadingActivityExpandedTrailing: View {
    let model: ReadingActivityModel

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ReadingActivityTimer(model: model, size: 26)
                .frame(maxWidth: 96, alignment: .trailing)
            Text(model.timerCaption)
                .font(.caption2)
                .foregroundStyle(ReadingActivityPalette.inkSecondary)
        }
        .padding(.trailing, 4)
    }
}

struct ReadingActivityExpandedCenter: View {
    let model: ReadingActivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.title)
                .font(.system(.subheadline, design: .serif).weight(.semibold))
                .foregroundStyle(ReadingActivityPalette.ink)
                .lineLimit(1)
            Text(model.headline)
                .font(.system(.caption, design: .serif).italic())
                .foregroundStyle(model.goalReached ? ReadingActivityPalette.accent : ReadingActivityPalette.inkSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(model.phase)
        .transition(.blurReplace)
    }
}

struct ReadingActivityExpandedBottom: View {
    let model: ReadingActivityModel

    var body: some View {
        VStack(spacing: 8) {
            ReadingActivityProgress(model: model)
            HStack {
                Text(model.pageText)
                    .font(.system(.caption2, weight: .medium).monospacedDigit())
                    .foregroundStyle(ReadingActivityPalette.inkSecondary)
                Spacer(minLength: 4)
                if model.content.state != .finishing {
                    ReadingActivityButtons(model: model, compact: true)
                }
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - A stand-in Lock Screen and island, for the app's debug gallery

// MARK: - Apple Watch

/// The card the Apple Watch shows in its Smart Stack for a Live Activity started on the iPhone (the `.small`
/// supplemental family). Built for a glance on the wrist: a glyph and one line of state, the digits large, a thin bar,
/// the book. High contrast on black, no cover (the wrist is too small for it to read), nothing bright filled in, so it
/// sits well in Always On. The digits run by themselves.
struct ReadingActivityWatchCard: View {
    let model: ReadingActivityModel

    private var glyph: String {
        if model.content.isSteep { return model.teaReady ? "cup.and.heat.waves" : "timer" }
        if model.isPaused { return "pause.fill" }
        if model.goalReached { return "checkmark" }
        return model.content.teaName == nil ? "book.pages" : "cup.and.heat.waves"
    }

    private var tint: Color {
        if model.content.isSteep { return ReadingActivityPalette.clay }
        if model.goalReached { return ReadingActivityPalette.accent }
        if model.isPaused { return ReadingActivityPalette.inkSecondary }
        return ReadingActivityPalette.amber
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(model.eyebrow)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ReadingActivityPalette.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if model.teaReady {
                Text("Ready")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(ReadingActivityPalette.clay)
            } else {
                Text(timerInterval: model.timerRange, pauseTime: model.pauseDate, countsDown: model.countsDown, showsHours: true)
                    .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(model.timerColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if model.hasGoal && !model.teaReady {
                ReadingActivityProgress(model: model)
                    .frame(height: 3)
            }
            Text(model.content.isSteep ? model.headline : model.title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(ReadingActivityPalette.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.spokenSummary)
    }
}

/// The Lock Screen card and the island regions laid out on a dark wallpaper, so screenshots can show the design.
struct ReadingActivityGallery: View {
    let model: ReadingActivityModel
    let images: ReadingActivityImages

    var body: some View {
        VStack(spacing: 18) {
            ReadingActivityLockScreen(model: model, images: images)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            HStack(spacing: 0) {
                ReadingActivityCompactLeading(model: model, images: images)
                    .frame(width: 44)
                Spacer()
                ReadingActivityCompactTrailing(model: model)
                    .frame(width: 60)
            }
            .frame(width: 250, height: 36)
            .background(Color.black, in: Capsule())
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ReadingActivityExpandedLeading(images: images)
                    ReadingActivityExpandedCenter(model: model)
                    ReadingActivityExpandedTrailing(model: model)
                }
                ReadingActivityExpandedBottom(model: model)
            }
            .padding(16)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
            HStack(spacing: 12) {
                ReadingActivityMinimal(model: model)
                    .frame(width: 30, height: 30)
                    .background(Color.black, in: Circle())
                Text("Minimal")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }
}
