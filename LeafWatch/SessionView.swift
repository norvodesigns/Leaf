import SwiftUI

/// A live session on the wrist. Mirrors a session started on the phone, too.
struct SessionView: View {
    @Environment(WatchStore.self) private var store
    var onMinimize: () -> Void

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var askingForPage = false
    @State private var celebratedGoal = false

    var body: some View {
        NavigationStack {
            Group {
                if let logged = store.lastLogged, store.activeSession == nil {
                    LoggedView(session: logged)
                } else if let session = store.activeSession {
                    if askingForPage {
                        PageEntryView(session: session, onBack: { askingForPage = false })
                    } else {
                        timer(for: session)
                    }
                } else {
                    ProgressView()
                }
            }
            // Opaque, so the page underneath never shows through the cover; black in Always-On.
            .containerBackground(isLuminanceReduced ? Color.black.gradient : WatchTheme.warm.gradient, for: .navigation)
        }
        .onAppear {
            if LaunchScreen.current == "pages" { askingForPage = true }
            if let session = store.activeSession {
                let elapsed = session.elapsed(at: Date())
                celebratedGoal = session.goalSeconds.map { elapsed >= $0 } ?? (store.goalProgress(at: Date()) >= 1)
            }
        }
    }

    /// The focus-pull countdown: big minutes to go, crisp for most of each minute, softening towards the change and
    /// pulling sharp as the next minute lands. Past the goal it counts up. In Always-On it keeps only the minutes.
    private func timer(for session: ActiveSession) -> some View {
        let book = store.snapshot.book(session.bookID)
        let target = store.sessionTarget(for: session)
        return TimelineView(.periodic(from: .now, by: isLuminanceReduced ? 60 : 1)) { context in
            let elapsed = session.elapsed(at: context.date)
            let left = target.map { max(0, $0 - elapsed) } ?? 0
            let countingDown = left > 0
            let minutes = countingDown ? Int((left / 60).rounded(.up)) : Int(elapsed / 60)
            let progress = session.goalSeconds.map { elapsed / max($0, 1) } ?? store.goalProgress(at: context.date)
            let blur = focusBlur(left: left, elapsed: elapsed, countingDown: countingDown, paused: session.isPaused)
            ZStack {
                WatchAtmosphere(isPaused: session.isPaused)
                VStack(spacing: 6) {
                    ZStack {
                        GoalRing(progress: progress, lineWidth: 8)
                            .opacity(isLuminanceReduced ? 0.6 : 1)
                        VStack(spacing: 0) {
                            Text("\(minutes)")
                                .font(WatchTheme.display(isLuminanceReduced ? 44 : 48).monospacedDigit())
                                .foregroundStyle(session.isPaused || isLuminanceReduced ? WatchTheme.inkSecondary : WatchTheme.paper)
                                .contentTransition(.numericText(countsDown: countingDown))
                                .animation(.snappy, value: minutes)
                                .blur(radius: blur)
                                .animation(.linear(duration: 0.95), value: blur)
                            Text(caption(paused: session.isPaused, countingDown: countingDown, progress: progress))
                                .font(.system(size: 11))
                                .foregroundStyle(!countingDown && progress >= 1 ? WatchTheme.accent : WatchTheme.inkSecondary)
                            if !isLuminanceReduced {
                                Text(LeafFormat.clock(seconds: elapsed))
                                    .font(.system(size: 11, design: .rounded).monospacedDigit())
                                    .foregroundStyle(WatchTheme.inkSecondary.opacity(0.8))
                            }
                        }
                    }
                    .frame(width: 108, height: 108)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spoken(minutes: minutes, elapsed: elapsed, countingDown: countingDown, paused: session.isPaused))
                    .onChange(of: progress >= 1) { _, reached in
                        if reached && !celebratedGoal {
                            celebratedGoal = true
                            // A wrist that went down is tapped by the runtime instead; never both.
                            if !ReadingRuntime.shared.isRunning { WatchHaptics.play(.success) }
                        }
                    }

                    if !isLuminanceReduced {
                        if let book {
                            Text(book.title)
                                .font(.system(.footnote, design: .serif))
                                .lineLimit(1)
                                .foregroundStyle(WatchTheme.inkSecondary)
                        }

                        HStack(spacing: 8) {
                            Button {
                                WatchHaptics.play(.click)
                                session.isPaused ? store.resume() : store.pause()
                            } label: {
                                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glass)
                            .handGestureShortcut(.primaryAction)
                            .accessibilityLabel(session.isPaused ? "Resume" : "Pause")

                            Button {
                                WatchHaptics.play(.stop)
                                askingForPage = true
                            } label: {
                                Text("End").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(WatchTheme.accent)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onMinimize()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Minimize")
            }
        }
    }

    /// Sharp for the first two thirds of each minute, then softening up to the change; the next digit lands sharp.
    private func focusBlur(left: Double, elapsed: Double, countingDown: Bool, paused: Bool) -> CGFloat {
        guard !paused, !reduceMotion, !isLuminanceReduced else { return 0 }
        let intoMinute = countingDown ? (60 - left.truncatingRemainder(dividingBy: 60)) : elapsed.truncatingRemainder(dividingBy: 60)
        let fraction = min(1, max(0, intoMinute / 60))
        guard fraction > 0.66, fraction < 0.995 else { return 0 }
        return CGFloat(2.6 * (fraction - 0.66) / 0.34)
    }

    private func caption(paused: Bool, countingDown: Bool, progress: Double) -> String {
        if paused { return "paused" }
        if countingDown { return "min to go" }
        return progress >= 1 ? "min · goal met" : "min read"
    }

    private func spoken(minutes: Int, elapsed: Double, countingDown: Bool, paused: Bool) -> String {
        let read = Int(elapsed / 60)
        var sentence = countingDown
            ? "\(minutes) \(minutes == 1 ? "minute" : "minutes") to go, \(read) read so far."
            : "\(read) \(read == 1 ? "minute" : "minutes") read."
        if paused { sentence += " Paused." }
        return sentence
    }
}

/// Turn the Digital Crown to the page you reached. Starts at a guess from your pace.
struct PageEntryView: View {
    @Environment(WatchStore.self) private var store
    let session: ActiveSession
    var onBack: () -> Void

    @State private var page: Double = 0
    @State private var lastWhole = 0

    var body: some View {
        let pages = store.snapshot.book(session.bookID)?.pages ?? max(session.startPage + 1, 1)
        VStack(spacing: 4) {
            Text("Which page?")
                .font(.footnote)
                .foregroundStyle(WatchTheme.inkSecondary)
            Text("\(Int(page))")
                .font(WatchTheme.display(48))
                .foregroundStyle(WatchTheme.paper)
                .contentTransition(.numericText())
                .focusable()
                .digitalCrownRotation($page, from: Double(session.startPage), through: Double(pages), by: 1, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityLabel("Page \(Int(page)) of \(pages)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: page = min(Double(pages), page + 1)
                    case .decrement: page = max(Double(session.startPage), page - 1)
                    @unknown default: break
                    }
                }
            Text(Int(page) >= pages ? "The end!" : "of \(pages) · +\(max(0, Int(page) - session.startPage)) pages")
                .font(.system(size: 11))
                .foregroundStyle(Int(page) >= pages ? WatchTheme.accent : WatchTheme.inkSecondary)

            Button {
                WatchHaptics.play(Int(page) >= pages ? .success : .directionUp)
                store.finish(at: Int(page))
            } label: {
                Text(Int(page) >= pages ? "Finish book" : "Save").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(WatchTheme.accent)
        }
        .onAppear {
            page = Double(store.estimatedPage(for: session))
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) { Image(systemName: "chevron.backward") }
                    .accessibilityLabel("Back to timer")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    WatchHaptics.play(.retry)
                    store.cancel()
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Discard session")
            }
        }
    }
}

/// A short wrap-up after logging.
struct LoggedView: View {
    @Environment(WatchStore.self) private var store
    let session: ReadingSession

    var body: some View {
        let book = store.snapshot.book(session.bookID)
        let finished = book.map { session.toPage >= $0.pages } ?? false
        VStack(spacing: 6) {
            Image(systemName: finished ? "book.closed.fill" : "leaf.fill")
                .font(.system(size: 28))
                .foregroundStyle(WatchTheme.accent)
                .symbolEffect(.bounce, value: session.id)
            Text(finished ? "Finished!" : "\(LeafFormat.duration(minutes: session.minutes)) read")
                .font(WatchTheme.display(24))
                .foregroundStyle(WatchTheme.paper)
            Text(finished ? (book?.title ?? "") : "\(session.pagesRead) pages · now on p. \(session.toPage)")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(WatchTheme.inkSecondary)
            Button("Done") { store.lastLogged = nil }
                .buttonStyle(.glass)
        }
    }
}
