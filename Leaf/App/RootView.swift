import SwiftUI

/// Temporary shell; replaced by onboarding + tabs.
struct RootView: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Text("Leaf · \(store.data.items.count) books")
    }
}
