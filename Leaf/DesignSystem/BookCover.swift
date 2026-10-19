import SwiftUI
import UIKit

/// A book as a physical object: the generated cover, the real scan fading in on top, the hinge
/// finish, an optional bookmark ribbon and the cover shadow (DESIGN.md §5). Always 2:3.
///
/// The frame is exactly the cover, so it works directly as a zoom source:
/// `BookCover(book: book, size: .m).matchedTransitionSource(id: book.id, in: namespace)`.
/// With `ribbon: true` (M and up) the tail hangs `size.ribbonTail` below the frame; leave room for it.
struct BookCover: View {
    enum Size: CaseIterable, Hashable, Sendable {
        /// 24×36, the accessory.
        case xs
        /// 44×66, rows.
        case s
        /// 96×144, shelves and carousels.
        case m
        /// 140×210, Today hero and the finished moment.
        case l
        /// 200×300, book detail.
        case xl

        var width: CGFloat {
            switch self {
            case .xs: 24
            case .s: 44
            case .m: 96
            case .l: 140
            case .xl: 200
            }
        }

        var height: CGFloat { width * 1.5 }

        var dimensions: CGSize { CGSize(width: width, height: height) }

        var cornerRadius: CGFloat {
            switch self {
            case .xs, .s: Radius.coverSmall
            case .m, .l, .xl: Radius.cover
            }
        }

        /// Ribbons are drawn on M and up.
        var allowsRibbon: Bool {
            switch self {
            case .xs, .s: false
            case .m, .l, .xl: true
            }
        }

        /// How far a ribbon hangs below the cover.
        var ribbonTail: CGFloat { allowsRibbon ? height * 0.12 : 0 }

        /// Ambient shadow layer (the contact layer is the same for every size).
        var ambientShadow: (radius: CGFloat, y: CGFloat) {
            switch self {
            case .xs, .s: (3, 2)
            case .m: (6, 4)
            case .l: (10, 7)
            case .xl: (16, 12)
            }
        }

        /// Which Open Library scan to fetch.
        var imageSize: Book.CoverSize {
            switch self {
            case .xs, .s, .m: .medium
            case .l, .xl: .large
            }
        }
    }

    let book: Book
    let size: Size
    var ribbon: Bool
    var swaysRibbon: Bool
    var ribbonTucked: Bool

    @State private var image: UIImage?

    /// - Parameters:
    ///   - ribbon: hangs the physical `ribbon` bookmark (M and up only). It follows the phone's tilt, can be tugged,
    ///     and sleeps when still.
    ///   - swaysRibbon: flicks the ribbon each time the cover appears, then lets it breathe a moment (Today hero).
    ///   - ribbonTucked: slides the ribbon up out of sight (a finished book).
    init(book: Book, size: Size, ribbon: Bool = false, swaysRibbon: Bool = false, ribbonTucked: Bool = false) {
        self.book = book
        self.size = size
        self.ribbon = ribbon
        self.swaysRibbon = swaysRibbon
        self.ribbonTucked = ribbonTucked
        let cached = BookCover.imageURL(for: book, size: size).flatMap { CoverImageCache.shared.cachedImage(for: $0) }
        _image = State(initialValue: cached)
    }

    init(_ book: Book, size: Size, ribbon: Bool = false, swaysRibbon: Bool = false, ribbonTucked: Bool = false) {
        self.init(book: book, size: size, ribbon: ribbon, swaysRibbon: swaysRibbon, ribbonTucked: ribbonTucked)
    }

    /// The Open Library scan for `book` at `size`, with `?default=false` so missing covers 404.
    static func imageURL(for book: Book, size: Size) -> URL? {
        guard let base = book.coverURL(size.imageSize) else { return nil }
        return URL(string: base.absoluteString + "?default=false")
    }

    private var imageURL: URL? { BookCover.imageURL(for: book, size: size) }

    private var showsRibbon: Bool { ribbon && size.allowsRibbon }

    var body: some View {
        ZStack {
            GeneratedCover(book: book, showsFinish: false)
            if let image {
                CoverArtwork(image: image, size: size, background: CoverPalette(book: book).background)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            CoverFinish(cornerRadius: size.cornerRadius)
        }
        .clipShape(Radius.shape(size.cornerRadius))
        .coverShadow(size)
        .background(alignment: .topLeading) {
            if showsRibbon {
                ribbonView
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cover of \(book.title) by \(book.author)")
        .accessibilityAddTraits(.isImage)
        .task(id: imageURL) {
            await loadImage()
        }
    }

    /// The ribbon hangs from the cover's top edge at 70% across and shows `ribbonTail` below it; the cover hides the rest.
    private var ribbonView: some View {
        let width = size.width * 0.09
        let length = size.height + size.ribbonTail
        let canvas = PhysicalRibbon.canvasSize(length: length, width: width)
        return PhysicalRibbon(
            length: length,
            width: width,
            seed: UInt64(truncatingIfNeeded: book.paletteSeed),
            breathes: swaysRibbon,
            swaysOnAppear: swaysRibbon,
            isTucked: ribbonTucked,
            grabFrom: size.height
        )
        .offset(x: size.width * 0.70 + width / 2 - canvas.width / 2)
    }

    private func loadImage() async {
        guard let url = imageURL else {
            image = nil
            return
        }
        if let cached = CoverImageCache.shared.cachedImage(for: url) {
            image = cached
            return
        }
        image = nil
        guard let loaded = await CoverImageCache.shared.image(for: url), !Task.isCancelled else { return }
        withAnimation(Motion.coverFade) {
            image = loaded
        }
    }
}

/// The real scan, filled, or letterboxed on the palette colour when its aspect is off.
private struct CoverArtwork: View {
    let image: UIImage
    let size: BookCover.Size
    let background: Color

    var body: some View {
        let aspect = image.size.width / max(image.size.height, 1)
        if aspect >= 0.57 && aspect <= 0.77 {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            ZStack {
                background
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(size.width * 0.06)
            }
            .frame(width: size.width, height: size.height)
        }
    }
}

/// The shared hinge overlay and inner stroke that make scans and generated covers read as one shelf.
struct CoverFinish: View {
    var cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                // Spine shadow across the left 7%.
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.18), location: 0),
                        .init(color: Color.black.opacity(0), location: 0.07),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                // The hinge crease.
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 0.5)
                    .offset(x: width * 0.06)
                // Sheen.
                LinearGradient(
                    colors: [Color.white.opacity(0.06), Color.white.opacity(0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Radius.shape(cornerRadius)
                    .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.10) : Color.ink.opacity(0.12), lineWidth: 0.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// In-memory cover scans shared by every `BookCover`. HTTP caching (URLCache) covers relaunches.
/// Scans under 10 px wide, and 404s from `?default=false`, count as missing.
final class CoverImageCache: @unchecked Sendable {
    static let shared = CoverImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let lock = NSLock()
    private var missing = Set<URL>()

    private init() {
        memory.countLimit = 400
    }

    func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    /// Loads, validates and pre-decodes a scan. Returns nil when it's missing or unusable.
    func image(for url: URL) async -> UIImage? {
        if let hit = cachedImage(for: url) { return hit }
        if isKnownMissing(url) { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard status == 200, let decoded = UIImage(data: data), decoded.size.width * decoded.scale >= 10 else {
                markMissing(url)
                return nil
            }
            let prepared = await decoded.byPreparingForDisplay() ?? decoded
            memory.setObject(prepared, forKey: url as NSURL)
            return prepared
        } catch {
            // Offline or cancelled: try again next time.
            return nil
        }
    }

    private func isKnownMissing(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return missing.contains(url)
    }

    private func markMissing(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        missing.insert(url)
    }
}

#Preview("Covers") {
    let store = LibraryStore(persistence: .ephemeral())
    store.replaceAll(with: DemoData.make())
    let custom = Book(id: "custom-preview", title: "The Unwritten Shelf: Notes on Reading Slowly", author: "Ada Leaf", year: 2026, pages: 240)
    return ScrollView {
        VStack(alignment: .leading, spacing: Space.xxl) {
            HStack(alignment: .top, spacing: Space.l) {
                BookCover(book: DemoData.hobbit, size: .l, ribbon: true, swaysRibbon: true)
                BookCover(book: custom, size: .l)
            }
            HStack(alignment: .top, spacing: Space.m) {
                BookCover(book: DemoData.circe, size: .m, ribbon: true)
                BookCover(book: custom, size: .m)
                BookCover(book: DemoData.piranesi, size: .s)
                BookCover(book: custom, size: .s)
                BookCover(book: custom, size: .xs)
            }
            BookCover(book: custom, size: .xl)
        }
        .padding(Space.margin)
    }
    .paperBackground()
    .environment(store)
    .environment(AppRouter())
    .environment(BookCatalog.shared)
}
