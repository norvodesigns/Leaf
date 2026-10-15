import Foundation

/// Reads and writes everything Leaf knows to a single JSON file in Application Support.
struct Persistence: Sendable {
    let url: URL

    static let shared: Persistence = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Leaf", isDirectory: true)
        return Persistence(url: base.appendingPathComponent("library.json"))
    }()

    /// A throwaway location for previews and screenshot runs, so they never touch real data.
    static func ephemeral() -> Persistence {
        Persistence(url: FileManager.default.temporaryDirectory.appendingPathComponent("leaf-\(UUID().uuidString).json"))
    }

    func load() -> LeafData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LeafData.self, from: data)
    }

    func save(_ value: LeafData) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
