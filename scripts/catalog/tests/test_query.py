import random
import re
import unittest

import support  # noqa: F401
from catalog import query

# The same table lives in LeafTests/CatalogTests.swift. Change both together.
NORMALIZE_CASES = [
    ("Harry Potter and the Philosopher's Stone", "harry potter and the philosopher s stone"),
    ("  J. R. R.  Tolkien ", "j r r tolkien"),
    ("Brontë", "bronte"),
    ("Gabriel García Márquez", "gabriel garcia marquez"),
    ("ÉMILE ZOLA", "emile zola"),
    ("War-and-Peace", "war and peace"),
    ("C++ & Rust", "c rust"),
    ("1984", "1984"),
    ("", ""),
    ("!!! ???", ""),
]
EXPRESSION_CASES = [
    ("Harry Pot", '"harry"* "pot"*'),
    ("dune", '"dune"*'),
    ("J. R. R. Tolkien", '"j" "r" "r" "tolkien"*'),
    ("a", '"a"'),
    ("O'Brien", '"o" "brien"*'),
    ("Brontë", '"bronte"*'),
    ("title:dune", '"title"* "dune"*'),
    ('"quoted" OR NEAR(a b)', '"quoted"* "or"* "near"* "a" "b"'),
    ("one two three four five six seven", '"one"* "two"* "three"* "four"* "five"* "six"*'),
    ("   ", None),
    ("***", None),
    ("", None),
]


class QueryTests(unittest.TestCase):
    def test_normalize_table(self):
        for text, expected in NORMALIZE_CASES:
            self.assertEqual(query.normalize(text), expected, text)

    def test_expression_table(self):
        for text, expected in EXPRESSION_CASES:
            self.assertEqual(query.fts_expression(text), expected, text)

    def test_long_words_are_cut(self):
        self.assertEqual(query.fts_expression("a" * 80), '"%s"*' % ("a" * query.MAX_TERM_LENGTH))

    def test_expressions_are_always_safe(self):
        rng = random.Random(4242)
        alphabet = list("abcXYZ019 \t\"'*:()-+^{}[]~|\\&,.;!?éÅßñ中ا")
        for _ in range(2000):
            text = "".join(rng.choice(alphabet) for _ in range(rng.randint(0, 40)))
            expr = query.fts_expression(text)
            if expr is None:
                self.assertEqual(query.terms(text), [])
                continue
            pieces = expr.split(" ")
            self.assertLessEqual(len(pieces), query.MAX_TERMS)
            for piece in pieces:
                self.assertRegex(piece, r'^"[^\W_]+"\*?$')


if __name__ == "__main__":
    unittest.main()
