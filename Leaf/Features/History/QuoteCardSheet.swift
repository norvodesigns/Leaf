import Photos
import SwiftUI

/// A quote from the journal as an image to share: pick the quote and a paper or tea style, then share it or save it
/// to Photos. The card carries the title, the author and the page.
struct QuoteCardSheet: View {
    let initialEntryID: UUID?

    @Environment(LibraryStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var entryID: UUID?
    @State private var style: QuoteCardStyle = .paper
    @State private var image: UIImage?
    @State private var saveState: SaveState = .idle

    private enum SaveState: Equatable { case idle, saving, saved, denied }

    /// Every quote, favourites first, then newest.
    private var quotes: [JournalEntry] {
        store.data.journal
            .filter { $0.kind == .quote && !$0.text.isEmpty }
            .sorted { (a: JournalEntry, b: JournalEntry) -> Bool in
                if a.isFavorite != b.isFavorite { return a.isFavorite }
                return a.createdAt > b.createdAt
            }
    }

    private var entry: JournalEntry? {
        let all = quotes
        return all.first { $0.id == entryID } ?? all.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Space.l) {
                    if let entry {
                        QuoteCardImage(entry: entry, author: author(for: entry), style: style)
                            .scaleEffect(previewScale, anchor: .top)
                            .frame(width: SharePoster.size.width * previewScale, height: SharePoster.size.height * previewScale)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Quote card: \(entry.text), from \(entry.bookTitle)")
                        stylePicker
                        quotePicker(current: entry)
                        actions(entry)
                    } else {
                        Text("Keep a quote while you read, from the session or a book’s journal, and it can become a card here.")
                            .leafStyle(.body, color: .inkSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, Space.xxl)
                    }
                }
                .leafMargins()
                .padding(.vertical, Space.l)
            }
            .scrollIndicators(.hidden)
            .paperBackground()
            .navigationTitle("Quote card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        Haptics.shared.tap()
                        dismiss()
                    }
                }
            }
            .task(id: renderKey) {
                render()
            }
            .onAppear {
                if entryID == nil { entryID = initialEntryID }
                if router.historyStage == "style" {
                    router.historyStage = nil
                    style = .matcha
                }
            }
        }
        .presentationBackground(Color.paper)
    }

    private var previewScale: CGFloat { 0.82 }

    private var renderKey: String { "\(entry?.id.uuidString ?? "")|\(style.rawValue)|\(entry?.text.count ?? 0)" }

    private func author(for entry: JournalEntry) -> String {
        store.item(entry.bookID)?.book.author ?? entry.bookAuthor
    }

    private func render() {
        guard let entry else {
            image = nil
            return
        }
        saveState = .idle
        image = SharePoster.render(QuoteCardImage(entry: entry, author: author(for: entry), style: style))
    }

    // MARK: Pickers

    private var stylePicker: some View {
        HStack(spacing: Space.m) {
            ForEach(QuoteCardStyle.allCases, id: \.self) { option in
                Button {
                    Haptics.shared.selection()
                    style = option
                } label: {
                    VStack(spacing: Space.xs) {
                        Circle()
                            .fill(option.background)
                            .overlay { Circle().strokeBorder(option == style ? Color.accent : Color.hairline, lineWidth: option == style ? 2 : 1) }
                            .overlay { Circle().fill(option.accent).frame(width: 10, height: 10) }
                            .frame(width: 36, height: 36)
                        Text(option.title)
                            .leafStyle(.caption, color: option == style ? .accent : nil)
                    }
                    .frame(minWidth: Space.hitTarget, minHeight: Space.hitTarget)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("\(option.title) style")
                .accessibilityAddTraits(option == style ? AccessibilityTraits.isSelected : AccessibilityTraits())
            }
        }
    }

    @ViewBuilder
    private func quotePicker(current: JournalEntry) -> some View {
        let all = quotes
        if all.count > 1 {
            Menu {
                ForEach(all) { quote in
                    Button {
                        Haptics.shared.selection()
                        entryID = quote.id
                    } label: {
                        Text("\(String(quote.text.prefix(60)))\(quote.text.count > 60 ? "…" : "") · \(quote.bookTitle)")
                    }
                }
            } label: {
                HStack(spacing: Space.xs) {
                    Text("Another quote")
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .leafStyle(.ui, color: .accent)
                .frame(minHeight: Space.hitTarget)
            }
        }
    }

    // MARK: Share and save

    @ViewBuilder
    private func actions(_ entry: JournalEntry) -> some View {
        VStack(spacing: Space.s) {
            if let image {
                ShareLink(item: Image(uiImage: image), preview: SharePreview(entry.bookTitle, image: Image(uiImage: image))) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(LeafType.ui)
                        .foregroundStyle(Color.paper)
                        .frame(maxWidth: .infinity, minHeight: Space.hitTarget)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ink)
                SecondaryGlassButton(saveTitle, systemImage: saveState == .saved ? "checkmark" : "photo.on.rectangle", compact: true) {
                    Task { await save(image) }
                }
                .disabled(saveState == .saving || saveState == .saved)
                if saveState == .denied {
                    Text("Leaf can’t add to your photos. Allow it in Settings, then Privacy, then Photos.")
                        .leafStyle(.caption)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var saveTitle: String {
        switch saveState {
        case .idle, .denied: return "Save to Photos"
        case .saving: return "Saving…"
        case .saved: return "Saved to Photos"
        }
    }

    private func save(_ image: UIImage) async {
        saveState = .saving
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveState = .denied
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            Haptics.shared.success()
            saveState = .saved
        } catch {
            saveState = .idle
        }
    }
}

// MARK: - Styles

/// The papers and teas a quote card comes in.
enum QuoteCardStyle: String, CaseIterable, Hashable {
    case paper, matcha, rooibos, night

    var title: String {
        switch self {
        case .paper: return "Paper"
        case .matcha: return "Matcha"
        case .rooibos: return "Rooibos"
        case .night: return "Night"
        }
    }

    var background: Color {
        switch self {
        case .paper: return Color(hex: 0xF6F0E4)
        case .matcha: return Color(hex: 0xE6EBD5)
        case .rooibos: return Color(hex: 0xF2DFD2)
        case .night: return Color(hex: 0x1F1B17)
        }
    }

    var ink: Color {
        switch self {
        case .paper: return Color(hex: 0x2B2520)
        case .matcha: return Color(hex: 0x2C3522)
        case .rooibos: return Color(hex: 0x45210F)
        case .night: return Color(hex: 0xF1E8DA)
        }
    }

    var accent: Color {
        switch self {
        case .paper: return Color(hex: 0xB8742E)
        case .matcha: return Color(hex: 0x7F9744)
        case .rooibos: return Color(hex: 0xA9502B)
        case .night: return Color(hex: 0xD6A25A)
        }
    }
}

// MARK: - The card

/// The image itself: a big opening quote mark, the words, then the book, the author and the page, and a tea ring.
/// Drawn at the share poster's size; long quotes get a smaller face.
struct QuoteCardImage: View {
    let entry: JournalEntry
    let author: String
    let style: QuoteCardStyle

    private var fontSize: CGFloat {
        switch entry.text.count {
        case ..<90: return 30
        case ..<180: return 24
        case ..<320: return 19
        default: return 16
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Image(systemName: "quote.opening")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(style.accent)
                .accessibilityHidden(true)
            Text(entry.text)
                .font(.custom(LeafFontName.italic, fixedSize: fontSize))
                .foregroundStyle(style.ink)
                .lineSpacing(fontSize * 0.18)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.m)
            Rectangle()
                .fill(style.accent.opacity(0.6))
                .frame(width: 40, height: 1.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.bookTitle)
                    .font(.custom(LeafFontName.regular, fixedSize: 17))
                    .foregroundStyle(style.ink)
                    .lineLimit(2)
                Text(attribution)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(style.ink.opacity(0.7))
                    .lineLimit(1)
            }
            HStack(alignment: .bottom) {
                TeaRingStamp(mark: .read(1), seed: entry.text.count, diameter: 40)
                Spacer()
                Text("Leaf")
                    .font(.custom(LeafFontName.italic, fixedSize: 18))
                    .foregroundStyle(style.ink.opacity(0.75))
            }
        }
        .padding(Space.xxl)
        .frame(width: SharePoster.size.width, height: SharePoster.size.height, alignment: .topLeading)
        .background(style.background)
    }

    /// "Madeline Miller · p. 74"
    private var attribution: String {
        var parts: [String] = []
        if !author.isEmpty { parts.append(author) }
        if let page = entry.page { parts.append("p. \(page)") }
        return parts.joined(separator: " · ")
    }
}
