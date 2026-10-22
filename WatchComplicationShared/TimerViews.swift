import SwiftUI
import WidgetKit

// The Timer widget's faces (LeafWatchWidgets/LeafWatchTimerWidget.swift), here so the watch app can draw them too in
// its debug gallery, since a CI simulator has no face to put them on.

// MARK: - The faces

/// Words and numbers for a timer in a state ("running", "paused", "reached").
struct TimerWords {
    let timer: ComplicationTimer
    let state: String

    var isReached: Bool { state == "reached" }
    var isPaused: Bool { state == "paused" }
    /// Down to the goal (or the tea) while it lasts; up through the time read once it's met, or with no goal.
    var countsDown: Bool { timer.hasGoal && !isReached }

    /// Canopy's symbols, the same as the iPhone's widgets (`LeafWidgetGlyph`): steep timer, tea, pause, done, reading.
    var glyph: String {
        if timer.isSteep { return isReached ? "cup.and.heat.waves" : "timer" }
        if isPaused { return "pause.fill" }
        if isReached { return "checkmark" }
        return "book.pages"
    }

    /// "Earl Grey · steeping", "Earl Grey is ready", "Paused", "Goal met", "Reading".
    var eyebrow: String {
        let tea = timer.teaName ?? "Your tea"
        if timer.isSteep { return isReached ? "\(tea) is ready" : "\(tea) · steeping" }
        if isPaused { return "Paused" }
        if isReached { return "Goal met" }
        return timer.teaName.map { "\($0) · one cup" } ?? "Reading"
    }

    var line: String {
        if timer.isSteep { return isReached ? "Pour, then read" : "Find your page" }
        return timer.title ?? "Your book"
    }

    var spoken: String {
        if timer.isSteep { return isReached ? "\(timer.teaName ?? "Your tea") is ready." : "\(timer.teaName ?? "Tea") is steeping." }
        if isPaused { return "Reading, paused." }
        if isReached { return "Today’s goal is met. Still reading." }
        return "Reading \(timer.title ?? "")."
    }
}

struct TimerDigits: View {
    let words: TimerWords
    var size: CGFloat = 22

    var body: some View {
        if words.timer.isSteep && words.isReached {
            Text("Ready")
                .font(.system(size: size, weight: .medium, design: .rounded))
        } else {
            Text(
                timerInterval: words.timer.range(countsDown: words.countsDown),
                pauseTime: words.timer.pauseDate(countsDown: words.countsDown),
                countsDown: words.countsDown,
                showsHours: true
            )
            .font(.system(size: size, weight: .medium, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

struct TimerRectangular: View {
    let timer: ComplicationTimer
    let state: String

    var body: some View {
        let words = TimerWords(timer: timer, state: state)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: words.glyph)
                    .widgetAccentable()
                Text(words.eyebrow)
                    .lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(timer.isSteep ? ComplicationPalette.tea : ComplicationPalette.dusk)
            TimerDigits(words: words, size: 24)
            if words.countsDown && !words.isPaused {
                ProgressView(timerInterval: timer.range(countsDown: true), countsDown: false, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.linear)
                    .tint(timer.isSteep ? ComplicationPalette.tea : ComplicationPalette.dusk)
            }
            Text(words.line)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words.spoken)
    }
}

struct TimerCorner: View {
    let timer: ComplicationTimer
    let state: String

    var body: some View {
        let words = TimerWords(timer: timer, state: state)
        Image(systemName: words.glyph)
            .font(.system(size: 20, weight: .semibold))
            .widgetAccentable()
            .widgetLabel {
                TimerDigits(words: words, size: 14)
            }
            .accessibilityLabel(words.spoken)
    }
}

struct TimerCircular: View {
    let timer: ComplicationTimer
    let state: String

    var body: some View {
        let words = TimerWords(timer: timer, state: state)
        ZStack {
            if words.countsDown && !words.isPaused {
                ProgressView(timerInterval: timer.range(countsDown: true), countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                    .progressViewStyle(.circular)
                    .widgetAccentable()
            } else {
                AccessoryWidgetBackground()
            }
            VStack(spacing: 0) {
                Image(systemName: words.glyph)
                    .font(.system(size: 12, weight: .semibold))
                TimerDigits(words: words, size: 12)
            }
            .padding(6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(words.spoken)
    }
}

struct TimerInline: View {
    let timer: ComplicationTimer
    let state: String

    var body: some View {
        let words = TimerWords(timer: timer, state: state)
        if timer.isSteep && words.isReached {
            Text("\(timer.teaName ?? "Tea") is ready")
        } else {
            Text("\(Image(systemName: words.glyph)) \(Text(timerInterval: timer.range(countsDown: words.countsDown), pauseTime: timer.pauseDate(countsDown: words.countsDown), countsDown: words.countsDown, showsHours: true))")
        }
    }
}

/// Sample timers for previews, the placeholder and the debug gallery.
enum TimerSamples {
    static func reading(now: Date = Date()) -> ComplicationTimer {
        ComplicationTimer(
            isSteep: false, start: now.addingTimeInterval(-9 * 60 - 41), pausedElapsed: nil, goalSeconds: 25 * 60,
            title: "The Hobbit", teaName: nil, phases: [ComplicationTimer.Phase(from: now, state: "running", relevance: 1)],
            expiresAt: now.addingTimeInterval(8 * 3600)
        )
    }

    static func paused(now: Date = Date()) -> ComplicationTimer {
        var timer = reading(now: now)
        timer.pausedElapsed = 12 * 60 + 5
        timer.phases = [ComplicationTimer.Phase(from: now, state: "paused", relevance: 0.6)]
        return timer
    }

    static func steeping(now: Date = Date()) -> ComplicationTimer {
        ComplicationTimer(
            isSteep: true, start: now.addingTimeInterval(-70), pausedElapsed: nil, goalSeconds: 240, title: nil,
            teaName: "Earl Grey", phases: [ComplicationTimer.Phase(from: now, state: "running", relevance: 1)],
            expiresAt: now.addingTimeInterval(170 + 30 * 60)
        )
    }
}

