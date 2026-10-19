import SwiftUI

/// Onboarding's deck step: swipe a few first reads before the grid. Kept books join the reader's picks (the next step
/// shows them as "Your stack"), "start now" puts a book first so it goes on the desk, and passes teach the deck what
/// not to show. Nothing asks "Where are you?" here; that waits for each book's first session. The page scrolls, so
/// the cards move sideways only and "start now" is a button.
struct OnboardingDeckView: View {
    @Binding var picks: [Book]

    @Environment(LibraryStore.self) private var store
    @Environment(BookCatalog.self) private var catalog
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model = SwipeDeckModel()

    var body: some View {
        OnboardingPage(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: Space.l) {
                OnboardingHeading(
                    title: "Swipe a few.",
                    message: "Keep what you’d like to read. The book icon puts one first, on your desk.",
                    centered: false
                )
                SwipeDeckView(model: model, style: .compact, wpm: store.wpm, height: typeSize.isAccessibilitySize ? 280 : 320)
            }
        }
        .task {
            await catalog.load()
            let binding = $picks
            let store = store
            model.onSwipe = { choice, book in
                switch choice {
                case .keep:
                    if !binding.wrappedValue.contains(where: { $0.id == book.id }) {
                        binding.wrappedValue.append(book)
                    }
                case .startNow:
                    binding.wrappedValue.removeAll { $0.id == book.id }
                    binding.wrappedValue.insert(book, at: 0)
                case .pass:
                    store.dismiss(book.id)
                }
            }
            model.onUndo = { swipe in
                switch swipe.choice {
                case .keep, .startNow:
                    binding.wrappedValue.removeAll { $0.id == swipe.book.id }
                case .pass:
                    store.undismiss(swipe.book.id)
                }
            }
            model.load(
                pool: catalog.books,
                stats: catalog.stats,
                context: store.recommendationContext(catalog: catalog),
                seed: SeededGenerator.daySeed(store.now, calendar: store.calendar)
            )
        }
    }
}
