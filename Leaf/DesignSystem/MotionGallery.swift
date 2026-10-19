#if DEBUG
import SwiftUI

/// The motion language on one page per section, for previews and screenshots (`-LeafScreen gallery.palette`,
/// `gallery.blur`, `gallery.scenes`, `gallery.ribbon`, `gallery.scrub`, `gallery.drum`). Debug builds only.
struct MotionGallery: View {
    enum Section: String, CaseIterable, Identifiable {
        case palette, blur, scenes, ribbon, scrub, drum

        var id: String { rawValue }

        var title: String {
            switch self {
            case .palette: "Cozy palette"
            case .blur: "Blur"
            case .scenes: "Scenes"
            case .ribbon: "Ribbon"
            case .scrub: "Scrub numbers"
            case .drum: "Drum and dates"
            }
        }
    }

    let section: Section

    @State private var minutes = 25
    @State private var page = 142
    @State private var steep = 240
    @State private var finishOffset = 12
    @State private var hour = 21
    @State private var minute = 30
    @State private var showsFirst = true
    @State private var number = 142
    @State private var calm = 1.0
    @State private var tucked = false
    @State private var ribbonPage = 142

    /// One page; push it, or wrap it in a `NavigationStack` to show it alone.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .leafMargins()
            .padding(.bottom, Space.section)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .paperBackground()
        .navigationTitle(section.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .palette: palette
        case .blur: blur
        case .scenes: scenes
        case .ribbon: ribbon
        case .scrub: scrub
        case .drum: drum
        }
    }

    // MARK: Palette

    private var palette: some View {
        let tokens: [(String, Color)] = [
            ("teaPaper", .teaPaper), ("chai", .chai), ("matcha", .matcha), ("rooibos", .rooibos),
            ("steam", .steam), ("amber", .amber), ("rose", .rose),
            ("ink", .ink), ("accent", .accent), ("ribbon", .ribbon),
        ]
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Cozy tokens, for atmosphere only", topSpacing: Space.l)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Space.m)], spacing: Space.m) {
                ForEach(tokens, id: \.0) { token in
                    VStack(spacing: Space.xs) {
                        Radius.shape(Radius.tile)
                            .fill(token.1)
                            .frame(height: 56)
                            .overlay { Radius.shape(Radius.tile).strokeBorder(Color.hairline) }
                        Text(token.0).leafStyle(.data)
                    }
                }
            }
            SectionHeader("Tea in the cup")
            HStack(spacing: Space.s) {
                ForEach(TeaCatalog.all.prefix(10)) { tea in
                    Circle().fill(CozyColor.liquor(for: tea)).frame(width: 26, height: 26)
                }
            }
        }
    }

    // MARK: Blur

    private var blur: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Focus pull", topSpacing: Space.l)
            ZStack {
                if showsFirst {
                    Text("Good evening.").leafStyle(.display).focusPullTransition()
                } else {
                    Text("Still up?").leafStyle(.display).focusPullTransition()
                }
            }
            .frame(height: 76)
            Text("Behind a sheet: out of focus")
                .leafStyle(.title)
                .focusPull(isFocused: false)
            SectionHeader("Numbers")
            HStack(alignment: .firstTextBaseline, spacing: Space.xl) {
                Text("\(number)").leafStyle(.heroNumeral).numericBlur(value: Double(number))
                PerDigitBlurText(text: "12:04", value: Double(number)).leafStyle(.statNumeral)
            }
            SecondaryGlassButton("Change", compact: true) {
                withAnimation(.smooth(duration: 0.5)) { showsFirst.toggle() }
                number += 7
            }
            SectionHeader("Cover backdrop")
            ZStack {
                BlurredCoverBackdrop(book: DemoData.hobbit)
                BookCover(book: DemoData.hobbit, size: .m)
            }
            .frame(height: 240)
            .clipShape(Radius.shape(Radius.card))
            ZStack {
                BlurredCoverBackdrop(book: DemoData.piranesi)
                Text("Piranesi").leafStyle(.masthead)
            }
            .frame(height: 140)
            .clipShape(Radius.shape(Radius.card))
            .padding(.top, Space.m)
        }
    }

    // MARK: Scenes

    private var scenes: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Bokeh", topSpacing: Space.l)
            AtmosphereScene(kind: .bokeh, calm: calm)
                .frame(height: 170)
                .background(Color.lamp, in: Radius.shape(Radius.card))
                .clipShape(Radius.shape(Radius.card))
            SectionHeader("Rain on glass")
            AtmosphereScene(kind: .rain, calm: calm)
                .frame(height: 190)
                .background(LinearGradient(colors: [Color(hex: 0x2B3A4A), Color(hex: 0x14181F)], startPoint: .top, endPoint: .bottom))
                .clipShape(Radius.shape(Radius.card))
            SectionHeader("Steam")
            HStack(alignment: .bottom) {
                AtmosphereScene(kind: .steam, calm: calm)
                    .frame(width: 140, height: 120)
                TeaCup(fill: 0.8, liquor: CozyColor.liquor(for: TeaCatalog.earlGrey), width: 110)
            }
            Text("Calm \(Int((calm * 100).rounded()))%").leafStyle(.caption).padding(.top, Space.m)
            Slider(value: $calm, in: 0...1)
        }
    }

    // MARK: Ribbon

    private var ribbon: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("On a cover: tilt it, tug it", topSpacing: Space.l)
            HStack(alignment: .top, spacing: Space.xxl) {
                BookCover(book: DemoData.hobbit, size: .l, ribbon: true, swaysRibbon: true)
                BookCover(book: DemoData.circe, size: .m, ribbon: true, ribbonTucked: tucked)
            }
            .padding(.bottom, Space.xl)
            SecondaryGlassButton(tucked ? "Untuck" : "Finish: tuck it away", compact: true) { tucked.toggle() }
            SectionHeader("The bookmark is the progress control")
            RibbonPageControl(page: $ribbonPage, pages: 310, startPage: 88)
        }
    }

    // MARK: Scrub

    private var scrub: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Minutes", topSpacing: Space.l)
            MinutesDial(minutes: $minutes)
            SectionHeader("Pages")
            VStack(spacing: Space.s) {
                Text("\(page)").leafStyle(.heroNumeral).numericBlur(value: Double(page)).frame(maxWidth: .infinity)
                PageScrubber(page: $page, range: 0...310, estimate: 158)
            }
            SectionHeader("Steep time")
            SteepTimeScrub(seconds: $steep, suggested: 240)
        }
    }

    // MARK: Drum and dates

    private var drum: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Finish by", topSpacing: Space.l)
            FinishByScrub(
                scrub: DateScrub(start: Date(), calendar: .current, earliestDay: 1, latestDay: 120) { _, days in
                    4_000.0 / Double(max(days, 1))
                },
                offset: $finishOffset,
                magnetOffsets: [9]
            )
            SectionHeader("A reading time")
            TimeDrum(hour: $hour, minute: $minute)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview("Motion · ribbon") {
    NavigationStack { MotionGallery(section: .ribbon) }
}

#Preview("Motion · blur, dark") {
    NavigationStack { MotionGallery(section: .blur) }
        .preferredColorScheme(.dark)
}

#Preview("Motion · scrub, dark") {
    NavigationStack { MotionGallery(section: .scrub) }
        .preferredColorScheme(.dark)
}
#endif
