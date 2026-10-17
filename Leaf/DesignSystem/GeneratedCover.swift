import SwiftUI

/// A typeset cover for books without a scan (DESIGN.md §9). Fills whatever 2:3 frame it's given;
/// every dimension is relative to the cover width w and height h and nothing scales with Dynamic Type.
///
/// Usually you want `BookCover`, which draws this underneath the real scan. Use `GeneratedCover`
/// directly only for a bare cover (pass `showsFinish: false` if you add your own hinge finish).
struct GeneratedCover: View {
    let book: Book
    var showsFinish: Bool

    @Environment(\.displayScale) private var displayScale

    init(book: Book, showsFinish: Bool = true) {
        self.book = book
        self.showsFinish = showsFinish
    }

    init(_ book: Book, showsFinish: Bool = true) {
        self.init(book: book, showsFinish: showsFinish)
    }

    var body: some View {
        GeometryReader { proxy in
            artwork(width: proxy.size.width, height: proxy.size.height)
        }
        .overlay {
            if showsFinish {
                CoverFinish(cornerRadius: Radius.cover)
            }
        }
        .clipShape(Radius.shape(showsFinish ? Radius.cover : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cover of \(book.title) by \(book.author)")
        .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder
    private func artwork(width w: CGFloat, height h: CGFloat) -> some View {
        let palette = CoverPalette(book: book)
        let initial = GeneratedCover.initial(for: book.title)
        let pixel = 1 / max(displayScale, 1)
        ZStack(alignment: .topLeading) {
            palette.background
            if w >= 80 {
                fullCover(width: w, height: h, palette: palette, initial: initial, pixel: pixel)
            } else {
                monogram(width: w, height: h, palette: palette, initial: initial, pixel: pixel)
            }
        }
        .frame(width: w, height: h)
    }

    @ViewBuilder
    private func fullCover(width w: CGFloat, height h: CGFloat, palette: CoverPalette, initial: String, pixel: CGFloat) -> some View {
        let margin = w * 0.10
        let parts = GeneratedCover.titleParts(book.title)
        let titleSize = w * 0.16
        let authorSize = w * 0.055
        let footSize = w * 0.07
        let titleTop = h * 0.26
        let titleHeight = max(0, h - titleTop - margin - footSize * 1.4 - w * 0.04)

        // A giant ghost initial bleeding off the trailing and bottom edges.
        Text(initial)
            .font(.custom(LeafFontName.regular, fixedSize: h * 1.2))
            .foregroundStyle(palette.foreground.opacity(0.08))
            .fixedSize()
            .frame(width: w, height: h, alignment: .trailing)
            .offset(x: w * 0.18, y: h * 0.10)

        // Author and a short rule at the top.
        VStack(alignment: .leading, spacing: 0) {
            Text(book.author.uppercased())
                .font(.system(size: authorSize, weight: .semibold))
                .tracking(authorSize * 0.14)
                .foregroundStyle(palette.foreground.opacity(0.8))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Rectangle()
                .fill(palette.rule)
                .frame(width: w * 0.24, height: pixel)
                .padding(.top, w * 0.035)
        }
        .frame(width: w - margin * 2, alignment: .leading)
        .offset(x: margin, y: margin)

        // Title, then any subtitle after a colon.
        VStack(alignment: .leading, spacing: w * 0.02) {
            Text(parts.main)
                .font(.custom(LeafFontName.regular, fixedSize: titleSize))
                .lineLimit(4)
                .minimumScaleFactor(0.55)
            if let subtitle = parts.subtitle {
                Text(subtitle)
                    .font(.custom(LeafFontName.italic, fixedSize: titleSize * 0.55))
                    .lineLimit(2)
                    .minimumScaleFactor(0.55)
            }
        }
        .foregroundStyle(palette.foreground)
        .multilineTextAlignment(.leading)
        .frame(width: w - margin * 2, height: titleHeight, alignment: .topLeading)
        .offset(x: margin, y: titleTop)

        // Foot: the year, and a small leaf.
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            if let year = book.year {
                Text(String(year))
                    .font(.custom(LeafFontName.italic, fixedSize: footSize))
                    .foregroundStyle(palette.foreground.opacity(0.8))
            }
            Spacer(minLength: 0)
            Image(systemName: "leaf.fill")
                .font(.system(size: footSize))
                .foregroundStyle(palette.rule)
        }
        .frame(width: w - margin * 2, height: h - margin * 2, alignment: .bottom)
        .offset(x: margin, y: margin)
    }

    @ViewBuilder
    private func monogram(width w: CGFloat, height h: CGFloat, palette: CoverPalette, initial: String, pixel: CGFloat) -> some View {
        Text(initial)
            .font(.custom(LeafFontName.regular, fixedSize: h * 0.6))
            .foregroundStyle(palette.foreground)
            .fixedSize()
            .frame(width: w, height: h)
        if w >= 40 {
            Rectangle()
                .fill(palette.rule)
                .frame(width: w * 0.4, height: pixel)
                .offset(x: w * 0.3, y: h * 0.82)
        }
    }

    /// The first letter of the title, skipping a leading "The", "A" or "An".
    static func initial(for title: String) -> String {
        let words = title.split(whereSeparator: \.isWhitespace)
        var start = words.startIndex
        if words.count > 1, let first = words.first, ["the", "a", "an"].contains(first.lowercased()) {
            start = words.index(after: start)
        }
        let rest = words[start...].joined(separator: " ")
        if let letter = rest.first(where: { $0.isLetter || $0.isNumber }) {
            return String(letter).uppercased()
        }
        return title.first.map { String($0).uppercased() } ?? "L"
    }

    /// Splits "Sapiens: A Brief History" into a title and a subtitle.
    static func titleParts(_ title: String) -> (main: String, subtitle: String?) {
        guard let colon = title.firstIndex(of: ":") else { return (title, nil) }
        let main = title[..<colon].trimmingCharacters(in: .whitespaces)
        let subtitle = title[title.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !main.isEmpty else { return (title, nil) }
        return (main, subtitle.isEmpty ? nil : subtitle)
    }
}

#Preview("Generated covers") {
    let books = (0..<10).map { index in
        Book(id: "custom-\(index * 7 + 3)", title: index.isMultiple(of: 3) ? "The Long Way: Letters from the Coast" : "Middlemarch", author: "George Eliot", year: 1871, pages: 880)
    }
    return ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Space.m)], spacing: Space.l) {
            ForEach(books, id: \.id) { book in
                BookCover(book: book, size: .m)
            }
        }
        .padding(Space.margin)
        HStack(spacing: Space.m) {
            ForEach(books.prefix(5), id: \.id) { book in
                BookCover(book: book, size: .s)
            }
        }
    }
    .paperBackground()
}
