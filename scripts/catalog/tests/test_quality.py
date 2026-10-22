import unittest
from collections import Counter

import support  # noqa: F401
from catalog import legacy, quality
from catalog.schema import BookRow


def evaluate(title="The Quiet Garden", author="Ann Lee", subjects=("Gardens", "Fiction"), count=1, tier="tagged",
             pages=(300,), en_title=None, popularity=10, years=(1999,), work_year=None, author_key=1):
    reasons = Counter()
    summary = quality.summarize_pages(list(pages))
    work = (5, title, count, work_year, None, list(subjects))
    out = quality.evaluate(work, author, author_key, popularity, summary, list(years), None, tier, en_title, "en", reasons)
    return out, reasons


class PageCountTests(unittest.TestCase):
    def test_median_is_a_real_page_count(self):
        self.assertEqual(quality.summarize_pages([310])[0], 310)
        self.assertEqual(quality.summarize_pages([300, 400])[0], 300)           # lower middle of an even list
        self.assertEqual(quality.summarize_pages([100, 300, 310, 320, 900])[0], 310)

    def test_alternates_most_common_first_and_capped(self):
        pages = [300] * 5 + [330] * 4 + [366] * 3 + [280] * 2 + [250] * 2 + [500] * 2 + [123]
        median, alternates, sources = quality.summarize_pages(pages)
        self.assertEqual(median, 300)
        self.assertEqual(alternates[:2], [330, 366])
        self.assertLessEqual(len(alternates), quality.MAX_ALTERNATE_PAGE_COUNTS)
        self.assertNotIn(123, alternates)       # a count one edition reports is a typo among many editions
        self.assertEqual(sources, len(pages))

    def test_singletons_survive_when_there_are_few_editions(self):
        self.assertEqual(sorted(quality.summarize_pages([200, 210, 220])[1]), [200, 220])

    def test_invariants_over_random_inputs(self):
        import random
        rng = random.Random(3)
        for _ in range(300):
            pages = [rng.randint(40, 2500) for _ in range(rng.randint(1, 40))]
            median, alternates, sources = quality.summarize_pages(pages)
            self.assertIn(median, pages)
            self.assertNotIn(median, alternates)
            self.assertEqual(len(set(alternates)), len(alternates))
            self.assertTrue(set(alternates) <= set(pages))
            self.assertEqual(sources, len(pages))
        with self.assertRaises(ValueError):
            quality.summarize_pages([])

    def test_language_choice_never_mixes_languages(self):
        rows = {"fre": [(500, None)], "eng": [(300, None)], "": [(111, None)]}
        self.assertEqual(quality.choose_edition_rows(rows, ["eng"]), ("eng", [(300, None)], "tagged"))
        self.assertEqual(quality.choose_edition_rows({"fre": [(1, None)], "": [(2, None)]}, ["eng"]), ("eng", [(2, None)], "untagged"))
        self.assertIsNone(quality.choose_edition_rows({"fre": [(1, None)]}, ["eng"]))
        self.assertEqual(quality.choose_edition_rows({"fre": [(1, None)]}, ["eng", "fre"])[0], "fre")


class FilterTests(unittest.TestCase):
    def test_a_normal_book_passes(self):
        c, reasons = evaluate()
        self.assertIsNotNone(c)
        self.assertEqual((c.title, c.author, c.pages, c.id), ("The Quiet Garden", "Ann Lee", 300, "OL5W"))
        self.assertFalse(reasons)

    def test_junk_titles_are_dropped(self):
        for title in ("SparkNotes: The Quiet Garden", "The Quiet Garden Study Guide", "The Complete Works of Ann Lee",
                      "Harry Potter Box Set", "The Quiet Garden Trilogy", "Summary of The Quiet Garden",
                      "Quiet Garden Workbook", "Books 1-3 The Quiet Garden"):
            c, reasons = evaluate(title=title)
            self.assertIsNone(c, title)
            self.assertEqual(reasons["junk_title"], 1, title)

    def test_junk_and_missing_authors(self):
        self.assertEqual(evaluate(author="Cengage Learning")[1]["junk_author"], 1)
        self.assertEqual(evaluate(author="Scholastic Inc.")[1]["junk_author"], 1)
        self.assertEqual(evaluate(author=None)[1]["no_author_name"], 1)
        self.assertEqual(evaluate(author="")[1]["no_author_name"], 1)

    def test_textbook_subjects(self):
        c, reasons = evaluate(subjects=["Textbooks", "Nursing"])
        self.assertIsNone(c)
        self.assertEqual(reasons["textbook"], 1)
        self.assertIsNotNone(evaluate(subjects=["Gardens", "Nursing homes"] + ["Fiction"] * 10)[0])

    def test_erotica_is_left_out(self):
        c, reasons = evaluate(subjects=["Fiction, erotica", "Erotic fiction", "Romance"] + ["Fiction"] * 10)
        self.assertIsNone(c)
        self.assertEqual(reasons["adult"], 1)
        self.assertEqual(evaluate(subjects=["Erotica", "Fiction"])[1]["adult"], 1)
        # One "eroticism" among many subjects (a literary classic) stays.
        self.assertIsNotNone(evaluate(subjects=["Eroticism", "Psychological fiction"] + ["Fiction"] * 10)[0])
        self.assertIsNotNone(evaluate(subjects=["Heroic fantasy", "Heroes"])[0])

    def test_anthologies_with_many_authors(self):
        self.assertEqual(evaluate(title="Best Short Stories of the Year", count=7)[1]["anthology"], 1)
        self.assertIsNotNone(evaluate(title="Best Short Stories of the Year", count=1)[0])

    def test_foreign_titles_need_proof(self):
        self.assertEqual(evaluate(title="Der Garten und die Liebe", tier="untagged")[1]["foreign_title"], 1)
        self.assertIsNotNone(evaluate(title="Les Misérables", tier="tagged")[0])
        c, _ = evaluate(title="Война и мир", en_title="War and Peace", tier="tagged")
        self.assertEqual(c.title, "War and Peace")
        self.assertEqual(evaluate(title="Война и мир", tier="tagged")[1]["foreign_title"], 1)
        self.assertEqual(evaluate(author="Лев Толстой")[1]["foreign_author"], 1)

    def test_title_cleanup_and_years(self):
        c, _ = evaluate(title="the quiet garden: a novel")
        self.assertEqual(c.title, "The Quiet Garden")
        self.assertIsNone(evaluate(title="The Odyssey", years=(1850,))[0].year)       # undated ancient texts
        c, _ = evaluate(years=(1999, 2005, 2010), work_year=1998)
        self.assertEqual(c.year, 1998)
        self.assertIsNone(evaluate(years=())[0].year)

    def test_dedupe_keeps_the_most_popular(self):
        a, _ = evaluate(popularity=10)
        b, _ = evaluate(popularity=50)
        b.work = 6
        reasons = Counter()
        kept = quality.dedupe([a, b], reasons)
        self.assertEqual([c.work for c in kept], [6])
        self.assertEqual(reasons["duplicate"], 1)
        c, _ = evaluate(title="Another Book")
        self.assertEqual(len(quality.dedupe([a, c], Counter())), 2)


class GenreAndThemeTests(unittest.TestCase):
    def classify(self, subjects, pages=320, year=2005):
        c, _ = evaluate(subjects=subjects, pages=(pages,), years=(year,))
        return quality.genres_and_words(c, list(subjects))

    def test_genres_come_from_the_seed_builders_mapping(self):
        genres, _ = self.classify(["Fantasy fiction", "Dragons", "Fiction", "Magic"])
        self.assertEqual(genres[0], "fantasy")
        genres, _ = self.classify(["Detective and mystery stories", "Fiction", "Murder"])
        self.assertIn("mystery", genres)
        genres, _ = self.classify(["Self-help", "Habit", "Success"])
        self.assertIn("self-help", genres)
        self.assertTrue(all(g in legacy.rules().GENRE_SET for g in genres))

    def test_old_fiction_is_classic_and_no_subjects_means_no_genres(self):
        genres, _ = self.classify(["Fiction", "English literature"], year=1860)
        self.assertEqual(genres[0], "classics")
        self.assertEqual(self.classify([])[0], [])

    def test_known_word_counts(self):
        c, _ = evaluate(title="The Hobbit", author="J. R. R. Tolkien", pages=(310,))
        self.assertEqual(quality.genres_and_words(c, ["Fantasy"])[1], 95000)
        self.assertIsNone(self.classify(["Fantasy"])[1])

    def test_themes_use_the_shared_lexicon(self):
        themes = legacy.themes()
        hits, universes = themes.themes_for_subjects(["Dragons", "Tea", "Cats", "Potter, Harry (Fictitious character)",
                                                       "Large type books", "Accessible book"])
        self.assertTrue({"dragons", "tea & cafes", "cats"} <= set(hits))
        self.assertEqual(list(universes), ["harry potter"])
        self.assertEqual(themes.themes_for_subjects(None), (Counter(), Counter()))
        df = {"dragons": 50, "cats": 50, "tea & cafes": 2, "series:harry potter": 5}
        chosen = themes.choose_themes(hits, universes, df, 1000)
        self.assertIn("dragons", chosen)
        self.assertNotIn("tea & cafes", chosen)            # shared by fewer than five books: not a useful theme
        self.assertEqual(chosen[0], "series:harry potter")  # a shared universe leads
        self.assertLessEqual(len(chosen), themes.PER_BOOK)

    def test_refactored_lexicon_reproduces_the_shipped_seed_themes(self):
        """With the crawl cache present, the importable functions give every seed book the `th` it already has."""
        import json
        import os
        themes = legacy.themes()
        seed_path = os.path.join(support.SCRIPTS, "data", "books.seed.json")
        if not os.path.isdir(themes.CACHE) or not os.path.exists(seed_path):
            self.skipTest("crawl cache not present")
        with open(seed_path, encoding="utf-8") as fh:
            books = json.load(fh)
        docs = themes.load_cache()
        if not docs:
            self.skipTest("crawl cache is empty")
        raw = {b["id"]: (themes.themes_for(docs[b["id"]]) if b["id"] in docs else (Counter(), Counter())) for b in books}
        df = themes.document_frequency(raw.values())
        mismatches = sum(1 for b in books if themes.choose_themes(*raw[b["id"]], df, len(books)) != b["th"])
        self.assertEqual(mismatches, 0)

    def test_importing_the_scripts_has_no_side_effects(self):
        import os
        before = os.listdir(os.path.dirname(legacy.themes().__file__))
        legacy.themes()
        self.assertEqual(before, os.listdir(os.path.dirname(legacy.themes().__file__)))


class PoolTests(unittest.TestCase):
    def rows(self):
        out = []
        for i in range(60):
            out.append(BookRow(id="OL%dW" % (i + 1), title="T%d" % i, author="A", pages=100, popularity=1000 - i,
                               genres=["fantasy"] if i % 2 == 0 else ["mystery"] if i % 5 else [], themes=[]))
        out.append(BookRow(id="OL900W", title="Rare", author="A", pages=100, popularity=6, genres=["poetry"]))
        out.append(BookRow(id="OL901W", title="Foreign", author="A", pages=100, popularity=2000, genres=["fantasy"], language="fr"))
        out.sort(key=lambda r: -r.popularity)
        return out

    def test_pool_needs_genres_english_and_enough_readers(self):
        rows = self.rows()
        chosen = quality.choose_pool(rows, 10, ["fantasy", "mystery", "poetry"], min_per_genre=0)
        self.assertEqual(chosen, sum(r.in_pool for r in rows))
        self.assertEqual(chosen, 10)
        self.assertFalse(any(r.in_pool for r in rows if not r.genres))
        self.assertFalse(next(r for r in rows if r.id == "OL901W").in_pool)

    def test_thin_genres_are_topped_up_and_must_haves_included(self):
        rows = self.rows()
        quality.choose_pool(rows, 10, ["fantasy", "mystery", "poetry"], min_per_genre=1)
        self.assertTrue(next(r for r in rows if r.id == "OL900W").in_pool)
        rows = self.rows()
        quality.choose_pool(rows, 3, ["fantasy"], min_per_genre=0, must_have_ids={"OL900W"})
        self.assertTrue(next(r for r in rows if r.id == "OL900W").in_pool)


if __name__ == "__main__":
    unittest.main()
