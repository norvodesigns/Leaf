import SwiftUI
import VisionKit

// MARK: - Ambience

/// The room's sound during a session: silence, rain, the fire, the kettle, a café, a library. Strictly opt-in: nothing
/// plays until the reader picks a sound here, it mixes with their own music, and it stops when the session ends.
struct AmbienceSheet: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var volume = Double(AmbiencePlayer.shared.volume)

    private var player: AmbiencePlayer { AmbiencePlayer.shared }

    /// Your usual (chosen here or in Settings) comes first; nothing plays until you tap it.
    private var options: [Ambience] {
        var all = AmbienceCatalog.all.filter { !$0.isSilence }
        if let saved = store.preferences.ambienceID, let index = all.firstIndex(where: { $0.id == saved }) {
            all.insert(all.remove(at: index), at: 0)
        }
        return all
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(nil)
                    ForEach(options) { ambience in
                        row(ambience)
                    }
                } footer: {
                    Text("Sounds play only when you choose one, and mix with your own music. They stop when the session ends.")
                        .leafStyle(.caption)
                }
                .listRowBackground(Color.paperRaised)

                if player.currentID != nil {
                    Section {
                        Slider(value: $volume, in: 0...1) {
                            Text("Volume")
                        } minimumValueLabel: {
                            Image(systemName: "speaker.fill")
                                .foregroundStyle(Color.inkTertiary)
                        } maximumValueLabel: {
                            Image(systemName: "speaker.wave.3.fill")
                                .foregroundStyle(Color.inkTertiary)
                        }
                        .onChange(of: volume) { _, level in
                            player.setVolume(Float(level))
                        }
                    } header: {
                        Text("Volume")
                            .leafStyle(.eyebrow)
                    }
                    .listRowBackground(Color.paperRaised)
                }
            }
            .scrollContentBackground(.hidden)
            .paperBackground()
            .tint(Color.accent)
            .navigationTitle("Ambience")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.shared.tap()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
    }

    private func row(_ ambience: Ambience?) -> some View {
        let isOn = player.currentID == ambience?.id
        return Button {
            choose(ambience)
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: ambience?.symbol ?? "speaker.slash")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isOn ? Color.accent : Color.inkSecondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text(ambience?.name ?? "Silence")
                        .leafStyle(.uiBody)
                    Text(caption(for: ambience))
                        .leafStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private func caption(for ambience: Ambience?) -> String {
        guard let ambience else { return "Just the page turning." }
        return ambience.id == store.preferences.ambienceID ? "Your usual. \(ambience.blurb)" : ambience.blurb
    }

    /// Starts the chosen sound (the reader's tap is the only thing that ever starts one), or stops it.
    private func choose(_ ambience: Ambience?) {
        Haptics.shared.selection()
        if let ambience {
            let level = player.currentID == nil ? (CozySettings.ambienceVolume ?? ambience.defaultVolume) : volume
            volume = level
            player.play(ambience.id, volume: Float(level))
        } else {
            player.stop()
        }
        // Remembered so this sheet can offer it first next time. It is never started on its own.
        store.updatePreferences { $0.ambienceID = ambience?.id }
    }
}

// MARK: - Journal

/// A thought or a quote, written mid-session without stopping the clock. A quote can be lifted from the page with
/// Live Text: only the words are kept, never a photo.
struct JournalCaptureSheet: View {
    let book: Book
    let sessionID: UUID?

    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var kind: JournalEntry.Kind = .thought
    @State private var text = ""
    @State private var pageText: String
    @State private var showsScanner = false
    @FocusState private var isWriting: Bool

    init(book: Book, sessionID: UUID?, page: Int) {
        self.book = book
        self.sessionID = sessionID
        _pageText = State(initialValue: page > 0 ? String(page) : "")
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    Picker("Kind", selection: $kind) {
                        Text("A thought").tag(JournalEntry.Kind.thought)
                        Text("A quote").tag(JournalEntry.Kind.quote)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, _ in Haptics.shared.selection() }

                    editor

                    HStack(spacing: Space.m) {
                        Text("Page")
                            .leafStyle(.ui)
                        TextField("142", text: $pageText)
                            .keyboardType(.numberPad)
                            .font(LeafType.data)
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                            .frame(width: 72)
                            .padding(.vertical, Space.s)
                            .background(Color.paperSunken, in: .capsule)
                            .accessibilityLabel("Page number")
                        Spacer(minLength: 0)
                        if QuoteScannerView.isAvailable {
                            Button {
                                Haptics.shared.tap()
                                isWriting = false
                                showsScanner = true
                            } label: {
                                Label("Scan the page", systemImage: "text.viewfinder")
                                    .font(.system(.subheadline, weight: .medium))
                                    .frame(minHeight: Space.hitTarget)
                            }
                            .buttonStyle(.pressable)
                        }
                    }

                    Text("Kept in your journal for \(Text(book.title).italic()). Only the words are saved.")
                        .leafStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .paperBackground()
            .navigationTitle(kind == .quote ? "A quote" : "A thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.paper)
        .onAppear { isWriting = true }
        .sheet(isPresented: $showsScanner) {
            QuoteScanSheet { scanned in
                kind = .quote
                text = trimmed.isEmpty ? scanned : trimmed + " " + scanned
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(kind == .quote ? "Copy the line that stopped you…" : "What are you thinking?")
                    .leafStyle(.body, color: .inkTertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .font(kind == .quote ? LeafType.passage.italic() : LeafType.body)
                .foregroundStyle(Color.ink)
                .scrollContentBackground(.hidden)
                .focused($isWriting)
                .frame(minHeight: 160)
                .accessibilityLabel(kind == .quote ? "Quote" : "Thought")
        }
        .padding(Space.m)
        .background(Color.paperRaised, in: Radius.shape(Radius.tile))
        .overlay {
            Radius.shape(Radius.tile)
                .strokeBorder(Color.hairline, lineWidth: 1 / displayScale)
        }
    }

    private func save() {
        let page = Int(pageText.filter(\.isNumber)).map { min(max(0, $0), book.pages) }
        _ = store.addJournalEntry(bookID: book.id, kind: kind, text: trimmed, page: page, sessionID: sessionID)
        Haptics.shared.success()
        dismiss()
    }
}

// MARK: - Live Text

/// The camera, reading the page: tap the lines you want and they are gathered as the quote. Text only; no picture is
/// kept. Needs a device with Live Text (the button hides otherwise).
struct QuoteScanSheet: View {
    let onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                QuoteScannerView { line in
                    Haptics.shared.selection()
                    lines.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .ignoresSafeArea()
                Text(lines.isEmpty ? "Tap the lines you want to keep." : lines.joined(separator: " "))
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Color.ink)
                    .lineLimit(5)
                    .padding(Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .padding(Space.l)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            .navigationTitle("Scan a quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        onDone(lines.joined(separator: " "))
                        dismiss()
                    }
                    .disabled(lines.isEmpty)
                }
            }
        }
    }
}

/// VisionKit's `DataScannerViewController`, set to text, reporting the lines the reader taps.
struct QuoteScannerView: UIViewControllerRepresentable {
    let onTap: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onTap: (String) -> Void

        init(onTap: @escaping (String) -> Void) {
            self.onTap = onTap
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .text(let text) = item {
                onTap(text.transcript)
            }
        }
    }
}
