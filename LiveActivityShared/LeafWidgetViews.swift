import AppIntents
import SwiftUI
import UIKit
import WidgetKit

// The Home Screen, StandBy and Lock Screen widgets' look, in Canopy (docs/design/DESIGN_SYSTEM.md, REDESIGN.md §4.12).
// Like the Live Activity's views they live here, beside the snapshot, so the app can draw them in a debug gallery for
// screenshots (CI has no Home Screen); the extension wraps them in its `StaticConfiguration`.
//
// Canopy on a widget: the cream page, green as the ink you act with, Dusk for reading and time, Clay for tea, black
// for the one hero action. Numerals are rounded, titles literary, and nothing sits blurred. Nothing animates per second
// except what the system draws for `Text(timerInterval:)` and `ProgressView(timerInterval:)`.

/// Canopy's Oat palette (the owner's pick) and its accents, light and dark. The extension can't see the app's
/// `Canopy` tokens, so the values are repeated here; keep them in step with `CanopyTokens.swift`.
enum LeafWidgetPalette {
    static let canvas = LeafWidgetPalette.dynamic(0xF5EFE4, 0x1B1916)
    static let surface = LeafWidgetPalette.dynamic(0xFCF8F1, 0x26231F)
    static let text = LeafWidgetPalette.dynamic(0x24201A, 0xF2EADA)
    static let textSecondary = LeafWidgetPalette.dynamic(0x665F54, 0xB5AB99)
    /// Non-text only: tracks, units beside big numerals.
    static let textTertiary = LeafWidgetPalette.dynamic(0x8C8478, 0x847B6E)
    static let separator = LeafWidgetPalette.dynamic(0xE5DCCB, 0x3A352E)
    /// Brand, progress, done.
    static let forest = LeafWidgetPalette.dynamic(0x48705A, 0xA9CDB2)
    /// Reading and time: sessions, reading times, timers.
    static let dusk = LeafWidgetPalette.dynamic(0x46559A, 0xA9B5F2)
    /// Tea: steeping.
    static let clay = LeafWidgetPalette.dynamic(0xA44A28, 0xEB9C74)
    static let duskSoft = LeafWidgetPalette.dynamic(0x46559A, 0xA9B5F2, lightAlpha: 0.12, darkAlpha: 0.22)
    static let claySoft = LeafWidgetPalette.dynamic(0xA44A28, 0xEB9C74, lightAlpha: 0.12, darkAlpha: 0.22)
    /// The one hero action: black in both modes, white label.
    static let hero = Color.black

    /// The ten generated-cover backgrounds, in the app's order.
    static let covers: [Color] = ([0x6B2B26, 0x26375C, 0x2F4A3A, 0x3D4A52, 0x573247, 0x2D5D5B, 0x9A4A2C, 0xC48A2C, 0x9CAE94, 0xE9E0CD] as [UInt32])
        .map { Color(uiColor: LeafWidgetPalette.rgb($0)) }

    static func cover(for seed: Int) -> Color { covers[abs(seed % covers.count)] }

    private static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor {
            $0.userInterfaceStyle == .dark
                ? LeafWidgetPalette.rgb(dark).withAlphaComponent(darkAlpha)
                : LeafWidgetPalette.rgb(light).withAlphaComponent(lightAlpha)
        })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The covers the app left in the App Group for the books on the widget.
struct LeafWidgetArt {
    var covers: [String: Image] = [:]

    /// Reads the pictures the snapshot names. Small files, a handful at most.
    static func load(for snapshot: LeafWidgetSnapshot, includeUpNext: Bool) -> LeafWidgetArt {
        var art = LeafWidgetArt()
        var ids: [(String, String?)] = snapshot.current.map { [($0.id, $0.coverFileName)] } ?? []
        if includeUpNext { ids += snapshot.upNext.map { ($0.id, $0.coverFileName) } }
        for (id, name) in ids where art.covers[id] == nil {
            guard let name, let url = ReadingActivityAssets.coverURL(name), let image = UIImage(contentsOfFile: url.path) else { continue }
            art.covers[id] = Image(uiImage: image)
        }
        return art
    }

    /// The picture for a book by id, from the current book or the ones up next.
    func cover(_ id: String) -> Image? { covers[id] }
}

// MARK: - Vocabulary

/// Canopy's one symbol per idea (DESIGN_SYSTEM.md §7), shared with the watch.
enum LeafWidgetGlyph {
    static let today = "sun.max"
    static let readingTime = "clock"
    static let reading = "book.pages"
    static let tea = "cup.and.heat.waves"
    static let steepTimer = "timer"

    static func name(for phase: LeafWidgetPhase) -> String {
        switch phase {
        case .today, .empty: return today
        case .goalMet, .goalReached: return "checkmark"
        case .rest: return "leaf"
        case .reading: return reading
        case .paused: return "pause.fill"
        case .steeping: return steepTimer
        case .teaReady: return tea
        }
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

    /// Clay for tea, Forest once the goal is met, Dusk for reading.
    var accent: Color {
        switch phase {
        case .steeping, .teaReady: return LeafWidgetPalette.clay
        case .goalReached: return LeafWidgetPalette.forest
        default: return LeafWidgetPalette.dusk
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

/// The digits: rounded and always sharp. The system advances them; a pause freezes them; a ready pot says so.
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
        .font(.system(size: size, weight: .medium, design: .rounded))
        .foregroundStyle(timer.phase == .paused ? LeafWidgetPalette.textSecondary : timer.accent)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
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
        .tint(timer.accent)
        .accessibilityHidden(true)
    }
}

// MARK: - Pieces

/// Today's goal ring in Forest on a separator track, with what's left inside.
struct LeafWidgetRing<Centre: View>: View {
    let progress: Double
    var lineWidth: CGFloat = 7
    @ViewBuilder var centre: Centre

    var body: some View {
        ZStack {
            Circle()
                .inset(by: lineWidth / 2)
                .stroke(LeafWidgetPalette.separator, lineWidth: lineWidth)
            Circle()
                .inset(by: lineWidth / 2)
                .trim(from: 0, to: max(0.002, min(1, progress)))
                .stroke(LeafWidgetPalette.forest, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            centre
                .padding(lineWidth + 3)
        }
    }
}

/// The numeral inside today's ring: minutes left, a check once met, a leaf on a rest day.
struct LeafWidgetRingCentre: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    var size: CGFloat = 26

    var body: some View {
        switch phase {
        case .goalMet, .rest, .empty:
            Image(systemName: LeafWidgetGlyph.name(for: phase))
                .font(.system(size: size * 0.7, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(phase == .goalMet ? LeafWidgetPalette.forest : LeafWidgetPalette.textSecondary)
                .widgetAccentable()
        default:
            VStack(spacing: -1) {
                Text(snapshot.minutesLeftText)
                    .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(LeafWidgetPalette.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("min")
                    .font(.system(size: max(9, size * 0.4), weight: .medium, design: .rounded))
                    .foregroundStyle(LeafWidgetPalette.textSecondary)
            }
        }
    }
}

/// A small label with its symbol: the time of the next read in Dusk, a timer's state in its accent.
struct LeafWidgetLabel: View {
    let text: String
    let glyph: String
    var accent: Color = LeafWidgetPalette.forest

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: glyph)
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(accent)
        .widgetAccentable()
    }
}

/// A small cover: the app's picture, or the generated cover's colour with the title's first letter.
struct LeafWidgetCover: View {
    let book: LeafWidgetSnapshot.Book
    let image: Image?
    var width: CGFloat = 36

    var body: some View {
        let radius = min(6, max(2, width * 0.1))
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
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LeafWidgetPalette.text.opacity(0.1), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// The week as seven little Forest rings, today marked with a Dusk dot.
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
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(isToday(day) ? LeafWidgetPalette.dusk : LeafWidgetPalette.textSecondary)
                    } else {
                        Circle()
                            .fill(isToday(day) ? LeafWidgetPalette.dusk : Color.clear)
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
                Circle().inset(by: 1).stroke(LeafWidgetPalette.separator, lineWidth: 2)
            } else {
                Circle().inset(by: 0.5).stroke(LeafWidgetPalette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [1.5, 1.5]))
            }
            if share >= 1 {
                Circle().fill(LeafWidgetPalette.forest).widgetAccentable()
            } else if share > 0 {
                Circle()
                    .inset(by: 1)
                    .trim(from: 0, to: share)
                    .stroke(LeafWidgetPalette.forest, style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
        let days = streak == 1 ? " 1 day in a row." : (streak > 1 ? " \(streak) days in a row." : "")
        return "This week: the goal met on \(met) \(met == 1 ? "day" : "days").\(days)"
    }

    private static func letter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: date)
    }
}

/// A capsule that runs an intent. `hero` is Canopy's one black action; the rest are quiet surface pills with the
/// icon in its job's accent.
struct LeafWidgetButton<Intent: AppIntent>: View {
    let title: String
    let systemImage: String
    let intent: Intent
    var hero = false
    var accent: Color = LeafWidgetPalette.forest
    var iconOnly = false

    var body: some View {
        Button(intent: intent) {
            Group {
                if iconOnly {
                    Image(systemName: systemImage)
                        .foregroundStyle(hero ? Color.white : accent)
                        .frame(width: 34, height: 34)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: systemImage)
                            .foregroundStyle(hero ? Color.white : accent)
                        Text(title)
                            .foregroundStyle(hero ? Color.white : LeafWidgetPalette.text)
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .background {
                if hero {
                    Capsule().fill(LeafWidgetPalette.hero)
                } else {
                    Capsule().fill(LeafWidgetPalette.surface)
                        .overlay(Capsule().strokeBorder(LeafWidgetPalette.separator, lineWidth: 1))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .widgetAccentable()
        .accessibilityLabel(title)
    }
}

/// The actions for the moment: Steep and Begin reading by day, Pause or Resume and a page while reading.
struct LeafWidgetActions: View {
    let phase: LeafWidgetPhase
    var showsSteep = true

    var body: some View {
        HStack(spacing: 6) {
            switch phase {
            case .reading, .goalReached:
                LeafWidgetButton(title: "Pause", systemImage: "pause.fill", intent: PauseReadingIntent(), accent: LeafWidgetPalette.dusk)
                LeafWidgetButton(title: "A page", systemImage: "plus", intent: LogPagesIntent(pages: 1), accent: LeafWidgetPalette.dusk)
            case .paused:
                LeafWidgetButton(title: "Resume", systemImage: "play.fill", intent: ResumeReadingIntent(), hero: true)
            case .steeping:
                LeafWidgetButton(title: "Open", systemImage: LeafWidgetGlyph.tea, intent: StartSteepIntent(), accent: LeafWidgetPalette.clay)
            case .teaReady:
                LeafWidgetButton(title: "Start the cup", systemImage: "play.fill", intent: StartSteepIntent(), hero: true)
            case .empty:
                EmptyView()
            case .today, .goalMet, .rest:
                if showsSteep {
                    LeafWidgetButton(title: "Steep and read", systemImage: LeafWidgetGlyph.tea, intent: StartSteepIntent(), accent: LeafWidgetPalette.clay, iconOnly: true)
                }
                LeafWidgetButton(title: phase == .today ? "Begin reading" : "Read a little", systemImage: "play.fill", intent: StartReadingIntent(), hero: phase == .today)
            }
        }
    }
}

/// The cream page with Canopy's soft daylight falling from the top. In StandBy and the tinted and clear Home
/// Screens the system removes it.
struct LeafWidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [LeafWidgetPalette.surface, LeafWidgetPalette.canvas], startPoint: .top, endPoint: .bottom)
            .accessibilityHidden(true)
    }
}

/// "8:30 PM", in the reader's own clock.
enum LeafWidgetTime {
    static func text(_ slot: LeafWidgetSnapshot.Slot, in snapshot: LeafWidgetSnapshot) -> String {
        snapshot.date(of: slot).formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Home Screen and StandBy

/// Small: the goal ring and the next reading time, or the timer while one runs. StandBy draws this one large.
struct LeafWidgetSmall: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    let art: LeafWidgetArt
    var now: Date = Date()

    var body: some View {
        if let timer = LeafWidgetTimer(snapshot: snapshot, phase: phase) {
            timerBody(timer)
        } else {
            todayBody
        }
    }

    private var next: LeafWidgetSnapshot.Slot? { snapshot.nextSlot(at: now) }

    private var todayBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                LeafWidgetRing(progress: snapshot.goalProgress) {
                    LeafWidgetRingCentre(snapshot: snapshot, phase: phase)
                }
                .frame(width: 70, height: 70)
                Spacer(minLength: 6)
                if let book = snapshot.current, phase != .empty {
                    LeafWidgetCover(book: book, image: art.cover(book.id), width: 28)
                }
            }
            Spacer(minLength: 6)
            if phase == .empty {
                Text("A book to begin")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(LeafWidgetPalette.text)
                Text("Open Leaf to choose one")
                    .font(.system(size: 11))
                    .foregroundStyle(LeafWidgetPalette.textSecondary)
            } else if let next, phase == .today {
                LeafWidgetLabel(text: LeafWidgetTime.text(next, in: snapshot), glyph: LeafWidgetGlyph.readingTime, accent: LeafWidgetPalette.dusk)
                Text(next.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(LeafWidgetPalette.text)
                    .lineLimit(1)
                Text(next.pagesText)
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(LeafWidgetPalette.textSecondary)
                    .lineLimit(1)
            } else if let book = snapshot.current {
                LeafWidgetLabel(text: statusText, glyph: LeafWidgetGlyph.name(for: phase), accent: LeafWidgetPalette.forest)
                Text(book.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(LeafWidgetPalette.text)
                    .lineLimit(1)
                Text("p. \(book.currentPage) of \(book.pages)")
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(LeafWidgetPalette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var statusText: String {
        switch phase {
        case .goalMet: return "Goal met"
        case .rest: return "A rest day"
        default: return "\(snapshot.minutesLeftText) min to go"
        }
    }

    private var spoken: String {
        guard phase != .empty else { return "Leaf. Choose a book to begin." }
        guard let next, phase == .today else { return snapshot.spoken }
        return "\(snapshot.spoken) Next: \(LeafWidgetTime.text(next, in: snapshot)), \(next.title), \(next.pagesText)."
    }

    private func timerBody(_ timer: LeafWidgetTimer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LeafWidgetLabel(text: timer.eyebrow, glyph: timer.glyph, accent: timer.accent)
            Spacer(minLength: 4)
            LeafWidgetDigits(timer: timer, size: 36)
            Text(timer.caption)
                .font(.system(size: 11))
                .foregroundStyle(LeafWidgetPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            LeafWidgetTimerBar(timer: timer)
                .padding(.top, 6)
            Spacer(minLength: 4)
            if let book = snapshot.current {
                Text(timer.isSteep ? "Then \(book.title)" : "\(book.title) · p. \(book.currentPage)")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(LeafWidgetPalette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timer.spoken + (snapshot.current.map { " \($0.title)." } ?? ""))
    }
}

/// A book with its cover, title, a second line and progress.
struct LeafWidgetBookRow: View {
    let book: LeafWidgetSnapshot.Book
    let image: Image?
    var coverWidth: CGFloat = 36
    var detail: String?
    var showsProgress = true

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            LeafWidgetCover(book: book, image: image, width: coverWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(LeafWidgetPalette.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text(detail ?? book.author)
                    .font(.system(size: 12, design: .rounded).monospacedDigit())
                    .foregroundStyle(LeafWidgetPalette.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if showsProgress {
                    ProgressView(value: book.progress)
                        .progressViewStyle(.linear)
                        .tint(LeafWidgetPalette.forest)
                        .padding(.top, 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(book.title) by \(book.author), page \(book.currentPage) of \(book.pages).")
    }
}

/// Medium: the ring on the left; the next reading time (cover, time, pages) and Begin reading on the right.
struct LeafWidgetMedium: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    let art: LeafWidgetArt
    var now: Date = Date()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            left
                .frame(width: 96)
            VStack(alignment: .leading, spacing: 6) {
                if phase == .empty {
                    Text("A book to begin")
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(LeafWidgetPalette.text)
                    Text("Open Leaf and choose one from the library.")
                        .font(.system(size: 12))
                        .foregroundStyle(LeafWidgetPalette.textSecondary)
                } else if let next = snapshot.nextSlot(at: now), phase == .today, let book = slotBook(next) {
                    LeafWidgetLabel(text: "Next · " + LeafWidgetTime.text(next, in: snapshot), glyph: LeafWidgetGlyph.readingTime, accent: LeafWidgetPalette.dusk)
                    LeafWidgetBookRow(book: book, image: art.cover(book.id), coverWidth: 34, detail: "\(Int(next.minutes)) min · \(next.pagesText)", showsProgress: false)
                } else if let book = snapshot.current {
                    LeafWidgetBookRow(book: book, image: art.cover(book.id), coverWidth: 34, detail: "p. \(book.currentPage) of \(book.pages)")
                }
                Spacer(minLength: 4)
                HStack {
                    Spacer(minLength: 0)
                    LeafWidgetActions(phase: phase)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The slot's book, from the current book or the ones up next; else a stand-in with the slot's title.
    private func slotBook(_ slot: LeafWidgetSnapshot.Slot) -> LeafWidgetSnapshot.Book? {
        if let current = snapshot.current, current.id == slot.bookID { return current }
        if let match = snapshot.upNext.first(where: { $0.id == slot.bookID }) { return match }
        return LeafWidgetSnapshot.Book(id: slot.bookID, title: slot.title, author: "", currentPage: slot.fromPage, pages: 0, paletteSeed: slot.title.count, coverFileName: nil, finish: nil, isReading: true)
    }

    @ViewBuilder private var left: some View {
        if let timer = LeafWidgetTimer(snapshot: snapshot, phase: phase) {
            VStack(alignment: .leading, spacing: 2) {
                LeafWidgetLabel(text: timer.isSteep ? "Tea" : (phase == .paused ? "Paused" : "Reading"), glyph: timer.glyph, accent: timer.accent)
                Spacer(minLength: 2)
                LeafWidgetDigits(timer: timer, size: 30)
                Text(timer.caption)
                    .font(.system(size: 11))
                    .foregroundStyle(LeafWidgetPalette.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                LeafWidgetTimerBar(timer: timer)
                    .padding(.top, 4)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(timer.spoken)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                LeafWidgetRing(progress: snapshot.goalProgress) {
                    LeafWidgetRingCentre(snapshot: snapshot, phase: phase)
                }
                .frame(width: 74, height: 74)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot.spoken)
                LeafWidgetWeek(snapshot: snapshot, dot: 9)
            }
        }
    }
}

/// Large: today at the top, today's reading times (or the books up next), the week, and the actions.
struct LeafWidgetLarge: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    let art: LeafWidgetArt
    var now: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Rectangle().fill(LeafWidgetPalette.separator).frame(height: 1)
            if let slots = snapshot.slots, !slots.isEmpty, phase != .empty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Today’s reading times")
                    ForEach(slots.prefix(3)) { slot in
                        slotRow(slot, isNext: slot.id == snapshot.nextSlot(at: now)?.id)
                    }
                }
            } else if let book = snapshot.current, phase != .empty {
                LeafWidgetBookRow(book: book, image: art.cover(book.id), coverWidth: 40, detail: "p. \(book.currentPage) of \(book.pages)")
            }
            if (snapshot.slots ?? []).count < 3, !snapshot.upNext.isEmpty, phase != .empty {
                VStack(alignment: .leading, spacing: 7) {
                    sectionLabel("Up next")
                    ForEach(snapshot.upNext.prefix(3 - min(2, (snapshot.slots ?? []).count))) { book in
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(LeafWidgetPalette.forest)
    }

    @ViewBuilder private var header: some View {
        if let timer = LeafWidgetTimer(snapshot: snapshot, phase: phase) {
            VStack(alignment: .leading, spacing: 3) {
                LeafWidgetLabel(text: timer.eyebrow, glyph: timer.glyph, accent: timer.accent)
                LeafWidgetDigits(timer: timer, size: 40)
                Text(timer.caption)
                    .font(.system(size: 12))
                    .foregroundStyle(LeafWidgetPalette.textSecondary)
                    .lineLimit(1)
                LeafWidgetTimerBar(timer: timer)
                    .padding(.top, 2)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(timer.spoken)
        } else {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(LeafWidgetPalette.textSecondary)
                    Text(headline)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(LeafWidgetPalette.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(subline)
                        .font(.system(size: 12))
                        .foregroundStyle(LeafWidgetPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                LeafWidgetRing(progress: snapshot.goalProgress, lineWidth: 6) {
                    LeafWidgetRingCentre(snapshot: snapshot, phase: phase, size: 20)
                }
                .frame(width: 60, height: 60)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.spoken)
        }
    }

    private var eyebrow: String {
        snapshot.day.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()
    }

    private var headline: String {
        switch phase {
        case .empty: return "A book to begin"
        case .goalMet: return "Goal met"
        case .rest: return "A rest day"
        default: return "\(snapshot.minutesLeftText) min to go"
        }
    }

    private var subline: String {
        switch phase {
        case .empty: return "Open Leaf and choose one from the library."
        case .goalMet: return "Anything more is a gift."
        case .rest: return "Read a little if you like."
        default:
            let read = Int(snapshot.minutesReadToday.rounded())
            let streak = snapshot.streak > 1 ? " · \(snapshot.streak)-day streak" : ""
            return "\(read) of \(snapshot.dailyMinutes) min read\(streak)"
        }
    }

    private func slotRow(_ slot: LeafWidgetSnapshot.Slot, isNext: Bool) -> some View {
        let book = snapshot.current?.id == slot.bookID ? snapshot.current : snapshot.upNext.first(where: { $0.id == slot.bookID })
        return HStack(spacing: 10) {
            Text(LeafWidgetTime.text(slot, in: snapshot))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isNext ? Color.white : LeafWidgetPalette.dusk)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .frame(minWidth: 62, minHeight: 24)
                .background(isNext ? LeafWidgetPalette.dusk : LeafWidgetPalette.duskSoft, in: Capsule())
                .widgetAccentable()
            if let book {
                LeafWidgetCover(book: book, image: art.cover(book.id), width: 18)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(slot.title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(LeafWidgetPalette.text)
                    .lineLimit(1)
                Text("\(Int(slot.minutes)) min · \(slot.pagesText)")
                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                    .foregroundStyle(LeafWidgetPalette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(LeafWidgetTime.text(slot, in: snapshot)), \(slot.title), \(slot.pagesText).")
    }

    private func upNextRow(_ book: LeafWidgetSnapshot.Book) -> some View {
        HStack(spacing: 10) {
            LeafWidgetCover(book: book, image: art.cover(book.id), width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(LeafWidgetPalette.text)
                    .lineLimit(1)
                Text(book.author)
                    .font(.system(size: 11))
                    .foregroundStyle(LeafWidgetPalette.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Text(book.finish.map { Self.day($0) } ?? (book.isReading ? "" : "Up next"))
                .font(.system(size: 11, design: .rounded).monospacedDigit())
                .foregroundStyle(LeafWidgetPalette.textSecondary)
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
                        Text("Ready").font(.system(size: 11, weight: .semibold, design: .rounded))
                    } else {
                        Text(timerInterval: timer.range, pauseTime: timer.pauseDate, countsDown: timer.countsDown, showsHours: false)
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
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
                default: Text(snapshot.minutesLeftText).font(.system(.body, design: .rounded).weight(.semibold))
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot.spoken)
        }
    }
}

/// Rectangular: "8:30 PM · Circe" with the pages and today's ring as a bar; the timer while one runs.
struct LeafWidgetRectangular: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    var now: Date = Date()

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
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                } else {
                    Text(timerInterval: timer.range, pauseTime: timer.pauseDate, countsDown: timer.countsDown, showsHours: true)
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
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
            let next = phase == .today ? snapshot.nextSlot(at: now) : nil
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: next == nil ? "leaf.fill" : LeafWidgetGlyph.readingTime)
                    Text(headline(next))
                        .lineLimit(1)
                }
                .font(.headline)
                .widgetAccentable()
                Text(secondLine(next))
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

    private func headline(_ next: LeafWidgetSnapshot.Slot?) -> String {
        if phase == .empty { return "Leaf" }
        if let next { return "\(LeafWidgetTime.text(next, in: snapshot)) · \(next.title)" }
        return snapshot.line
    }

    private func secondLine(_ next: LeafWidgetSnapshot.Slot?) -> String {
        if phase == .empty { return "Choose a book to begin" }
        if let next { return "\(Int(next.minutes)) min · \(next.pagesText)" }
        return snapshot.current?.title ?? ""
    }
}

/// Inline: "8:30 PM · Circe" beside the clock, else "13 min · The Hobbit", or the timer.
struct LeafWidgetInline: View {
    let snapshot: LeafWidgetSnapshot
    let phase: LeafWidgetPhase
    var now: Date = Date()

    var body: some View {
        if let timer = LeafWidgetTimer(snapshot: snapshot, phase: phase) {
            if timer.phase == .teaReady {
                Label(timer.eyebrow, systemImage: timer.glyph)
            } else {
                Text("\(Image(systemName: timer.glyph)) \(Text(timerInterval: timer.range, pauseTime: timer.pauseDate, countsDown: timer.countsDown, showsHours: true))")
            }
        } else if phase == .today, let next = snapshot.nextSlot(at: now) {
            Label("\(LeafWidgetTime.text(next, in: snapshot)) · \(next.title)", systemImage: LeafWidgetGlyph.readingTime)
                .accessibilityLabel(snapshot.spoken)
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
