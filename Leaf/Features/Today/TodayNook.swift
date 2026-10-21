import SwiftUI

/// What the Nook's one button does right now.
enum NookAction: Equatable {
    /// "Steep and read": pour, wait for the tea, then read one cup.
    case steep
    case steeping(TeaSteepState)
    case ready(TeaSteepState)
    /// A session is running: return to it.
    case live
    /// Today's minutes are read: "Read a little more".
    case readMore
    /// A rest day: the same ritual, offered quietly.
    case restDay
    /// Nothing to read yet.
    case findBook(firstEver: Bool)
}

/// The things the Nook can ask Today to do.
struct NookActions {
    var steep: () -> Void
    /// Start reading the book on the table (with the steeped tea, if there is one).
    var start: () -> Void
    var startWithoutTea: () -> Void
    var startBook: (String) -> Void
    var pourOut: () -> Void
    var chooseTea: (Tea) -> Void
    var findBook: () -> Void
    var openBook: (Book) -> Void
    var readingTimes: () -> Void
}

/// The Reading Nook (NEXT.md section 4, concept A): the top of Today. The day's light, the greeting set large in
/// Instrument Serif, a still life of the book on the table beside a cup that fills as the day's minutes come in
/// (the real minutes beside it), and one button: "Steep and read". Steeping happens here, before the session, so
/// the session's clock only ever counts reading.
struct TodayNook: View {
    let brief: TodayBrief
    let daypart: Daypart
    let dateline: String
    let issueNumber: Int
    let issueSpoken: String
    /// The tea for this hour (or the one the reader picked), its steep time, and other teas that suit the hour.
    let tea: Tea
    let steepSeconds: Int
    let teaChoices: [Tea]
    let action: NookAction
    /// Books open in Reading, for "read instead" in the button's menu.
    let readingBooks: [LibraryItem]
    let actions: NookActions
    /// How far the scroll view's content starts below the top of the screen (the status bar and the bar with the
    /// gear). The nook's light reaches up behind them, so the top of Today is one scene, not a band of plain paper.
    var topInset: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var typeSize

    private var book: Book? { brief.current?.item.book }

    private static let overscroll: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            datelineView
                .inkIn(0)
            greetingView
                .padding(.top, Space.xl)
                .inkIn(1)
            stillLife
                .padding(.top, Space.xxl)
                .inkIn(2)
            controls
                .padding(.top, Space.l)
                .inkIn(3)
        }
        .leafMargins()
        .padding(.top, Space.s)
        .padding(.bottom, Space.l)
        .background {
            // The light fills the screen from its very top edge down to the table; above that, a stretch of the top
            // colour, so a pull past the top never shows a seam.
            VStack(spacing: 0) {
                NookAtmosphere.edge(daypart: daypart)
                    .frame(height: Self.overscroll)
                NookAtmosphere(daypart: daypart)
            }
            .padding(.top, -(topInset + Self.overscroll))
            .accessibilityHidden(true)
        }
    }

    // MARK: Dateline and greeting

    private var datelineView: some View {
        VStack(spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                Text(dateline)
                    .leafStyle(.eyebrow)
                Spacer(minLength: Space.m)
                Text("No. \(issueNumber)")
                    .leafStyle(.eyebrow)
                    .accessibilityLabel(issueSpoken)
            }
            DoubleRule()
        }
    }

    private var greetingView: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(brief.greeting.headline)
                .leafStyle(.display)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subline = brief.greeting.subline {
                Text(subline)
                    .leafStyle(.pullQuote, color: .inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Still life

    /// The cup is full, or a pot is on.
    private var steams: Bool {
        switch action {
        case .steeping, .ready: return true
        default: return brief.goalMinutes > 0 && brief.goalProgress >= 1
        }
    }

    private var cupFill: Double {
        if case .ready = action, brief.goalProgress < 0.15 { return 0.9 }
        return brief.goalProgress
    }

    private var liquor: Color {
        switch action {
        case .steeping(let state), .ready(let state): return CozyColor.liquor(for: state.tea)
        default: return CozyColor.liquor(for: tea)
        }
    }

    private var stillLife: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: Space.l) {
                if let book {
                    Button {
                        actions.openBook(book)
                    } label: {
                        BookCover(book: book, size: typeSize.isAccessibilitySize ? .s : .m, ribbon: !typeSize.isAccessibilitySize, swaysRibbon: true)
                            .todayBookZoomSource(book.id)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityHint("Opens book details")
                }
                TeaCup(fill: cupFill, liquor: liquor, steams: steams, width: typeSize.isAccessibilitySize ? 64 : 88)
                cupCaption
                    .padding(.bottom, Space.m)
                Spacer(minLength: 0)
            }
            .zIndex(1)
            table
        }
    }

    /// A strip of tea-stained table under the cup and the book, full bleed.
    private var table: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [CozyColor.teaPaper, CozyColor.teaPaper.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
            Rectangle()
                .fill(Color.hairlineStrong)
                .frame(height: 1)
        }
        .padding(.horizontal, -Space.margin)
        .accessibilityHidden(true)
    }

    private var cupCaption: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(minutesLine)
                .leafStyle(.data)
                .numericBlur(value: brief.minutesReadToday)
            Text(cupPhrase)
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "12 of 25 min today"
    private var minutesLine: String {
        let read = Int(brief.minutesReadToday.rounded())
        if brief.goalMinutes > 0 { return "\(read) of \(brief.goalMinutes) min" }
        return "\(read) min today"
    }

    /// The cup in words. The minutes beside it are the real measure.
    private var cupPhrase: String {
        switch action {
        case .steeping(let state): return "\(state.tea.name), steeping"
        case .ready(let state): return "\(state.tea.name), ready"
        default: break
        }
        if brief.mode == .restDay && brief.minutesReadToday < 1 { return "A rest day. No cup needed." }
        let progress = brief.goalProgress
        if brief.goalMinutes > 0 && progress >= 1 { return "A full cup" }
        if brief.minutesReadToday < 1 { return "An empty cup, for now" }
        if progress < 0.34 { return "A few sips in" }
        if progress < 0.67 { return "About half a cup" }
        return "Nearly a full cup"
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        switch action {
        case .steep:
            steepControls(prominent: true)
        case .restDay:
            steepControls(prominent: false)
        case .steeping(let state):
            steepingControls(state)
        case .ready(let state):
            readyControls(state)
        case .live:
            PrimaryGlassButton("Return to session", systemImage: "book") {
                actions.start()
            }
            .sessionZoomSource(ReadingSessionLauncher.heroSource)
        case .readMore:
            VStack(alignment: .leading, spacing: Space.s) {
                SecondaryGlassButton("Read a little more", systemImage: "book") {
                    actions.startWithoutTea()
                }
                .sessionZoomSource(ReadingSessionLauncher.heroSource)
                .contextMenu { optionsMenu }
                Text("Today’s reading is done. Anything more is a gift.")
                    .leafStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .findBook(let firstEver):
            PrimaryGlassButton(firstEver ? "Find your first book" : "Browse the shelves", systemImage: "magnifyingglass") {
                actions.findBook()
            }
        }
    }

    private var teaChip: some View {
        Menu {
            Section("Teas for this hour") {
                ForEach(teaChoices) { choice in
                    Button {
                        actions.chooseTea(choice)
                    } label: {
                        Label(
                            "\(choice.name) · \(SteepText.duration(seconds: TeaSuggester.steepSeconds(for: choice, strength: CozySettings.teaStrength)))",
                            systemImage: choice.id == tea.id ? "checkmark" : "leaf"
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: Space.xs) {
                Chip("\(tea.name) · \(SteepText.duration(seconds: steepSeconds)) steep", systemImage: "cup.and.saucer")
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.inkTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Space.hitTarget)
            .contentShape(.rect)
        }
        .accessibilityLabel("Tea: \(tea.name), steeps \(SteepText.spoken(seconds: steepSeconds))")
        .accessibilityHint("Choose another tea")
    }

    /// The tea, what steeping means today, then the two ways in as a pair: "Steep and read" in glass, "Begin
    /// reading" in ink. Side by side when they fit, one above the other when the type is large.
    private func steepControls(prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                teaChip
                ritualCaption
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.s) {
                    steepButton(prominent: prominent)
                    beginButton(prominent: prominent)
                }
                VStack(spacing: Space.s) {
                    steepButton(prominent: prominent)
                    beginButton(prominent: prominent)
                }
            }
        }
    }

    private func steepButton(prominent: Bool) -> some View {
        SecondaryGlassButton(prominent ? "Steep and read" : "Steep and read anyway", systemImage: "cup.and.heat.waves") {
            actions.steep()
        }
        .sessionZoomSource(ReadingSessionLauncher.heroSource)
        .contextMenu { optionsMenu }
        .accessibilityHint("Steeps your tea first, then starts a cup of reading")
    }

    /// Reading straight away, no tea. A ring of ink on a rest day, so neither choice pushes.
    private func beginButton(prominent: Bool) -> some View {
        InkButton("Begin reading", outline: !prominent) {
            actions.startWithoutTea()
        }
        .accessibilityHint("Starts reading now, without steeping tea")
    }

    private var ritualCaption: some View {
        Text("Steep \(SteepText.duration(seconds: steepSeconds)), then read a \(brief.cupMinutes)-minute cup.")
            .leafStyle(.caption)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func steepingControls(_ state: TeaSteepState) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .lastTextBaseline, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Eyebrow("\(state.tea.name) is steeping")
                    Text(timerInterval: state.startedAt...state.readyAt, countsDown: true)
                        .font(LeafType.statNumeral.monospacedDigit())
                        .foregroundStyle(Color.ink)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                }
                Spacer(minLength: 0)
            }
            Text("Find your page and settle in. It’s ready at \(LeafFormat.format(state.readyAt, template: "jmm")).")
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryGlassButton("Start reading now", systemImage: "book") {
                actions.start()
            }
            .sessionZoomSource(ReadingSessionLauncher.heroSource)
            TextButton("Pour it out", color: .inkSecondary) {
                actions.pourOut()
            }
        }
    }

    private func readyControls(_ state: TeaSteepState) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Eyebrow("Your \(state.tea.name) is ready")
            Text("One cup is \(brief.cupMinutes) minutes. Leaf counts it down for you.")
                .leafStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryGlassButton("Start reading", systemImage: "book") {
                actions.start()
            }
            .sessionZoomSource(ReadingSessionLauncher.heroSource)
            TextButton("Pour it out", color: .inkSecondary) {
                actions.pourOut()
            }
        }
    }

    @ViewBuilder
    private var optionsMenu: some View {
        if readingBooks.count > 1 {
            Section("Read instead") {
                ForEach(readingBooks) { item in
                    Button(item.book.title, systemImage: "book") {
                        actions.startBook(item.id)
                    }
                }
            }
        }
        Button("Begin reading without tea", systemImage: "book") {
            actions.startWithoutTea()
        }
        Button("Reading times", systemImage: "clock") {
            actions.readingTimes()
        }
    }
}
