"""The catalog database: schema, writer and reader helpers.

One row per Open Library work. Everything the app shows lives in `books`; `books_fts` is an external-content FTS5
index over title and author (the text is not stored twice); `vocab` names the genre and theme ids that `books` stores
as short space-separated lists; `meta` says what the file is.

Design notes (the numbers are in docs/CATALOG.md):

* `rowid` is the popularity rank (1 is the most read book). FTS5 hands back matches in rowid order, so
  `ORDER BY rowid LIMIT 300` on a prefix query returns the 300 most popular matches without ranking everything that
  matches "th*". The app re-ranks that short list with match quality.
* Genres and themes are ids into `vocab`, not names: a theme list is about 25 bytes instead of 60, which is most of
  the difference between a 35 MB and a 50 MB file at 250,000 books.
* `words` is NULL unless the word count is known; the app estimates it from pages and genre exactly as the build
  scripts do, so nothing is lost.
"""

import os
import re
import sqlite3
import time
from collections import Counter
from dataclasses import dataclass, field

SCHEMA_VERSION = 1

PAGE_SIZE = 4096

DDL = """
CREATE TABLE books (
    id          TEXT NOT NULL PRIMARY KEY,
    title       TEXT NOT NULL,
    author      TEXT NOT NULL,
    year        INTEGER,
    pages       INTEGER NOT NULL,
    words       INTEGER,
    cover_id    INTEGER,
    genres      TEXT NOT NULL DEFAULT '',
    themes      TEXT NOT NULL DEFAULT '',
    popularity  INTEGER NOT NULL DEFAULT 0,
    language    TEXT NOT NULL DEFAULT 'en',
    page_counts TEXT,
    page_sources INTEGER NOT NULL DEFAULT 0,
    in_pool     INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE vocab (
    id   INTEGER NOT NULL PRIMARY KEY,
    kind TEXT NOT NULL,
    name TEXT NOT NULL
);
CREATE TABLE meta (
    key   TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
);
"""

# prefix='2 3 4' makes "ha", "har" and "harr" index terms of their own, so typing is a lookup, not a scan.
FTS_DDL = """
CREATE VIRTUAL TABLE books_fts USING fts5(
    title, author,
    content='books', content_rowid='rowid',
    tokenize='unicode61 remove_diacritics 2',
    prefix='2 3 4'{extra}
);
"""

# The statement the app runs for search, kept here so the build checks time exactly what ships. `?1` is an FTS5
# expression from CatalogQuery.ftsExpression. Rows come back most popular first (rowid is the popularity rank), so
# LIMIT cuts the 300 best-known matches without ranking everything that matches a short prefix.
CANDIDATE_LIMIT = 300
SEARCH_SQL = (
    "SELECT b.id, b.title, b.author, b.popularity, bm25(books_fts, 5.0, 1.0) "
    "FROM books_fts JOIN books b ON b.rowid = books_fts.rowid "
    "WHERE books_fts MATCH ?1 ORDER BY books_fts.rowid LIMIT %d" % CANDIDATE_LIMIT)

# detail=none drops word positions and column numbers from the index. We only ever run "all of these prefixes" queries,
# never phrase or column queries, and bm25 still works; the saving is about a third of the whole file at 250,000 books.
FTS_DETAIL = ", detail=none"

POOL_INDEX = "CREATE INDEX books_pool ON books(in_pool) WHERE in_pool = 1;"

BOOK_COLUMNS = ("id, title, author, year, pages, words, cover_id, genres, themes, popularity, language,"
                " page_counts, page_sources, in_pool")


@dataclass
class BookRow:
    """One catalog book in the shape the app reads, with genre and theme names (ids are assigned on write)."""

    id: str
    title: str
    author: str
    pages: int
    year: int = None
    words: int = None
    cover_id: int = None
    genres: list = field(default_factory=list)
    themes: list = field(default_factory=list)
    popularity: int = 0
    language: str = "en"
    page_counts: list = field(default_factory=list)
    page_sources: int = 0
    in_pool: bool = False


def work_number(book_id):
    """38 for OL38W; raises ValueError for anything that is not an Open Library work id."""
    m = re.fullmatch(r"OL(\d+)W", book_id)
    if not m:
        raise ValueError("not a work id: %r" % (book_id,))
    return int(m.group(1))


def encode_ids(ids):
    return " ".join(str(i) for i in ids)


def decode_ids(text):
    return [int(p) for p in (text or "").split()]


def encode_counts(counts):
    return ",".join(str(c) for c in counts) if counts else None


def decode_counts(text):
    return [int(p) for p in text.split(",")] if text else []


def build_vocab(rows, genre_order):
    """(genre ids, theme ids): genres keep the app's fixed order from 1; themes follow, most used first.

    Most used first keeps the common ids short ("7 12" instead of "1043 1291"), and sorting ties by name keeps the
    ids identical between two builds of the same data.
    """
    genre_ids = {g: i + 1 for i, g in enumerate(genre_order)}
    used = Counter(t for r in rows for t in r.themes)
    ordered = sorted(used, key=lambda t: (-used[t], t))
    theme_ids = {t: len(genre_ids) + 1 + i for i, t in enumerate(ordered)}
    return genre_ids, theme_ids


def write_database(out_path, rows, genre_order, meta=None, fts_extra=FTS_DETAIL, page_size=PAGE_SIZE, progress=None):
    """Write `rows` to a new database at `out_path` (replacing it) and return the final statistics.

    Rows are stored in popularity order so `rowid` is the rank. The file is built beside the target and moved into
    place at the end, so a failed build never leaves a half-written catalog behind.
    """
    rows = sorted(rows, key=lambda r: (-r.popularity, r.id))
    genre_ids, theme_ids = build_vocab(rows, genre_order)
    unknown = {g for r in rows for g in r.genres if g not in genre_ids}
    if unknown:
        raise ValueError("genres outside the fixed list: %s" % sorted(unknown))

    tmp = out_path + ".tmp"
    for suffix in ("", "-journal", "-wal", "-shm"):
        if os.path.exists(tmp + suffix):
            os.remove(tmp + suffix)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)

    db = sqlite3.connect(tmp)
    try:
        db.execute("PRAGMA page_size = %d" % page_size)
        db.execute("PRAGMA journal_mode = OFF")
        db.execute("PRAGMA synchronous = OFF")
        db.executescript(DDL)

        def values():
            for rank, r in enumerate(rows, 1):
                yield (
                    rank, r.id, r.title, r.author, r.year, r.pages, r.words, r.cover_id,
                    encode_ids(genre_ids[g] for g in r.genres),
                    encode_ids(theme_ids[t] for t in r.themes),
                    r.popularity, r.language, encode_counts(r.page_counts), r.page_sources, 1 if r.in_pool else 0,
                )

        db.execute("BEGIN")
        db.executemany(
            "INSERT INTO books(rowid, id, title, author, year, pages, words, cover_id, genres, themes, popularity,"
            " language, page_counts, page_sources, in_pool) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", values())
        vocab_rows = [(i, "genre", g) for g, i in genre_ids.items()] + [(i, "theme", t) for t, i in theme_ids.items()]
        db.executemany("INSERT INTO vocab(id, kind, name) VALUES (?,?,?)", sorted(vocab_rows))
        db.execute("COMMIT")
        if progress:
            progress("books written: %d" % len(rows))

        db.executescript(FTS_DDL.format(extra=fts_extra))
        db.execute("INSERT INTO books_fts(rowid, title, author) SELECT rowid, title, author FROM books ORDER BY rowid")
        db.execute("INSERT INTO books_fts(books_fts) VALUES('optimize')")
        db.execute(POOL_INDEX)

        pool = sum(1 for r in rows if r.in_pool)
        info = {
            "schema_version": str(SCHEMA_VERSION),
            "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "books": str(len(rows)),
            "pool": str(pool),
            "genres": " ".join(genre_order),
        }
        info.update(meta or {})
        db.executemany("INSERT OR REPLACE INTO meta(key, value) VALUES (?,?)", sorted(info.items()))
        db.execute("PRAGMA user_version = %d" % SCHEMA_VERSION)
        db.commit()
        db.execute("PRAGMA journal_mode = DELETE")
        db.execute("VACUUM")
        db.close()
    except BaseException:
        db.close()
        if os.path.exists(tmp):
            os.remove(tmp)
        raise
    os.replace(tmp, out_path)
    return {"books": len(rows), "pool": pool, "bytes": os.path.getsize(out_path)}


def read_vocab(db):
    """({id: genre name}, {id: theme name}) from an open database."""
    genres, themes = {}, {}
    for i, kind, name in db.execute("SELECT id, kind, name FROM vocab"):
        (genres if kind == "genre" else themes)[i] = name
    return genres, themes


def row_to_book(row, genres, themes):
    """A `books` row (columns as in `BOOK_COLUMNS`) back to a BookRow, for tests and the sanity checks."""
    (id_, title, author, year, pages, words, cover, g, t, pop, lang, counts, sources, pool) = row
    return BookRow(
        id=id_, title=title, author=author, year=year, pages=pages, words=words, cover_id=cover,
        genres=[genres[i] for i in decode_ids(g)], themes=[themes[i] for i in decode_ids(t)],
        popularity=pop, language=lang, page_counts=decode_counts(counts), page_sources=sources, in_pool=bool(pool))


def read_meta(db):
    return dict(db.execute("SELECT key, value FROM meta"))


def open_readonly(path):
    """Open a catalog the way the app does: read-only and immutable (no journal, no locks)."""
    return sqlite3.connect("file:%s?mode=ro&immutable=1" % os.path.abspath(path).replace("?", "%3f"), uri=True)
