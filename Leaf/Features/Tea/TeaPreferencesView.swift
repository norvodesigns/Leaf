import SwiftUI

/// "Teas you like" (docs/design/REDESIGN.md §4.6): one page of glass chips, no forms. Kinds, caffeine, flavours, and
/// optionally kinds for a time of day. Today's tea and the ritual's choices follow it (`TeaPreferences`).
struct TeaPreferencesView: View {
    @State private var prefs = CozySettings.teaPreferences
    @State private var showsTimes = !CozySettings.teaPreferences.familiesByTime.isEmpty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Canopy.Space.section) {
                Text("Leaf leans toward what you like when it suggests a tea. Late at night it still keeps to caffeine free.")
                    .canopyText(.callout, color: Canopy.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                section("Teas you like") {
                    chips(TeaFamily.allCases, title: \.title, isOn: { prefs.likedFamilies.contains($0) }) { family in
                        toggle(family, in: &prefs.likedFamilies)
                    }
                }

                section("Caffeine") {
                    chips(TeaCaffeineChoice.allCases, title: \.title, isOn: { prefs.caffeine == $0 }) { choice in
                        prefs.caffeine = choice
                    }
                }

                section("Flavours") {
                    chips(TastingAroma.all, title: { $0.capitalized }, isOn: { prefs.likedFlavours.contains($0) }) { flavour in
                        toggle(flavour, in: &prefs.likedFlavours)
                    }
                }

                VStack(alignment: .leading, spacing: Canopy.Space.m) {
                    Toggle(isOn: $showsTimes.animation(Canopy.Motion.smooth)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("By time of day").canopyText(.headline)
                            Text("Say, green in the morning and herbal at night.").canopyText(.caption)
                        }
                    }
                    .tint(CanopyAccent.forest.color)
                    .onChange(of: showsTimes) { _, on in
                        CanopyFeel.play(.select)
                        if !on { prefs.familiesByTime = [:] }
                    }
                    if showsTimes {
                        ForEach(TeaTimeOfDay.allCases, id: \.self) { time in
                            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                                Text(time.title).canopyText(.caption)
                                chips(TeaFamily.allCases, title: \.title, isOn: { prefs.familiesByTime[time, default: []].contains($0) }) { family in
                                    toggle(family, in: &prefs.familiesByTime[time, default: []])
                                }
                            }
                            .canopyFocusInTransition()
                        }
                    }
                }
                .canopyCard()

                if !prefs.isEmpty {
                    Button("Clear my preferences") {
                        CanopyFeel.play(.tap)
                        withAnimation(Canopy.Motion.smooth) {
                            prefs = TeaPreferences()
                            showsTimes = false
                        }
                    }
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Canopy.textSecondary)
                }
            }
            .padding(.horizontal, Canopy.Space.margin)
            .padding(.vertical, Canopy.Space.l)
        }
        .paperBackground()
        .navigationTitle("Teas you like")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: prefs) { _, new in
            CozySettings.teaPreferences = new
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel(title, accent: .clay)
            content()
        }
    }

    private func chips<Item: Hashable>(_ items: [Item], title: @escaping (Item) -> String, isOn: @escaping (Item) -> Bool, tap: @escaping (Item) -> Void) -> some View {
        CanopyFlowLayout(spacing: Canopy.Space.s) {
            ForEach(items, id: \.self) { item in
                CanopyChip(title(item), accent: .clay, isSelected: isOn(item)) {
                    tap(item)
                }
            }
        }
    }

    private func toggle<Item: Hashable>(_ item: Item, in set: inout Set<Item>) {
        if set.contains(item) { set.remove(item) } else { set.insert(item) }
    }
}

/// Lays chips out in rows, wrapping to the next line when a row is full.
struct CanopyFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
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

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if extra > width, !current.indices.isEmpty {
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

#Preview("Teas you like") {
    NavigationStack { TeaPreferencesView() }
}
