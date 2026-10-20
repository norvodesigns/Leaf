import Foundation

/// Reads and writes everything Leaf knows to a single JSON file in Application Support.
///
/// The file is the reader's whole library, so it is treated carefully: a rolling backup is kept next to it, and a file
/// that cannot be read is set aside rather than overwritten by an empty library.
struct Persistence: Sendable {
    let url: URL

    /// How often the rolling backup is refreshed from the live file.
    static let backupInterval: TimeInterval = 6 * 3600

    static let shared: Persistence = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Leaf", isDirectory: true)
        return Persistence(url: base.appendingPathComponent("library.json"))
    }()

    /// A throwaway location for previews and screenshot runs, so they never touch real data.
    static func ephemeral() -> Persistence {
        Persistence(url: FileManager.default.temporaryDirectory.appendingPathComponent("leaf-\(UUID().uuidString).json"))
    }

    var backupURL: URL { url.deletingPathExtension().appendingPathExtension("backup.json") }

    /// The saved library, falling back to the backup when the main file is damaged. Returns nil only when there is
    /// nothing readable (a first launch, or both files are unusable; the damaged file is kept for recovery).
    func load() -> LeafData? {
        if let value = read(url) { return value }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        // The main file exists but won't decode: keep it for inspection, then try the last good backup.
        let stamp = Int(Date().timeIntervalSince1970)
        let aside = url.deletingPathExtension().appendingPathExtension("damaged-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return read(backupURL)
    }

    func save(_ value: LeafData) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        refreshBackupIfDue()
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Removes the library, its rolling backup and any damaged copies set aside, so nothing of it stays on disk.
    func delete() {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: backupURL)
        let folder = url.deletingLastPathComponent()
        let damagedPrefix = url.deletingPathExtension().lastPathComponent + ".damaged-"
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(damagedPrefix) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    // MARK: Internals

    private func read(_ location: URL) -> LeafData? {
        guard let data = try? Data(contentsOf: location) else { return nil }
        return try? JSONDecoder().decode(LeafData.self, from: data)
    }

    /// Copies the current file to the backup at most once per interval, and only if it is itself readable, so a
    /// bad write can never replace a good backup.
    private func refreshBackupIfDue() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path), read(url) != nil else { return }
        if let attributes = try? fm.attributesOfItem(atPath: backupURL.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Self.backupInterval {
            return
        }
        try? fm.removeItem(at: backupURL)
        try? fm.copyItem(at: url, to: backupURL)
    }
}
