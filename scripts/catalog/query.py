"""Search text to FTS5 expression: the Python twin of Shared/CatalogQuery.swift.

The Swift file is what the app runs; this one lets the build checks and the tests ask the database the same questions.
Both are tested against the same table of cases (scripts/catalog/tests/test_query.py and LeafTests/CatalogTests.swift),
so changing one without the other fails a test.
"""

import unicodedata

MAX_TERMS = 6
MAX_TERM_LENGTH = 32


def normalize(text):
    """Lower-cased, accents removed, anything that is not a letter or digit turned into a single space."""
    folded = unicodedata.normalize("NFKD", text or "")
    folded = "".join(ch for ch in folded if not unicodedata.combining(ch)).lower()
    return " ".join("".join(ch if ch.isalnum() else " " for ch in folded).split())


def terms(text):
    return [t[:MAX_TERM_LENGTH] for t in normalize(text).split()][:MAX_TERMS]


def fts_expression(text):
    """`"harry"* "pot"*` for "Harry Pot"; None when nothing searchable is left.

    Every term of two or more characters is a prefix, so results appear as the reader types. A one character term is
    an exact word: a prefix on a single letter has to merge every term starting with it, which costs ten times more
    than any other query and matches nearly everything anyway.
    """
    parts = []
    for term in terms(text):
        parts.append('"%s"*' % term if len(term) >= 2 else '"%s"' % term)
    return " ".join(parts) if parts else None
