import SwiftUI

/// The tea ritual before a session (NEXT.md section 6): pick a tea, pour, wait out the steep, then read one cup.
///
/// The steep is not reading time, so nothing is counted until the cup starts (`TeaRitual`). The countdown is soft
/// while the tea steeps and comes into focus as it gets ready: a slow focus pull. The pot lives in `TeaSteepState`, so
/// minimizing the screen (or a look at Today) leaves it steeping. Nothing plays a sound unless the reader has turned
/// Leaf's sounds on.
struct SessionRitualView: View {
    let request: RitualRequest

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var teaID: String
    @State private var strength: TeaStrength
    @State private var pot: TeaSteepState?
    @State private var isReady = false
    @State private var showsAmbience = false
    /// Whether the opening tea has been settled (the book's pairing, when no tea was asked for).
    @State private var didSettleTea = false

    init(request: RitualRequest) {
        self.request = request
        let saved = TeaSteepState.load()
        let pot = saved?.bookID == request.bookID ? saved : nil
        _pot = State(initialValue: pot)
        _teaID = State(initialValue: pot?.teaID ?? request.teaID ?? TeaCatalog.earlGrey.id)
        _strength = State(initialValue: pot?.strength ?? CozySettings.teaStrength)
        _isReady = State(initialValue: pot?.isReady(at: Date()) ?? false)
    }

    private var tea: Tea { store.tea(id: teaID) ?? TeaCatalog.earlGrey }

    private var item: LibraryItem? { store.item(request.bookID) }

    private var book: Book? { item?.book }

    private var cupMinutes: Int { store.preferences.cupMinutes }

    private var steepSeconds: Int { TeaSuggester.steepSeconds(for: tea, strength: strength) }

    /// The cabinet's teas for the hour (or Leaf's), with the chosen one always among them.
    private var offer: TeaShelf.Choices {
        var offer = store.teaChoices(limit: 8, for: request.bookID)
        if !offer.teas.contains(where: { $0.id == teaID }) { offer.teas.insert(tea, at: 0) }
        return offer
    }

    /// The best of the offered teas for this book: the reader's pinned pairing when it's on offer.
    private func pairing(in choices: [Tea]) -> (tea: Tea, reason: String, isPinned: Bool)? {
        guard let book, let best = TeaShelf.preferred(for: book, pinnedTeaID: item?.pairedTeaID, choices: choices) else { return nil }
        return (best, TeaPairing.reason(for: best, with: book), best.id == item?.pairedTeaID)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                VStack(spacing: Space.xl) {
                    heading
                    cupAndClock
                    if pot == nil {
                        teaPicker
                    }
                }
                .padding(.top, Space.l)
                .padding(.bottom, Space.xl)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            actions
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.l)
        .sheet(isPresented: $showsAmbience) {
            AmbienceSheet()
        }
        .task(id: pot?.startedAt) {
            await waitForTea()
        }
        .onAppear(perform: settleTea)
    }

    /// With no tea asked for, the ritual opens on the book's pairing among what's on offer.
    private func settleTea() {
        guard !didSettleTea else { return }
        didSettleTea = true
        guard pot == nil, request.teaID == nil, let best = pairing(in: store.teaChoices(limit: 8, for: request.bookID).teas) else { return }
        teaID = best.tea.id
    }

    // MARK: Top

    private var topBar: some View {
        HStack(spacing: Space.m) {
            GlassIconButton(systemImage: "chevron.down", label: "Minimize") {
                router.showSession = false
            }
            Text(eyebrow)
                .leafStyle(.eyebrow, color: isReady ? Color.accent : nil)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
            GlassIconButton(systemImage: AmbiencePlayer.shared.currentID == nil ? "speaker.slash" : "speaker.wave.2", label: "Ambience") {
                showsAmbience = true
            }
        }
    }

    private var eyebrow: String {
        guard let pot else { return "Before you read" }
        return isReady ? "Your \(pot.tea.name) is ready" : "Steeping · \(pot.tea.name)"
    }

    private var heading: some View {
        VStack(spacing: Space.xs) {
            Text(pot == nil ? "A pot for" : (isReady ? "Pour a cup of" : "While it steeps, find your page in"))
                .leafStyle(.pullQuote, color: .inkSecondary)
                .multilineTextAlignment(.center)
            Text(book?.title ?? "your book")
                .leafStyle(.title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Cup and countdown

    @ViewBuilder
    private var cupAndClock: some View {
        let cupWidth: CGFloat = typeSize.isAccessibilitySize ? 110 : 150
        if let pot {
            TimelineView(.periodic(from: pot.startedAt, by: 1)) { context in
                let remaining = max(0, pot.readyAt.timeIntervalSince(context.date))
                let progress = 1 - remaining / Double(max(1, pot.steepSeconds))
                VStack(spacing: Space.l) {
                    // The tea darkens as it steeps.
                    TeaCup(fill: 0.9, liquor: CozyColor.liquor(for: pot.tea).opacity(0.3 + 0.7 * progress), steams: true, width: cupWidth)
                    Text(isReady ? "Ready" : LeafFormat.clock(seconds: remaining.rounded(.up)))
                        .leafStyle(.timer, color: isReady ? Color.accent : Color.ink)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: Int(remaining))
                        .blur(radius: focusBlur(progress: progress))
                        .accessibilityLabel(isReady ? "Your tea is ready" : "Steeping, \(SteepText.spoken(seconds: Int(remaining.rounded(.up)))) left")
                    Text(steepCaption(pot))
                        .leafStyle(.caption)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            VStack(spacing: Space.m) {
                TeaCup(fill: 0, liquor: CozyColor.liquor(for: tea), width: cupWidth)
                Text(SteepText.duration(seconds: steepSeconds))
                    .leafStyle(.statNumeral)
                    .contentTransition(.numericText(value: Double(steepSeconds)))
                    .leafAnimation(Motion.paper, value: steepSeconds)
                    .accessibilityLabel("Steeps \(SteepText.spoken(seconds: steepSeconds))")
                Text("then a \(cupMinutes)-minute cup of reading")
                    .leafStyle(.caption)
            }
        }
    }

    /// Soft while the tea steeps, sharp when it's ready. Never blurred under Reduce Motion or Reduce Transparency.
    private func focusBlur(progress: Double) -> CGFloat {
        guard !reduceMotion, !reduceTransparency, !isReady else { return 0 }
        return CGFloat(2.2 * max(0, min(1, 1 - progress)))
    }

    private func steepCaption(_ pot: TeaSteepState) -> String {
        if isReady {
            return "One cup is \(cupMinutes) minutes. Leaf counts it down; the steep wasn’t counted."
        }
        return "Ready at \(LeafFormat.format(pot.readyAt, template: "jmm")). The steep isn’t reading time."
    }

    // MARK: Picking a tea

    private var teaPicker: some View {
        let offer = self.offer
        return VStack(alignment: .leading, spacing: Space.m) {
            if let pairing = pairing(in: offer.teas) {
                pairingNote(pairing)
            }
            Eyebrow(offer.fromCabinet ? "From your cabinet" : "Teas for this hour")
            ScrollView(.horizontal) {
                HStack(spacing: Space.s) {
                    ForEach(offer.teas) { choice in
                        Button {
                            Haptics.shared.selection()
                            withAnimation(Motion.resolved(Motion.glass, reduceMotion: reduceMotion)) {
                                teaID = choice.id
                            }
                        } label: {
                            Chip(choice.name, systemImage: choice.id == teaID ? "checkmark" : nil, tone: choice.id == teaID ? .accent : .neutral)
                                .frame(minHeight: Space.hitTarget)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityAddTraits(choice.id == teaID ? AccessibilityTraits.isSelected : AccessibilityTraits())
                    }
                }
            }
            .scrollIndicators(.hidden)
            if offer.cabinetUnsuitable {
                Text("Nothing in your cabinet suits the hour, so these are Leaf’s.")
                    .leafStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Strength", selection: $strength) {
                ForEach(TeaStrength.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: strength) { _, _ in Haptics.shared.selection() }
            Text(teaFacts)
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Pairs well with this book": the best tea on offer for it, why, and a tap to choose it.
    private func pairingNote(_ pairing: (tea: Tea, reason: String, isPinned: Bool)) -> some View {
        let isChosen = pairing.tea.id == teaID
        return VStack(alignment: .leading, spacing: Space.xs) {
            Eyebrow(pairing.isPinned ? "Your pairing for this book" : "Pairs well with this book")
            Button {
                guard !isChosen else { return }
                Haptics.shared.selection()
                withAnimation(Motion.resolved(Motion.glass, reduceMotion: reduceMotion)) {
                    teaID = pairing.tea.id
                }
            } label: {
                HStack(alignment: .top, spacing: Space.s) {
                    TeaSwatch(tea: pairing.tea, size: 20)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(isChosen ? pairing.tea.name : "\(pairing.tea.name) · choose it")
                            .leafStyle(.uiBody, color: isChosen ? nil : .accent)
                        Text(pairing.reason)
                            .leafStyle(.caption)
                            .italic()
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.pressable)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isChosen ? AccessibilityTraits.isSelected : AccessibilityTraits())
            .accessibilityHint(isChosen ? "The tea you’ll pour" : "Chooses this tea")
        }
    }

    /// "Bergamot and black tea. 95°C · Some caffeine."
    private var teaFacts: String {
        var blurb = tea.blurb.trimmingCharacters(in: .whitespacesAndNewlines)
        let facts = "\(tea.celsius)°C · \(tea.caffeine.title)."
        guard !blurb.isEmpty else { return facts }
        // A tea of the reader's own carries their notes, which may not end a sentence.
        if let last = blurb.last, !".?!…".contains(last) { blurb += "." }
        return "\(blurb) \(facts)"
    }

    // MARK: Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: Space.xxs) {
            if let pot {
                if isReady {
                    PrimaryGlassButton("Start the cup", systemImage: "book", playsHaptic: false) {
                        startReading(withTea: true)
                    }
                } else {
                    SecondaryGlassButton("Start reading now", systemImage: "book", playsHaptic: false) {
                        startReading(withTea: true)
                    }
                }
                TextButton("Pour it out", color: .inkSecondary) {
                    pourOut()
                }
                .accessibilityHint("Clears the \(pot.tea.name) without reading")
            } else {
                PrimaryGlassButton("Pour and steep", systemImage: "cup.and.heat.waves") {
                    pour()
                }
                // A real way in, not a footnote: plain reading is as welcome as tea.
                SecondaryGlassButton("Read without tea", systemImage: "book", compact: true, playsHaptic: false) {
                    startReading(withTea: false)
                }
                .padding(.top, Space.xs)
            }
        }
        .padding(.top, Space.s)
    }

    private func pour() {
        let ritual = TeaRitual.plan(tea: tea, strength: strength, cupMinutes: cupMinutes)
        let isOwn = store.data.cabinet.contains { $0.teaID == tea.id }
        let state = TeaSteepState(teaID: tea.id, steepSeconds: ritual.steepSeconds, startedAt: Date(), bookID: request.bookID, strength: strength, ownTea: isOwn ? tea : nil)
        TeaSteepState.save(state)
        Haptics.shared.soft(0.6)
        CozySounds.shared.teaBrewStarted()
        withAnimation(Motion.resolved(Motion.board, reduceMotion: reduceMotion)) {
            isReady = false
            pot = state
        }
    }

    private func pourOut() {
        TeaSteepState.save(nil)
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            pot = nil
            isReady = false
        }
    }

    /// Starts the session: one cup of the steeped tea, or plain reading.
    private func startReading(withTea: Bool) {
        let ambience = AmbiencePlayer.shared.currentID
        if withTea {
            let poured = pot?.tea ?? tea
            let ritual = TeaRitual.plan(tea: poured, strength: pot?.strength ?? strength, cupMinutes: cupMinutes)
            store.startSession(bookID: request.bookID, teaID: poured.id, goalSeconds: ritual.goalSeconds, ambienceID: ambience)
        } else {
            store.startSession(bookID: request.bookID, ambienceID: ambience)
        }
        TeaSteepState.save(nil)
        router.ritual = nil
        Haptics.shared.play(.sessionStart)
    }

    /// Waits out the steep, then says so with `teaReady` (and the opt-in cue sound).
    private func waitForTea() async {
        guard let current = pot else { return }
        let wait = current.readyAt.timeIntervalSinceNow
        guard wait > 0 else {
            isReady = true
            return
        }
        try? await Task.sleep(for: .seconds(wait))
        guard !Task.isCancelled, pot == current else { return }
        withAnimation(Motion.resolved(Motion.board, reduceMotion: reduceMotion)) {
            isReady = true
        }
        Haptics.shared.play(.teaReady)
        CozySounds.shared.teaReady()
    }
}
