import SwiftUI

/// "The bookmark is the progress control" (NEXT.md section 3): a stylised page block, as thick as the book is long,
/// with the ribbon hanging down its fore-edge. Drag the ribbon's end down the block to set the page; the ribbon's depth
/// is the page (`RibbonDepthMapping`, which spreads long books out near the top so every page stays reachable). A slow
/// drag lands on single pages; a fast one snaps to round numbers. The page is set large above, and a typed field and
/// VoiceOver's adjustable action are always there as the accessible way in.
struct RibbonPageControl: View {
    @Binding var page: Int
    let pages: Int
    /// The page the reader started from, if any: drawn as a faint mark.
    var startPage: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var dragDepth: Double?
    @State private var lastSample: (depth: Double, time: Double)?
    @State private var velocity = 0.0
    @State private var typed = ""
    @State private var ribbonKick = 0
    @FocusState private var isTyping: Bool

    private var mapping: RibbonDepthMapping { RibbonDepthMapping(pages: pages) }

    /// The block's height on screen: taller for longer books, within the room a phone has.
    private var blockHeight: CGFloat {
        CGFloat(RibbonDepthMapping.pageBlockThickness(forPages: pages, from: 220, to: 320))
    }

    private var depth: Double { dragDepth ?? mapping.depth(forPage: page) }

    var body: some View {
        VStack(spacing: Space.l) {
            VStack(spacing: -8) {
                Text("\(page)")
                    .leafStyle(.heroNumeral)
                    .numericBlur(value: Double(page), velocityBlur: CGFloat(min(6, abs(velocity) * 0.6)))
                Text("of \(LeafFormat.number(pages)) pages")
                    .leafStyle(.caption)
            }
            .accessibilityHidden(true)

            block
                .frame(height: blockHeight + 40)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Bookmark")
                .accessibilityValue("Page \(page) of \(pages)")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: set(page + 1, haptic: true)
                    case .decrement: set(page - 1, haptic: true)
                    @unknown default: break
                    }
                }

            HStack(spacing: Space.s) {
                Text("Or type the page")
                    .leafStyle(.caption)
                TextField("\(page)", text: $typed)
                    .keyboardType(.numberPad)
                    .font(LeafType.data)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
                    .padding(.vertical, Space.s)
                    .background(Color.paperSunken, in: .capsule)
                    .focused($isTyping)
                    .accessibilityLabel("Page number")
                    .onChange(of: typed) { _, text in
                        if let value = Int(text.filter(\.isNumber)) { set(value, haptic: false) }
                    }
            }
            .frame(minHeight: Space.hitTarget)
        }
    }

    // MARK: The block

    private var block: some View {
        let ribbonWidth: CGFloat = 16
        let canvas = PhysicalRibbon.canvasSize(length: blockHeight, width: ribbonWidth)
        let ribbonLength = max(18, CGFloat(depth) * blockHeight)
        return HStack(alignment: .top, spacing: 0) {
            pageBlock
                .frame(width: 150, height: blockHeight)
                .overlay(alignment: .topTrailing) {
                    // The ribbon hangs down the fore-edge to the page.
                    // Setting a page nudges the ribbon that is already hanging there; it never starts over mid-swing.
                    PhysicalRibbon(length: ribbonLength, width: ribbonWidth, seed: 7, swaysOnAppear: true, nudge: ribbonKick, isInteractive: false)
                        .frame(width: canvas.width, height: canvas.height, alignment: .top)
                        .offset(x: canvas.width / 2 - ribbonWidth * 0.2, y: -4)
                        .allowsHitTesting(false)
                }
            markers
                .frame(width: 64, height: blockHeight, alignment: .topLeading)
                .padding(.leading, Space.xl)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .gesture(dragGesture)
    }

    /// The closed book seen from the fore-edge: a stack of page lines in a soft frame.
    private var pageBlock: some View {
        let lines = RibbonDepthMapping.edgeLineCount(forPages: pages)
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.paperRaised)
            VStack(spacing: 0) {
                ForEach(0..<lines, id: \.self) { _ in
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(Color.hairline)
                        .frame(height: 1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            // Pages read: a warm wash down to the bookmark.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.accentSoft.opacity(0.7))
                    .frame(height: CGFloat(depth) * blockHeight)
                Spacer(minLength: 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.hairlineStrong, lineWidth: 1)
        }
    }

    private var markers: some View {
        let step = RibbonDepthMapping.markerStep(forPages: pages)
        return ZStack(alignment: .topLeading) {
            ForEach(mapping.markerDepths(everyPages: step, limit: 10), id: \.self) { markerDepth in
                Text("\(mapping.page(forDepth: markerDepth))")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.inkTertiary)
                    .offset(y: CGFloat(markerDepth) * blockHeight - 7)
            }
            if let startPage, startPage > 0 {
                Text("began \(startPage)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.ribbon)
                    .offset(y: CGFloat(mapping.depth(forPage: startPage)) * blockHeight - 7)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: Dragging

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let raw = Double((value.location.y - 8) / blockHeight)
                let clamped = min(1, max(0, raw))
                let now = value.time.timeIntervalSinceReferenceDate
                if let lastSample, now > lastSample.time {
                    velocity = (clamped - lastSample.depth) / (now - lastSample.time)
                }
                lastSample = (clamped, now)
                dragDepth = clamped
                let snapped = mapping.snappedPage(forDepth: clamped, depthVelocity: velocity)
                set(snapped, haptic: true)
            }
            .onEnded { _ in
                withAnimation(reduceMotion ? Motion.fade : Motion.paper) {
                    dragDepth = nil
                    velocity = 0
                }
                lastSample = nil
                Haptics.shared.play(.pageTurn)
                ribbonKick += 1
            }
    }

    private func set(_ newPage: Int, haptic: Bool) {
        let clamped = min(max(0, newPage), max(0, pages))
        guard clamped != page else { return }
        let crossedMarker = clamped / 10 != page / 10
        page = clamped
        guard haptic else { return }
        if crossedMarker { Haptics.shared.play(.dialDetent) } else { Haptics.shared.selection() }
    }
}

#Preview("Ribbon page control") {
    @Previewable @State var page = 142
    RibbonPageControl(page: $page, pages: 310, startPage: 88)
        .padding(Space.xl)
        .frame(maxHeight: .infinity)
        .paperBackground()
}

#Preview("Ribbon page control · dark, long book") {
    @Previewable @State var page = 420
    RibbonPageControl(page: $page, pages: 1_100)
        .padding(Space.xl)
        .frame(maxHeight: .infinity)
        .paperBackground()
        .preferredColorScheme(.dark)
}
