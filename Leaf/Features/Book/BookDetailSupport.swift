import SwiftUI
import UIKit

// MARK: - Genre chips

/// Chips that wrap onto as many centred lines as they need.
struct BookChipFlow: Layout {
    var spacing: CGFloat = Space.s

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let available = proposal.width.map { $0.isFinite ? $0 : CGFloat.greatestFiniteMagnitude } ?? CGFloat.greatestFiniteMagnitude
        let lines = arrange(width: available, subviews: subviews)
        let height = lines.reduce(CGFloat(0)) { $0 + $1.height } + spacing * CGFloat(max(lines.count - 1, 0))
        let widest = lines.map(\.width).max() ?? 0
        return CGSize(width: min(widest, available), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let lines = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX + (bounds.width - line.width) / 2
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = []
        var current = Line()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                lines.append(current)
                current = Line()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { lines.append(current) }
        return lines
    }
}

// MARK: - Page sheet

/// "Where are you now?": set the page a book has reached (a ruler, like the session's page entry).
struct BookPageSheet: View {
    let book: Book
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page: Int

    init(book: Book, page: Int, onSave: @escaping (Int) -> Void) {
        self.book = book
        self.onSave = onSave
        _page = State(initialValue: min(max(page, 0), max(book.pages, 1)))
    }

    var body: some View {
        VStack(spacing: Space.l) {
            VStack(spacing: Space.xs) {
                Text("Where are you now?")
                    .leafStyle(.title)
                    .accessibilityAddTraits(.isHeader)
                Text(book.title)
                    .leafStyle(.caption)
                    .italic()
                    .lineLimit(1)
            }

            Text("\(page)")
                .leafStyle(.heroNumeral)
                .numericBlur(value: Double(page))
                .leafAnimation(Motion.paper, value: page)
                .accessibilityHidden(true)

            PageScrubber(page: $page, range: 0...max(book.pages, 1), estimate: nil)

            Text("of \(LeafFormat.number(book.pages)) pages")
                .leafStyle(.caption)

            GlassEffectContainer(spacing: Space.m) {
                VStack(spacing: Space.m) {
                    PrimaryGlassButton("Save page", playsHaptic: false) {
                        onSave(page)
                        dismiss()
                    }
                    SecondaryGlassButton("Keep reading", compact: true) {
                        dismiss()
                    }
                }
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(580), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
    }
}

// MARK: - Page count sheet

/// Fixes a wrong page count. The reader's place and the word count scale with it.
struct BookPagesSheet: View {
    let book: Book
    let onSave: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(book: Book, onSave: @escaping (Int) -> Void) {
        self.book = book
        self.onSave = onSave
        _text = State(initialValue: String(book.pages))
    }

    private var pages: Int? { Int(text) }

    private var isValid: Bool {
        guard let pages else { return false }
        return pages >= 1 && pages <= 20_000 && pages != book.pages
    }

    var body: some View {
        VStack(spacing: Space.l) {
            VStack(spacing: Space.xs) {
                Text("Page count")
                    .leafStyle(.title)
                    .accessibilityAddTraits(.isHeader)
                Text("Fix it if the edition in your hands differs. Your place and your plan adjust.")
                    .leafStyle(.caption)
                    .multilineTextAlignment(.center)
            }

            TextField("Pages", text: $text)
                .font(LeafType.statNumeral)
                .foregroundStyle(Color.ink)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .focused($isFocused)
                .padding(.vertical, Space.m)
                .background(Color.paperRaised, in: Radius.shape(Radius.tile))
                .accessibilityLabel("Pages")
                .onChange(of: text) { _, new in
                    let digits = String(new.filter { "0123456789".contains($0) }.prefix(5))
                    if digits != new { text = digits }
                }

            GlassEffectContainer(spacing: Space.m) {
                VStack(spacing: Space.m) {
                    PrimaryGlassButton("Save") {
                        if let pages, isValid {
                            onSave(pages)
                            dismiss()
                        }
                    }
                    .disabled(!isValid)
                    SecondaryGlassButton("Cancel", compact: true) {
                        dismiss()
                    }
                }
            }
        }
        .padding(.horizontal, Space.margin)
        .padding(.top, Space.xl)
        .padding(.bottom, Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
        .onAppear { isFocused = true }
    }
}
