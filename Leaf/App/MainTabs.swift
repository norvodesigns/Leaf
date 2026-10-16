import SwiftUI

/// Placeholder until the tab screens land.
struct MainTabs: View {
    @Environment(LibraryStore.self) private var store

    var body: some View {
        Text("\(store.reading.count) reading · \(store.toRead.count) to read")
    }
}
