import SwiftUI
import UIKit

/// The full-screen reading session (DESIGN.md §6): a lamp-lit page, a ring around the timer, and two
/// glass controls. Reads `store.activeSession`, so it works for a session started on the watch too.
struct SessionView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    /// The last session we saw, so the screen holds still while it closes after saving.
    @State private var frozen: ActiveSession?
    @State private var isEnding = false
    @State private var page = 0
    @State private var estimatedPage = 0
    @State private var wasPausedBeforeEnding = false
    /// Reading mode: after 20 s without a touch everything but the ring and timer fades.
    @State private var isDimmed = false
    @State private var interaction = 0
    @State private var showDiscardDialog = false
    @State private var showShortNotice = false
    @State private var goalIsMet = false
    @State private var showsAmbience = false
    @State private var showsJournal = false

    @ScaledMetric(relativeTo: .headline) private var controlHeight: CGFloat = 54

    private var session: ActiveSession? { store.activeSession ?? frozen }

    var body: some View {
        ZStack {
            SessionBackground()

            if let session, let book = store.item(session.bookID)?.book {
                content(session: session, book: book)
            } else if let ritual = router.ritual, store.item(ritual.bookID) != nil {
                SessionRitualView(request: ritual)
                    .transition(.opacity)
            }

            if isDimmed && !isEnding {
                // Reading mode: the first touch only wakes the screen.
                Color.clear
                    .contentShape(.rect)
                    .ignoresSafeArea()
                    .onTapGesture(perform: wake)
                    .accessibilityHidden(true)
            }

            if showShortNotice {
                shortSessionNotice
                    .transition(.opacity)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { interaction += 1 })
        .interactiveDismissDisabled(isEnding || showShortNotice)
        .confirmationDialog("Discard this session?", isPresented: $showDiscardDialog, titleVisibility: .visible) {
            Button("Discard session", role: .destructive, action: discard)
            Button("Keep reading", role: .cancel) {}
        } message: {
            Text("The time you’ve read won’t be logged.")
        }
        .task(id: interaction) {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, !isEnding, !showDiscardDialog, !showsJournal, !showsAmbience,
                  store.activeSession != nil else { return }
            withAnimation(Motion.fade) { isDimmed = true }
        }
        .onAppear {
            frozen = store.activeSession
            UIApplication.shared.isIdleTimerDisabled = true
            if store.activeSession == nil && router.ritual == nil { router.showSession = false }
            // Screenshot runs open the note or the ambience over the session.
            switch LaunchOptions.current.screen ?? "" {
            case "session.note": showsJournal = true
            case "session.ambience": showsAmbience = true
            default: break
            }
        }
        .sheet(isPresented: $showsAmbience) {
            AmbienceSheet()
        }
        .sheet(isPresented: $showsJournal) {
            if let session, let book = store.item(session.bookID)?.book {
                JournalCaptureSheet(book: book, sessionID: session.id, page: max(session.startPage, store.item(book.id)?.currentPage ?? 0))
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: store.activeSession) { _, new in
            if let new {
                frozen = new
                // Reading has begun, from the ritual or from anywhere else: the tea stage is done.
                router.ritual = nil
            }
        }
        .onChange(of: store.activeSession == nil) { _, ended in
            // Ended or discarded somewhere else (the watch): close the cover.
            if ended { router.showSession = false }
        }
    }

    // MARK: Layout

    private func content(session: ActiveSession, book: Book) -> some View {
        VStack(spacing: 0) {
            topBar(session: session, book: book)
                .opacity(isEnding ? 0 : (isDimmed ? 0.25 : 1))
                .allowsHitTesting(!isEnding)

            Spacer(minLength: Space.l)

            if !isEnding {
                face(session: session)
                    .transition(.opacity)
                Spacer(minLength: Space.l)
                extras
                    .opacity(isDimmed ? 0.25 : 1)
                    .padding(.bottom, Space.l)
            }

            controls(session: session, book: book)
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.l)
    }

    private func topBar(session: ActiveSession, book: Book) -> some View {
        HStack(spacing: Space.m) {
            GlassIconButton(systemImage: "chevron.down", label: "Minimize session") {
                router.showSession = false
            }
            Text(goalIsMet ? "Goal met · keep going" : eyebrow(session: session, book: book))
                .leafStyle(.eyebrow, color: goalIsMet ? Color.accent : nil)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : Motion.paper, value: goalIsMet)
            Menu {
                Button("Discard session", systemImage: "trash", role: .destructive) {
                    showDiscardDialog = true
                }
            } label: {
                GlassIcon(systemImage: "ellipsis", diameter: 44)
            }
            .accessibilityLabel("Session options")
        }
    }

    /// "The Hobbit · pp. 142–158": the book and today's pages.
    private func eyebrow(session: ActiveSession, book: Book) -> String {
        if let planned = store.todayAssignments.first(where: { $0.item.id == book.id }) {
            return "\(book.title) · \(LeafFormat.pages(from: planned.assignment.fromPage, to: planned.assignment.toPage))"
        }
        return "\(book.title) · from p. \(min(book.pages, session.startPage + 1))"
    }

    // MARK: The face: ring, timer, caption

    private func face(session: ActiveSession) -> some View {
        TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
            let clock = SessionClock(session: session, store: store, at: context.date)
            VStack(spacing: Space.l) {
                ProgressRing.session(progress: clock.ringProgress)
                    .overlay {
                        Text(LeafFormat.clock(seconds: clock.displaySeconds))
                            .leafStyle(.timer, color: timerColor(clock: clock, isPaused: session.isPaused))
                            .contentTransition(.numericText(countsDown: clock.countsDown))
                            .animation(reduceMotion ? nil : Animation.snappy(duration: 0.3), value: Int(clock.displaySeconds))
                            .breathing(session.isPaused)
                            .padding(.horizontal, Space.xxl)
                    }
                VStack(spacing: Space.xs) {
                    if let tea = session.teaID.flatMap({ TeaCatalog.tea(id: $0) }) {
                        Text(cupLine(clock: clock, tea: tea))
                            .leafStyle(.eyebrow, color: clock.cupDone ? Color.accent : nil)
                            .contentTransition(.opacity)
                    }
                    Text(caption(clock: clock, session: session))
                        .leafStyle(.caption)
                        .contentTransition(.opacity)
                    if session.origin == .watch {
                        Label("Started on Apple Watch", systemImage: "applewatch")
                            .leafStyle(.caption)
                    }
                }
                .opacity(isDimmed ? 0.25 : 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(clock.countsDown ? (clock.hasCup ? "Time left in the cup" : "Time left to today’s goal") : "Time read in this session")
            .accessibilityValue(spokenTime(clock.displaySeconds) + (session.isPaused ? ", paused" : ""))
            .accessibilityAddTraits(.updatesFrequently)
            .onChange(of: clock.crossedGoal) { _, crossed in
                if crossed {
                    Haptics.shared.play(.goalReached)
                    LiveActivityController.shared.sync()
                }
            }
            .onChange(of: clock.cupDone) { _, done in
                if done {
                    if !clock.crossedGoal { Haptics.shared.soft(0.7) }
                    LiveActivityController.shared.sync()
                }
            }
            .onChange(of: clock.goalMet, initial: true) { _, met in
                goalIsMet = met
            }
        }
    }

    private func timerColor(clock: SessionClock, isPaused: Bool) -> Color {
        if isPaused { return Color.inkTertiary }
        if clock.hasCup { return clock.cupDone ? Color.accent : Color.ink }
        return clock.goalMet ? Color.accent : Color.ink
    }

    /// "Earl Grey · one cup", then "Cup finished · stretch for 5 min".
    private func cupLine(clock: SessionClock, tea: Tea) -> String {
        guard clock.cupDone, let cup = clock.cup else { return "\(tea.name) · one cup" }
        let stretch = TeaRitual.breakSeconds(forReadSeconds: Int(cup)) / 60
        return "Cup finished · stretch for \(stretch) min"
    }

    // MARK: Note and ambience

    /// A thought or a quote, and the room's sound: quiet glass capsules under the face.
    private var extras: some View {
        GlassEffectContainer(spacing: Space.m) {
            HStack(spacing: Space.m) {
                extraButton(title: "Note", systemImage: "square.and.pencil", label: "Write a thought or a quote") {
                    showsJournal = true
                }
                extraButton(title: ambienceTitle, systemImage: AmbiencePlayer.shared.currentID == nil ? "speaker.slash" : "speaker.wave.2", label: "Ambience: \(ambienceTitle)") {
                    showsAmbience = true
                }
            }
        }
    }

    private var ambienceTitle: String {
        AmbienceCatalog.ambience(id: AmbiencePlayer.shared.currentID)?.name ?? "Silence"
    }

    private func extraButton(title: String, systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.shared.tap()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Color.ink)
                .lineLimit(1)
                .padding(.horizontal, Space.l)
                .frame(minHeight: Space.hitTarget)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Color.glassTint).interactive(), in: .capsule)
        .accessibilityLabel(label)
    }

    private func caption(clock: SessionClock, session: ActiveSession) -> String {
        if session.isPaused { return "Paused" }
        if clock.goalMet {
            return "\(LeafFormat.duration(minutes: clock.total / 60)) today"
        }
        if clock.elapsed < 30 { return "Just started" }
        return "\(LeafFormat.duration(minutes: clock.elapsed / 60)) read"
    }

    // MARK: Controls and the page panel

    private func controls(session: ActiveSession, book: Book) -> some View {
        GlassEffectContainer(spacing: 20) {
            if isEnding {
                pageEntryPanel(session: session, book: book)
            } else {
                HStack(spacing: 20) {
                    pauseButton(isPaused: session.isPaused)
                    endButton(session: session, book: book)
                }
                .opacity(isDimmed ? 0.25 : 1)
            }
        }
    }

    private func pauseButton(isPaused: Bool) -> some View {
        Button {
            togglePause(isPaused: isPaused)
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
                Text(isPaused ? "Resume" : "Pause")
            }
            .font(.system(.headline, weight: .semibold))
            .foregroundStyle(Color.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: controlHeight)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Color.glassTint).interactive(), in: .capsule)
        .glassEffectID("pause", in: glassNamespace)
        .accessibilityLabel(isPaused ? "Resume" : "Pause")
    }

    private func endButton(session: ActiveSession, book: Book) -> some View {
        Button {
            beginEnding(session: session, book: book)
        } label: {
            Text("End")
                .font(.system(.headline, weight: .semibold))
                .foregroundStyle(Color.paper)
                .frame(maxWidth: .infinity, minHeight: controlHeight)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Color.ink).interactive(), in: .capsule)
        .glassEffectID("end", in: glassNamespace)
        .accessibilityLabel("End session")
    }

    /// "Where did you stop?" The End button morphs into this glass panel (rule 6: plain buttons inside).
    private func pageEntryPanel(session: ActiveSession, book: Book) -> some View {
        let range = ReadingSessionLauncher.pageRange(for: session, book: book)
        return VStack(spacing: Space.m) {
            Text("Where did you stop?")
                .leafStyle(.title)
                .accessibilityAddTraits(.isHeader)
            Text("\(page)")
                .leafStyle(.heroNumeral)
                .numericBlur(value: Double(page))
                .leafAnimation(Motion.paper, value: page)
                .accessibilityHidden(true)
            PageScrubber(page: $page, range: range, estimate: estimatedPage)
            Text("We guessed p. \(estimatedPage) from your pace.")
                .leafStyle(.caption)
            VStack(spacing: Space.xs) {
                Button {
                    savePage()
                } label: {
                    Text("Save page")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(Color.paper)
                        .frame(maxWidth: .infinity, minHeight: controlHeight)
                        .background(Color.ink, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                Button {
                    keepReading()
                } label: {
                    Text("Keep reading")
                        .leafStyle(.ui)
                        .frame(maxWidth: .infinity, minHeight: Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.pressable)
            }
            .padding(.top, Space.s)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.xl)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular.tint(Color.glassTint), in: .rect(cornerRadius: Radius.panel, style: .continuous))
        .glassEffectID("end", in: glassNamespace)
        .accessibilityElement(children: .contain)
    }

    private var shortSessionNotice: some View {
        ZStack {
            Color.paper.opacity(0.94)
                .ignoresSafeArea()
            Text("Session under a minute. Not logged.")
                .leafStyle(.pullQuote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Space.xxxl)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func wake() {
        interaction += 1
        if isDimmed {
            withAnimation(Motion.fade) { isDimmed = false }
        }
    }

    private func togglePause(isPaused: Bool) {
        if isPaused {
            Haptics.shared.tap()
        } else {
            Haptics.shared.soft(0.6)
        }
        withAnimation(Motion.resolved(Motion.glass, reduceMotion: reduceMotion)) {
            if isPaused {
                store.resumeSession()
            } else {
                store.pauseSession()
            }
        }
    }

    private func beginEnding(session: ActiveSession, book: Book) {
        Haptics.shared.play(.sessionEnd)
        let now = Date()
        if session.elapsed(at: now) < 60 {
            discardShortSession()
            return
        }
        wasPausedBeforeEnding = session.isPaused
        // The page panel stops the clock, so time spent choosing a page isn't logged as reading.
        if !session.isPaused { store.pauseSession() }
        let guess = ReadingSessionLauncher.estimatedPage(for: session, book: book, wpm: store.wpm, at: now)
        // Pages logged on the way (the Live Activity's button, Siri) are a floor for the guess.
        let logged = min(book.pages, max(session.startPage, store.item(book.id)?.currentPage ?? 0))
        estimatedPage = max(guess, logged)
        page = max(guess, logged)
        withAnimation(Motion.resolved(Motion.board, reduceMotion: reduceMotion)) {
            isEnding = true
        }
    }

    private func keepReading() {
        Haptics.shared.tap()
        withAnimation(Motion.resolved(Motion.board, reduceMotion: reduceMotion)) {
            isEnding = false
        }
        if !wasPausedBeforeEnding { store.resumeSession() }
        wake()
    }

    private func savePage() {
        Haptics.shared.play(.pageTurn)
        AmbiencePlayer.shared.stop()
        if let outcome = store.finishSession(toPage: page) {
            ReadingSessionLauncher.present(outcome, router: router)
        } else {
            router.showSession = false
        }
    }

    private func discardShortSession() {
        AmbiencePlayer.shared.stop()
        withAnimation(Motion.fade) { showShortNotice = true }
        let store = store
        let router = router
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            store.cancelSession()
            router.showSession = false
        }
    }

    private func discard() {
        Haptics.shared.warning()
        AmbiencePlayer.shared.stop()
        store.cancelSession()
        router.showSession = false
    }

    private func spokenTime(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let rest = total % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) \(hours == 1 ? "hour" : "hours")") }
        if minutes > 0 { parts.append("\(minutes) \(minutes == 1 ? "minute" : "minutes")") }
        if rest > 0 || parts.isEmpty { parts.append("\(rest) \(rest == 1 ? "second" : "seconds")") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Background

/// A 3×3 mesh of `paper` with a `lamp` at the top centre that drifts a few percent over twelve
/// seconds (DESIGN.md §6). Still under Reduce Motion.
private struct SessionBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                mesh(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
                    mesh(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func mesh(at time: TimeInterval) -> some View {
        let phase = time * 2 * Double.pi / 12
        let lampDrift = Float(sin(phase) * 0.03)
        let centreX = Float(0.5 + cos(phase * 0.7) * 0.03)
        let centreY = Float(0.5 + sin(phase * 0.5) * 0.03)
        let points: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(0.5 + lampDrift, 0), SIMD2<Float>(1, 0),
            SIMD2<Float>(0, 0.5), SIMD2<Float>(centreX, centreY), SIMD2<Float>(1, 0.5),
            SIMD2<Float>(0, 1), SIMD2<Float>(0.5, 1), SIMD2<Float>(1, 1),
        ]
        let colors: [Color] = [
            Color.paper, Color.lamp, Color.paper,
            Color.paper, Color.paper, Color.paper,
            Color.paper, Color.paper, Color.paper,
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: colors)
    }
}

// MARK: - Previews

@MainActor
private func sessionPreviewStore(startedAgo seconds: Double, origin: SessionDevice = .phone) -> LibraryStore {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    store.startSession(bookID: DemoData.hobbit.id, origin: origin, startedAt: Date().addingTimeInterval(-seconds))
    return store
}

#Preview("Session") {
    SessionView()
        .environment(sessionPreviewStore(startedAgo: 9 * 60 + 41))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Session · goal met") {
    SessionView()
        .environment(sessionPreviewStore(startedAgo: 16 * 60))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}

#Preview("Session · from the watch") {
    SessionView()
        .environment(sessionPreviewStore(startedAgo: 4 * 60, origin: .watch))
        .environment(AppRouter())
        .environment(BookCatalog.shared)
}
