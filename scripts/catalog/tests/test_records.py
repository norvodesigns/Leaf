import json
import unittest

import support  # noqa: F401  (puts scripts/ on sys.path)
from catalog import records


class KeyAndLineTests(unittest.TestCase):
    def test_key_numbers(self):
        self.assertEqual(records.key_number("/works/OL38W"), 38)
        self.assertEqual(records.key_number(b"/authors/OL7A"), 7)
        self.assertEqual(records.key_number("/books/OL9M"), 9)
        for bad in (None, 5, "", "/works/38", "/works/OLxW", "/works/OL12"):
            self.assertIsNone(records.key_number(bad), bad)

    def test_rating_and_reading_log_lines(self):
        self.assertEqual(records.parse_rating_line(b"/works/OL5W\t\\N\t4\t2020-01-01"), 5)
        self.assertIsNone(records.parse_rating_line(b"/books/OL5M\t\\N\t4\t2020-01-01"))
        self.assertIsNone(records.parse_rating_line(b"garbage"))
        self.assertEqual(records.parse_reading_log_line(b"/works/OL5W\t/books/OL1M\tAlready Read\t2020-01-01"), (5, "Already Read"))
        self.assertIsNone(records.parse_reading_log_line(b"/works/OLxW\t\\N\tWant to Read\t2020"))

    def test_redirects(self):
        line = support.redirect("works", 3, 9).encode()
        self.assertEqual(records.parse_redirect_line(line), ("work", 3, 9))
        self.assertEqual(records.parse_redirect_line(support.redirect("authors", 4, 2).encode()), ("author", 4, 2))
        self.assertIsNone(records.parse_redirect_line(b"/type/redirect\t/about/people\t5\t2023\t{}"))
        self.assertIsNone(records.parse_redirect_line(support.redirect("works", 3, 3).encode()))
        self.assertIsNone(records.parse_redirect_line(b"/type/redirect\t/works/OL3W\t1\t2020\tnot json"))

    def test_years_and_covers(self):
        self.assertEqual(records.year_of("June 26, 1997"), 1997)
        self.assertEqual(records.year_of("c1997"), 1997)
        self.assertEqual(records.year_of("[2004?]"), 2004)
        self.assertIsNone(records.year_of("12345"))
        self.assertIsNone(records.year_of("unknown"))
        self.assertIsNone(records.year_of(None))
        self.assertEqual(records.first_cover([-1, 0, 77, 5]), 77)
        self.assertIsNone(records.first_cover([-1]))
        self.assertIsNone(records.first_cover("nope"))


class WorkTests(unittest.TestCase):
    def test_work_fields(self):
        obj = {"type": {"key": "/type/work"}, "title": " A Title ", "covers": [-1, 12],
               "authors": [{"author": {"key": "/authors/OL4A"}}, {"author": {"key": "/authors/OL5A"}}],
               "subjects": ["Dragons", 7, None, "Tea"], "first_publish_date": "1999"}
        self.assertEqual(records.parse_work(obj), ("A Title", 4, 2, 1999, 12, ["Dragons", "Tea"]))

    def test_odd_but_real_shapes(self):
        # authors as bare keys, no authors at all, redirect records, missing titles
        self.assertEqual(records.parse_work({"title": "T", "authors": [{"key": "/authors/OL4A"}]})[1], 4)
        self.assertIsNone(records.parse_work({"title": "T"})[1])
        self.assertIsNone(records.parse_work({"type": {"key": "/type/redirect"}, "title": "T"}))
        self.assertIsNone(records.parse_work({"title": "  "}))
        self.assertIsNone(records.parse_work({}))
        self.assertIsNone(records.parse_work("text"))


class EditionTests(unittest.TestCase):
    def parse(self, **kw):
        return records.parse_edition(json.loads(support.edition(1, 5, **kw).split("\t", 4)[4]))

    def test_pages_range_and_types(self):
        self.assertEqual(self.parse(pages=300)[2], 300)
        for pages in (0, 39, 2501, 99999):
            self.assertIsNone(self.parse(pages=pages)[2], pages)
        obj = {"works": [{"key": "/works/OL5W"}], "number_of_pages": "310"}
        self.assertEqual(records.parse_edition(obj)[2], 310)
        obj["number_of_pages"] = True
        self.assertIsNone(records.parse_edition(obj)[2])
        obj["number_of_pages"] = 120.0
        self.assertEqual(records.parse_edition(obj)[2], 120)

    def test_non_print_formats_are_dropped(self):
        for fmt in ("Audio CD", "audio cassette", "MP3 CD", "Microform", "DVD", "Calendar"):
            self.assertIsNone(self.parse(pages=300, fmt=fmt), fmt)
        for fmt in ("Paperback", "Hardcover", "Mass Market Paperback", "ebook", "Unknown Binding"):
            self.assertIsNotNone(self.parse(pages=300, fmt=fmt), fmt)

    def test_language_year_cover_work(self):
        work, langs, pages, cover, year, title, isbns = self.parse(pages=200, langs=("eng", "fre"), cover=9, date="1901", title="T")
        self.assertEqual(isbns, [])
        self.assertEqual((work, langs, pages, cover, year, title), (5, ["eng", "fre"], 200, 9, 1901, "T"))
        self.assertEqual(self.parse(pages=200, langs=())[1], [])
        self.assertIsNone(records.parse_edition({"number_of_pages": 100}))
        self.assertIsNone(records.parse_edition({"works": [], "number_of_pages": 100}))

    def test_isbns_are_checked_and_folded_to_isbn13(self):
        # The Hobbit: 0-261-10221-4 is the ISBN-10 of 978-0-261-10221-7.
        self.assertEqual(records.isbn13("978-0-261-10221-7"), 9780261102217)
        self.assertEqual(records.isbn13("0261102214"), 9780261102217)
        self.assertEqual(records.isbn13("080442957X"), 9780804429573)
        for bad in ("9780261102218", "0261102215", "12345", "9771234567003", None, 9780261102217, "X261102214"):
            self.assertIsNone(records.isbn13(bad), bad)
        obj = {"works": [{"key": "/works/OL5W"}], "isbn_13": ["9780261102217", "junk"], "isbn_10": ["0261102214", "080442957X"]}
        self.assertEqual(records.parse_edition(obj)[6], [9780261102217, 9780804429573])
        self.assertEqual(records.isbns_of({"isbn_13": "9780261102217"}), [])

    def test_prefilter_finds_the_work_without_parsing(self):
        line = support.edition(1, 12345, pages=100).encode()
        self.assertEqual(records.edition_work_number(line), 12345)
        self.assertIsNone(records.edition_work_number(b"no works here"))
        self.assertIsNone(records.edition_work_number(b'"/works/OLxW"'))

    def test_authors(self):
        self.assertEqual(records.parse_author({"name": "  Ann   Lee "}), "Ann Lee")
        self.assertEqual(records.parse_author({"personal_name": "Bo"}), "Bo")
        self.assertIsNone(records.parse_author({"name": ""}))
        self.assertIsNone(records.parse_author([]))


if __name__ == "__main__":
    unittest.main()
