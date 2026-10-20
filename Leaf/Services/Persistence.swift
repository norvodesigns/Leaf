import Foundation

/// Reads and writes everything Leaf knows to a single JSON file in Application Support.
///
/// The file is the reader's whole library, so it is treated carefully: a rolling backup is kept next to it, a file
/// that cannot be decoded is set aside rather than overwritten by an empty library, and a file that cannot be *read*
/// right now (the iPhone hasn't been unlocked since it restarted, and Leaf was woken in the background) is left alone.
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

    /// Where the original is kept when loading had to leave entries out (written by a newer Leaf, say). Only the
    /// first such copy is kept, because later saves no longer hold what was left out.
    var partialCopyURL: URL { url.deletingPathExtension().appendingPathExtension("partial.json") }

    /// What a launch found on disk.
    enum Loaded {
        /// The saved library, or its backup when the main file was damaged or missing.
        case library(LeafData)
        /// Nothing saved: a first launch, or both files were damaged (those are kept for recovery).
        case nothing
        /// The library is there but can't be read yet (protected until the first unlock after a restart). Nothing may
        /// be written over it until it has been read.
        case unavailable
    }

    /// The saved library, falling back to the backup when the main file is damaged or missing.
    func loadLibrary() -> Loaded {
        switch read(url) {
        case .decoded(let value):
            return .library(value)
        case .unreadable:
            return .unavailable
        case .missing:
            // A backup with no library beside it means the library went missing; the backup beats starting over.
            return fallBackToBackup()
        case .damaged:
            // The file exists but won't decode: keep it for inspection, then try the last good backup.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingPathExtension().appendingPathExtension("damaged-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            return fallBackToBackup()
        }
    }

    /// The saved library, or nil when there is nothing readable.
    func load() -> LeafData? {
        if case .library(let value) = loadLibrary() { return value }
        return nil
    }

    func save(_ value: LeafData) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        refreshBackupIfDue()
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Removes the library, its rolling backup and any damaged or partial copies set aside, so nothing of it stays.
    func delete() {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(at: backupURL)
        try? fm.removeItem(at: partialCopyURL)
        let folder = url.deletingLastPathComponent()
        let damagedPrefix = url.deletingPathExtension().lastPathComponent + ".damaged-"
        for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(damagedPrefix) {
            try? fm.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    // MARK: Internals

    private enum ReadResult {
        case decoded(LeafData)
        case missing
        /// There, but the bytes can't be read (data protection, I/O). Says nothing about whether it is damaged.
        case unreadable
        case damaged
    }

    private func read(_ location: URL, keepingPartialCopy: Bool = true) -> ReadResult {
        guard FileManager.default.fileExists(atPath: location.path) else { return .missing }
        guard let bytes = try? Data(contentsOf: location) else { return .unreadable }
        let skips = DecodeSkips()
        guard let value = try? skips.decoder().decode(LeafData.self, from: bytes) else { return .damaged }
        if skips.count > 0, keepingPartialCopy, !FileManager.default.fileExists(atPath: partialCopyURL.path) {
            try? bytes.write(to: partialCopyURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        return .decoded(value)
    }

    private func fallBackToBackup() -> Loaded {
        switch read(backupURL) {
        case .decoded(let value): return .library(value)
        case .unreadable: return .unavailable
        case .missing, .damaged: return .nothing
        }
    }

    /// Copies the current file to the backup at most once per interval, and only if it is itself readable, so a
    /// bad write can never replace a good backup.
    private func refreshBackupIfDue() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        if let attributes = try? fm.attributesOfItem(atPath: backupURL.path),
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < Self.backupInterval {
            return
        }
        // Decoding the whole library is the expensive part, so it only happens when the backup is due.
        guard case .decoded = read(url, keepingPartialCopy: false) else { return }
        try? fm.removeItem(at: backupURL)
        try? fm.copyItem(at: url, to: backupURL)
    }
}

/// Writes the library file in order. Saves run off the main thread and a flush runs on it; whichever finishes last
/// must be the newest snapshot, and nothing may land after the library was erased.
final class LibraryWriter: @unchecked Sendable {
    let persistence: Persistence
    private let lock = NSLock()
    /// The newest generation written or erased; anything older that arrives late is dropped.
    private var newest = 0

    init(persistence: Persistence) {
        self.persistence = persistence
    }

    func save(_ data: LeafData, generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard generation > newest else { return }
        newest = generation
        try? persistence.save(data)
    }

    func erase(generation: Int) {
        lock.lock()
        defer { lock.unlock() }
        newest = max(newest, generation)
        persistence.delete()
    }
}
