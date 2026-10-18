import os
import sqlite3
import statistics
import time
import unittest

import support
from catalog import checks, legacy, query, schema, synthetic
from catalog.schema import BookRow

GENRES = legacy.rules().GENRES


def sample_rows():
    return [
        BookRow(id="OL3W", title="Harry Potter and the Philosopher's Stone", author="J. K. Rowling", pages=309, year=1997,
                genres=["fantasy", "young-adult"], themes=["magic", "series:harry potter"], popularity=900, in_pool=True,
                page_counts=[223, 336], page_sources=14),
        BookRow(id="OL1W", title="The Hobbit", author="J. R. R. Tolkien", pages=310, words=95000, cover_id=77,
                genres=["fantasy"], themes=["dragons", "magic"], popularity=900, in_pool=True),
        BookRow(id="OL2W", title="Brontë Country Walks", author="Ann Lee", pages=120, popularity=5, language="fr"),
        BookRow(id="OL4W", title="Dune", author="Frank Herbert", pages=412, genres=["science-fiction"], popularity=2000, in_pool=True),
    ]


class RoundTripTests(unittest.TestCase):
    def setUp(self):
        self._tmp = support.temp_dir()
        self.path = os.path.join(self._tmp.name, "catalog.sqlite")
        schema.write_database(self.path, sample_rows(), GENRES, meta={"source_dump": "test"})
        self.db = schema.open_readonly(self.path)

    def tearDown(self):
        self.db.close()
        self._tmp.cleanup()

    def books(self, sql="SELECT %s FROM books ORDER BY rowid" % schema.BOOK_COLUMNS):
        genres, themes = schema.read_vocab(self.db)
        return [schema.row_to_book(r, genres, themes) for r in self.db.execute(sql)]

    def test_rowid_is_the_popularity_rank(self):
        ids = [b.id for b in self.books()]
        self.assertEqual(ids, ["OL4W", "OL1W", "OL3W", "OL2W"])     # ties broken by id
        self.assertEqual([r[0] for r in self.db.execute("SELECT rowid FROM books ORDER BY rowid")], [1, 2, 3, 4])

    def test_everything_survives_the_round_trip(self):
        by_id = {b.id: b for b in self.books()}
        original = {r.id: r for r in sample_rows()}
        for book_id, book in by_id.items():
            self.assertEqual(book, original[book_id])

    def test_metadata_and_versions(self):
        meta = schema.read_meta(self.db)
        self.assertEqual(meta["schema_version"], str(schema.SCHEMA_VERSION))
        self.assertEqual((meta["books"], meta["pool"], meta["source_dump"]), ("4", "3", "test"))
        self.assertEqual(self.db.execute("PRAGMA user_version").fetchone()[0], schema.SCHEMA_VERSION)
        self.assertEqual(self.db.execute("PRAGMA journal_mode").fetchone()[0].lower(), "delete")
        self.assertFalse(os.path.exists(self.path + ".tmp"))

    def test_vocab_ids_are_stable_and_complete(self):
        genres, themes = schema.read_vocab(self.db)
        self.assertEqual([genres[i + 1] for i in range(len(GENRES))], GENRES)
        self.assertEqual(min(themes), len(GENRES) + 1)
        self.assertEqual(themes[len(GENRES) + 1], "magic")           # most used theme gets the first id
        self.assertEqual(sorted(themes.values()), ["dragons", "magic", "series:harry potter"])

    def test_fts_prefix_search_in_popularity_order(self):
        def ids(text):
            expr = query.fts_expression(text)
            return [r[0] for r in self.db.execute(schema.SEARCH_SQL, (expr,))]
        self.assertEqual(ids("ha po"), ["OL3W"])
        self.assertEqual(ids("tolk"), ["OL1W"])
        self.assertEqual(ids("j r r tolkien"), ["OL1W"])
        self.assertEqual(ids("BRONTE"), ["OL2W"])                    # accents fold on both sides
        self.assertEqual(ids("brontë"), ["OL2W"])
        self.assertEqual(ids("philosopher's stone"), ["OL3W"])
        self.assertEqual(ids("the"), ["OL1W", "OL3W"])
        self.assertEqual(ids("zzz"), [])
        self.assertEqual(ids("x OR title:dune NEAR("), [])           # operators are only words
        self.assertEqual(ids("dune"), ["OL4W"])

    def test_bm25_is_available_and_negative(self):
        row = self.db.execute(schema.SEARCH_SQL, (query.fts_expression("hobbit"),)).fetchone()
        self.assertLess(row[4], 0)

    def test_pool_query_uses_the_partial_index(self):
        plan = " ".join(str(r) for r in self.db.execute("EXPLAIN QUERY PLAN SELECT id FROM books WHERE in_pool = 1 ORDER BY rowid"))
        self.assertIn("books_pool", plan)
        self.assertEqual([r[0] for r in self.db.execute("SELECT id FROM books WHERE in_pool = 1 ORDER BY rowid")], ["OL4W", "OL1W", "OL3W"])

    def test_id_lookup_uses_the_primary_key(self):
        plan = " ".join(str(r) for r in self.db.execute("EXPLAIN QUERY PLAN SELECT * FROM books WHERE id = 'OL1W'"))
        self.assertIn("sqlite_autoindex_books_1", plan)

    def test_read_only_connection_refuses_writes(self):
        with self.assertRaises(sqlite3.OperationalError):
            self.db.execute("DELETE FROM books")

    def test_checks_pass_and_catch_problems(self):
        report = checks.check(self.path, min_rows=4, max_mb=5, probes=20)
        self.assertTrue(report.ok, report.text())
        self.assertFalse(checks.check(self.path, min_rows=5, probes=20).ok)
        self.assertFalse(checks.check(self.path, min_rows=4, max_mb=0.001, probes=20).ok)

    def test_checks_flag_empty_titles(self):
        bad = os.path.join(self._tmp.name, "bad.sqlite")
        rows = sample_rows() + [BookRow(id="OL9W", title="  ", author="X", pages=100)]
        schema.write_database(bad, rows, GENRES)
        report = checks.check(bad, min_rows=1, probes=10)
        self.assertFalse(report.ok)
        self.assertIn("empty title", report.text())

    def test_unknown_genre_is_refused_and_leaves_no_file(self):
        out = os.path.join(self._tmp.name, "refused.sqlite")
        with self.assertRaises(ValueError):
            schema.write_database(out, [BookRow(id="OL1W", title="T", author="A", pages=100, genres=["not-a-genre"])], GENRES)
        self.assertFalse(os.path.exists(out))
        self.assertFalse(os.path.exists(out + ".tmp"))

    def test_work_ids(self):
        self.assertEqual(schema.work_number("OL38W"), 38)
        for bad in ("OL38M", "38", "OLW", ""):
            with self.assertRaises(ValueError):
                schema.work_number(bad)


class SyntheticScaleTests(unittest.TestCase):
    """Size and latency on a made-up 60,000 book catalog; docs/CATALOG.md has the 250,000 book numbers."""

    @classmethod
    def setUpClass(cls):
        cls._tmp = support.temp_dir()
        cls.path = os.path.join(cls._tmp.name, "synthetic.sqlite")
        cls.rows = synthetic.make_rows(60_000, seed=5)
        schema.write_database(cls.path, cls.rows, GENRES + [g for g in synthetic.GENRES if g not in GENRES])
        cls.db = schema.open_readonly(cls.path)

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        cls._tmp.cleanup()

    def test_size_per_book_stays_inside_the_budget(self):
        per_book = os.path.getsize(self.path) / len(self.rows)
        # 45 MB for 250,000 books is 180 bytes each; synthetic titles are shorter than real ones, so leave headroom.
        self.assertLess(per_book, 175, "%.0f bytes per book" % per_book)

    def test_search_latency(self):
        times = checks.search_latency(self.db, checks.probe_queries(self.db, 150))
        self.assertGreater(len(times), 100)
        self.assertLess(sorted(times)[int(len(times) * 0.95)], 15.0)
        self.assertLess(max(times), 60.0)

    def test_a_one_letter_prefix_would_be_much_slower_than_the_exact_word(self):
        # Why CatalogQuery makes one letter words exact: measure instead of assuming.
        def best_of(expr):
            runs = []
            for _ in range(5):
                start = time.perf_counter()
                self.db.execute(schema.SEARCH_SQL, (expr,)).fetchall()
                runs.append(time.perf_counter() - start)
            return statistics.median(runs)
        self.assertGreater(best_of('"a"*'), best_of('"a"'))

    def test_probe_queries_are_deterministic(self):
        self.assertEqual(checks.probe_queries(self.db, 20), checks.probe_queries(self.db, 20))

    def test_pool_rows_are_the_ones_flagged(self):
        flagged = sum(1 for r in self.rows if r.in_pool)
        self.assertEqual(self.db.execute("SELECT COUNT(*) FROM books WHERE in_pool = 1").fetchone()[0], flagged)


if __name__ == "__main__":
    unittest.main()
