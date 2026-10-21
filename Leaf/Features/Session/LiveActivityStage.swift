import SwiftUI

/// A stand-in Lock Screen that draws the reading Live Activity and its Dynamic Island regions with the same views the
/// widget extension uses. CI can't show a real Lock Screen, so screenshot runs land here (`-LeafScreen
/// liveactivity.reading`, `.paused`, `.goal`, `.cup`, `.steeping`, and `.watch` for the Apple Watch Smart Stack card in
/// every state). Not reachable in release builds.
struct LiveActivityStage: View {
    enum Kind: String, CaseIterable {
        case reading, paused, goal, cup, steeping, watch
    }

    let kind: Kind

    @State private var images = ReadingActivityImages()

    private var model: ReadingActivityModel { Self.model(kind) }

    static func model(_ kind: Kind, teaReady: Bool = false) -> ReadingActivityModel {
        let now = Date()
        let book = DemoData.hobbit
        let content: ReadingActivityContent
        switch kind {
        case .steeping, .watch:
            content = ReadingActivityContent(
                timerStart: now.addingTimeInterval(teaReady ? -300 : -70), goalSeconds: 240, currentPage: 142,
                state: teaReady ? .teaReady : .steeping, teaName: "Earl Grey"
            )
        case .reading:
            content = ReadingActivityContent(
                timerStart: now.addingTimeInterval(-(9 * 60 + 41)), goalSeconds: 13 * 60, currentPage: 142,
                state: .reading, line: "Steeped in The Hobbit"
            )
        case .paused:
            content = ReadingActivityContent(
                timerStart: now.addingTimeInterval(-(14 * 60)), isPaused: true, pausedElapsedSeconds: 9 * 60 + 41,
                goalSeconds: 13 * 60, currentPage: 146, state: .paused, line: "Your place is saved"
            )
        case .goal:
            content = ReadingActivityContent(
                timerStart: now.addingTimeInterval(-(27 * 60 + 12)), goalSeconds: 25 * 60, currentPage: 158,
                state: .goalReached, line: "Goal met. Read on?"
            )
        case .cup:
            content = ReadingActivityContent(
                timerStart: now.addingTimeInterval(-(6 * 60 + 5)), goalSeconds: 25 * 60, currentPage: 144,
                state: .reading, line: "A quiet read", teaName: "Earl Grey"
            )
        }
        return ReadingActivityModel(title: book.title, author: book.author, totalPages: book.pages, content: content, isStale: false)
    }

    /// The Apple Watch Smart Stack card in every state, at one and a half times its size on a 46 mm watch.
    private var watchCards: some View {
        let names = ["Reading", "Paused", "Goal met", "A cup", "Steeping", "Tea ready"]
        let models = [
            Self.model(.reading), Self.model(.paused), Self.model(.goal), Self.model(.cup), Self.model(.steeping),
            Self.model(.steeping, teaReady: true),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
            ForEach(names.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text(names[index]).font(.caption2).foregroundStyle(.white.opacity(0.6))
                    ReadingActivityWatchCard(model: models[index])
                        .padding(10)
                        .frame(width: 150, height: 80, alignment: .leading)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .scaleEffect(1.15, anchor: .topLeading)
                        .frame(width: 172, height: 92, alignment: .topLeading)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(hex: 0x2B3A4A), Color(hex: 0x14181F)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 28) {
                VStack(spacing: 2) {
                    Text(LeafFormat.format(Date(), template: "EEEEdMMMM"))
                        .font(.system(.headline, weight: .semibold))
                    Text("9:41")
                        .font(.system(size: 88, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 12)
                if kind == .watch {
                    watchCards
                } else {
                    ReadingActivityGallery(model: model, images: images)
                        .padding(.horizontal, 12)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            let rendered = LiveActivityCover.images(for: DemoData.hobbit)
            images = ReadingActivityImages(
                cover: rendered.cover.map { Image(uiImage: $0) },
                backdrop: rendered.backdrop.map { Image(uiImage: $0) }
            )
        }
    }
}

#Preview("Live Activity · reading") {
    LiveActivityStage(kind: .reading)
}

#Preview("Live Activity · goal") {
    LiveActivityStage(kind: .goal)
}
