import ActivityKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Keeps the reading Live Activity in step with the live session, or the pot steeping before it (NEXT.md section 11).
///
/// - Starts one when a session starts, or when tea goes on to steep for a book, and only while the app is in the
///   foreground (ActivityKit's rule). A steep that turns into the cup of reading for the same book carries on in the
///   same activity rather than ending one and starting another.
/// - The system mirrors the activity to the Apple Watch's Smart Stack (its small card is `ReadingActivityWatchCard`);
///   the watch is told which session it covers (`sessionShown`), so it never shows a second card of its own.
/// - Updates it on state changes only: pause, resume, a page logged, the goal crossed. The digits advance by themselves
///   (`Text(timerInterval:)`), and the stale date is the moment the goal will be reached, so the activity turns to
///   "goal met" on time even while the app sleeps.
/// - Ends it when the session ends or is discarded, when the reader turns Live Activities off, or when the system has
///   ended it. An activity lasts at most 8 hours, so a session still running after 7½ gets a fresh one the next
///   time the app is open.
///
/// `sync()` is cheap to call often: it only talks to ActivityKit when the content would change.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    /// Renew an activity this old the next time the app is in the foreground (the system ends them at 8 hours).
    static let renewAfter: TimeInterval = 7.5 * 3600

    private weak var store: LibraryStore?
    private var activity: Activity<ReadingActivityAttributes>?
    /// What the activity shows: "session:<id>" or "steep:<start>".
    private var key: String?
    /// The reading session the activity is showing, for the watch (nil for a steep or none).
    private(set) var sessionShown: UUID?
    private var startedAt: Date?
    private var lastContent: ReadingActivityContent?

    private init() {}

    func configure(store: LibraryStore) {
        self.store = store
        // An activity left over from an earlier launch: keep it if it is for the book being read, end it otherwise.
        let existing = Activity<ReadingActivityAttributes>.activities
        let liveBook = store.activeSession?.bookID
        for leftover in existing {
            if activity == nil, leftover.attributes.bookID == liveBook, leftover.activityState == .active {
                activity = leftover
                sessionShown = store.activeSession?.id
                key = sessionShown.map { "session:\($0)" }
                startedAt = Date()
            } else {
                end(leftover, closing: nil)
            }
        }
        sync()
    }

    /// Brings the activity in line with the store: start, update, end or nothing.
    func sync() {
        guard let store else { return }
        guard store.preferences.liveActivities, ActivityAuthorizationInfo().areActivitiesEnabled else {
            endCurrent()
            return
        }
        let now = Date()
        if let session = store.activeSession, let item = store.item(session.bookID) {
            show(key: "session:\(session.id)", sessionID: session.id, item: item, content: Self.content(for: session, item: item, store: store, now: now))
        } else if let steep = TeaSteepState.load(now: now), let item = Self.book(for: steep, store: store) {
            show(key: "steep:\(Int(steep.startedAt.timeIntervalSince1970))", sessionID: nil, item: item, content: Self.steepContent(steep, item: item, now: now))
        } else {
            endCurrent()
        }
    }

    private func show(key newKey: String, sessionID: UUID?, item: LibraryItem, content: ReadingActivityContent) {
        let isForeground = UIApplication.shared.applicationState == .active
        if let current = activity {
            let isGone = current.activityState == .ended || current.activityState == .dismissed
            let isOld = startedAt.map { Date().timeIntervalSince($0) > Self.renewAfter } ?? false
            // The tea is poured and the cup of reading begins, for the same book: one activity all the way through.
            let carriesOn = key?.hasPrefix("steep:") == true && newKey.hasPrefix("session:") && current.attributes.bookID == item.id
            if carriesOn && !isGone {
                key = newKey
                sessionShown = sessionID
                WatchBridge.shared.push()
            } else if key != newKey || isGone || (isOld && isForeground) {
                endCurrent()
            }
        }

        if let current = activity {
            guard content != lastContent else { return }
            lastContent = content
            let update = ActivityContent(state: content, staleDate: content.goalDate)
            Task { await current.update(update) }
        } else if isForeground {
            start(key: newKey, sessionID: sessionID, item: item, content: content)
        }
    }

    private func start(key newKey: String, sessionID: UUID?, item: LibraryItem, content: ReadingActivityContent) {
        let attributes = ReadingActivityAttributes(
            bookID: item.id,
            title: item.book.title,
            author: item.book.author,
            totalPages: item.book.pages,
            coverFileName: LiveActivityCover.prepare(book: item.book)
        )
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: content, staleDate: content.goalDate),
                pushType: nil
            )
            key = newKey
            sessionShown = sessionID
            startedAt = Date()
            lastContent = content
            WatchBridge.shared.push()
        } catch {
            // Live Activities off for Leaf, too many running, or not in the foreground after all: the session goes on.
            activity = nil
        }
    }

    private func endCurrent() {
        guard let current = activity else { return }
        var closing = lastContent
        closing?.state = .finishing
        end(current, closing: closing)
        activity = nil
        key = nil
        let wasShowingSession = sessionShown != nil
        sessionShown = nil
        startedAt = nil
        lastContent = nil
        if wasShowingSession { WatchBridge.shared.push() }
    }

    private func end(_ activity: Activity<ReadingActivityAttributes>, closing: ReadingActivityContent?) {
        let content = closing.map { ActivityContent(state: $0, staleDate: nil) }
        Task { await activity.end(content, dismissalPolicy: .immediate) }
    }

    // MARK: Content

    /// The tiny state for a session at `now`. Stable between state changes, so syncing often costs nothing.
    static func content(for session: ActiveSession, item: LibraryItem, store: LibraryStore, now: Date) -> ReadingActivityContent {
        let elapsed = session.elapsed(at: now)
        let goal = goalSeconds(for: session, store: store)
        let page = max(session.startPage, item.currentPage)

        let moment: LiveActivityMoment
        if session.isPaused {
            moment = .paused
        } else if let goal, elapsed >= Double(goal) {
            moment = .goalReached
        } else if item.pagesLeft > 0 && item.pagesLeft <= 20 {
            moment = .finishing
        } else {
            moment = .reading
        }
        let line = LiveActivityLines.line(
            for: moment,
            bookTitle: item.book.title,
            pagesLeft: item.pagesLeft,
            seed: SeededGenerator.hash("\(session.id)|\(moment.rawValue)")
        )

        let state: ReadingActivityState
        switch moment {
        case .paused: state = .paused
        case .goalReached: state = .goalReached
        case .reading, .finishing: state = .reading
        }

        return ReadingActivityContent(
            timerStart: session.startedAt.addingTimeInterval(session.pausedSeconds),
            isPaused: session.isPaused,
            pausedElapsedSeconds: Int(elapsed.rounded(.down)),
            goalSeconds: goal,
            currentPage: page,
            state: state,
            line: line,
            teaName: store.tea(id: session.teaID)?.name
        )
    }

    /// The book a steep is for: the one it was poured for, else the first being read. Nil when there is none, and then
    /// no activity, since one is always about a book.
    static func book(for steep: TeaSteepState, store: LibraryStore) -> LibraryItem? {
        if let id = steep.bookID, let item = store.item(id) { return item }
        return store.reading.first
    }

    /// The steep as the activity shows it: counting down to the tea, which the stale date turns to ready on time.
    static func steepContent(_ steep: TeaSteepState, item: LibraryItem, now: Date) -> ReadingActivityContent {
        ReadingActivityContent(
            timerStart: steep.startedAt,
            goalSeconds: steep.steepSeconds,
            currentPage: item.currentPage,
            state: steep.isReady(at: now) ? .teaReady : .steeping,
            teaName: steep.tea.name
        )
    }

    /// The cup for a tea ritual, else what was left of today's goal when the session began, else nothing.
    static func goalSeconds(for session: ActiveSession, store: LibraryStore) -> Int? {
        if let cup = session.goalSeconds, cup > 0 { return Int(cup.rounded()) }
        guard store.isReadingDay else { return nil }
        let goal = Double(store.preferences.dailyMinutes) * 60
        let readBefore = store.minutesReadToday * 60
        guard goal > 0, readBefore < goal else { return nil }
        return Int((goal - readBefore).rounded(.up))
    }
}

// MARK: - Cover pictures

/// Renders a book's cover small, and a heavily blurred copy for the Live Activity's backdrop, into the App Group
/// (NEXT.md section 7: blur pre-rendered bitmaps, never live). Uses the scan if one is cached, else the generated
/// cover. Returns the base file name for `ReadingActivityAttributes.coverFileName`, or nil if nothing could be written
/// (no App Group in an unsigned build, say). The activity then shows plain night paper.
@MainActor
enum LiveActivityCover {
    static let size = CGSize(width: 80, height: 120)

    static func prepare(book: Book) -> String? {
        guard let directory = ReadingActivityAssets.directory else { return nil }
        let base = ReadingActivityAssets.baseName(forBookID: book.id)
        guard let coverURL = ReadingActivityAssets.coverURL(base),
              let blurURL = ReadingActivityAssets.blurredCoverURL(base) else { return nil }
        let scan = cachedScan(for: book)
        let manager = FileManager.default
        // A generated cover never changes; a scan may arrive later and is worth rendering again.
        if scan == nil, manager.fileExists(atPath: coverURL.path), manager.fileExists(atPath: blurURL.path) {
            return base
        }
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let image = render(book, scan: scan), let sharp = image.jpegData(compressionQuality: 0.82) else { return nil }
            try sharp.write(to: coverURL, options: .atomic)
            if let blurred = blur(image)?.jpegData(compressionQuality: 0.7) {
                try blurred.write(to: blurURL, options: .atomic)
            }
            return base
        } catch {
            return nil
        }
    }

    /// The cover and its blurred copy without writing them anywhere (the debug gallery draws these).
    static func images(for book: Book) -> (cover: UIImage?, backdrop: UIImage?) {
        let image = render(book, scan: cachedScan(for: book))
        return (image, image.flatMap { blur($0) })
    }

    private static func cachedScan(for book: Book) -> UIImage? {
        for size in [BookCover.Size.l, .m, .s, .xl] {
            if let url = BookCover.imageURL(for: book, size: size), let image = CoverImageCache.shared.cachedImage(for: url) {
                return image
            }
        }
        return nil
    }

    private static func render(_ book: Book, scan: UIImage?) -> UIImage? {
        let content: AnyView
        if let scan {
            content = AnyView(
                Image(uiImage: scan)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
            )
        } else {
            content = AnyView(
                GeneratedCover(book: book, showsFinish: false)
                    .frame(width: size.width, height: size.height)
            )
        }
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        return renderer.uiImage
    }

    /// A soft, low-detail copy for the backdrop: blurred edge to edge (clamped, so the edges don't fade to clear).
    private static func blur(_ image: UIImage) -> UIImage? {
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter.gaussianBlur()
        filter.inputImage = input.clampedToExtent()
        filter.radius = 18
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let cgImage = CIContext().createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
