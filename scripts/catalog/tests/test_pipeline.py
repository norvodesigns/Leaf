import json
import os
import subprocess
import sys
import unittest

import support
from catalog import legacy, pipeline, schema, streams
from catalog.from_json import load_rows

SCRIPT = os.path.join(support.SCRIPTS, "catalog", "build_catalog_db.py")


def write_dumps(directory):
    """A tiny Open Library: eleven works, each there to exercise one rule."""
    W, E = support.work, support.edition
    works = [
        W(101, "The Dragon Tea Shop", 1, ["Dragons", "Fantasy fiction", "Tea", "Fiction", "Magic"], covers=[-1, 555]),
        W(102, "Study Guide: The Dragon Tea Shop", 1, ["Fantasy fiction"]),
        W(103, "Quiet Years", 2, ["Fiction"]),                       # no edition with pages
        W(104, "Short Thing", 2, ["Fiction"]),                       # only a 20 page edition
        W(105, "Une Histoire", 2, ["Fiction"]),                      # only French editions
        W(106, "The Dragon Tea Shop", 1, ["Fantasy fiction"]),       # duplicate of 101, less read
        W(107, "Merged Work", 4, ["Mystery and detective stories", "Fiction", "Murder"]),
        W(109, "Lonely Book", 2, ["Fiction"]),                       # too few readers
        W(110, "Author Redirect", 3, ["Fiction", "Romance", "Love stories"]),
        W(111, "Nursing Basics", 2, ["Textbooks", "Nursing"]),
        W(112, "No Author At All", 2, ["Fiction"], authors=[]),
    ]
    editions = [
        E(1, 101, 300, date="2001", cover=9), E(2, 101, 300, date="1999"), E(3, 101, 320), E(4, 101, 280, cover=12),
        E(5, 101, 500, langs=("fre",)), E(6, 101, 9999, fmt="Audio CD"), E(7, 101, None, date="1997"),
        E(8, 102, 200), E(10, 104, 20), E(11, 105, 300, langs=("fre",)),
        E(12, 106, 250), E(13, 107, 350), E(14, 108, 350, date="2010"),   # 108 redirects to 107
        E(15, 109, 100), E(16, 110, 220, langs=()), E(17, 111, 400), E(18, 112, 100),
    ]
    authors = [support.author(1, "Ann Lee"), support.author(2, "Bo Chan"), support.author(4, "Cy Day")]
    log = [support.shelf(101)] * 30 + [support.shelf(106)] * 4 + [support.shelf(108)] * 6 + [support.shelf(107)] * 3
    log += [support.shelf(102)] * 9 + [support.shelf(103)] * 9 + [support.shelf(104)] * 9 + [support.shelf(105)] * 9
    log += [support.shelf(109)] + [support.shelf(110)] * 8 + [support.shelf(111)] * 9 + [support.shelf(112)] * 9
    ratings = [support.rating(101)] * 5 + [support.rating(109)]
    redirects = [support.redirect("works", 108, 107), support.redirect("authors", 3, 4)]
    for name, lines in (("works", works), ("editions", editions), ("authors", authors), ("reading-log", log),
                        ("ratings", ratings), ("redirects", redirects)):
        support.write_gz(os.path.join(directory, "ol_dump_%s_2026-09-30.txt.gz" % name), lines)


def run(directory, out, **overrides):
    options = pipeline.Options(
        source=streams.DumpSource(directory=directory), out=out, work_dir=os.path.join(directory, "work"),
        min_popularity=3, max_books=1000, pool_size=100, min_per_genre=0)
    for key, value in overrides.items():
        setattr(options, key, value)
    return pipeline.run(options)


class PipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._tmp = support.temp_dir()
        write_dumps(cls._tmp.name)
        cls.out = os.path.join(cls._tmp.name, "catalog.sqlite")
        cls.stats = run(cls._tmp.name, cls.out)
        cls.db = schema.open_readonly(cls.out)
        genres, themes = schema.read_vocab(cls.db)
        cls.books = {b.id: b for b in (schema.row_to_book(r, genres, themes)
                                       for r in cls.db.execute("SELECT %s FROM books" % schema.BOOK_COLUMNS))}

    @classmethod
    def tearDownClass(cls):
        cls.db.close()
        cls._tmp.cleanup()

    def test_exactly_the_books_that_pass_every_rule(self):
        self.assertEqual(sorted(self.books), ["OL101W", "OL107W", "OL110W"])

    def test_every_rejection_has_its_reason(self):
        rejected = self.stats["rejected"]
        for reason in ("junk_title", "duplicate", "textbook", "no_edition_pages"):
            self.assertGreaterEqual(rejected.get(reason, 0), 1, reason)

    def test_page_counts_are_the_median_over_english_print_editions(self):
        book = self.books["OL101W"]
        self.assertEqual(book.pages, 300)              # [280, 300, 300, 320]: French and audio editions ignored
        self.assertEqual(book.page_counts, [280, 320])
        self.assertEqual(book.page_sources, 4)
        self.assertEqual(book.language, "en")

    def test_popularity_year_cover_author(self):
        book = self.books["OL101W"]
        self.assertEqual(book.popularity, 35)          # 30 reading-log entries + 5 ratings
        self.assertEqual(book.year, 1997)              # earliest edition, even one with no page count
        self.assertEqual(book.cover_id, 555)           # the work's own cover wins over edition covers
        self.assertEqual(book.author, "Ann Lee")

    def test_redirects_merge_popularity_editions_and_authors(self):
        merged = self.books["OL107W"]
        self.assertEqual(merged.popularity, 9)         # 3 for the work plus 6 filed under the merged one
        self.assertEqual(merged.page_sources, 2)       # edition 13 and edition 14 (filed under the merged work)
        self.assertEqual(self.books["OL110W"].author, "Cy Day")   # author 3 was merged into author 4

    def test_untagged_editions_stand_in_for_english(self):
        self.assertEqual(self.books["OL110W"].pages, 220)

    def test_genres_themes_and_pool(self):
        book = self.books["OL101W"]
        self.assertEqual(book.genres[0], "fantasy")
        self.assertEqual(book.themes, [])              # a theme must be shared by five books; this catalog has three
        self.assertTrue(book.in_pool)
        self.assertEqual(self.stats["result"]["books"], 3)

    def test_metadata(self):
        meta = schema.read_meta(self.db)
        self.assertEqual(meta["source_dump"], "2026-09-30")
        self.assertEqual(meta["truncated_sample"], "no")
        self.assertEqual(meta["languages"], "en")

    def test_resume_skips_finished_stages_and_gives_the_same_database(self):
        again = os.path.join(self._tmp.name, "again.sqlite")
        stats = run(self._tmp.name, again, resume=True)
        self.assertEqual(stats["result"]["books"], 3)
        other = schema.open_readonly(again)
        self.assertEqual([r[0] for r in other.execute("SELECT id FROM books ORDER BY rowid")],
                         [r[0] for r in self.db.execute("SELECT id FROM books ORDER BY rowid")])
        other.close()

    def test_a_second_language_changes_only_what_it_should(self):
        out = os.path.join(self._tmp.name, "multi.sqlite")
        run(self._tmp.name, out, languages=("en", "fr"), resume=False)
        db = schema.open_readonly(out)
        rows = dict(db.execute("SELECT id, language FROM books"))
        db.close()
        self.assertEqual(rows["OL101W"], "en")
        self.assertEqual(rows.get("OL105W"), "fr")     # French only, and a French-looking title is allowed there
        self.assertEqual(self.books["OL101W"].pages, 300)

    def test_min_popularity_and_max_books(self):
        out = os.path.join(self._tmp.name, "small.sqlite")
        run(self._tmp.name, out, max_books=1, resume=False)
        db = schema.open_readonly(out)
        self.assertEqual([r[0] for r in db.execute("SELECT id FROM books")], ["OL101W"])
        db.close()


class SeedAndCliTests(unittest.TestCase):
    def test_seed_loader_keeps_words_only_when_known(self):
        with support.temp_dir() as tmp:
            path = os.path.join(tmp, "seed.json")
            with open(path, "w", encoding="utf-8") as fh:
                json.dump([
                    {"id": "OL1W", "t": "Known", "a": "A", "y": 1990, "p": 300, "w": 95000, "c": 5, "g": ["fantasy"], "pop": 9, "th": ["magic"]},
                    {"id": "OL2W", "t": "Estimated", "a": "A", "y": None, "p": 300, "w": 81000, "c": None, "g": ["fantasy"], "pop": 8},
                    {"id": "OL3W", "t": "Kids", "a": "A", "p": 100, "w": 12000, "g": ["children"], "pop": 7},
                    {"id": "OL4M", "t": "An edition id", "a": "A", "p": 100, "g": ["fantasy"], "pop": 7},
                    {"id": "OL1W", "t": "Duplicate", "a": "A", "p": 100, "g": [], "pop": 1},
                    {"id": "OL5W", "t": "Bare", "a": "A", "p": 100, "pop": 0},
                ], fh)
            rows = {r.id: r for r in load_rows(path)}
            self.assertEqual(sorted(rows), ["OL1W", "OL2W", "OL3W", "OL5W"])
            self.assertEqual(rows["OL1W"].words, 95000)
            self.assertIsNone(rows["OL2W"].words)          # 300 pages x 270 words per page: the app estimates it
            self.assertIsNone(rows["OL3W"].words)          # 100 pages x 120 for children's books
            self.assertEqual(rows["OL1W"].title, "Known")
            self.assertFalse(rows["OL5W"].in_pool)         # no genres or themes: searchable, never browsed

    def test_seed_loader_rejects_unknown_genres(self):
        with support.temp_dir() as tmp:
            path = os.path.join(tmp, "seed.json")
            with open(path, "w", encoding="utf-8") as fh:
                json.dump([{"id": "OL1W", "t": "T", "a": "A", "p": 100, "g": ["nonsense"]}], fh)
            with self.assertRaises(ValueError):
                load_rows(path)

    def test_the_shipped_seed_builds_the_same_books_as_the_json(self):
        seed = os.path.join(support.SCRIPTS, "data", "books.seed.json")
        if not os.path.exists(seed):
            self.skipTest("seed not present")
        with support.temp_dir() as tmp:
            out = os.path.join(tmp, "seed.sqlite")
            done = subprocess.run([sys.executable, "-I", SCRIPT, "--from-json", seed, "--out", out],
                                  capture_output=True, text=True, timeout=120)
            self.assertEqual(done.returncode, 0, done.stderr[-500:])
            db = schema.open_readonly(out)
            with open(seed, encoding="utf-8") as fh:
                records = [r for r in json.load(fh) if r["id"].endswith("W")]
            self.assertEqual(db.execute("SELECT COUNT(*) FROM books").fetchone()[0], len(records))
            genres, themes = schema.read_vocab(db)
            by_id = {r["id"]: r for r in records}
            for row in db.execute("SELECT %s FROM books ORDER BY rowid LIMIT 400" % schema.BOOK_COLUMNS):
                book = schema.row_to_book(row, genres, themes)
                rec = by_id[book.id]
                self.assertEqual((book.title, book.author, book.pages, book.year, book.cover_id, book.popularity),
                                 (rec["t"], rec["a"], rec["p"], rec["y"], rec["c"], rec["pop"]))
                self.assertEqual(book.genres, rec["g"])
                self.assertEqual(book.themes, rec.get("th") or [])
            db.close()

    def test_cli_help_and_bad_arguments(self):
        done = subprocess.run([sys.executable, "-I", SCRIPT, "--help"], capture_output=True, text=True, timeout=60)
        self.assertEqual(done.returncode, 0)
        self.assertIn("--from-json", done.stdout)
        bad = subprocess.run([sys.executable, "-I", SCRIPT, "--nonsense"], capture_output=True, text=True, timeout=60)
        self.assertNotEqual(bad.returncode, 0)


if __name__ == "__main__":
    unittest.main()
