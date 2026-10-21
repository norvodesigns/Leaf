import SwiftUI
import UIKit

// MARK: - The wall

/// The Finished shelf as a wall of spines (Library, Finished, shown as a shelf): a shelf for each year, newest on top,
/// each year's books standing in the order they were finished. A spine is as thick as the book is long, as tall as its
/// id says, in the colour of its real cover when Leaf has seen it (its generated cover's palette until then), with a
/// ribbon hanging from the favourites and a tea ring on the ones read with tea. Tap a spine to open the book; hold it
/// to pull it out and see when it was finished and how it was rated. The books' shadows on the back of the shelf
/// shift a little as the phone tilts (`ParallaxTilt`), never under Reduce Motion.
///
/// Built for long shelves: the wall is worked out once per change to the library, rows are packed to the width and
/// drawn lazily, and a spine's cover colour is read once and remembered.
struct LibraryShelfWall: View {
    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var width: CGFloat = 0
    @State private var held: String?
    @State private var poster: ShelfPosterRequest?
    @State private var isTilting = false
    @State private var cache = ShelfWallCache()

    static let shelfHeight: CGFloat = 132

    var body: some View {
        let wall = cache.wall(for: store.data, calendar: store.calendar)
        // One container, so the sheet and the tilt stay put while the wall swaps in once it knows its width.
        VStack(alignment: .leading, spacing: 0) {
            if wall.isEmpty {
                EmptyState(title: "Your finished books will live here.", message: "")
            } else if width > 0 {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(wall.years) { year in
                        header(year)
                        ForEach(rows(year)) { row in
                            ShelfPlankRow(spines: row.spines, shelfHeight: Self.shelfHeight, bleed: Space.margin, parallax: isTilting) { spine in
                                spineView(spine)
                            }
                            .padding(.bottom, Space.l)
                        }
                    }
                }
            } else {
                Color.clear.frame(height: Self.shelfHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            width = newWidth
        }
        .onAppear {
            startTilt()
            applyStage(wall)
        }
        .onDisappear(perform: stopTilt)
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { stopTilt() } else { startTilt() }
        }
        .sheet(item: $poster) { request in
            if let year = wall.years.first(where: { $0.year == request.year }) {
                ShelfPosterSheet(year: year)
            }
        }
    }

    private struct Row: Identifiable {
        let spines: [ShelfSpine]
        var id: String { spines.first?.id ?? "" }
    }

    private func rows(_ year: ShelfWall.Year) -> [Row] {
        ShelfWall.rows(year.spines, width: Double(width), spacing: Double(ShelfPlankRow<EmptyView>.spacing)).map { Row(spines: $0) }
    }

    private func header(_ year: ShelfWall.Year) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .lastTextBaseline, spacing: Space.m) {
                Text(String(year.year))
                    .leafStyle(.display)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Space.m)
                Eyebrow(ShelfWallText.count(year))
                Button {
                    Haptics.shared.tap()
                    poster = ShelfPosterRequest(year: year.year)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(Color.accent)
                        .frame(width: Space.hitTarget, height: Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Share the \(String(year.year)) shelf")
            }
            Hairline()
        }
        .padding(.top, Space.l)
        .padding(.bottom, Space.l)
    }

    private func spineView(_ spine: ShelfSpine) -> some View {
        let isHeld = held == spine.id
        return ShelfSpineView(spine: spine, shelfHeight: Self.shelfHeight, isLifted: isHeld)
            .contentShape(.rect)
            .onTapGesture { open(spine) }
            .onLongPressGesture(minimumDuration: 0.35) { hold(spine) }
            .popover(isPresented: heldBinding(spine.id), attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                SpineSlip(spine: spine, teaName: teaName(spine), calendar: store.calendar) {
                    held = nil
                    open(spine)
                }
                .presentationCompactAdaptation(.popover)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(spine.book.title) by \(spine.book.author)")
            .accessibilityValue(ShelfWallText.spokenDetails(spine, teaName: teaName(spine), calendar: store.calendar))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the book")
            .accessibilityAction { open(spine) }
            .accessibilityAction(named: "When it was finished") { hold(spine) }
    }

    private func heldBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { held == id },
            set: { isPresented in
                if !isPresented, held == id {
                    withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) { held = nil }
                }
            }
        )
    }

    private func open(_ spine: ShelfSpine) {
        Haptics.shared.tap()
        router.libraryPath.append(BookRoute(book: store.item(spine.book.id)?.book ?? spine.book))
    }

    private func hold(_ spine: ShelfSpine) {
        Haptics.shared.selection()
        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
            held = spine.id
        }
    }

    private func teaName(_ spine: ShelfSpine) -> String? {
        TeaShelf.tea(id: spine.teaID, cabinet: store.data.cabinet)?.name
    }

    private func startTilt() {
        guard !reduceMotion, !isTilting else { return }
        isTilting = true
        ParallaxTilt.shared.start()
    }

    private func stopTilt() {
        guard isTilting else { return }
        isTilting = false
        ParallaxTilt.shared.stop()
    }

    /// Screenshots: a spine pulled out (`shelf.slip`) or the year's poster (`shelf.poster`).
    private func applyStage(_ wall: ShelfWall) {
        guard let stage = router.libraryStage, let year = wall.years.first else { return }
        router.libraryStage = nil
        switch stage {
        case "slip":
            let pick = year.spines.last { $0.isFavorite && $0.hasTea } ?? year.spines.last { $0.isFavorite } ?? year.spines.last
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                held = pick?.id
            }
        case "poster":
            poster = ShelfPosterRequest(year: year.year)
        default:
            break
        }
    }
}

struct ShelfPosterRequest: Identifiable, Hashable {
    let year: Int
    var id: Int { year }
}

/// Works the wall out again only when the library has changed in a way the wall can show.
@MainActor
private final class ShelfWallCache {
    private var key: Int?
    private var wall = ShelfWall(years: [])

    func wall(for data: LeafData, calendar: Calendar) -> ShelfWall {
        var hasher = Hasher()
        hasher.combine(data.items.count)
        for item in data.items {
            hasher.combine(item.id)
            hasher.combine(item.updatedAt)
            hasher.combine(item.shelf)
            hasher.combine(item.finishedAt)
            hasher.combine(item.rating)
            hasher.combine(item.reads.count)
            hasher.combine(item.book.title)
        }
        hasher.combine(data.sessions.count)
        hasher.combine(calendar.timeZone.identifier)
        let next = hasher.finalize()
        if next != key {
            key = next
            wall = ShelfWall.build(data: data, calendar: calendar)
        }
        return wall
    }
}

// MARK: - A shelf

/// One plank of spines: the books standing on it, their shadows on the back of the shelf (which drift a little with
/// the tilt), and the plank itself, bleeding past the margins like a shelf fixed to the wall.
struct ShelfPlankRow<Spine: View>: View {
    let spines: [ShelfSpine]
    let shelfHeight: CGFloat
    /// How far the plank reaches past the content on each side.
    var bleed: CGFloat = 0
    var parallax = false
    @ViewBuilder let spine: (ShelfSpine) -> Spine

    static var spacing: CGFloat { 2 }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: Self.spacing) {
                ForEach(spines) { item in
                    spine(item)
                }
            }
            .frame(maxWidth: .infinity, minHeight: shelfHeight, alignment: .bottomLeading)
            .background(alignment: .bottomLeading) {
                SpineShadows(spines: spines, shelfHeight: shelfHeight, parallax: parallax)
            }
            .zIndex(1)
            ShelfPlank()
                .padding(.horizontal, -bleed)
        }
    }
}

/// The books' shadows on the back of the shelf, all in one drawing. With parallax on, they slide the opposite way to
/// the tilt, so the books seem to stand a little in front of the wall.
private struct SpineShadows: View {
    let spines: [ShelfSpine]
    let shelfHeight: CGFloat
    let parallax: Bool

    var body: some View {
        let tilt = parallax ? ParallaxTilt.shared.tilt : .zero
        let shift = CGSize(width: 3 - 14 * tilt.x, height: -2 + 6 * tilt.y)
        Canvas { context, size in
            var x: CGFloat = 0
            var path = Path()
            for spine in spines {
                let width = CGFloat(spine.width)
                let height = shelfHeight * CGFloat(spine.height)
                path.addRoundedRect(
                    in: CGRect(x: x + shift.width, y: size.height - height + shift.height, width: width, height: height),
                    cornerSize: CGSize(width: 2, height: 2)
                )
                x += width + ShelfPlankRow<EmptyView>.spacing
            }
            context.fill(path, with: .color(Color.coverShadow.opacity(0.13)))
        }
        .frame(height: shelfHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A plank: its top in the light, its front edge, and the soft shadow it throws on the wall below.
struct ShelfPlank: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(ShelfColor.plankTop).frame(height: 5)
            Rectangle().fill(ShelfColor.plankFront).frame(height: 8)
            LinearGradient(colors: [Color.coverShadow.opacity(0.14), Color.coverShadow.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 9)
        }
        .accessibilityHidden(true)
    }
}

enum ShelfColor {
    static let plankTop = Color(uiColor: .leafDynamic(light: 0xE2D2B4, dark: 0x3D3128))
    static let plankFront = Color(uiColor: .leafDynamic(light: 0xC9B28C, dark: 0x2B231C))
    /// A tea ring that shows on dark and light cloth alike.
    static let teaStain = Color(hex: 0xC9955F)
}

// MARK: - A spine

/// The colours of one spine: the cloth, the lettering and the bands.
struct SpineTint: Hashable {
    var background: Color
    var foreground: Color
    var rule: Color

    init(background: Color, foreground: Color, rule: Color) {
        self.background = background
        self.foreground = foreground
        self.rule = rule
    }

    init(palette: CoverPalette) {
        self.init(background: palette.background, foreground: palette.foreground, rule: palette.rule)
    }

    /// The cover scan's average colour, made a little richer and kept in a bookish brightness, with lettering that
    /// reads on it.
    @MainActor
    static func from(scan: UIImage) -> SpineTint? {
        guard let average = CoverBackdropRenderer.grid(of: scan, side: 1)?.first else { return nil }
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(average).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return nil }
        let cloth = UIColor(hue: hue, saturation: min(1, saturation * 1.2), brightness: min(0.82, max(0.22, brightness * 0.92)), alpha: 1)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        cloth.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance: CGFloat = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        let lettering = luminance > 0.55 ? Color(hex: 0x1F1A14) : Color(hex: 0xF3E9D7)
        return SpineTint(background: Color(uiColor: cloth), foreground: lettering, rule: lettering.opacity(0.5))
    }
}

/// Spine colours read from cover scans, once per book.
@MainActor
final class SpineTints {
    static let shared = SpineTints()

    private var tints: [String: SpineTint] = [:]

    private init() {}

    /// The colour from a scan Leaf already holds, or nil.
    func cached(_ book: Book) -> SpineTint? {
        if let hit = tints[book.id] { return hit }
        guard let url = BookCover.imageURL(for: book, size: .m), let scan = CoverImageCache.shared.cachedImage(for: url),
              let tint = SpineTint.from(scan: scan) else { return nil }
        tints[book.id] = tint
        return tint
    }

    /// The colour from the scan, fetching it (the same small scan the cover grid uses) when it isn't held yet.
    func load(_ book: Book) async -> SpineTint? {
        if let hit = cached(book) { return hit }
        guard let url = BookCover.imageURL(for: book, size: .m), let scan = await CoverImageCache.shared.image(for: url),
              let tint = SpineTint.from(scan: scan) else { return nil }
        tints[book.id] = tint
        return tint
    }

    /// The colour to draw now: the scan's when held, otherwise the generated cover's palette.
    func current(_ book: Book) -> SpineTint {
        cached(book) ?? SpineTint(palette: CoverPalette(book: book))
    }
}

/// A book's spine: cloth with a rounded, lit edge, two bands, the title running down it (and the author's surname on a
/// thick one), a ribbon tail for a five-star read and a tea ring for a read with tea. `tint` fixes the colours (the
/// poster); without it the spine shows its cover's colour once known.
struct ShelfSpineView: View {
    let spine: ShelfSpine
    let shelfHeight: CGFloat
    var isLifted = false
    var tint: SpineTint?

    @State private var loaded: SpineTint?

    init(spine: ShelfSpine, shelfHeight: CGFloat, isLifted: Bool = false, tint: SpineTint? = nil) {
        self.spine = spine
        self.shelfHeight = shelfHeight
        self.isLifted = isLifted
        self.tint = tint
        _loaded = State(initialValue: tint == nil ? SpineTints.shared.cached(spine.book) : nil)
    }

    private var width: CGFloat { CGFloat(spine.width) }
    private var height: CGFloat { shelfHeight * CGFloat(spine.height) }
    private var colors: SpineTint { tint ?? loaded ?? SpineTint(palette: CoverPalette(book: spine.book)) }

    var body: some View {
        let colors = colors
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        shape
            .fill(colors.background)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.18), location: 0),
                        .init(color: .white.opacity(0), location: 0.32),
                        .init(color: .black.opacity(0), location: 0.62),
                        .init(color: .black.opacity(0.22), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .overlay { bands(colors) }
            .overlay { lettering(colors) }
            .overlay(alignment: .top) {
                if spine.hasTea { teaRing }
            }
            .clipShape(shape)
            .frame(width: width, height: height)
            .overlay(alignment: .bottomLeading) {
                if spine.isFavorite { ribbonTail }
            }
            .offset(y: isLifted ? -12 : 0)
            .task(id: spine.book.id) {
                guard tint == nil, loaded == nil else { return }
                if let found = await SpineTints.shared.load(spine.book) {
                    withAnimation(Motion.coverFade) { loaded = found }
                }
            }
    }

    private func bands(_ colors: SpineTint) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(colors.rule).frame(height: 1.5)
                .padding(.top, 9)
            Spacer(minLength: 0)
            Rectangle().fill(colors.rule).frame(height: 1.5)
                .padding(.bottom, 11)
        }
        .accessibilityHidden(true)
    }

    /// The title runs down the spine, top to bottom, as English spines do.
    private func lettering(_ colors: SpineTint) -> some View {
        let size = min(11, max(7, width * 0.38))
        let showsAuthor = width >= 30
        return VStack(alignment: .leading, spacing: 1) {
            Text(spine.book.title)
                .font(.custom(LeafFontName.regular, fixedSize: size))
                .lineLimit(1)
            if showsAuthor {
                Text(ShelfWallText.surname(spine.book.author).uppercased())
                    .font(.system(size: 6.5, weight: .semibold))
                    .tracking(0.6)
                    .lineLimit(1)
                    .opacity(0.8)
            }
        }
        .foregroundStyle(colors.foreground)
        .frame(width: max(0, height - 36), alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .rotationEffect(.degrees(90))
        .accessibilityHidden(true)
    }

    /// A cup's ring near the head of the spine, partly off its edge.
    private var teaRing: some View {
        let diameter = max(16, width * 1.05)
        return ZStack {
            Circle().stroke(ShelfColor.teaStain.opacity(0.7), lineWidth: 1.3)
            Circle()
                .trim(from: 0.05, to: 0.38)
                .stroke(ShelfColor.teaStain.opacity(0.45), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(Double(spine.book.paletteSeed % 360)))
        }
        .frame(width: diameter, height: diameter)
        .offset(x: width * 0.32, y: 16)
        .accessibilityHidden(true)
    }

    /// A satin tail hanging from the foot of the book, over the front of the plank.
    private var ribbonTail: some View {
        let ribbonWidth = min(7, max(4, width * 0.26))
        return SwallowtailRibbon()
            .fill(Color.ribbon)
            .overlay {
                SwallowtailRibbon()
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing))
            }
            .frame(width: ribbonWidth, height: 22)
            .offset(x: width * 0.6 - ribbonWidth / 2, y: 18)
            .accessibilityHidden(true)
    }
}

/// A strip with a swallowtail notch at its foot.
struct SwallowtailRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let notch = min(rect.width * 0.6, rect.height * 0.25)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - notch))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Held out

/// What a spine shows when it is held: like the date slip in a library book, when it was finished, how it was rated,
/// how often it was read that year and with which tea, and the way into the book.
struct SpineSlip: View {
    let spine: ShelfSpine
    let teaName: String?
    let calendar: Calendar
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spine.book.title)
                    .leafStyle(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(spine.book.author)
                    .leafStyle(.caption)
                    .lineLimit(1)
            }
            Hairline()
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Finished")
                Spacer(minLength: Space.m)
                Text(ShelfWallText.finishedDate(spine, calendar: calendar))
                    .leafStyle(.data)
            }
            HStack(alignment: .firstTextBaseline) {
                Eyebrow("Rated")
                Spacer(minLength: Space.m)
                if let rating = spine.rating {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            Image(systemName: index < rating ? "star.fill" : "star")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(Color.accent)
                } else {
                    Text("Not rated").leafStyle(.caption)
                }
            }
            if let line = ShelfWallText.extraLine(spine, teaName: teaName) {
                Text(line)
                    .leafStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextButton("Open the book", action: open)
                .padding(.top, Space.xs)
        }
        .padding(Space.l)
        .frame(width: 248, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Words

enum ShelfWallText {
    /// "11 books", "1 book", "12 books, 13 reads".
    static func count(_ year: ShelfWall.Year) -> String {
        let books = year.spines.count == 1 ? "1 book" : "\(year.spines.count) books"
        return year.finishes > year.spines.count ? "\(books), \(year.finishes) reads" : books
    }

    /// "Station Eleven" by "Emily St. John Mandel" stands as MANDEL.
    static func surname(_ author: String) -> String {
        let first = author.split(separator: ",").first.map(String.init) ?? author
        return first.split(separator: " ").last.map(String.init) ?? first
    }

    /// "3 March 2026", or "Some time in 2025" for a book marked finished without a date.
    static func finishedDate(_ spine: ShelfSpine, calendar: Calendar) -> String {
        guard let date = spine.finishedAt else { return "Some time in \(String(spine.year))" }
        return LeafFormat.format(date, template: "dMMMMyyyy", calendar: calendar)
    }

    /// "Read twice that year, with Earl Grey." and its parts.
    static func extraLine(_ spine: ShelfSpine, teaName: String?) -> String? {
        var parts: [String] = []
        if spine.finishes == 2 {
            parts.append("Read twice that year")
        } else if spine.finishes > 2 {
            parts.append("Read \(spine.finishes) times that year")
        }
        if let teaName {
            parts.append(parts.isEmpty ? "Read with \(teaName)" : "with \(teaName)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ") + "."
    }

    /// What VoiceOver reads after the title.
    static func spokenDetails(_ spine: ShelfSpine, teaName: String?, calendar: Calendar) -> String {
        var parts = ["Finished \(finishedDate(spine, calendar: calendar))"]
        parts.append(spine.rating.map { "rated \($0) out of 5" } ?? "not rated")
        if let extra = extraLine(spine, teaName: teaName) { parts.append(extra.trimmingCharacters(in: CharacterSet(charactersIn: "."))) }
        return parts.joined(separator: ", ")
    }

    static func posterTitle(_ year: ShelfWall.Year) -> String {
        year.spines.count == 1 ? "One book." : "\(year.spines.count) books."
    }
}

// MARK: - Poster

/// A year's shelf as a share image: the year, the count and the pages, up to three planks of spines in their real
/// colours where Leaf has them, and the wordmark.
struct ShelfPoster: View {
    let year: ShelfWall.Year
    let tints: [String: SpineTint]

    static let size = CGSize(width: 360, height: 640)
    static let shelfHeight: CGFloat = 112
    static let maximumRows = 3

    var body: some View {
        let rows = ShelfWall.rows(
            year.spines, width: Double(Self.size.width - Space.xxl * 2), spacing: Double(ShelfPlankRow<EmptyView>.spacing)
        )
        let shown = Array(rows.prefix(Self.maximumRows))
        let more = rows.dropFirst(Self.maximumRows).reduce(0) { $0 + $1.count }
        // Taller books when there are only a plank or two to fill the card.
        let height: CGFloat = shown.count <= 2 ? 150 : Self.shelfHeight
        VStack(alignment: .leading, spacing: Space.m) {
            Eyebrow("My \(String(year.year)) shelf")
            Text(ShelfWallText.posterTitle(year))
                .leafStyle(.display)
            Text("\(LeafFormat.number(year.pages)) pages, finished one by one.")
                .leafStyle(.pullQuote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            ForEach(Array(shown.enumerated()), id: \.offset) { _, row in
                ShelfPlankRow(spines: row, shelfHeight: height, bleed: Space.xxl) { spine in
                    ShelfSpineView(spine: spine, shelfHeight: height, tint: tints[spine.book.id] ?? SpineTint(palette: CoverPalette(book: spine.book)))
                }
                .padding(.bottom, Space.s)
            }
            if more > 0 {
                Text("and \(more) more")
                    .leafStyle(.caption)
            }
            Spacer(minLength: 0)
            HStack(alignment: .lastTextBaseline) {
                Text(ShelfWallText.favouritesLine(year))
                    .leafStyle(.caption, color: .inkTertiary)
                    .lineLimit(2)
                Spacer(minLength: Space.m)
                Text("Leaf").leafStyle(.wordmark)
            }
        }
        .padding(Space.xxl)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color.paper)
    }
}

extension ShelfWallText {
    /// "3 favourites, 7 with tea."
    static func favouritesLine(_ year: ShelfWall.Year) -> String {
        let favourites = year.spines.filter(\.isFavorite).count
        let tea = year.spines.filter(\.hasTea).count
        var parts: [String] = []
        if favourites > 0 { parts.append(favourites == 1 ? "1 favourite" : "\(favourites) favourites") }
        if tea > 0 { parts.append("\(tea) read with tea") }
        return parts.isEmpty ? "" : parts.joined(separator: ", ") + "."
    }
}

/// The poster for one year, with the share sheet.
struct ShelfPosterSheet: View {
    let year: ShelfWall.Year

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    private let previewScale: CGFloat = 0.78

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    poster
                        .scaleEffect(previewScale, anchor: .topLeading)
                        .frame(width: ShelfPoster.size.width * previewScale, height: ShelfPoster.size.height * previewScale, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                        .environment(\.colorScheme, .light)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Your \(String(year.year)) shelf: \(ShelfWallText.count(year)).")
                    if let image {
                        ShareLink(
                            item: Image(uiImage: image),
                            preview: SharePreview("My \(String(year.year)) shelf", image: Image(uiImage: image))
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(LeafType.ui)
                                .foregroundStyle(Color.paper)
                                .frame(maxWidth: .infinity, minHeight: Space.hitTarget)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ink)
                    }
                }
                .leafMargins()
                .padding(.vertical, Space.l)
            }
            .scrollIndicators(.hidden)
            .paperBackground()
            .navigationTitle("Your \(String(year.year)) shelf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        Haptics.shared.tap()
                        dismiss()
                    }
                }
            }
            .task(id: year) {
                image = SharePoster.render(poster, size: ShelfPoster.size)
            }
        }
        .presentationBackground(Color.paper)
    }

    private var poster: ShelfPoster {
        var tints: [String: SpineTint] = [:]
        for spine in year.spines {
            tints[spine.book.id] = SpineTints.shared.current(spine.book)
        }
        return ShelfPoster(year: year, tints: tints)
    }
}
