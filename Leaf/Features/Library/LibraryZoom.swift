import SwiftUI

private struct LibraryBookZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// The namespace Library covers zoom into book detail from. `MainTabs` owns it for the Library
    /// tab's navigation stack: provide it with `.environment(\.libraryBookZoomNamespace, ns)` and add
    /// `.navigationTransition(.zoom(sourceID: route.book.id, in: ns))` to the Library destination.
    /// Without it, covers simply push (no zoom).
    var libraryBookZoomNamespace: Namespace.ID? {
        get { self[LibraryBookZoomNamespaceKey.self] }
        set { self[LibraryBookZoomNamespaceKey.self] = newValue }
    }
}

/// Registers a cover as a zoom source when the namespace has been provided, and does nothing otherwise
/// (previews, or a Library shown outside `MainTabs`).
private struct LibraryZoomSourceModifier: ViewModifier {
    let id: String
    @Environment(\.libraryBookZoomNamespace) private var namespace

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace = namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

extension View {
    /// Marks a cover in the Library as the zoom source for that book's detail (`id` is the book id).
    func libraryBookZoomSource(_ id: String) -> some View {
        modifier(LibraryZoomSourceModifier(id: id))
    }
}
