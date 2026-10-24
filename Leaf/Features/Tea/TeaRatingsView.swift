import SwiftUI

/// "Rate your teas": every tea on one page, rated with a tap on its leaves, no forms. The teas the reader has read
/// with come first, then the rest of the cabinet, then Leaf's other teas by kind. Five leaves and the ritual and Today
/// offer a tea more often; one leaf and they hardly do (`TeaPreferences.ratingWeight`). A tin keeps its rating on the
/// tin, any other tea with "Teas you like".
struct TeaRatingsView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var prefs = CozySettings.teaPreferences
    @State private var filter: Filter = .all

    enum Filter: Hashable {
        case all, rated
        case family(TeaFamily)

        var title: String {
            switch self {
            case .all: return "All"
            case .rated: return "Rated"
            case .family(let family): return family.title
            }
        }
    }

    private static let filters: [Filter] = [.all, .rated] + TeaFamily.allCases.map { Filter.family($0) }

    /// A tea and the words under its name.
    private struct Line: Identifiable {
        var tea: Tea
        var detail: String

        var id: String { tea.id }
    }

    private struct Shelf: Identifiable {
        var title: String
        var lines: [Line]

        var id: String { title }
    }

    var body: some View {
        let shelves = self.shelves
        ScrollView {
            VStack(alignment: .leading, spacing: Canopy.Space.section) {
                VStack(alignment: .leading, spacing: Canopy.Space.l) {
                    Text("Tap the leaves. Leaf pours the teas you love more often, and the ones you don’t, hardly ever.")
                        .canopyText(.callout, color: Canopy.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    chips
                }
                if shelves.isEmpty {
                    Text(filter == .rated ? "Nothing rated yet. Tap the leaves on any tea and it shows up here." : "No teas of this kind yet.")
                        .canopyText(.body, color: Canopy.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(shelves) { shelf in
                        section(shelf)
                    }
                }
                NavigationLink {
                    TeaPreferencesView()
                } label: {
                    HStack(spacing: Canopy.Space.m) {
                        Image(systemName: "heart")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(CanopyAccent.clay.color)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Teas you like").canopyText(.body)
                            Text("Kinds, caffeine and flavours, for the teas you haven’t met yet.")
                                .canopyText(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: Canopy.Space.s)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Canopy.textTertiary)
                    }
                    .frame(minHeight: Canopy.Space.hitTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .canopyCard(padding: Canopy.Space.l)
            }
            .padding(.horizontal, Canopy.Space.margin)
            .padding(.vertical, Canopy.Space.l)
        }
        .scrollIndicators(.hidden)
        .paperBackground()
        .navigationTitle("Rate your teas")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            prefs = CozySettings.teaPreferences
        }
    }

    // MARK: Filter

    /// The chips never break mid-word: at large text they scroll sideways instead.
    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Canopy.Space.s) {
                ForEach(Self.filters, id: \.self) { item in
                    CanopyChip(chipTitle(item), accent: .clay, isSelected: item == filter) {
                        withAnimation(Canopy.Motion.smooth) { filter = item }
                    }
                    .fixedSize()
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func chipTitle(_ item: Filter) -> String {
        guard item == .rated else { return item.title }
        let count = ratedCount
        return count > 0 ? "Rated · \(count)" : item.title
    }

    // MARK: Sections

    private func section(_ shelf: Shelf) -> some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel(shelf.title, accent: .clay)
            VStack(spacing: 0) {
                ForEach(shelf.lines) { line in
                    row(line)
                    if line.id != shelf.lines.last?.id {
                        Divider().overlay(Canopy.separator)
                    }
                }
            }
            .canopyCard(padding: Canopy.Space.l)
        }
    }

    /// The name and its detail on one line, the leaves under the name. Beside the leaves, names ran to three lines.
    private func row(_ line: Line) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Canopy.Space.m) {
                TeaSwatch(tea: line.tea, size: 22)
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.tea.name)
                            .canopyText(.body)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(line.detail)
                            .canopyText(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Canopy.Space.s) {
                        Text(line.tea.name)
                            .canopyText(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .layoutPriority(1)
                        Spacer(minLength: Canopy.Space.s)
                        Text(line.detail)
                            .canopyText(.caption)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            TeaLeafRating(rating: ratingBinding(for: line.tea))
                .accessibilityLabel("Rating for \(line.tea.name)")
                // Each leaf is centred in a 36 pt button, so this puts the first leaf under the name.
                .padding(.leading, 24)
        }
        .padding(.top, Canopy.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: Ratings

    private var ratedCount: Int {
        let ids = Set(prefs.ratings.keys).union(store.data.cabinet.filter { $0.rating != nil }.map(\.teaID))
        return ids.filter { rating(for: $0) != nil && store.tea(id: $0) != nil }.count
    }

    private func rating(for teaID: String) -> Int? {
        TeaShelf.rating(for: teaID, cabinet: store.data.cabinet, preferences: prefs)
    }

    private func ratingBinding(for tea: Tea) -> Binding<Int?> {
        Binding(
            get: { rating(for: tea.id) },
            set: { value in setRating(value, for: tea) }
        )
    }

    /// On the tin when the reader keeps one, and with their preferences either way, so a tin added later starts with
    /// the leaves they already gave it.
    private func setRating(_ value: Int?, for tea: Tea) {
        withAnimation(Canopy.Motion.snappy) {
            if var tin = TeaShelf.tin(id: tea.id, cabinet: store.data.cabinet) {
                tin.rating = value
                store.updateCabinetTea(tin)
            }
            var saved = CozySettings.teaPreferences
            saved.setRating(value, for: tea.id)
            CozySettings.teaPreferences = saved
            prefs = saved
        }
    }

    // MARK: What's on the page

    private var shelves: [Shelf] {
        var shown = Set<String>()
        var shelves: [Shelf] = []
        func keep(_ tea: Tea) -> Bool {
            switch filter {
            case .all: return true
            case .rated: return rating(for: tea.id) != nil
            case .family(let family): return tea.family == family
            }
        }

        let history = TeaHistory.build(data: store.data)
        let tried: [Line] = history.teas.compactMap { line in
            guard let tea = store.tea(id: line.teaID), shown.insert(tea.id).inserted else { return nil }
            return Line(tea: tea, detail: triedDetail(line, tea: tea))
        }
        let triedShown = tried.filter { keep($0.tea) }
        if !triedShown.isEmpty {
            shelves.append(Shelf(title: "Read with", lines: triedShown))
        }

        let cabinet = store.data.cabinet
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .compactMap { tin -> Line? in
                guard shown.insert(tin.teaID).inserted else { return nil }
                let tea = (TeaShelf.tin(id: tin.teaID, cabinet: store.data.cabinet) ?? tin).tea
                return Line(tea: tea, detail: tin.isOutOf ? "\(tea.family.title) · run out" : tea.family.title)
            }
        let cabinetShown = cabinet.filter { keep($0.tea) }
        if !cabinetShown.isEmpty {
            shelves.append(Shelf(title: "In your cabinet", lines: cabinetShown))
        }

        // The rest of Leaf's teas, a card for each kind.
        let rest = TeaCatalog.all.filter { !shown.contains($0.id) && keep($0) }
        for family in TeaFamily.allCases {
            let lines = rest.filter { $0.family == family }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                .map { Line(tea: $0, detail: $0.caffeine.title) }
            guard !lines.isEmpty else { continue }
            shelves.append(Shelf(title: family.title, lines: lines))
        }
        return shelves
    }

    /// "4 h 10 min" read with it.
    private func triedDetail(_ line: TeaHistory.TeaLine, tea: Tea) -> String {
        line.minutes > 0 ? LeafFormat.duration(minutes: line.minutes) : tea.family.title
    }
}

#Preview("Rate your teas") {
    NavigationStack { TeaRatingsView() }
        .environment(LibraryStore(persistence: .ephemeral()))
}
