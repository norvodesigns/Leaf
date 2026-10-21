import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// The Home Screen, StandBy and Lock Screen widgets' look. Like the Live Activity's views they live here, beside the
// snapshot, so the app can draw them in a debug gallery for screenshots (CI has no Home Screen); the extension wraps
// them in its `StaticConfiguration`.
//
// Same rules as the Live Activity: nothing animates per second except what the system draws for
// `Text(timerInterval:)` and `ProgressView(timerInterval:)`; covers and their blur are pre-rendered by the app.
// Unlike it, the widgets sit on the Home Screen beside everything else, so they follow light and dark: paper by day,
// paper at night, one green accent.

/// Leaf's paper palette (DESIGN.md §2), light and dark. The extension can't see the app's `LeafColor`.
enum LeafWidgetPalette {
    static let paper = LeafWidgetPalette.dynamic(0xF4EFE6, 0x1A1714)
    static let paperRaised = LeafWidgetPalette.dynamic(0xFBF8F2, 0x24201B)
    static let ink = LeafWidgetPalette.dynamic(0x1F1A15, 0xEFE7D8)
    static let inkSecondary = LeafWidgetPalette.dynamic(0x5C554B, 0xB5AB98)
    static let inkTertiary = LeafWidgetPalette.dynamic(0x6E6457, 0x958B7B)
    static let hairline = LeafWidgetPalette.dynamic(0xDDD5C7, 0x36302A)
    static let track = LeafWidgetPalette.dynamic(0xE3DBCD, 0x332D26)
    static let accent = LeafWidgetPalette.dynamic(0x3E6B4F, 0x8DBB98)
    /// The label on an accent fill: paper by day, deep green at night (DESIGN.md's watch button label).
    static let onAccent = LeafWidgetPalette.dynamic(0xFBF8F2, 0x0E1A12)
    static let ribbon = LeafWidgetPalette.dynamic(0xB23F2C, 0xE0694F)
    /// Chai, a shade deeper by day so it reads on paper.
    static let tea = LeafWidgetPalette.dynamic(0x8F5F33, 0xC99A6E)

    /// The ten generated-cover backgrounds, in the app's order.
    static let covers: [Color] = ([0x6B2B26, 0x26375C, 0x2F4A3A, 0x3D4A52, 0x573247, 0x2D5D5B, 0x9A4A2C, 0xC48A2C, 0x9CAE94, 0xE9E0CD] as [UInt32])
        .map { Color(uiColor: LeafWidgetPalette.rgb($0)) }

    static func cover(for seed: Int) -> Color { covers[abs(seed % covers.count)] }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? LeafWidgetPalette.rgb(dark) : LeafWidgetPalette.rgb(light) })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The covers the app left in the App Group for the books on the widget, and the blurred one behind it.
struct LeafWidgetArt {
    var covers: [String: Image] = [:]
    var backdrop: Image?

    /// Reads the pictures the snapshot names. Small files, a handful at most.
    static func load(for snapshot: LeafWidgetSnapshot, includeUpNext: Bool) -> LeafWidgetArt {
        var art = LeafWidgetArt()
        var books = snapshot.current.map { [$0] } ?? []
        if includeUpNext { books += snapshot.upNext }
        for book in books {
            guard let name = book.coverFileName, let url = ReadingActivityAssets.coverURL(name),
                  let image = UIImage(contentsOfFile: url.path) else { continue }
            art.covers[book.id] = Image(uiImage: image)
        }
        if let name = snapshot.current?.coverFileName, let url = ReadingActivityAssets.blurredCoverURL(name),
           let image = UIImage(contentsOfFile: url.path) {
            art.backdrop = Image(uiImage: image)
        }
        return art
    }
}

// MARK: - The timer

/// A session or a steep as the widgets draw it: the same arguments the Live Activity hands the system.
struct LeafWidgetTimer {
    let phase: LeafWidgetPhase
    let start: Date
    let goal: Double?
    let pausedElapsed: Double?
    let teaName: String?

    init?(snapshot: LeafWidgetSnapshot, phase: LeafWidgetPhase) {
        guard phase.isTimer else { return nil }
        self.phase = phase
        if let session = snapshot.session {
            start = session.timerStart
            goal = session.goalSeconds
            pausedElapsed = session.isPaused ? session.pausedElapsed : nil
            teaName = session.teaName
        } else if let steep = snapshot.steep {
            start = steep.startedAt
            goal = Double(steep.steepSeconds)
            pausedElapsed = nil
            teaName = steep.teaName
        } else {
            return nil
        }
    }

    static let longest: TimeInterval = 12 * 3600

    var isSteep: Bool { phase == .steeping || phase == .teaReady }
    var hasGoal: Bool { (goal ?? 0) > 0 }
    /// Down to the goal (or the tea) while it lasts; up through the time read once it's met, or with no goal.
    var countsDown: Bool { hasGoal && (phase == .reading || phase == .paused || phase == .steeping) }
    /// Showing a bar the system fills by itself.
    var runsBar: Bool { countsDown && phase != .paused }

    var range: ClosedRange<Date> {
        if countsDown, let goal { return start...start.addingTimeInterval(min(goal, Self.longest)) }
        return start...start.addingTimeInterval(Self.longest)
    }

    var goalRange: ClosedRange<Date> {
        start...start.addingTimeInterval(min(max(goal ?? 1, 1), Self.longest))
    }

    var pauseDate: Date? {
        guard let pausedElapsed else { return nil }
        let span = range.upperBound.timeIntervalSince(range.lowerBound)
        return range.lowerBound.addingTimeInterval(min(max(pausedElapsed, 0), span))
    }

    var pausedFraction: Double {
        guard let goal, goal > 0, let pausedElapsed else { return 0 }
        return min(1, pausedElapsed / goal)
    }

    /// "Earl Grey · steeping", "Earl Grey is ready", "Paused", "Goal met", "Earl Grey · one cup", "Reading".
    var eyebrow: String {
        let tea = teaName ?? "Your tea"
        switch phase {
        case .steeping: return "\(tea) · steeping"
        case .teaReady: return "\(tea) is ready"
        case .paused: return "Paused"
        case .goalReached: return "Goal met"
        default: return teaName.map { "\($0) · one cup" } ?? "Reading"
        }
    }

    var caption: String {
        switch phase {
        case .steeping: return "until it’s ready"
        case .teaReady: return "pour, then read"
        case .paused: return "paused"
        case .goalReached: return "read · anything more is a gift"
        default: return countsDown ? (teaName == nil ? "to your goal" : "left in the cup") : "read"
        }
    }

    var glyph: String { LeafWidgetGlyph.name(for: phase) }

    var tint: Color {
        switch phase {
        case .steeping, .teaReady: return LeafWidgetPalette.tea
        case .goalReached: return LeafWidgetPalette.accent
        default: return LeafWidgetPalette.ribbon
        }
    }

    var spoken: String {
        switch phase {
        case .steeping: return "\(teaName ?? "Your tea") is steeping."
        case .teaReady: return "\(teaName ?? "Your tea") is ready."
        case .paused: return "Reading, paused."
        case .goalReached: return "Today’s goal is met. Still reading."
        default: return "Reading now."
        }
    }
}

enum LeafWidgetGlyph {
    static func name(for phase: LeafWidgetPhase) -> String {
        switch phase {
        case .today, .empty: return "leaf.fill"
        case .goalMet: return "checkmark"
        case .rest: return "cup.and.saucer.fill"
        // The timer glyphs are the Apple Watch's (its Timer widget and Live Activity card): outlines, so nothing bright
        // sits filled in on an Always On screen.
        case .reading: return "book"
        case .paused: return "pause.circle"
        case .goalReached: return "checkmark.circle"
        case .steeping: return "cup.and.heat.waves"
        case .teaReady: return "cup.and.saucer.fill"
        }
    }
}

/// The digits: the system advances them; a pause freezes them; a ready pot just says so.
struct LeafWidgetDigits: View {
    let timer: LeafWidgetTimer
    var size: CGFloat = 40

    var body: some View {
        Group {
            if timer.phase == .teaReady {
                Text("Ready")
            } else {
                Text(timerInterval: timer.range, pauseTime: timer.pauseDate, countsDown: timer.countsDown, showsHours: true)
                    .monospacedDigit()
            }
        }
        .font(.system(size: size, weight: .light, design: .serif))
        .foregroundStyle(timer.phase == .paused ? LeafWidgetPalette.inkSecondary : LeafWidgetPalette.ink)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .multilineTextAlignment(.leading)
        .widgetAccentable()
    }
}

/// How far into the goal or the steep: filled by the system while it runs, still otherwise.
struct LeafWidgetTimerBar: View {
    let timer: LeafWidgetTimer

    var body: some View {
        Group {
            if timer.runsBar {
                ProgressView(timerInterval: timer.goalRange, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
            } else if timer.phase == .goalReached || timer.phase == .teaReady {
                ProgressView(value: 1.0)
            } else {
                ProgressView(value: timer.pausedFraction)
            }
        }
        .progressViewStyle(.linear)
        .tint(timer.tint)
        .accessibilityHidden(true)
    }
}

// MARK: - Pieces

/// Today's ring: a static arc, filled to the share of the goal read, with what's left inside.
struct LeafWidgetRing<Centre: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 6
    var tint: Color = LeafWidgetPalette.accent
    @ViewBuilder var centre: Centre

    var body: some View {
        ZStack {
            Circle()
                .stroke(LeafWidgetPalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.002, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            centre
                .padding(lineWidth + 2)
        }
    }
}

/// The numeral inside today's ring: minutes left, a check once met, a cup on a rest day.
struct LeafWidgetRingCentre: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    var size: CGFloat = 30

    var body: some View {
        switch phase {
        case .goalMet, .rest, .empty:
            Image(systemName: LeafWidgetGlyph.name(for: phase))
                .font(.system(size: size * 0.6, weight: .medium))
                .foregroundStyle(phase == .goalMet ? LeafWidgetPalette.accent : LeafWidgetPalette.inkSecondary)
                .widgetAccentable()
        default:
            VStack(spacing: -2) {
                Text(snapshot.minutesLeftText)
                    .font(.system(size: size, weight: .light, design: .serif).monospacedDigit())
                    .foregroundStyle(LeafWidgetPalette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("min")
                    .font(.system(size: max(9, size * 0.34), weight: .medium))
                    .foregroundStyle(LeafWidgetPalette.inkSecondary)
            }
        }
    }
}

/// An uppercase eyebrow with its glyph.
struct LeafWidgetEyebrow: View {
    let text: String
    let glyph: String
    var tint: Color = LeafWidgetPalette.accent

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: glyph)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .widgetAccentable()
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(LeafWidgetPalette.inkTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// A small cover: the app's picture, or the generated cover's colour with the title's first letter.
struct LeafWidgetCover: View {
    let book: LeafWidgetSnapshot.Book
    let image: Image?
    var width: CGFloat = 36

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .widgetAccentedRenderingMode(.desaturated)
                    .scaledToFill()
            } else {
                ZStack {
                    LeafWidgetPalette.cover(for: book.paletteSeed)
                    Text(String(book.title.prefix(1)))
                        .font(.system(size: width * 0.45, weight: .regular, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
        }
        .frame(width: width, height: width * 1.5)
        .clipShape(RoundedRectangle(cornerRadius: max(2, width * 0.06), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(2, width * 0.06), style: .continuous)
                .strokeBorder(LeafWidgetPalette.ink.opacity(0.12), lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

/// The week as seven little tea rings, today marked with the ribbon.
struct LeafWidgetWeek: View {
    let snapshot: LeafWidgetSnapshot
    var dot: CGFloat = 11
    var showsLetters = false

    var body: some View {
        HStack(spacing: dot * 0.45) {
            ForEach(Array(snapshot.week.enumerated()), id: \.offset) { _, day in
                VStack(spacing: 2) {
                    ring(day)
                        .frame(width: dot, height: dot)
                    if showsLetters {
                        Text(Self.letter(day.date))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(isToday(day) ? LeafWidgetPalette.ribbon : LeafWidgetPalette.inkTertiary)
                    } else {
                        Circle()
                            .fill(isToday(day) ? LeafWidgetPalette.ribbon : Color.clear)
                            .frame(width: 3, height: 3)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func ring(_ day: LeafWidgetSnapshot.Day) -> some View {
        let goal = Double(max(snapshot.dailyMinutes, 1))
        let share = min(1, day.minutes / goal)
        return ZStack {
            if day.isReadingDay {
                Circle().stroke(LeafWidgetPalette.track, lineWidth: 2)
            } else {
                Circle().stroke(LeafWidgetPalette.hairline, style: StrokeStyle(lineWidth: 1, dash: [1.5, 1.5]))
            }
            if share >= 1 {
                Circle().fill(LeafWidgetPalette.accent).widgetAccentable()
            } else if share > 0 {
                Circle()
                    .trim(from: 0, to: share)
                    .stroke(LeafWidgetPalette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
            }
        }
    }

    private func isToday(_ day: LeafWidgetSnapshot.Day) -> Bool {
        Calendar.current.isDate(day.date, inSameDayAs: snapshot.day)
    }

    private var spoken: String {
        let met = snapshot.week.filter { $0.minutes >= Double(max(snapshot.dailyMinutes, 1)) }.count
        let streak = snapshot.streak
        let days = streak == 1 ? "1 day in a row" : "\(streak) days in a row"
        return "This week: the goal met on \(met) \(met == 1 ? "day" : "days"). \(streak > 0 ? days + "." : "")"
    }

    private static func letter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: date)
    }
}

/// A pill that runs an intent: Read, Steep, Pause, Resume, +1 page.
struct LeafWidgetButton<Intent: AppIntent>: View {
    let title: String
    let systemImage: String
    let intent: Intent
    var prominent = true
    var iconOnly = false

    var body: some View {
        Button(intent: intent) {
            Group {
                if iconOnly {
                    Image(systemName: systemImage)
                        .frame(width: 30, height: 30)
                } else {
                    Label(title, systemImage: systemImage)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? LeafWidgetPalette.onAccent : LeafWidgetPalette.ink)
            .background(prominent ? LeafWidgetPalette.accent : LeafWidgetPalette.ink.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .widgetAccentable()
        .accessibilityLabel(title)
    }
}

/// The actions for the moment: Read (and Steep) by day, Pause or Resume and a page while reading.
struct LeafWidgetActions: View {
    let phase: LeafWidgetPhase
    var showsSteep = true
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            switch phase {
            case .reading, .goalReached:
                LeafWidgetButton(title: "Pause", systemImage: "pause.fill", intent: PauseReadingIntent(), prominent: false, iconOnly: compact)
                LeafWidgetButton(title: "A page", systemImage: "plus", intent: LogPagesIntent(pages: 1), prominent: true, iconOnly: compact)
            case .paused:
                LeafWidgetButton(title: "Resume", systemImage: "play.fill", intent: ResumeReadingIntent(), prominent: true, iconOnly: compact)
            case .steeping, .teaReady:
                LeafWidgetButton(title: phase == .teaReady ? "Start the cup" : "Open", systemImage: "book", intent: StartSteepIntent(), prominent: phase == .teaReady)
            case .empty:
                EmptyView()
            case .today, .goalMet, .rest:
                if showsSteep {
                    LeafWidgetButton(title: "Steep", systemImage: "cup.and.heat.waves", intent: StartSteepIntent(), prominent: false, iconOnly: true)
                }
                LeafWidgetButton(title: phase == .today ? "Read" : "Read on", systemImage: "book", intent: StartReadingIntent())
            }
        }
    }
}

/// Paper, with the current book's blurred cover glowing through from the top corner. In StandBy and the tinted
/// and clear Home Screens the system removes it.
struct LeafWidgetBackground: View {
    let backdrop: Image?

    var body: some View {
        ZStack {
            LeafWidgetPalette.paper
            if let backdrop {
                backdrop
                    .resizable()
                    .scaledToFill()
                    .opacity(0.55)
                    .mask {
                        RadialGradient(colors: [.black, .black.opacity(0)], center: .topTrailing, startRadius: 0, endRadius: 260)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Home Screen and StandBy

/// Small: today's ring and the page to start from, or the timer while one runs. StandBy draws this one large.
struct LeafWidgetSmall: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    let art: LeafWidgetArt

    var body: some View {
        if let timer = LeafWidgetTimer(snapshot: snapshot, phase: phase) {
            timerBody(timer)
        } else {
            todayBody
        }
    }

    private var todayBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                LeafWidgetRing(progress: snapshot.goalProgress, lineWidth: 7) {
                    LeafWidgetRingCentre(snapshot: snapshot, phase: phase, size: 28)
                }
                .frame(width: 74, height: 74)
                Spacer(minLength: 6)
                if let book = snapshot.current {
                    LeafWidgetCover(book: book, image: art.covers[book.id], width: 30)
                }
            }
            Spacer(minLength: 6)
            Text(headline)
                .font(.system(.subheadline, design: .serif).weight(.medium))
                .foregroundStyle(LeafWidgetPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subline)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(LeafWidgetPalette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase == .empty ? "Leaf. Choose a book to begin." : snapshot.spoken)
    }

    private var headline: String {
        guard phase != .empty, let book = snapshot.current else { return "A book to begin" }
        return book.title
    }

    private var subline: String {
        switch phase {
        case .empty: return "Open Leaf to choose one"
        case .goalMet: return snapshot.current.map { "Goal met · p. \($0.currentPage)" } ?? "Goal met"
        case .rest: return snapshot.current.map { "Rest day · p. \($0.currentPage)" } ?? "Rest day"
        default: return snapshot.current.map { "p. \($0.currentPage) · \(snapshot.minutesLeftText) min to go" } ?? ""
        }
    }

    private func timerBody(_ timer: LeafWidgetTimer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LeafWidgetEyebrow(text: timer.eyebrow, glyph: timer.glyph, tint: timer.tint)
            Spacer(minLength: 4)
            LeafWidgetDigits(timer: timer, size: 38)
            Text(timer.caption)
                .font(.caption2)
                .foregroundStyle(LeafWidgetPalette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            LeafWidgetTimerBar(timer: timer)
                .padding(.top, 6)
            Spacer(minLength: 4)
            if let book = snapshot.current {
                Text(timer.isSteep ? "Then \(book.title)" : "\(book.title) · p. \(book.currentPage)")
                    .font(.system(.caption, design: .serif))
                    .foregroundStyle(LeafWidgetPalette.inkSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timer.spoken + (snapshot.current.map { " \($0.title)." } ?? ""))
    }
}

/// The current book with its cover, author and place.
struct LeafWidgetBookRow: View {
    let book: LeafWidgetSnapshot.Book
    let image: Image?
    var coverWidth: CGFloat = 36
    var detail: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LeafWidgetCover(book: book, image: image, width: coverWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(LeafWidgetPalette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(book.author)
                    .font(.caption)
                    .foregroundStyle(LeafWidgetPalette.inkSecondary)
                    .lineLimit(1)
                ProgressView(value: book.progress)
                    .progressViewStyle(.linear)
                    .tint(LeafWidgetPalette.accent)
                    .padding(.top, 3)
                Text(detail ?? "p. \(book.currentPage) of \(book.pages)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(LeafWidgetPalette.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title) by \(book.author), page \(book.currentPage) of \(book.pages).")
    }
}

/// Medium: the ring and the week on the left, the book and what to do on the right.
struct LeafWidgetMedium: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    let art: LeafWidgetArt

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            left
                .frame(width: 104)
            VStack(alignment: .leading, spacing: 0) {
                if let book = snapshot.current, phase != .empty {
                    LeafWidgetBookRow(book: book, image: art.covers[book.id], coverWidth: 38, detail: detail(book))
                } else {
                    Text("A book to begin")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(LeafWidgetPalette.ink)
                    Text("Open Leaf and choose one from the library.")
                        .font(.caption)
                        .foregroundStyle(LeafWidgetPalette.inkSecondary)
                }
                Spacer(minLength: 6)
                HStack {
                    Spacer(minLength: 0)
                    LeafWidgetActions(phase: phase)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var left: some View {
        if let timer = LeafWidgetTimer(snapshot: snapshot, phase: phase) {
            VStack(alignment: .leading, spacing: 2) {
                LeafWidgetEyebrow(text: timer.isSteep ? "Tea" : (phase == .paused ? "Paused" : "Reading"), glyph: timer.glyph, tint: timer.tint)
                Spacer(minLength: 2)
                LeafWidgetDigits(timer: timer, size: 32)
                Text(timer.caption)
                    .font(.caption2)
                    .foregroundStyle(LeafWidgetPalette.inkSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                LeafWidgetTimerBar(timer: timer)
                    .padding(.top, 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(timer.spoken)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                LeafWidgetRing(progress: snapshot.goalProgress, lineWidth: 7) {
                    LeafWidgetRingCentre(snapshot: snapshot, phase: phase, size: 28)
                }
                .frame(width: 76, height: 76)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.spoken)
                LeafWidgetWeek(snapshot: snapshot, dot: 10)
            }
        }
    }

    private func detail(_ book: LeafWidgetSnapshot.Book) -> String {
        if phase == .today, let from = snapshot.fromPage, let to = snapshot.toPage, to > from {
            return "p. \(book.currentPage) · to p. \(to) today"
        }
        if phase == .goalMet { return "Goal met · p. \(book.currentPage) of \(book.pages)" }
        return "p. \(book.currentPage) of \(book.pages)"
    }
}

/// Large: today, the current book with its forecast, the next three books with theirs, and the week.
struct LeafWidgetLarge: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    let art: LeafWidgetArt

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Rectangle().fill(LeafWidgetPalette.hairline).frame(height: 0.5)
            if let book = snapshot.current, phase != .empty {
                LeafWidgetBookRow(book: book, image: art.covers[book.id], coverWidth: 46, detail: detail(book))
            }
            if !snapshot.upNext.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("UP NEXT")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(LeafWidgetPalette.inkTertiary)
                    ForEach(snapshot.upNext.prefix(3)) { book in
                        upNextRow(book)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                if !phase.isTimer {
                    LeafWidgetWeek(snapshot: snapshot, dot: 12, showsLetters: true)
                }
                Spacer(minLength: 6)
                LeafWidgetActions(phase: phase)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var header: some View {
        if let timer = LeafWidgetTimer(snapshot: snapshot, phase: phase) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    LeafWidgetEyebrow(text: timer.eyebrow, glyph: timer.glyph, tint: timer.tint)
                    LeafWidgetDigits(timer: timer, size: 40)
                    Text(timer.caption)
                        .font(.caption)
                        .foregroundStyle(LeafWidgetPalette.inkSecondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(timer.spoken)
                Spacer(minLength: 0)
            }
            LeafWidgetTimerBar(timer: timer)
        } else {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    LeafWidgetEyebrow(text: eyebrow, glyph: LeafWidgetGlyph.name(for: phase))
                    Text(headline)
                        .font(.system(.title2, design: .serif))
                        .foregroundStyle(LeafWidgetPalette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(subline)
                        .font(.caption)
                        .foregroundStyle(LeafWidgetPalette.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                LeafWidgetRing(progress: snapshot.goalProgress, lineWidth: 6) {
                    LeafWidgetRingCentre(snapshot: snapshot, phase: phase, size: 22)
                }
                .frame(width: 62, height: 62)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.spoken)
        }
    }

    private var eyebrow: String {
        "Today · " + snapshot.day.formatted(.dateTime.weekday(.wide))
    }

    private var headline: String {
        switch phase {
        case .empty: return "A book to begin"
        case .goalMet: return "Goal met"
        case .rest: return "A rest day"
        default:
            let left = snapshot.minutesLeftText
            return "\(left) min to go"
        }
    }

    private var subline: String {
        switch phase {
        case .empty: return "Open Leaf and choose one from the library."
        case .goalMet: return "Anything more is a gift."
        case .rest: return "Read if you like. Nothing is counting."
        default:
            let read = Int(snapshot.minutesReadToday.rounded())
            let streak = snapshot.streak > 1 ? " · \(snapshot.streak) days in a row" : ""
            return "\(read) of \(snapshot.dailyMinutes) min read\(streak)"
        }
    }

    private func detail(_ book: LeafWidgetSnapshot.Book) -> String {
        var parts = ["p. \(book.currentPage) of \(book.pages)"]
        if let finish = book.finish { parts.append("done around \(Self.day(finish))") }
        return parts.joined(separator: " · ")
    }

    private func upNextRow(_ book: LeafWidgetSnapshot.Book) -> some View {
        HStack(spacing: 10) {
            LeafWidgetCover(book: book, image: art.covers[book.id], width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(book.title)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(LeafWidgetPalette.ink)
                    .lineLimit(1)
                Text(book.author)
                    .font(.caption2)
                    .foregroundStyle(LeafWidgetPalette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(book.finish.map { Self.day($0) } ?? (book.isReading ? "" : "To read"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(LeafWidgetPalette.inkSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title) by \(book.author)." + (book.finish.map { " Likely done around \(Self.day($0))." } ?? ""))
    }

    /// "Sun 2 Nov" (or the locale's order).
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}

// MARK: - Lock Screen (they match the Apple Watch complications)

/// Circular: today's ring with the minutes left inside, or the timer's ring and digits.
struct LeafWidgetCircular: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase

    var body: some View {
        if let timer = LeafWidgetTimer(snapshot: snapshot, phase: phase) {
            ZStack {
                if timer.runsBar {
                    ProgressView(timerInterval: timer.goalRange, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .progressViewStyle(.circular)
                        .widgetAccentable()
                } else {
                    AccessoryWidgetBackground()
                }
                VStack(spacing: 0) {
                    Image(systemName: timer.glyph)
                        .font(.system(size: 12, weight: .semibold))
                    if timer.phase == .teaReady {
                        Text("Ready").font(.system(size: 11, weight: .medium, design: .rounded))
                    } else {
                        Text(timerInterval: timer.range, pauseTime: timer.pauseDate, countsDown: timer.countsDown, showsHours: false)
                            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                    }
                }
                .padding(6)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(timer.spoken)
        } else {
            Gauge(value: snapshot.goalProgress) {
                Image(systemName: "leaf.fill")
            } currentValueLabel: {
                switch phase {
                case .goalMet, .rest, .empty: Image(systemName: LeafWidgetGlyph.name(for: phase))
                default: Text(snapshot.minutesLeftText)
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.spoken)
        }
    }
}

/// Rectangular: "13 min · p. 143" over the book, with today's ring as a bar; the timer while one runs.
struct LeafWidgetRectangular: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase

    var body: some View {
        if let timer = LeafWidgetTimer(snapshot: snapshot, phase: phase) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: timer.glyph)
                    Text(timer.eyebrow).lineLimit(1)
                }
                .font(.system(size: 13, weight: .semibold))
                .widgetAccentable()
                if timer.phase == .teaReady {
                    Text("Pour, then read")
                        .font(.system(.title3, design: .serif))
                } else {
                    Text(timerInterval: timer.range, pauseTime: timer.pauseDate, countsDown: timer.countsDown, showsHours: true)
                        .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                        .lineLimit(1)
                }
                if timer.runsBar {
                    ProgressView(timerInterval: timer.goalRange, countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .progressViewStyle(.linear)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(timer.spoken)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "leaf.fill")
                    Text(phase == .empty ? "Leaf" : snapshot.line)
                }
                .font(.headline)
                .widgetAccentable()
                Text(phase == .empty ? "Choose a book to begin" : (snapshot.current?.title ?? ""))
                    .font(.system(.body, design: .serif))
                    .lineLimit(1)
                Gauge(value: snapshot.goalProgress) {
                    EmptyView()
                }
                .gaugeStyle(.accessoryLinearCapacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.spoken)
        }
    }
}

/// Inline: the line beside the clock, "13 min · The Hobbit", or the timer.
struct LeafWidgetInline: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase

    var body: some View {
        if let timer = LeafWidgetTimer(snapshot: snapshot, phase: phase) {
            if timer.phase == .teaReady {
                Label(timer.eyebrow, systemImage: timer.glyph)
            } else {
                Text("\(Image(systemName: timer.glyph)) \(Text(timerInterval: timer.range, pauseTime: timer.pauseDate, countsDown: timer.countsDown, showsHours: true))")
            }
        } else {
            Label(inline, systemImage: "leaf.fill")
                .accessibilityLabel(snapshot.spoken)
        }
    }

    private var inline: String {
        guard phase != .empty, let title = snapshot.current?.title else { return "Leaf" }
        switch phase {
        case .goalMet: return "Goal met · \(title)"
        case .rest: return "Rest day · \(title)"
        default: return "\(snapshot.minutesLeftText) min · \(title)"
        }
    }
}
