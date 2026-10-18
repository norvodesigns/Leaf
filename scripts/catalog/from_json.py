"""Build catalog rows from the seed JSON (scripts/data/books.seed.json), so the new loader ships before the full build.

The seed has the short keys the old app bundled: id, t (title), a (author), y (year), p (pages), w (words), c (cover),
g (genres), pop (popularity), th (themes).
"""

import json
import re

from catalog import legacy
from catalog.schema import BookRow


def estimated_words(pages, genres):
    """What the app assumes when `words` is NULL (Book.estimatedWords): pages times words per page for the genre."""
    return int(round(pages * legacy.rules().words_per_page(genres)))


def load_rows(path):
    rules = legacy.rules()
    with open(path, encoding="utf-8") as fh:
        records = json.load(fh)
    known = set(rules.GENRES)
    seen = set()
    rows = []
    for rec in records:
        # The seed crawl once let an edition id (OL...M) through; only work ids belong in the catalog.
        if rec["id"] in seen or not re.fullmatch(r"OL\d+W", rec["id"]):
            continue
        seen.add(rec["id"])
        genres = list(rec.get("g") or [])
        bad = [g for g in genres if g not in known]
        if bad:
            raise ValueError("%s has genres outside the fixed list: %s" % (rec["id"], bad))
        words = rec.get("w")
        if words is not None and words == estimated_words(rec["p"], genres):
            words = None
        themes = list(rec.get("th") or [])
        rows.append(BookRow(
            id=rec["id"], title=rec["t"], author=rec["a"], pages=rec["p"], year=rec.get("y"), words=words,
            cover_id=rec.get("c"), genres=genres, themes=themes, popularity=int(rec.get("pop") or 0),
            in_pool=bool(genres or themes)))
    return rows
