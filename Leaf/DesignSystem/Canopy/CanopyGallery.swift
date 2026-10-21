import SwiftUI

/// The Canopy gallery: foundations, components, and Today and Plan mock-ups built on the real tokens with sample
/// data. Screenshot runs open it with `-LeafScreen gallery.canopy` (`.components`, `.today`, `.plan`).
struct CanopyGallery: View {
    enum Page: String, CaseIterable, Identifiable {
        case foundations, components, today, plan

        var id: String { rawValue }

        var title: String {
            switch self {
            case .foundations: return "Foundations"
            case .components: return "Components"
            case .today: return "Today"
            case .plan: return "Plan"
            }
        }
    }

    @State var page: Page = .foundations

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Canopy.Space.section) {
                    switch page {
                    case .foundations: CanopyFoundationsPage()
                    case .components: CanopyComponentsPage()
                    case .today: CanopyTodayMock()
                    case .plan: CanopyPlanMock()
                    }
                }
                .padding(.horizontal, Canopy.Space.margin)
                .padding(.bottom, Canopy.Space.xxxl)
                .id(page)
                .canopyFocusInTransition()
            }
            .canopyBackdrop(page == .plan || page == .today ? .forest : .clay)
            .navigationTitle(page.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(Page.allCases) { item in
                            Button(item.title) {
                                CanopyFeel.play(.select)
                                withAnimation(Canopy.Motion.focusIn) { page = item }
                            }
                        }
                    } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel("Gallery pages")
                }
            }
        }
    }
}

// MARK: - Foundations

private struct CanopyFoundationsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.l) {
            CanopyLabel("Minimal, clean, cozy")
            Text("Deep forest green on a clean cream. Glass you can touch. Blur is a moment, never a state.")
                .canopyText(.callout, color: Canopy.textSecondary)
        }

        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Neutrals")
            HStack(spacing: Canopy.Space.s) {
                swatch("canvas", Canopy.canvas)
                swatch("surface", Canopy.surface)
                swatch("text", Canopy.text)
                swatch("second", Canopy.textSecondary)
                swatch("hero", Canopy.hero)
            }
        }

        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Accents, one job each")
            ForEach(CanopyAccent.allCases) { accent in
                HStack(spacing: Canopy.Space.m) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.color)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(accent.title).canopyText(.headline, color: accent.color)
                        Text(accent.job).canopyText(.caption)
                    }
                    Spacer()
                    Text("Aa")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(accent.color)
                        .frame(width: 44, height: 44)
                        .canopyGlass(accent, interactive: false, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .canopyCard()

        VStack(alignment: .leading, spacing: Canopy.Space.s) {
            CanopyLabel("Type")
            Text("Good evening").canopyText(.display)
            Text("Circe").canopyText(.bookTitle)
            Text("Today’s plan").canopyText(.title)
            Text("Card title, buttons").canopyText(.headline)
            Text("Leaf tells you what to read, when, and gets you reading in one tap.").canopyText(.body)
            Text("Madeline Miller · 393 pages").canopyText(.caption)
            HStack(alignment: .firstTextBaseline) {
                Text("14:02").canopyText(.timer)
            }
            Text("“Witches are not so delicate.”").canopyText(.quote, color: CanopyAccent.bloom.color)
        }
        .canopyCard()
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: Canopy.Space.xs) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
                .frame(height: 44)
                .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Canopy.separator) }
            Text(name).canopyText(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Components

private struct CanopyComponentsPage: View {
    @State private var selectedFamily = "Green"
    @State private var seconds = 192

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Buttons")
            CanopyHeroButton("Begin reading", systemImage: "play.fill") {}
            CanopyGlassButton("Steep and read", systemImage: "cup.and.heat.waves", accent: .clay, feel: .steepStart) {}
            GlassEffectContainer(spacing: Canopy.Space.m) {
                HStack(spacing: Canopy.Space.m) {
                    CanopyGlassButton("Log pages", systemImage: "book.pages", accent: .forest, compact: true) {}
                    CanopyGlassButton("Pause", systemImage: "pause.fill", accent: .dusk, compact: true, feel: .pause) {}
                }
            }
            HStack(spacing: Canopy.Space.m) {
                CanopyIconButton("plus", accessibilityLabel: "Add") {}
                CanopyIconButton("clock", accessibilityLabel: "Reading time", accent: .dusk) {}
                CanopyIconButton("cup.and.heat.waves", accessibilityLabel: "Tea", accent: .clay) {}
                CanopyIconButton("quote.bubble", accessibilityLabel: "Journal", accent: .bloom) {}
            }
        }

        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Chips", accent: .clay)
            ScrollView(.horizontal) {
                HStack(spacing: Canopy.Space.s) {
                    ForEach(["Black", "Green", "Oolong", "Herbal", "Rooibos"], id: \.self) { family in
                        CanopyChip(family, accent: .clay, isSelected: family == selectedFamily) {
                            selectedFamily = family
                        }
                    }
                }
                .padding(.vertical, Canopy.Space.xs)
            }
            .scrollIndicators(.hidden)
        }

        VStack(alignment: .leading, spacing: Canopy.Space.l) {
            CanopyLabel("Steep timer, always sharp", accent: .clay)
            HStack(spacing: Canopy.Space.xl) {
                CanopyRing(value: 1 - Double(seconds) / 240, accent: .clay, lineWidth: 6) {
                    Image(systemName: "cup.and.heat.waves")
                        .font(.title2)
                        .foregroundStyle(CanopyAccent.clay.color)
                }
                .frame(width: 72, height: 72)
                CanopyTimerText(seconds: seconds, countsDown: true)
            }
            CanopyGlassButton("Step 10 seconds", compact: true, feel: .select) {
                seconds = max(0, seconds - 10)
            }
        }
        .canopyCard()

        VStack(alignment: .leading, spacing: Canopy.Space.l) {
            CanopyLabel("Progress")
            HStack(spacing: Canopy.Space.xl) {
                CanopyRing(value: 0.48) {
                    Text("12").canopyText(.statSmall)
                }
                .frame(width: 64, height: 64)
                CanopyStat(value: "12", unit: "of 25 min", caption: "Read today")
            }
            CanopyProgressBar(value: 0.48)
            CanopyBookRow(title: "Circe", author: "Madeline Miller", paletteIndex: 2, progress: 0.48, trailing: "p. 189")
        }
        .canopyCard()

        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Haptics map", accent: .dusk)
            ForEach(CanopyFeel.allCases, id: \.self) { feel in
                Button {
                    CanopyFeel.play(feel)
                } label: {
                    HStack {
                        Text(feel.rawValue).canopyText(.headline)
                        Spacer()
                        Text(feel.pattern)
                            .canopyText(.caption)
                            .multilineTextAlignment(.trailing)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .canopyCard()
    }
}

// MARK: - Mock-ups

/// Today on Canopy, with sample data: one Hero, today's reading times, the goal and the streak.
private struct CanopyTodayMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.xs) {
            Text("Good evening").canopyText(.display)
            Text("12 of 25 minutes read today").canopyText(.callout, color: Canopy.textSecondary)
        }

        VStack(alignment: .leading, spacing: Canopy.Space.l) {
            CanopyLabel("Next · 8:30 PM", accent: .dusk)
            HStack(spacing: Canopy.Space.l) {
                CanopyCoverSwatch(title: "Circe", paletteIndex: 2, width: 64)
                VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                    Text("Circe").canopyText(.bookTitle)
                    Text("Madeline Miller").canopyText(.caption)
                    Text("20 min · pp. 142–158").canopyText(.caption, color: CanopyAccent.dusk.color)
                    CanopyProgressBar(value: 0.48, height: 4)
                        .padding(.top, Canopy.Space.xs)
                }
            }
            CanopyHeroButton("Begin reading", systemImage: "play.fill") {}
            CanopyGlassButton("Steep and read", systemImage: "cup.and.heat.waves", accent: .clay, compact: true, feel: .steepStart) {}
        }
        .canopyCard()

        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Today’s plan", accent: .dusk, linkTitle: "Edit") {}
            CanopySlotRow(time: "7:30 AM", title: "Project Hail Mary", detail: "15 min · pp. 80–96", paletteIndex: 5, state: .done)
            CanopySlotRow(time: "8:30 PM", title: "Circe", detail: "20 min · pp. 142–158", paletteIndex: 2, state: .next)
            CanopySlotRow(time: "10:00 PM", title: "Circe", detail: "10 min · pp. 158–164", paletteIndex: 2)
        }
        .canopyCard()

        HStack(spacing: Canopy.Space.cardGap) {
            VStack(alignment: .leading, spacing: Canopy.Space.m) {
                CanopyRing(value: 0.48) {
                    Text("12").canopyText(.statSmall)
                }
                .frame(width: 56, height: 56)
                Text("of 25 min").canopyText(.caption)
            }
            .canopyCard()
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                CanopyStat(value: "9", unit: "days", caption: "Reading streak", accent: .forest)
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { day in
                        Circle()
                            .fill(day < 5 ? CanopyAccent.forest.color : Canopy.separator)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .canopyCard()
        }
    }
}

/// Plan on Canopy, with sample data: a book per reading time, one tap to change the time or swap the book.
private struct CanopyPlanMock: View {
    @State private var severalBooks = true
    @State private var day = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            HStack(spacing: Canopy.Space.s) {
                CanopyChip("One book at a time", accent: .forest, isSelected: !severalBooks) { severalBooks = false }
                CanopyChip("Several books", accent: .forest, isSelected: severalBooks) { severalBooks = true }
            }
            HStack(spacing: 0) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { index, letter in
                    Button {
                        CanopyFeel.play(.select)
                        day = index
                    } label: {
                        Text(letter)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(index == day ? CanopyAccent.forest.color : Canopy.textSecondary)
                            .frame(width: 36, height: 36)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .canopyGlass(index == day ? CanopyAccent.forest : nil, in: Circle())
                    .frame(maxWidth: .infinity)
                }
            }
        }

        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Thursday · 3 reading times · 45 min", accent: .dusk)
            CanopySlotRow(time: "7:30 AM", period: "Morning", title: "Project Hail Mary", detail: "15 min · pp. 80–96", paletteIndex: 5, state: .done)
            Divider().overlay(Canopy.separator)
            CanopySlotRow(time: "8:30 PM", period: "Evening", title: "Circe", detail: "20 min · pp. 142–158", paletteIndex: 2, state: .next)
            Divider().overlay(Canopy.separator)
            CanopySlotRow(time: "10:00 PM", period: "Bedtime", title: "Shared", detail: "10 min · Circe pp. 158–164", paletteIndex: nil)
            CanopyGlassButton("Add a reading time", systemImage: "plus", accent: .dusk, compact: true, feel: .planChanged) {}
        }
        .canopyCard()

        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Up next", linkTitle: "Edit") {}
            CanopyBookRow(title: "Piranesi", author: "Susanna Clarke", paletteIndex: 1, trailing: "Nov 4")
            CanopyBookRow(title: "The Remains of the Day", author: "Kazuo Ishiguro", paletteIndex: 0, trailing: "Nov 19")
        }
        .canopyCard()

        VStack(alignment: .leading, spacing: Canopy.Space.s) {
            CanopyLabel("Finish dates")
            Text("Circe: likely November 3, a day sooner than last week.")
                .canopyText(.callout)
        }
        .canopyCard(tint: .forest)
    }
}

#Preview("Canopy · foundations") { CanopyGallery(page: .foundations) }
#Preview("Canopy · components") { CanopyGallery(page: .components) }
#Preview("Canopy · Today") { CanopyGallery(page: .today) }
#Preview("Canopy · Plan, dark") { CanopyGallery(page: .plan).preferredColorScheme(.dark) }
