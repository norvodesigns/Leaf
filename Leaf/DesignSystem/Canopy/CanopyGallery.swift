import SwiftUI

/// The Canopy gallery: foundations, components, and Today and Plan mock-ups built on the real tokens with sample
/// data. Screenshot runs open it with `-LeafScreen gallery.canopy` (`.components`, `.today`, `.plan`, `.palettes`), and
/// `-CanopyPalette linen|oat|ivory` picks the palette.
struct CanopyGallery: View {
    enum Page: String, CaseIterable, Identifiable {
        case foundations, components, today, plan, palettes

        var id: String { rawValue }

        var title: String {
            switch self {
            case .foundations: return "Foundations"
            case .components: return "Components"
            case .today: return "Today"
            case .plan: return "Plan"
            case .palettes: return "Palettes"
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
                    case .palettes: CanopyPalettesPage()
                    }
                }
                .padding(.horizontal, Canopy.Space.margin)
                .padding(.bottom, Canopy.Space.xxxl)
                .id(page)
                .canopyFocusInTransition()
            }
            .canopyBackdrop(.forest)
            .navigationTitle(page == .today ? "" : page.title)
            .navigationBarTitleDisplayMode(page == .today ? .inline : .large)
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
            CanopyLabel("\(CanopyPalette.current.title) · \(CanopyPalette.current.summary)")
            Text("Cream is the page, green is the ink you act with, black is the one hero button. Glass you can touch. Blur is a moment, never a state.")
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

/// Today, evolved from the live screen: the same masthead, greeting, cover and cup, and the Steep / Begin pair, on a
/// cleaner cream with green as a light touch, then today's reading times.
private struct CanopyTodayMock: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.s) {
            HStack {
                Text("Thursday, October 22").canopyText(.eyebrow)
                Spacer()
                Text("No. 42").canopyText(.eyebrow)
            }
            Rectangle().fill(Canopy.separator).frame(height: 1)
            Text("Evening hush.")
                .canopyText(.display)
                .padding(.top, Canopy.Space.l)
            Text("The lamp and the book do the talking.").canopyText(.subline)
        }

        HStack(alignment: .bottom, spacing: Canopy.Space.xl) {
            CanopyCoverSwatch(title: "The Hobbit", paletteIndex: 5, width: 104)
            VStack(alignment: .leading, spacing: Canopy.Space.s) {
                TeaCup(fill: 0.48, liquor: CanopyAccent.clay.color.opacity(0.55), width: 84)
                HStack(alignment: .firstTextBaseline, spacing: Canopy.Space.xs) {
                    Text("12").canopyText(.stat)
                    Text("of 25 min").canopyText(.callout, color: Canopy.textSecondary)
                }
                CanopyProgressBar(value: 0.48, height: 4)
            }
        }

        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            HStack(spacing: Canopy.Space.xs) {
                Image(systemName: "cup.and.saucer")
                    .foregroundStyle(CanopyAccent.clay.color)
                Text("Bedtime blend · 7 min steep")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Canopy.text)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .canopyGlass(interactive: false)
            GlassEffectContainer(spacing: Canopy.Space.m) {
                HStack(spacing: Canopy.Space.m) {
                    CanopyGlassButton("Steep and read", systemImage: "cup.and.heat.waves", accent: .clay, feel: .steepStart) {}
                    CanopyHeroButton("Begin reading") {}
                }
            }
        }

        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            CanopyLabel("Today’s reading times", linkTitle: "Edit") {}
            CanopySlotRow(time: "7:30", period: "Morning", title: "Project Hail Mary", detail: "15 min · pp. 80–96", paletteIndex: 1, state: .done)
            CanopySlotRow(time: "8:30", period: "Evening", title: "The Hobbit", detail: "20 min · pp. 143–154", paletteIndex: 5, state: .next)
        }
        .canopyCard()

        HStack(alignment: .top, spacing: Canopy.Space.m) {
            Image(systemName: "leaf")
                .foregroundStyle(CanopyAccent.forest.color)
            VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                Text("A short book would bring the year goal back within reach.")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Canopy.text)
                Text("Find a short book")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(CanopyAccent.forest.color)
            }
        }
        .canopyCard(tint: .forest)
    }
}

/// The three palettes side by side, each drawn with its own colours, in the current light or dark mode.
private struct CanopyPalettesPage: View {
    var body: some View {
        Text("Same layout, three creams. Each shows the page, a card, text, the green and the hero button.")
            .canopyText(.callout, color: Canopy.textSecondary)
        HStack(alignment: .top, spacing: Canopy.Space.s) {
            ForEach(CanopyPalette.allCases) { palette in
                swatch(palette)
            }
        }
    }

    private func swatch(_ palette: CanopyPalette) -> some View {
        let c = palette.colors
        return VStack(alignment: .leading, spacing: Canopy.Space.s) {
            Text("Evening hush.")
                .font(.custom(LeafFontName.regular, size: 24, relativeTo: .title2))
                .foregroundStyle(c.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text("Thu · No. 42")
                .font(.system(.caption2, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            VStack(alignment: .leading, spacing: Canopy.Space.xs) {
                Text("The Hobbit")
                    .font(.system(.footnote, design: .serif, weight: .semibold))
                    .foregroundStyle(c.text)
                Capsule().fill(c.separator).frame(height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(c.forest).frame(width: 40, height: 4)
                    }
                Text("Edit ›")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(c.forest)
            }
            .padding(Canopy.Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(c.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Begin")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(Canopy.hero, in: Capsule())
            Text(palette.title)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(c.text)
            Text(palette.summary)
                .font(.system(.caption2))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Canopy.Space.s)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(c.canvas, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(palette == CanopyPalette.current ? c.forest : c.separator, lineWidth: palette == CanopyPalette.current ? 2 : 1)
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
