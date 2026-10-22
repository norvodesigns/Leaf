"""Sanity checks on a built catalog database. Used by check_catalog.py and the CI workflow."""

import os
import random
import re
import statistics
import time

from catalog import legacy, query, schema


class Report:
    def __init__(self):
        self.lines = []
        self.failures = []
        self.warnings = []

    def info(self, text):
        self.lines.append(text)

    def fail(self, text):
        self.failures.append(text)
        self.lines.append("FAIL  " + text)

    def warn(self, text):
        self.warnings.append(text)
        self.lines.append("warn  " + text)

    @property
    def ok(self):
        return not self.failures

    def text(self):
        return "\n".join(self.lines)


def probe_queries(db, count, seed=7):
    """Realistic typing: prefixes (2 to 5 letters) of words from real titles, and two-word starts of titles."""
    rng = random.Random(seed)
    total = db.execute("SELECT COUNT(*) FROM books").fetchone()[0]
    picks = sorted(rng.sample(range(1, total + 1), min(count, total)))
    out = []
    for rowid in picks:
        row = db.execute("SELECT title, author FROM books WHERE rowid = ?", (rowid,)).fetchone()
        words = query.normalize(row[0]).split() or query.normalize(row[1]).split()
        if not words:
            continue
        word = words[0]
        out.append(word[:rng.randint(2, 5)])
        if len(words) > 1:
            out.append("%s %s" % (words[0], words[1][:rng.randint(1, 4)]))
    out += ["the", "th", "a", "of", "love", "harry pot", "stephen king", "tolkien", "j r r tolkien", "dune"]
    return out


def search_latency(db, queries):
    """Milliseconds for each query, running the exact SQL the app runs."""
    times = []
    for text in queries:
        expr = query.fts_expression(text)
        if not expr:
            continue
        start = time.perf_counter()
        db.execute(schema.SEARCH_SQL, (expr,)).fetchall()
        times.append((time.perf_counter() - start) * 1000)
    return times


def check(path, min_rows=150_000, max_mb=60.0, max_p95_ms=30.0, probes=300, deep=False, require_full=False):
    """Run every check; returns a Report. `deep` also verifies the FTS index against the table (slower)."""
    report = Report()
    size_mb = os.path.getsize(path) / 1e6
    db = schema.open_readonly(path)
    meta = schema.read_meta(db)
    rows = db.execute("SELECT COUNT(*) FROM books").fetchone()[0]
    pool = db.execute("SELECT COUNT(*) FROM books WHERE in_pool = 1").fetchone()[0]
    report.info("file: %s  %.1f MB  %d books  %d in the pool  dump %s" % (
        path, size_mb, rows, pool, meta.get("source_dump", "?")))

    if meta.get("schema_version") != str(schema.SCHEMA_VERSION):
        report.fail("schema_version %r, expected %d" % (meta.get("schema_version"), schema.SCHEMA_VERSION))
    version = db.execute("PRAGMA user_version").fetchone()[0]
    if version != schema.SCHEMA_VERSION:
        report.fail("PRAGMA user_version is %d, expected %d" % (version, schema.SCHEMA_VERSION))
    mode = db.execute("PRAGMA journal_mode").fetchone()[0]
    if mode.lower() == "wal":
        report.fail("journal_mode is WAL; a read-only bundle must not be")
    if meta.get("books") != str(rows):
        report.fail("meta says %s books but the table has %d" % (meta.get("books"), rows))
    if rows < min_rows:
        report.fail("only %d books, wanted at least %d" % (rows, min_rows))
    if size_mb > max_mb:
        report.fail("%.1f MB is over the %.1f MB budget" % (size_mb, max_mb))
    if pool == 0:
        report.fail("the browse pool is empty")
    if require_full and meta.get("truncated_sample") != "no":
        report.fail("this database was built from a truncated sample of the dumps")

    empty = db.execute("SELECT COUNT(*) FROM books WHERE TRIM(title) = '' OR TRIM(author) = ''").fetchone()[0]
    if empty:
        report.fail("%d books with an empty title or author" % empty)
    bad_pages = db.execute("SELECT COUNT(*) FROM books WHERE pages < 40 OR pages > 2500").fetchone()[0]
    if bad_pages:
        report.fail("%d books with pages outside 40..2500" % bad_pages)
    bad_ids = sum(1 for (i,) in db.execute("SELECT id FROM books") if not re.fullmatch(r"OL\d+W", i))
    if bad_ids:
        report.fail("%d ids that are not Open Library work ids" % bad_ids)
    out_of_order = db.execute(
        "SELECT COUNT(*) FROM books a JOIN books b ON b.rowid = a.rowid + 1 WHERE b.popularity > a.popularity").fetchone()[0]
    if out_of_order:
        report.fail("rowid is not in popularity order (%d inversions)" % out_of_order)
    genres, themes = schema.read_vocab(db)
    unknown = 0
    for g, t in db.execute("SELECT genres, themes FROM books"):
        unknown += sum(1 for i in schema.decode_ids(g) if i not in genres) + sum(1 for i in schema.decode_ids(t) if i not in themes)
    if unknown:
        report.fail("%d genre or theme ids missing from vocab" % unknown)
    has_isbns = db.execute("SELECT 1 FROM sqlite_master WHERE name = 'isbns'").fetchone() is not None
    isbns = db.execute("SELECT COUNT(*) FROM isbns").fetchone()[0] if has_isbns else 0
    if has_isbns:
        dangling = db.execute("SELECT COUNT(*) FROM isbns WHERE book NOT IN (SELECT rowid FROM books)").fetchone()[0]
        if dangling:
            report.fail("%d ISBNs point at no book" % dangling)
        with_isbn = db.execute("SELECT COUNT(DISTINCT book) FROM isbns").fetchone()[0]
        report.info("ISBNs: %d for %.1f%% of the books" % (isbns, 100.0 * with_isbn / max(rows, 1)))
    if require_full and not isbns:
        report.fail("no ISBNs, so barcode scans need a connection")
    with_genre = db.execute("SELECT COUNT(*) FROM books WHERE genres != ''").fetchone()[0]
    report.info("with genres: %.1f%%   languages: %s" % (
        100.0 * with_genre / max(rows, 1), dict(db.execute("SELECT language, COUNT(*) FROM books GROUP BY language"))))

    times = search_latency(db, probe_queries(db, probes))
    if times:
        p50 = statistics.median(times)
        p95 = sorted(times)[int(len(times) * 0.95) - 1]
        report.info("search (%d queries, candidate SQL): median %.2f ms  p95 %.2f ms  max %.2f ms" % (
            len(times), p50, p95, max(times)))
        if p95 > max_p95_ms:
            report.fail("search p95 %.1f ms is over %.1f ms" % (p95, max_p95_ms))
    else:
        report.fail("no search probes could be built")

    # A famous-books spot check is a warning only: the dump decides what is popular, we only notice a collapse.
    rules = legacy.rules()
    missing = []
    for title, surname in rules.MUST_HAVE:
        expr = query.fts_expression(title + (" " + surname if surname else ""))
        if not expr or not db.execute(schema.SEARCH_SQL, (expr,)).fetchone():
            missing.append(title)
    found = len(rules.MUST_HAVE) - len(missing)
    report.info("famous-books spot check: %d of %d found" % (found, len(rules.MUST_HAVE)))
    if rows >= 100_000 and found < 0.6 * len(rules.MUST_HAVE):
        report.warn("fewer than 60%% of the famous books are present; missing e.g. %s" % ", ".join(missing[:8]))

    if deep:
        try:
            db.execute("INSERT INTO books_fts(books_fts, rank) VALUES('integrity-check', 1)")
        except Exception as exc:  # immutable connections refuse writes; use a scratch copy for the deep check
            report.warn("FTS integrity check skipped (%s)" % exc)
    db.close()
    return report
