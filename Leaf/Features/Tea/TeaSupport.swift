import SwiftUI

/// The tea pages that open as a sheet over the tabs (from Today, Settings links push the same views).
enum TeaPage: String, Identifiable, Hashable {
    case cabinet, history

    var id: String { rawValue }
}

extension LibraryStore {
    /// What the ritual and the nook offer now: the cabinet's teas in stock, ranked for the hour, or the catalog's,
    /// with the book's pinned tea first whenever the hour and the cabinet allow it.
    func teaChoices(limit: Int = 8, for bookID: String? = nil) -> TeaShelf.Choices {
        TeaShelf.ritualChoices(
            cabinet: data.cabinet,
            daypart: Daypart.of(now, calendar: calendar),
            season: Season.of(now, calendar: calendar),
            favoriteTeaID: preferences.favoriteTeaID,
            seed: SeededGenerator.daySeed(now, calendar: calendar),
            limit: limit,
            pinnedTeaID: bookID.flatMap { item($0)?.pairedTeaID }
        )
    }

    /// A tea the reader picked (or pinned), if it can still be offered at this hour from what they have.
    func offerableTea(_ id: String?) -> Tea? {
        TeaShelf.offerable(id, cabinet: data.cabinet, daypart: Daypart.of(now, calendar: calendar))
    }

    /// Every tea a book can pair with: the catalog (the reader's tins in place of the catalog's own) and their own
    /// teas in stock.
    var pairingTeas: [Tea] {
        let catalog = TeaCatalog.all.map { tea(id: $0.id) ?? $0 }
        let own = data.cabinet.filter { $0.catalogID == nil && !$0.isOutOf }.map(\.tea)
        return catalog + own
    }

    /// Whether a tea is in the cabinet and not run out.
    func hasInStock(_ teaID: String) -> Bool {
        data.cabinet.contains { $0.teaID == teaID && !$0.isOutOf }
    }
}

/// A round swatch of a tea's liquor.
struct TeaSwatch: View {
    let tea: Tea
    var size: CGFloat = 28

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Circle()
            .fill(CozyColor.liquor(for: tea))
            .overlay {
                Circle().strokeBorder(Color.hairline, lineWidth: 1 / displayScale)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// One to five leaves for a rating; tapping the current rating again clears it.
struct TeaLeafRating: View {
    @Binding var rating: Int?
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    Haptics.shared.selection()
                    rating = rating == value ? nil : value
                } label: {
                    Image(systemName: value <= (rating ?? 0) ? "leaf.fill" : "leaf")
                        .font(.system(size: size * 0.7, weight: .regular))
                        .foregroundStyle(value <= (rating ?? 0) ? Color.accent : Color.inkTertiary)
                        .frame(width: size + Space.s, height: Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(value == 1 ? "1 leaf" : "\(value) leaves")
                .accessibilityAddTraits(value == rating ? AccessibilityTraits.isSelected : AccessibilityTraits())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rating")
    }
}

/// Leaves for a rating that can't be changed here ("★★★★☆" in leaves).
struct TeaLeaves: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { value in
                Image(systemName: value <= rating ? "leaf.fill" : "leaf")
                    .font(.caption2)
                    .foregroundStyle(value <= rating ? Color.accent : Color.inkTertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rating == 1 ? "1 leaf of 5" : "\(rating) leaves of 5")
    }
}

/// Aroma words to tap, as chips that wrap.
struct TeaAromaPicker: View {
    @Binding var aromas: [String]

    var body: some View {
        TeaFlowLayout(spacing: Space.s) {
            ForEach(TastingAroma.all, id: \.self) { aroma in
                let isOn = aromas.contains(aroma)
                Button {
                    Haptics.shared.selection()
                    if isOn { aromas.removeAll { $0 == aroma } } else { aromas.append(aroma) }
                } label: {
                    Chip(aroma, systemImage: isOn ? "checkmark" : nil, tone: isOn ? .accent : .neutral)
                        .frame(minHeight: Space.hitTarget)
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
            }
        }
    }
}

/// Lays its children out in rows, wrapping when a row is full.
struct TeaFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let finite = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let rows = arrange(subviews, width: finite ?? .greatestFiniteMagnitude)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: finite ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = measure(subviews[index], width: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// A child's natural size, never wider than the row.
    private func measure(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let natural = subview.sizeThatFits(.unspecified)
        guard natural.width > width, width.isFinite else { return natural }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = measure(subviews[index], width: width)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}


/// The tea cabinet or the tea history as a sheet over the tabs, with its own navigation.
struct TeaPageSheet: View {
    let page: TeaPage

    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .cabinet: TeaCabinetView()
                case .history: TeaHistoryView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.shared.tap()
                        router.teaPage = nil
                        dismiss()
                    }
                }
            }
        }
        .presentationBackground(Color.paper)
        .presentationDragIndicator(.visible)
    }
}
