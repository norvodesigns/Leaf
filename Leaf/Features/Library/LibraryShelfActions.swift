import Foundation

/// Shelf changes that come with a signature haptic, shared by the Library and book detail.
@MainActor
enum LibraryShelfActions {
    /// Marks a book finished (adding it to the Finished shelf first if it isn't in the library):
    /// `bookFinished` scaled by the book's heft, then `success()` a second later (DESIGN.md §8).
    /// `readBeforeLeaf` is Search's "Already read": no finish date unless the book was started in Leaf.
    static func markFinished(_ book: Book, store: LibraryStore, readBeforeLeaf: Bool = false) {
        Motion.animate(Motion.paper) {
            if readBeforeLeaf {
                store.addReadBeforeLeaf(book)
            } else if store.item(book.id) == nil {
                store.add(book, to: .finished)
            } else {
                store.markFinished(book.id)
            }
        }
        Haptics.shared.play(.bookFinished, heft: Haptics.heft(pages: book.pages))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            Haptics.shared.success()
        }
    }

    /// Moves a book to another shelf with a light tap.
    static func move(_ bookID: String, to shelf: Shelf, store: LibraryStore) {
        Motion.animate(Motion.paper) {
            store.move(bookID, to: shelf)
        }
        Haptics.shared.tap()
    }

    /// Takes a book off every shelf (after the reader confirmed): `warning()`.
    static func remove(_ bookID: String, store: LibraryStore) {
        Motion.animate(Motion.paper) {
            store.remove(bookID)
        }
        Haptics.shared.warning()
    }
}
