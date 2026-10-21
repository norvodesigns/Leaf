import SwiftUI

// MARK: - Pairs well with

/// A book's teas (`TeaPairing`): the best three from the catalog and the reader's own, each with why, and a pin for
/// the reader's own choice. A pinned tea is what the ritual and the week's card start with for this book.
struct TeaPairingSection: View {
    let book: Book

    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: LibraryItem? { store.item(book.id) }

    /// The pinned tea first (even when it isn't among the engine's picks), then the best of the rest.
    private var picks: [TeaPairing.Pick] {
        var picks = TeaPairing.picks(for: book, from: store.pairingTeas, limit: 3)
        if let pinnedID = item?.pairedTeaID, let pinned = store.tea(id: pinnedID) {
            picks.removeAll { $0.tea.id == pinnedID }
            picks.insert(TeaPairing.Pick(tea: pinned, score: .infinity, reason: TeaPairing.reason(for: pinned, with: book)), at: 0)
        }
        return Array(picks.prefix(3))
    }

    var body: some View {
        let picks = self.picks
        VStack(alignment: .leading, spacing: Space.m) {
            SectionHeader("Pairs well with", topSpacing: 0)
            if let lead = picks.first {
                Text(lead.reason)
                    .leafStyle(.pullQuote)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            VStack(spacing: 0) {
                ForEach(picks, id: \.tea.id) { pick in
                    row(pick)
                    if pick.tea.id != picks.last?.tea.id {
                        Divider().overlay(Color.hairline)
                    }
                }
            }
            if item == nil {
                Text("Add the book to your shelves to pin a pairing.")
                    .leafStyle(.caption)
            } else {
                otherTeas(shown: Set(picks.map(\.tea.id)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ pick: TeaPairing.Pick) -> some View {
        let isPinned = item?.pairedTeaID == pick.tea.id
        return HStack(spacing: Space.m) {
            TeaSwatch(tea: pick.tea)
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(pick.tea.name)
                    .leafStyle(.uiBody)
                Text(detail(pick.tea, isPinned: isPinned))
                    .leafStyle(.caption)
            }
            Spacer(minLength: Space.s)
            if item != nil {
                Button {
                    Haptics.shared.selection()
                    withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                        store.setPairedTea(book.id, teaID: isPinned ? nil : pick.tea.id)
                    }
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.body)
                        .foregroundStyle(isPinned ? Color.ribbon : Color.inkTertiary)
                        .frame(width: Space.hitTarget, height: Space.hitTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPinned ? "Unpin \(pick.tea.name)" : "Pin \(pick.tea.name) as this book’s tea")
            }
        }
        .padding(.vertical, Space.xs)
        .accessibilityElement(children: .contain)
    }

    /// Any other tea, from Leaf's or the reader's own, to pin instead.
    private func otherTeas(shown: Set<String>) -> some View {
        let others = store.pairingTeas
            .filter { !shown.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return Menu {
            ForEach(others) { tea in
                Button(tea.name) {
                    Haptics.shared.selection()
                    withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                        store.setPairedTea(book.id, teaID: tea.id)
                    }
                }
            }
        } label: {
            Text("Pin another tea")
                .leafStyle(.caption, color: .accent)
                .frame(minHeight: Space.hitTarget)
                .contentShape(.rect)
        }
        .accessibilityHint("Choose any tea as this book’s pairing")
    }

    /// "Your pairing · in your cabinet", "Oolong · 4 min"
    private func detail(_ tea: Tea, isPinned: Bool) -> String {
        var parts: [String] = []
        if isPinned { parts.append("Your pairing") }
        parts.append(tea.family.title)
        parts.append(SteepText.duration(seconds: tea.steepSeconds))
        if store.hasInStock(tea.id) { parts.append("in your cabinet") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Tasting card

/// After a cup, a few words about it: one tap on how it came out saves a note; aromas and leaves can follow.
/// Never required, and nothing is saved until the reader taps.
struct TastingCard: View {
    let session: ReadingSession
    let tea: Tea

    @Environment(LibraryStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    @State private var strength: TastingStrength?
    @State private var aromas: [String] = []
    @State private var rating: Int?
    @State private var didLoad = false

    private var isSaved: Bool { strength != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                TeaSwatch(tea: tea, size: 18)
                Eyebrow(isSaved ? "Your note on the \(tea.name)" : "How was the \(tea.name)?")
                    .accessibilityAddTraits(.isHeader)
            }
            TeaFlowLayout(spacing: Space.s) {
                ForEach(TastingStrength.allCases, id: \.self) { option in
                    Button {
                        Haptics.shared.selection()
                        withAnimation(Motion.resolved(Motion.paper, reduceMotion: reduceMotion)) {
                            strength = option
                        }
                        save()
                    } label: {
                        Chip(option.title, systemImage: strength == option ? "checkmark" : nil, tone: strength == option ? .accent : .neutral)
                            .frame(minHeight: Space.hitTarget)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityAddTraits(strength == option ? AccessibilityTraits.isSelected : AccessibilityTraits())
                }
            }
            if isSaved {
                TeaAromaPicker(aromas: $aromas)
                TeaLeafRating(rating: $rating)
                Text("Kept in your tea history.")
                    .leafStyle(.caption)
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.paperRaised, in: Radius.shape(Radius.card))
        .overlay {
            Radius.shape(Radius.card)
                .strokeBorder(Color.hairline, lineWidth: 1 / displayScale)
        }
        .onAppear(perform: load)
        .onChange(of: aromas) { _, _ in save() }
        .onChange(of: rating) { _, _ in save() }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        guard let note = store.tasting(forSession: session.id) else { return }
        strength = note.strength
        aromas = note.aromas
        rating = note.rating
    }

    /// Only once the reader has said how it came out; loading an old note never re-saves it.
    private func save() {
        guard didLoad, let teaID = session.teaID, strength != nil else { return }
        store.saveTasting(sessionID: session.id, teaID: teaID, bookID: session.bookID, strength: strength, aromas: aromas, rating: rating)
    }
}

// MARK: - Tea and book of the week

/// Today's weekly suggestion (`TeaOfTheWeek`): the book to read this week and a pot to read it with.
struct TeaWeekCard: View {
    let pick: TeaAndBook
    let book: Book?
    let onSteep: () -> Void
    let onOpen: () -> Void
    let onCabinet: () -> Void

    var body: some View {
        TodayCard("Tea & book of the week", actionTitle: "Cabinet", action: onCabinet) {
            VStack(alignment: .leading, spacing: Space.m) {
                Text(pick.line)
                    .leafStyle(.pullQuote)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: Space.m) {
                        if let book {
                            BookCover(book: book, size: .s)
                        }
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            Text(pick.title)
                                .leafStyle(.headline)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            if let book {
                                Text(book.author)
                                    .leafStyle(.author)
                            }
                            HStack(spacing: Space.xs) {
                                TeaSwatch(tea: pick.tea, size: 14)
                                Text(pick.isPinned ? "\(pick.tea.name) · your pairing" : pick.tea.name)
                                    .leafStyle(.caption, color: .ink)
                            }
                            .padding(.top, Space.xxs)
                            Text(pick.reason)
                                .leafStyle(.caption)
                                .italic()
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.pressable)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens book details")
                TextButton("Steep and read", color: .accent) {
                    Haptics.shared.tap()
                    onSteep()
                }
            }
        }
    }
}
