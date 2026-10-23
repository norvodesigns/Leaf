import Foundation

// MARK: - The tips

/// Where a tip lives. A place shows one tip at a time, in the order of `tips`.
enum FirstUsePlace: String, CaseIterable, Codable, Sendable {
    case today, session, plan, library, book, you

    var tips: [FirstUseTip] { FirstUseTip.allCases.filter { $0.place == self } }
}

/// The first-use tips (docs/design/DESIGN_SYSTEM.md §12): one short note the first few times a reader reaches a part
/// of the app, about the one thing there worth knowing. Each goes for good once the reader closes it or does what it
/// says. The words live here so they can be checked anywhere; the iPhone app draws them (`FirstUseTipCard`).
enum FirstUseTip: String, CaseIterable, Codable, Sendable {
    /// Today: the two ways to start.
    case todayStart = "today.start"
    /// The reading timer: the scene and the sound.
    case sessionNook = "session.nook"
    /// The reading timer, the next visit: tuck it away and look around.
    case sessionMinimize = "session.minimize"
    /// Plan: a reading time's time and book are each one tap.
    case planTimes = "plan.times"
    /// Library: adding a book.
    case libraryAdd = "library.add"
    /// A book: telling Leaf your page.
    case bookPage = "book.page"
    /// You: where to make Leaf yours.
    case youCorner = "you.corner"

    var place: FirstUsePlace {
        switch self {
        case .todayStart: return .today
        case .sessionNook, .sessionMinimize: return .session
        case .planTimes: return .plan
        case .libraryAdd: return .library
        case .bookPage: return .book
        case .youCorner: return .you
        }
    }

    var title: String {
        switch self {
        case .todayStart: return "Two ways to begin"
        case .sessionNook: return "Make it your nook"
        case .sessionMinimize: return "Your timer keeps going"
        case .planTimes: return "Your reading times"
        case .libraryAdd: return "Add a book"
        case .bookPage: return "Not on this page?"
        case .youCorner: return "Make Leaf yours"
        }
    }

    var message: String {
        switch self {
        case .todayStart:
            return "Begin reading starts the timer now. Steep and read brews your tea first, then times one cup."
        case .sessionNook:
            return "Change the scene behind your timer here, and pick a sound to read by beside it."
        case .sessionMinimize:
            return "The arrow tucks your session into a bar above the tabs, so you can look around. Tap the bar to come back."
        case .planTimes:
            return "Tap a time to move it, or the arrows to read a different book then. The plan reflows by itself."
        case .libraryAdd:
            return "Tap + up top to find a book. Touch and hold it to scan a barcode or type one in."
        case .bookPage:
            return "Tap your page to tell Leaf where your bookmark is. The plan picks up from there."
        case .youCorner:
            return "How your reading is going, at a glance. Just below: rate your teas, the teas you like, your cabinet and settings."
        }
    }

    /// An SF Symbol for the note, from the design system's fixed vocabulary.
    var symbol: String {
        switch self {
        case .todayStart: return "book.pages"
        case .sessionNook: return "sparkles"
        case .sessionMinimize: return "chevron.down"
        case .planTimes: return "clock"
        case .libraryAdd: return "plus"
        case .bookPage: return "bookmark"
        case .youCorner: return "heart"
        }
    }
}

// MARK: - What the reader has seen

/// What this device remembers about the tips: how many launches each has shown on, and which are done. A tip shows
/// on at most `launchesToShow` launches, as often as its place comes on screen within one, so a note the reader didn't
/// get to read comes back, and one they ignore stops asking.
struct FirstUseJournal: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        /// Launches the tip has shown on.
        var launches = 0
        /// The launch it last showed on.
        var lastLaunch: String?
        /// Closed, or the reader did what it says.
        var isDone = false
    }

    static let launchesToShow = 3

    var entries: [String: Entry] = [:]

    init(entries: [String: Entry] = [:]) {
        self.entries = entries
    }

    /// A journal where every tip but `open` is done: screenshot runs show only the tips they name.
    static func only(_ open: Set<FirstUseTip>) -> FirstUseJournal {
        var journal = FirstUseJournal()
        for tip in FirstUseTip.allCases where !open.contains(tip) { journal.finish(tip) }
        return journal
    }

    func entry(_ tip: FirstUseTip) -> Entry { entries[tip.rawValue] ?? Entry() }

    func isDone(_ tip: FirstUseTip) -> Bool { entry(tip).isDone }

    /// Done, or shown on enough launches already (it may still finish showing on the launch that used the last one).
    func isRetired(_ tip: FirstUseTip, launch: String) -> Bool {
        let entry = entry(tip)
        if entry.isDone { return true }
        return entry.launches >= Self.launchesToShow && entry.lastLaunch != launch
    }

    /// The tip a place has for the reader on this launch: its first one not retired.
    func next(at place: FirstUsePlace, launch: String) -> FirstUseTip? {
        place.tips.first { !isRetired($0, launch: launch) }
    }

    /// The tip came on screen. Counts once per launch.
    mutating func noteShown(_ tip: FirstUseTip, launch: String) {
        var entry = entry(tip)
        guard !entry.isDone, entry.lastLaunch != launch else { return }
        entry.launches += 1
        entry.lastLaunch = launch
        entries[tip.rawValue] = entry
    }

    /// The reader closed the tip, or did what it says: it never shows again.
    mutating func finish(_ tip: FirstUseTip) {
        var entry = entry(tip)
        entry.isDone = true
        entries[tip.rawValue] = entry
    }

    /// Nothing seen: every tip shows again as the reader comes to it.
    var isFresh: Bool { entries.values.allSatisfy { !$0.isDone && $0.launches == 0 } }
}

// MARK: - One tip out at a time

/// Which tip is out at each place right now, so a place shows one at a time and, once the reader closes it, the next
/// waits for the next visit instead of popping up in its place.
struct FirstUseStage: Equatable, Sendable {
    private(set) var out: [FirstUsePlace: FirstUseTip] = [:]

    /// A screen holding `tip` came into view. If its place has nothing out and `tip` is the place's next one, it goes
    /// out. Returns whether it did (the caller notes it as shown).
    mutating func arrive(_ tip: FirstUseTip, journal: FirstUseJournal, launch: String) -> Bool {
        guard out[tip.place] == nil, journal.next(at: tip.place, launch: launch) == tip else { return false }
        out[tip.place] = tip
        return true
    }

    /// The screen holding `tip` left. Its place is free for the next visit.
    mutating func leave(_ tip: FirstUseTip) {
        if out[tip.place] == tip { out[tip.place] = nil }
    }

    /// Whether `tip` is on screen: out at its place and not done.
    func isShowing(_ tip: FirstUseTip, journal: FirstUseJournal) -> Bool {
        out[tip.place] == tip && !journal.isDone(tip)
    }

    mutating func clear() { out = [:] }
}
