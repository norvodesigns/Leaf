import AppIntents
import SwiftUI
import UIKit

// The reading Live Activity's look: Lock Screen (and StandBy), and the Dynamic Island's compact, minimal and expanded
// regions. The views live here, beside the attributes, so the app can draw them too (a debug gallery stages them for
// screenshots, since CI can't show a real Lock Screen). The extension wraps them in its `ActivityConfiguration`.
//
// Hard limits (NEXT.md section 11): nothing animates per second except what the system draws for
// `Text(timerInterval:)` and `ProgressView(timerInterval:)`. The focus pull comes from state changes (pause, resume,
// goal, page logged), which the system animates with the transitions below, over a cover blurred in advance by the app.

/// The fixed colours of the Live Activity. It always sits on a darkened, blurred cover, so it uses Leaf's night palette
/// (the watch palette in DESIGN.md §2) in both appearances.
enum ReadingActivityPalette {
    static let ink = Color(red: 0xF1 / 255, green: 0xEA / 255, blue: 0xDC / 255)
    static let inkSecondary = Color(red: 0xB9 / 255, green: 0xB0 / 255, blue: 0xA0 / 255)
    static let accent = Color(red: 0x8D / 255, green: 0xBB / 255, blue: 0x98 / 255)
    static let ribbon = Color(red: 0xE0 / 255, green: 0x69 / 255, blue: 0x4F / 255)
    static let amber = Color(red: 0xE5 / 255, green: 0xAA / 255, blue: 0x55 / 255)
    static let night = Color(red: 0x1A / 255, green: 0x17 / 255, blue: 0x14 / 255)
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
        content.state == .goalReached || (isStale && content.countsDown && !content.isPaused)
    }

    var isPaused: Bool { content.isPaused }

    var countsDown: Bool { content.countsDown && !goalReached }

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

    /// "Goal met", "Paused", "Earl Grey · one cup", "Reading".
    var eyebrow: String {
        if goalReached { return "Goal met" }
        if isPaused { return "Paused" }
        if content.state == .finishing { return "The last pages" }
        if let tea = content.teaName { return "\(tea) · one cup" }
        return "Reading"
    }

    /// The app's line, or plain words for the state.
    var headline: String {
        if goalReached, content.state != .goalReached { return "Goal met. Read on?" }
        if let line = content.line, !line.isEmpty { return line }
        switch content.state {
        case .reading: return "A quiet read"
        case .paused: return "Your place is saved"
        case .goalReached: return "Anything more is a gift"
        case .finishing: return "Nearly done"
        }
    }

    /// "to your goal", "to the end of the cup", "read", "paused".
    var timerCaption: String {
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
        goalReached ? "goal" : (isPaused ? "paused" : content.state.rawValue)
    }

    var timerColor: Color {
        if isPaused { return ReadingActivityPalette.inkSecondary }
        return goalReached ? ReadingActivityPalette.accent : ReadingActivityPalette.ink
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
            .font(.system(size: size, weight: .light, design: .serif).monospacedDigit())
            .foregroundStyle(model.timerColor)
            .multilineTextAlignment(.trailing)
            .blur(radius: model.isPaused ? 0.8 : 0)
            .opacity(model.isPaused ? 0.75 : 1)
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
        .tint(model.goalReached ? ReadingActivityPalette.accent : ReadingActivityPalette.amber)
        .accessibilityHidden(true)
    }
}

/// Pause or resume, and a page logged, as intents (they run in the app).
struct ReadingActivityButtons: View {
    let model: ReadingActivityModel
    var compact = false

    var body: some View {
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

/// The blurred cover behind everything, darkened so cream text reads on any cover. Plain night paper without one.
struct ReadingActivityBackdrop: View {
    let image: Image?

    var body: some View {
        ZStack {
            ReadingActivityPalette.night
            if let image {
                image
                    .resizable()
                    .scaledToFill()
                    .opacity(0.9)
            }
            LinearGradient(
                colors: [Color.black.opacity(0.42), Color.black.opacity(0.62)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Lock Screen and StandBy

struct ReadingActivityLockScreen: View {
    let model: ReadingActivityModel
    let images: ReadingActivityImages

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                ReadingActivityCover(image: images.cover, width: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.eyebrow.uppercased())
                        .font(.system(.caption2, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(model.goalReached ? ReadingActivityPalette.accent : ReadingActivityPalette.inkSecondary)
                        .lineLimit(1)
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
            Image(systemName: "cup.and.saucer.fill")
                .foregroundStyle(ReadingActivityPalette.amber)
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
            Image(systemName: "book.fill")
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
