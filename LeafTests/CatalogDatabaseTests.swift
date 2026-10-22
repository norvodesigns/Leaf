import Foundation
import Testing
#if !canImport(LeafCore)
import SQLite3
@testable import Leaf

/// `CatalogDatabase` against a tiny file in the shape `scripts/catalog/schema.py` writes (app-only: it needs the system
/// SQLite and the app target, so it is not part of the Linux run).
struct CatalogDatabaseTests {
    private static let books = """
    CREATE TABLE books (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, author TEXT NOT NULL, year INTEGER,
        pages INTEGER NOT NULL, words INTEGER, cover_id INTEGER, genres TEXT NOT NULL DEFAULT '',
        themes TEXT NOT NULL DEFAULT '', popularity INTEGER NOT NULL DEFAULT 0, language TEXT NOT NULL DEFAULT 'en',
        page_counts TEXT, page_sources INTEGER NOT NULL DEFAULT 0, in_pool INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE vocab (id INTEGER NOT NULL PRIMARY KEY, kind TEXT NOT NULL, name TEXT NOT NULL);
    CREATE TABLE meta (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
    INSERT INTO vocab VALUES (1, 'genre', 'fantasy');
    INSERT INTO meta VALUES ('schema_version', '1'), ('books', '2'), ('pool', '2');
    INSERT INTO books(rowid, id, title, author, pages, genres, popularity, in_pool)
        VALUES (1, 'OL27482W', 'The Hobbit', 'J.R.R. Tolkien', 310, '1', 900, 1),
               (2, 'OL5W', 'Second Book', 'Ann Lee', 200, '', 10, 1);
    """
    private static let isbns = """
    CREATE TABLE isbns (isbn INTEGER NOT NULL PRIMARY KEY, book INTEGER NOT NULL);
    INSERT INTO isbns VALUES (9780261102217, 1), (9780306406157, 2);
    """

    private func makeCatalog(_ sql: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("catalog-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        return url
    }

    @Test func anISBNFindsItsBookOffline() throws {
        let url = try makeCatalog(Self.books + Self.isbns)
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try #require(CatalogDatabase(url: url))
        #expect(database.book(isbn: "9780261102217")?.id == "OL27482W")
        #expect(database.book(isbn: ISBN.parse("0-306-40615-2") ?? "")?.title == "Second Book")
        #expect(database.book(isbn: "9780000000019") == nil)
        #expect(database.book(isbn: "not a number") == nil)
    }

    @Test func aCatalogBuiltBeforeISBNsSaysNotFound() throws {
        let url = try makeCatalog(Self.books)
        defer { try? FileManager.default.removeItem(at: url) }
        let database = try #require(CatalogDatabase(url: url))
        #expect(database.book(isbn: "9780261102217") == nil)
        #expect(database.book(id: "OL27482W")?.title == "The Hobbit")
    }
}
#endif
