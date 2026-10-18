import Foundation

/// The reader's answer to "Where are you?". Progress is the whole model of the app, so starting from the right page
/// matters: every forecast and the first session's speed depend on it.
enum StartingPosition: Hashable, Sendable {
    /// Page one; nothing read yet.
    case justStarting
    /// "I'm on page 142." The page they have finished up to.
    case page(Int)
    /// "I'm 40 percent in" (e-readers show percentages, not pages).
    case percent(Double)
    /// "I've already read it." Goes to Finished, optionally with the date.
    case alreadyRead(on: Date?)

    /// The page this lands on in a book of `pages` pages, or nil for `alreadyRead` (which finishes the book).
    func page(inBookOf pages: Int) -> Int? {
        switch self {
        case .justStarting:
            return 0
        case .page(let page):
            return min(max(0, page), pages)
        case .percent(let percent):
            return LibraryItem.page(forPercent: percent, pages: pages)
        case .alreadyRead:
            return nil
        }
    }

    /// Whether the reader entered a percentage, so the book keeps showing percentages.
    var progressMode: ProgressMode {
        if case .percent = self { return .percent }
        return .pages
    }
}
