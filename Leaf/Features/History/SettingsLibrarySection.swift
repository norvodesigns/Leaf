import SwiftUI
import UniformTypeIdentifiers

/// Settings, "Your library": the reading log, a backup file of everything, and restoring one. Restoring merges with
/// iCloud's own rules, so nothing newer on this phone is replaced.
struct SettingsLibrarySection: View {
    @Environment(LibraryStore.self) private var store

    @State private var importsBackup = false
    @State private var pending: PendingRestore?
    @State private var restoreMessage: String?

    private struct PendingRestore: Identifiable {
        let id = UUID()
        var library: LeafData
        var preview: LeafBackup.Preview
    }

    var body: some View {
        Section {
            NavigationLink {
                ReadingLogView()
            } label: {
                Text("Reading log").leafStyle(.uiBody)
            }

            ShareLink(
                item: LibraryBackupFile(data: store.data, exportedAt: store.now, name: LeafBackup.fileName(now: store.now, calendar: store.calendar)),
                preview: SharePreview("Leaf backup")
            ) {
                SettingsDisclosureRow("Back up your library")
            }
            .buttonStyle(.plain)

            Button {
                Haptics.shared.tap()
                importsBackup = true
            } label: {
                SettingsDisclosureRow("Restore from a backup")
            }
            .buttonStyle(.plain)
        } header: {
            Text("Your library").leafStyle(.eyebrow)
        } footer: {
            Text(restoreMessage ?? "A backup is one file with everything: books, sittings, notes, teas and settings. Keep it wherever you like. Restoring adds what’s missing; nothing newer here is replaced.")
                .leafStyle(.caption)
        }
        .settingsRows()
        .fileImporter(isPresented: $importsBackup, allowedContentTypes: [.json]) { result in
            read(result)
        }
        .confirmationDialog("Restore this backup?", isPresented: pendingBinding, titleVisibility: .visible, presenting: pending) { restore in
            Button("Restore") {
                store.importBackup(restore.library)
                Haptics.shared.success()
                restoreMessage = "Restored. \(summary(restore.preview))"
                pending = nil
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { restore in
            Text(confirmation(restore.preview))
        }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private func read(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let bytes = try Data(contentsOf: url)
            let library = try LeafBackup.decode(bytes)
            let preview = LeafBackup.preview(of: library, against: store.data, exportedAt: LeafBackup.exportedAt(bytes))
            pending = PendingRestore(library: library, preview: preview)
        } catch {
            if case LeafBackup.Failure.tooNew? = error as? LeafBackup.Failure {
                restoreMessage = "That backup is from a newer Leaf. Update Leaf, then restore it."
            } else {
                restoreMessage = "That file isn’t a Leaf backup. Nothing was changed."
            }
        }
    }

    /// "From 12 Oct 2026. It adds 3 books, 41 sittings and 2 notes; everything already here stays."
    private func confirmation(_ preview: LeafBackup.Preview) -> String {
        let made = preview.exportedAt.map { "From \(LeafFormat.format($0, template: "dMMMyyyy", calendar: store.calendar)). " } ?? ""
        if preview.isEmpty { return made + "Everything in it is already here; restoring brings back any newer settings or changes it holds." }
        return made + "It adds \(summary(preview)); everything already here stays."
    }

    /// "3 books, 41 sittings and 2 notes"
    private func summary(_ preview: LeafBackup.Preview) -> String {
        var parts: [String] = []
        func add(_ count: Int, _ one: String, _ many: String) {
            if count > 0 { parts.append("\(LeafFormat.number(count)) \(count == 1 ? one : many)") }
        }
        add(preview.books, "book", "books")
        add(preview.sittings, "sitting", "sittings")
        add(preview.notes, "note", "notes")
        add(preview.teas, "tea", "teas")
        add(preview.tastings, "tasting note", "tasting notes")
        guard !parts.isEmpty else { return "nothing new" }
        if parts.count == 1 { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
    }
}
