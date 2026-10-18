import Foundation
import SQLite3

/// Read-only access to the bundled `catalog.sqlite` (built by `scripts/catalog/build_catalog_db.py`, see
/// `docs/CATALOG.md`).
///
/// It uses the system SQLite directly, no packages, and opens the file immutable: the bundle is read-only, so there is
/// no journal, no lock and nothing to recover. One connection is shared; the lock makes it safe to call from any thread,
/// so `BookCatalog` loads the browse pool on a background task while search and `book(id:)` answer on the main actor.
/// The queries are cheap (a search is a few milliseconds at 250,000 books), so the lock is never held for long.
final class CatalogDatabase: @unchecked Sendable {
    /// The newest schema this code understands. A file built for a newer one is refused instead of misread.
    static let supportedSchemaVersion = 1

    struct Info: Sendable {
        var schemaVersion: Int
        var builtAt: String
        var sourceDump: String
        var bookCount: Int
        var poolCount: Int
    }

    let info: Info

    private var handle: OpaquePointer?
    private let lock = NSLock()
    private var statements: [String: OpaquePointer] = [:]
    private let genreNames: [Int: String]
    private let themeNames: [Int: String]

    /// The columns every book query returns, in the order `book(from:)` reads them.
    private static let bookColumns = "b.id, b.title, b.author, b.year, b.pages, b.words, b.cover_id, b.genres, b.themes, b.popularity, b.language, b.page_counts"
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Opens `url` read-only. Nil if the file is missing, is not a catalog, or was built for a newer schema.
    init?(url: URL) {
        var opened: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_FULLMUTEX
        let encoded = url.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
        guard sqlite3_open_v2("file:" + encoded + "?immutable=1", &opened, flags, nil) == SQLITE_OK, let db = opened else {
            sqlite3_close(opened)
            return nil
        }

        var meta: [String: String] = [:]
        var genres: [Int: String] = [:]
        var themes: [Int: String] = [:]
        let metaOK = Self.run(db, "SELECT key, value FROM meta") { row in
            if let key = Self.text(row, 0), let value = Self.text(row, 1) { meta[key] = value }
        }
        let vocabOK = Self.run(db, "SELECT id, kind, name FROM vocab") { row in
            guard let kind = Self.text(row, 1), let name = Self.text(row, 2) else { return }
            let id = Int(sqlite3_column_int64(row, 0))
            if kind == "genre" { genres[id] = name } else { themes[id] = name }
        }
        guard metaOK, vocabOK, let version = Int(meta["schema_version"] ?? ""), version <= Self.supportedSchemaVersion else {
            sqlite3_close(db)
            return nil
        }

        handle = db
        genreNames = genres
        themeNames = themes
        info = Info(
            schemaVersion: version,
            builtAt: meta["built_at"] ?? "",
            sourceDump: meta["source_dump"] ?? "",
            bookCount: Int(meta["books"] ?? "") ?? 0,
            poolCount: Int(meta["pool"] ?? "") ?? 0
        )
    }

    /// The copy in the app bundle, if there is one.
    convenience init?(bundle: Bundle) {
        guard let url = bundle.url(forResource: "catalog", withExtension: "sqlite") else { return nil }
        self.init(url: url)
    }

    deinit {
        for statement in statements.values { sqlite3_finalize(statement) }
        sqlite3_close(handle)
    }

    // MARK: Queries

    /// The browse pool: the best-known books that have genres or themes, most popular first.
    func pool() -> [Book] {
        books("SELECT \(Self.bookColumns) FROM books b WHERE b.in_pool = 1 ORDER BY b.rowid")
    }

    /// Any book in the catalog by Open Library work id.
    func book(id: String) -> Book? {
        books("SELECT \(Self.bookColumns) FROM books b WHERE b.id = ?1", bind: { sqlite3_bind_text($0, 1, id, -1, Self.transient) }).first
    }

    func count() -> Int { info.bookCount }

    /// Up to `limit` books matching an FTS5 expression from `CatalogQuery.ftsExpression`, most popular first, each with
    /// its bm25 score. Rank them with `CatalogQuery.rank`.
    func search(match expression: String, limit: Int = CatalogQuery.candidateLimit) -> [CatalogCandidate] {
        var scores: [Double] = []
        let found = books(
            "SELECT \(Self.bookColumns), bm25(books_fts, 5.0, 1.0) FROM books_fts JOIN books b ON b.rowid = books_fts.rowid WHERE books_fts MATCH ?1 ORDER BY books_fts.rowid LIMIT ?2",
            bind: { statement in
                sqlite3_bind_text(statement, 1, expression, -1, Self.transient)
                sqlite3_bind_int64(statement, 2, Int64(limit))
            },
            extra: { scores.append(sqlite3_column_double($0, 12)) }
        )
        // A row that failed to decode is skipped by `books`, so only pair up when nothing was skipped.
        guard found.count == scores.count else { return found.map { CatalogCandidate(book: $0, bm25: 0) } }
        return zip(found, scores).map { CatalogCandidate(book: $0, bm25: $1) }
    }

    // MARK: SQLite plumbing

    /// Runs `sql` and decodes each row as a book. `extra` sees every row first (for extra columns).
    private func books(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil, extra: (OpaquePointer) -> Void = { _ in }) -> [Book] {
        lock.lock()
        defer { lock.unlock() }
        guard let statement = cachedStatement(sql) else { return [] }
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        bind?(statement)
        var out: [Book] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let book = book(from: statement) else { continue }
            extra(statement)
            out.append(book)
        }
        return out
    }

    private func cachedStatement(_ sql: String) -> OpaquePointer? {
        if let existing = statements[sql] { return existing }
        guard let handle else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return nil
        }
        statements[sql] = statement
        return statement
    }

    private func book(from row: OpaquePointer) -> Book? {
        guard let id = Self.text(row, 0), let title = Self.text(row, 1), let author = Self.text(row, 2) else { return nil }
        let genres = CatalogQuery.decodeIDs(Self.text(row, 7)).compactMap { genreNames[$0] }
        let themes = CatalogQuery.decodeIDs(Self.text(row, 8)).compactMap { themeNames[$0] }
        let counts = CatalogQuery.decodeCounts(Self.text(row, 11))
        let language = Self.text(row, 10)
        return Book(
            id: id, title: title, author: author, year: Self.int(row, 3), pages: Self.int(row, 4) ?? 1,
            words: Self.int(row, 5), coverID: Self.int(row, 6), genres: genres, popularity: Self.int(row, 9) ?? 0,
            themes: themes.isEmpty ? nil : themes,
            language: language == "en" ? nil : language,
            pageCounts: counts.isEmpty ? nil : counts
        )
    }

    /// Runs a query that has no parameters, calling `row` for each result row. False if it could not be prepared.
    private static func run(_ db: OpaquePointer, _ sql: String, row: (OpaquePointer) -> Void) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return false
        }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
        return true
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private static func int(_ statement: OpaquePointer, _ column: Int32) -> Int? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, column))
    }
}
