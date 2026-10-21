import SwiftUI

/// The haptics map (docs/design/REDESIGN.md §6). Screens name the moment; this decides how it feels, through
/// `Haptics.shared`, which follows Settings → Feel. No screen calls a feedback generator directly.
enum CanopyFeel: String, CaseIterable {
    /// Begin reading, start a session.
    case start
    /// A session paused.
    case pause
    /// A session resumed.
    case resume
    /// Done: the session ends.
    case finishSession
    /// Pages saved after a session or a quick log.
    case pageLogged
    /// Today's goal reached.
    case goalReached
    /// A book finished. Pass the book's heft to `play(_:heft:)`.
    case bookFinished
    /// The kettle poured: a steep begins.
    case steepStart
    /// Once a second through the steep's last three seconds.
    case countdown
    /// The tea is ready.
    case teaReady
    /// A reading time moved, a book swapped into a time, the plan mode switched.
    case planChanged
    /// A wheel or dial detent, a chip, a toggle, a tab.
    case select
    /// A detent that matters (the hour on a time wheel, the forecast page on the page dial).
    case snap
    /// A swipe action crossing its threshold.
    case swipeThreshold
    /// The swipe deck: keep a book.
    case keep
    /// The swipe deck: start a book now.
    case startNow
    /// A row lifted to reorder.
    case lift
    /// A row dropped after reordering.
    case drop
    /// A secondary glass button.
    case tap
    /// Something can't be done.
    case warning

    /// What the reader feels, for the gallery and the docs.
    var pattern: String {
        switch self {
        case .start: return "A firm tap and a short low swell"
        case .pause: return "One soft, dull tap"
        case .resume: return "A light tap"
        case .finishSession: return "A swell into a firm tap"
        case .pageLogged: return "A soft brush, then a tap"
        case .goalReached: return "Two rising taps and a glow"
        case .bookFinished: return "Three rising taps, a swell, a cover closing"
        case .steepStart: return "A short low rumble, like pouring"
        case .countdown: return "A heartbeat"
        case .teaReady: return "Two soft clinks"
        case .planChanged: return "A crisp click with a soft echo"
        case .select: return "A selection tick"
        case .snap: return "A firm click with a small echo"
        case .swipeThreshold: return "A rigid knock"
        case .keep: return "A heavy tap that settles"
        case .startNow: return "A rising double tap"
        case .lift: return "A lift"
        case .drop: return "A drop"
        case .tap: return "A light tap"
        case .warning: return "A warning"
        }
    }

    @MainActor
    static func play(_ feel: CanopyFeel, heft: Double = 0) {
        let haptics = Haptics.shared
        switch feel {
        case .start: haptics.play(.sessionStart)
        case .pause: haptics.play(.pauseSettle)
        case .resume: haptics.tap()
        case .finishSession: haptics.play(.sessionEnd)
        case .pageLogged: haptics.play(.pageTurn)
        case .goalReached: haptics.play(.goalReached)
        case .bookFinished: haptics.play(.bookFinished, heft: heft)
        case .steepStart: haptics.play(.steepPour)
        case .countdown: haptics.play(.countdownBeat)
        case .teaReady: haptics.play(.teaReady)
        case .planChanged: haptics.play(.planChanged)
        case .select: haptics.selection()
        case .snap: haptics.play(.magnetSnap)
        case .swipeThreshold: haptics.rigid(0.6)
        case .keep: haptics.play(.deckKeep)
        case .startNow: haptics.play(.deckStart)
        case .lift: haptics.play(.reorderLift, heft: heft)
        case .drop: haptics.play(.reorderDrop, heft: heft)
        case .tap: haptics.tap()
        case .warning: haptics.warning()
        }
    }
}
