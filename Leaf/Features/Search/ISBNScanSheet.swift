import AVFoundation
import SwiftUI
import Vision
import VisionKit

/// What a hand-added book starts with: blank, or what the search or a barcode already told us.
struct ManualBookDraft: Identifiable, Hashable {
    var title = ""
    var author = ""
    var pages: Int?
    var year: Int?

    var id: String { "\(title)|\(author)|\(pages ?? 0)|\(year ?? 0)" }
}

/// How a scan ended: a book to add, or what we learned before handing over to the form.
enum ISBNScanOutcome: Hashable {
    case found(Book)
    case addByHand(ManualBookDraft)
}

/// Where an ISBN lookup landed.
enum ISBNLookupResult: Hashable {
    case found(Book)
    /// Open Library knows the book but not its length, so the form asks for it.
    case partial(OpenLibrary.ISBNMatch)
    case notFound
    case offline
}

@MainActor
enum ISBNLookup {
    /// Open Library finds the work; the catalog's copy of it is preferred, since it has the word count, themes and
    /// edition page counts. The catalog has no ISBNs, so this needs a connection.
    static func resolve(_ isbn: String, catalog: BookCatalog) async -> ISBNLookupResult {
        do {
            guard let match = try await OpenLibrary.lookup(isbn: isbn) else { return .notFound }
            if let known = catalog.book(id: match.workID) { return .found(known) }
            if let book = match.book { return .found(book) }
            return .partial(match)
        } catch {
            return .offline
        }
    }
}

/// "Scan a book" (Canopy): point the camera at the barcode on the back cover and the book comes up, ready to add. The
/// ISBN can be typed instead, which is also the whole screen where there is no camera.
struct ISBNScanSheet: View {
    let onOutcome: (ISBNScanOutcome) -> Void

    @Environment(BookCatalog.self) private var catalog
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var phase: Phase = .scanning
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool
    /// Bumped once the camera question has been answered, so the camera state is read again.
    @State private var cameraRevision = 0

    private enum Phase: Hashable {
        case scanning
        case lookingUp(String)
        case missing(isbn: String, result: ISBNLookupResult)
    }

    /// The ISBN being looked up, which drives the lookup task.
    private var lookingUp: String? {
        if case .lookingUp(let isbn) = phase { return isbn }
        return nil
    }

    private var cameraState: CameraState {
        _ = cameraRevision
        if !DataScannerViewController.isSupported { return .unsupported }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted: return .denied
        case .notDetermined: return .ready
        default: return DataScannerViewController.isAvailable ? .ready : .denied
        }
    }

    private enum CameraState {
        case ready, denied, unsupported
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Canopy.Space.xl) {
                    camera
                    status
                    typeIn
                }
                .padding(.horizontal, Canopy.Space.margin)
                .padding(.top, Canopy.Space.s)
                .padding(.bottom, Canopy.Space.xl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .canopyBackdrop()
            .navigationTitle("Scan a book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: lookingUp) {
                guard let isbn = lookingUp else { return }
                let result = await ISBNLookup.resolve(isbn, catalog: catalog)
                guard !Task.isCancelled, lookingUp == isbn else { return }
                if case .found(let book) = result {
                    CanopyFeel.play(.snap)
                    finish(.found(book))
                } else {
                    CanopyFeel.play(.warning)
                    withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
                        phase = .missing(isbn: isbn, result: result)
                    }
                }
            }
            .task {
                // Ask for the camera up front, so the scanner starts with an answer rather than a blank view.
                guard DataScannerViewController.isSupported, AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
                _ = await AVCaptureDevice.requestAccess(for: .video)
                cameraRevision += 1
            }
            .onChange(of: typed) { _, new in
                // A complete, valid ISBN looks itself up; no button to find.
                if let isbn = ISBN.parse(new), lookingUp != isbn { lookUp(isbn) }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Camera

    @ViewBuilder
    private var camera: some View {
        switch cameraState {
        case .ready:
            ISBNScannerView(isActive: phase == .scanning) { isbn in
                CanopyFeel.play(.select)
                lookUp(isbn)
            }
            .frame(height: 280)
            .clipShape(.rect(cornerRadius: Canopy.Radius.card, style: .continuous))
            .overlay { reticle }
            .overlay(alignment: .bottom) {
                Text("Point at the barcode on the back cover")
                    .canopyText(.caption, color: Canopy.text)
                    .padding(.horizontal, Canopy.Space.m)
                    .padding(.vertical, Canopy.Space.xs)
                    .canopyGlass(interactive: false)
                    .padding(.bottom, Canopy.Space.m)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Camera. Point it at the barcode on the back cover.")
        case .denied:
            cameraNote(
                title: "The camera is off for Leaf.",
                message: "Turn it on in Settings to scan barcodes, or type the ISBN below.",
                actionTitle: "Open Settings"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .unsupported:
            cameraNote(
                title: "No camera to scan with here.",
                message: "Type the ISBN from the back cover or the copyright page instead.",
                actionTitle: nil,
                action: nil
            )
        }
    }

    /// A soft frame where the barcode should sit; static, so it costs nothing.
    private var reticle: some View {
        RoundedRectangle(cornerRadius: Canopy.Radius.control, style: .continuous)
            .strokeBorder(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
            .frame(width: 240, height: 110)
            .opacity(phase == .scanning ? 1 : 0.3)
            .allowsHitTesting(false)
    }

    private func cameraNote(title: String, message: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        VStack(spacing: Canopy.Space.m) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 44, weight: .light))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Canopy.textSecondary)
                .accessibilityHidden(true)
            Text(title)
                .canopyText(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .canopyText(.body, color: Canopy.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                CanopyGlassButton(actionTitle, systemImage: "gearshape", compact: true, action: action)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Canopy.Space.l)
        .canopyCard()
    }

    // MARK: Status

    @ViewBuilder
    private var status: some View {
        switch phase {
        case .scanning:
            EmptyView()
        case .lookingUp(let isbn):
            HStack(spacing: Canopy.Space.s) {
                ProgressView()
                Text("Looking up \(Self.formatted(isbn))…")
                    .canopyText(.caption)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        case .missing(let isbn, let result):
            missing(isbn: isbn, result: result)
                .canopyFocusInTransition()
        }
    }

    private func missing(isbn: String, result: ISBNLookupResult) -> some View {
        VStack(alignment: .leading, spacing: Canopy.Space.m) {
            Text("ISBN \(Self.formatted(isbn))").canopyText(.label)
            Text(missingMessage(result))
                .canopyText(.body)
                .fixedSize(horizontal: false, vertical: true)
            GlassEffectContainer(spacing: Canopy.Space.m) {
                VStack(spacing: Canopy.Space.m) {
                    CanopyGlassButton("Add it by hand", systemImage: "square.and.pencil", accent: .forest) {
                        finish(.addByHand(draft(from: result)))
                    }
                    CanopyGlassButton("Scan another", systemImage: "barcode.viewfinder", accent: .forest, compact: true) {
                        typed = ""
                        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) { phase = .scanning }
                    }
                }
            }
        }
    }

    private func missingMessage(_ result: ISBNLookupResult) -> String {
        switch result {
        case .partial(let match): return "Found “\(match.title)”, but not how long it is. Add the page count and it’s on your shelf."
        case .offline: return "Open Library couldn’t be reached, and the books on this device don’t carry ISBNs. Add it by hand, or try again when you’re online."
        default: return "Open Library doesn’t know this one. Add it by hand; it only takes a title and a page count."
        }
    }

    private func draft(from result: ISBNLookupResult) -> ManualBookDraft {
        guard case .partial(let match) = result else { return ManualBookDraft() }
        return ManualBookDraft(title: match.title, author: match.author ?? "", pages: match.pages, year: match.year)
    }

    // MARK: Typing

    private var typeIn: some View {
        VStack(alignment: .leading, spacing: Canopy.Space.xs) {
            Text("Or type the ISBN").canopyText(.label)
            TextField("978-0-00-000000-0", text: $typed)
                .font(.system(.title2, design: .rounded, weight: .medium).monospacedDigit())
                .foregroundStyle(Canopy.text)
                .keyboardType(.numbersAndPunctuation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($fieldFocused)
                .padding(.vertical, Canopy.Space.s)
                .accessibilityLabel("ISBN")
                .onSubmit {
                    if let isbn = ISBN.parse(typed) { lookUp(isbn) }
                }
            Rectangle()
                .fill(fieldFocused ? CanopyAccent.forest.color : Canopy.separator)
                .frame(height: fieldFocused ? 2 : 1)
                .animation(Canopy.Motion.snappy, value: fieldFocused)
            if !typed.isEmpty, ISBN.looksLikeISBN(typed), ISBN.parse(typed) == nil, typed.filter(\.isNumber).count >= 10 {
                Text("That doesn’t add up to an ISBN. Check the digits?")
                    .canopyText(.caption)
            }
        }
    }

    // MARK: Actions

    private func lookUp(_ isbn: String) {
        fieldFocused = false
        withAnimation(Canopy.Motion.resolved(Canopy.Motion.smooth, reduceMotion: reduceMotion)) {
            phase = .lookingUp(isbn)
        }
    }

    private func finish(_ outcome: ISBNScanOutcome) {
        onOutcome(outcome)
        dismiss()
    }

    /// "978-0-261-10221-7" reads better than a run of 13 digits; the groups here are only for the eye.
    static func formatted(_ isbn: String) -> String {
        guard isbn.count == 13 else { return isbn }
        let chars = Array(isbn)
        return "\(String(chars[0..<3]))-\(String(chars[3..<12]))-\(chars[12])"
    }
}

/// VisionKit's `DataScannerViewController`, set to book barcodes (EAN-13, 978/979), reporting each new ISBN once.
/// Scanning stops while `isActive` is false (a lookup is running), which saves the camera and the battery.
struct ISBNScannerView: UIViewControllerRepresentable {
    let isActive: Bool
    let onISBN: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onISBN = onISBN
        if isActive, !scanner.isScanning {
            context.coordinator.lastISBN = nil
            try? scanner.startScanning()
        } else if !isActive, scanner.isScanning {
            scanner.stopScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onISBN: onISBN)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onISBN: (String) -> Void
        /// The last ISBN reported, so a barcode held in view is looked up once.
        var lastISBN: String?

        init(onISBN: @escaping (String) -> Void) {
            self.onISBN = onISBN
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue,
                      let isbn = ISBN.fromBarcode(payload), isbn != lastISBN else { continue }
                lastISBN = isbn
                onISBN(isbn)
                return
            }
        }
    }
}
