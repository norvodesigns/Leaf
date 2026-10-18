import Foundation

/// How ribbon depth is spread over a book's pages.
enum RibbonDepthCurve: Sendable, Equatable {
    /// Depth is the share of pages read. Fine for short books.
    case linear
    /// Gives the first pages more room. 0 is linear and 1 is the strongest. A thousand-page novel on a linear block puts
    /// its first fifty pages in the top 5 percent, a few points of travel, which is too cramped to place a bookmark.
    case expanded(strength: Double)
    /// Linear for short books, and more expanded as the page count grows past about 250.
    case automatic
}

/// Maps between how far down the page block the ribbon hangs (depth 0 at the top, 1 at the last page) and a page number
/// in a book. Pure and monotonic: further down never means an earlier page, and every page has a depth that maps back
/// to it, so the bookmark can both set and show progress.
///
/// The spine of the maths is `fraction = depth ^ exponent`. An exponent above 1 stretches the top of the block (small
/// depths cover few pages), which is what the expanded curves use.
struct RibbonDepthMapping: Sendable, Equatable {
    /// Pages in the book. Zero or less means the length is unknown and every depth maps to page 0.
    let pages: Int
    let curve: RibbonDepthCurve

    init(pages: Int, curve: RibbonDepthCurve = .automatic) {
        self.pages = max(pages, 0)
        self.curve = curve
    }

    /// The exponent the curve resolves to for this book: 1 is linear, up to 1.9.
    var exponent: Double {
        switch curve {
        case .linear:
            return 1
        case .expanded(let strength):
            return 1 + 0.9 * InteractionMath.clamp(InteractionMath.finite(strength), 0, 1)
        case .automatic:
            return 1 + 0.9 * 0.7 * InteractionMath.smoothstep(250, 1500, Double(pages))
        }
    }

    // MARK: Depth and page

    /// The page a ribbon at `depth` marks, 0...pages. Depth outside 0...1 (a drag past the ends) is clamped, and a
    /// non-number counts as the top.
    func page(forDepth depth: Double) -> Int {
        guard pages > 0 else { return 0 }
        let clamped = InteractionMath.clamp(depth, 0, 1)
        let fraction = pow(clamped, exponent)
        return min(max(Int((fraction * Double(pages)).rounded()), 0), pages)
    }

    /// Where the ribbon hangs for `page`, 0...1. The inverse of `page(forDepth:)` for every page in the book.
    func depth(forPage page: Int) -> Double {
        guard pages > 0 else { return 0 }
        let fraction = Double(min(max(page, 0), pages)) / Double(pages)
        return InteractionMath.clamp(pow(fraction, 1 / exponent), 0, 1)
    }

    /// How many pages one whole block of depth covers right here. Small at the top of an expanded block, large at the
    /// bottom. The feel of the drag, and what turns finger speed into pages per second.
    func pagesPerDepth(at depth: Double) -> Double {
        guard pages > 0 else { return 0 }
        let clamped = InteractionMath.clamp(depth, 0, 1)
        return Double(pages) * exponent * pow(clamped, exponent - 1)
    }

    // MARK: Snapping

    /// The page for `depth` while the finger moves at `depthVelocity` (block-heights per second, either sign). A slow
    /// drag lands on single pages; a fast one rounds to 5, 10, 25 or 50, so a flick across a thick book doesn't fight
    /// for individual pages. The first and last pages are always reachable.
    func snappedPage(forDepth depth: Double, depthVelocity: Double) -> Int {
        let raw = page(forDepth: depth)
        let pagesPerSecond = pagesPerDepth(at: depth) * (depthVelocity.isNaN ? 0 : abs(depthVelocity))
        let step = RibbonPageSnap.step(forPagesPerSecond: pagesPerSecond, pages: pages)
        return RibbonPageSnap.snap(raw, step: step, pages: pages)
    }

    // MARK: The stylised book edge

    /// How thick the page block looks, 0 (no pages) to 1 (1,500 pages and up). Logarithmic, because a 1,200-page book is
    /// thicker than a 300-page one but not four times as thick on a phone.
    static func pageBlockThickness(forPages pages: Int) -> Double {
        guard pages > 0 else { return 0 }
        return InteractionMath.clamp(log(1 + Double(pages) / 60) / log(1 + 1500.0 / 60), 0, 1)
    }

    /// The thickness in points, between `minimum` (a novella) and `maximum` (a doorstop).
    static func pageBlockThickness(forPages pages: Int, from minimum: Double, to maximum: Double) -> Double {
        InteractionMath.lerp(minimum, maximum, pageBlockThickness(forPages: pages))
    }

    /// How many page lines to draw along the edge: 3 for a pamphlet up to 12 for a brick.
    static func edgeLineCount(forPages pages: Int) -> Int {
        3 + Int((pageBlockThickness(forPages: pages) * 9).rounded())
    }

    /// A tidy spacing for page markers beside the block, so there are at most about a dozen: 10, 25, 50, 100, 250, 500.
    static func markerStep(forPages pages: Int) -> Int {
        for step in [10, 25, 50, 100, 250, 500] where pages / step <= 12 { return step }
        return 1000
    }

    /// Depths of the page markers, every `step` pages, leaving out the first and last page. Capped at `limit` markers by
    /// thinning evenly, so a huge book can't flood the view.
    func markerDepths(everyPages step: Int, limit: Int = 40) -> [Double] {
        guard pages > 1, step > 0, limit > 0 else { return [] }
        let count = (pages - 1) / step
        guard count > 0 else { return [] }
        let thinning = max(1, Int((Double(count) / Double(limit)).rounded(.up)))
        return stride(from: 1, through: count, by: thinning).map { depth(forPage: $0 * step) }
    }
}

/// Picks how coarsely a fast drag lands on pages.
enum RibbonPageSnap {
    /// The steps a drag can snap to, finest first.
    static let steps = [1, 5, 10, 25, 50]

    /// The step for a drag moving through `pagesPerSecond` pages. Below 20 pages a second it's single pages; above 500
    /// it's 50. A step is only allowed when the book has at least a dozen of them, so a 120-page book never snaps to 50.
    static func step(forPagesPerSecond pagesPerSecond: Double, pages: Int) -> Int {
        let speed = pagesPerSecond.isNaN ? 0 : max(pagesPerSecond, 0)
        let wanted: Int
        switch speed {
        case ..<20: wanted = 1
        case ..<80: wanted = 5
        case ..<200: wanted = 10
        case ..<500: wanted = 25
        default: wanted = 50
        }
        return steps.last { $0 <= wanted && $0 * 12 <= max(pages, 12) } ?? 1
    }

    /// The nearest multiple of `step`, or the first or last page when one of those is closer. Never outside 0...pages,
    /// and never earlier for a later `page`.
    static func snap(_ page: Int, step: Int, pages: Int) -> Int {
        guard pages > 0 else { return 0 }
        let clamped = min(max(page, 0), pages)
        guard step > 1 else { return clamped }
        let below = (clamped / step) * step
        let above = min(below + step, pages)
        var best = below
        for candidate in [above, 0, pages] where abs(candidate - clamped) < abs(best - clamped) {
            best = candidate
        }
        return best
    }
}
