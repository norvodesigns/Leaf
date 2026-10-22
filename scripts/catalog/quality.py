"""Turning what the dumps say about one work into a catalog entry, or a reason to leave it out.

The rules themselves live in scripts/build_catalog.py (junk titles and authors, textbook subjects, title cleanup, the
subject-to-genre mapping), so the small seed catalog and the full catalog can never drift apart. This module adds what
only the dumps allow: page counts from every edition, the language of the editions, and the popularity counts.
"""

import re
from collections import Counter
from dataclasses import dataclass, field

from catalog import legacy

MAX_ALTERNATE_PAGE_COUNTS = 4
POOL_MIN_POPULARITY = 5

_EDITION_TITLE_JUNK = re.compile(r"edition|classics|volume|\bvol\b|collection|notes|summary|study|selected|works", re.I)


def summarize_pages(pages):
    """(median, alternates, editions counted) for the page counts of a work's editions.

    The median is the lower middle value, so it is always a page count some edition really has. Alternates are the
    other counts, most common first (ties: nearest the median); a count only one edition reports is kept just when
    there are five editions or fewer, because beyond that it is as likely a typo as a second printing.
    """
    if not pages:
        raise ValueError("no page counts")
    ordered = sorted(pages)
    median = ordered[(len(ordered) - 1) // 2]
    counts = Counter(pages)
    ranked = sorted((p for p in counts if p != median), key=lambda p: (-counts[p], abs(p - median), p))
    keep = [p for p in ranked if counts[p] >= 2 or len(ordered) <= 5]
    return median, keep[:MAX_ALTERNATE_PAGE_COUNTS], len(ordered)


def choose_edition_rows(rows_by_language, preferred):
    """(language, rows, tier) from a work's edition rows, or None.

    `rows_by_language` maps an Open Library language code ('eng', or '' for editions with no language) to its rows.
    The first preferred language that has rows wins ('tagged'); otherwise untagged editions stand in for the first
    preferred language ('untagged'), which the caller treats with more suspicion. Page counts are never mixed across
    languages, because a translation's page count is not the original's.
    """
    for code in preferred:
        if rows_by_language.get(code):
            return code, rows_by_language[code], "tagged"
    if rows_by_language.get(""):
        return preferred[0], rows_by_language[""], "untagged"
    return None


@dataclass
class Candidate:
    """A work that passed the quality rules, before genres and themes are worked out."""

    work: int
    title: str
    author: str
    pages: int
    popularity: int
    year: int = None
    cover: int = None
    words: int = None
    language: str = "en"
    page_counts: list = field(default_factory=list)
    page_sources: int = 0

    @property
    def id(self):
        return "OL%dW" % self.work

    @property
    def dedupe_key(self):
        rules = legacy.rules()
        return rules.norm_title(self.title) + "|" + rules.author_last(self.author)


def pick_title(raw, tier, english_title, work_id):
    """(title, reject reason). Mirrors the seed builder: a foreign-looking title needs proof it is English."""
    rules = legacy.rules()
    if work_id in rules.TITLE_OVERRIDES:
        return rules.TITLE_OVERRIDES[work_id], None
    title = rules.clean_title(raw)
    if not rules.looks_foreign(raw):
        return (title, None) if title else (None, "empty_title")
    alt = rules.clean_title(english_title or "")
    if (alt and rules.is_latin_text(alt) and not rules.looks_foreign(alt) and 2 <= len(alt) <= 80
            and not _EDITION_TITLE_JUNK.search(alt)):
        return alt, None
    if not rules.is_latin_text(raw):
        return None, "foreign_title"
    if tier != "tagged":
        return None, "foreign_title"
    return (title, None) if title else (None, "empty_title")


def evaluate(work, author_name, author_key, popularity, summary, years, cover, tier, english_title, language,
             reasons):
    """A Candidate for one work, or None with the reason counted in `reasons` (a Counter).

    `work` is the staging row (number, title, author_count, year, subjects); `summary` is `summarize_pages`' result.
    """
    rules = legacy.rules()
    number, raw_title, author_count, work_year, work_cover, subjects = work
    wid = "OL%dW" % number
    if not author_name:
        reasons["no_author_name"] += 1   # the work lists an author but the authors dump has no name for them
        return None
    is_bible = (rules.fold(author_name) == "bible"
                and rules.norm_title(raw_title) in ("bible", "holy bible"))
    if rules.JUNK_AUTHOR.search(author_name) and not is_bible:
        reasons["junk_author"] += 1
        return None
    title, why = pick_title(raw_title, tier, english_title, wid)
    if is_bible:
        title = "The Bible"
    elif why:
        reasons[why] += 1
        return None
    if rules.JUNK_TITLE.search(raw_title) or rules.JUNK_TITLE.search(title):
        reasons["junk_title"] += 1
        return None
    author = "Various" if is_bible else rules.english_author(
        {"author_name": [author_name], "author_key": ["OL%dA" % author_key] if author_key else []})
    if not author:
        reasons["foreign_author"] += 1
        return None
    if author_count >= 5 and re.search(
            r"stories|tales|poems|poetry|essays|best|great|treasury|reader|writings|voices", title, re.I):
        reasons["anthology"] += 1
        return None
    pages, alternates, sources = summary
    folded = [rules.fold(s) for s in subjects]
    textbook = sum(1 for s in folded if rules.TEXTBOOK_SUBJECT.search(s))
    if textbook >= 1 and (textbook >= 2 or len(subjects) <= 8):
        reasons["textbook"] += 1
        return None
    if rules.is_adult(folded):
        reasons["adult"] += 1
        return None
    year = rules.YEAR_OVERRIDES.get(wid)
    if year is None:
        first = work_year if work_year else (min(years) if years else None)
        year = rules.robust_year({"first_publish_year": first, "publish_year": sorted(set(years))})
    if wid not in rules.YEAR_OVERRIDES and (rules.norm_title(title) in rules.UNDATED_TITLES
                                            or (year is not None and year < 1450)):
        year = None
    return Candidate(
        work=number, title=title, author=author, pages=pages, popularity=popularity, year=year,
        cover=work_cover or cover, language=language, page_counts=alternates, page_sources=sources)


def genres_and_words(candidate, subjects):
    """(genres, known word count or None) for a selected candidate, from the seed builder's own classifier."""
    rules = legacy.rules()
    tags, _is_fiction = rules.classify({"subject": subjects}, [], candidate.year, candidate.pages)
    if rules.fold(candidate.author) in rules.ILLUSTRATED_CHILDREN_AUTHORS:
        tags = (["children"] + [t for t in tags if t not in ("children", "young-adult")])[:3]
    tags = [t for t in tags if t in rules.GENRE_SET]
    return tags, rules.known_words(candidate.title, candidate.author)


def dedupe(candidates, reasons):
    """One entry per (normalised title, author surname): the most popular, then the lowest id."""
    best = {}
    for c in candidates:
        key = c.dedupe_key
        current = best.get(key)
        if current is None or (c.popularity, -c.work) > (current.popularity, -current.work):
            if current is not None:
                reasons["duplicate"] += 1
            best[key] = c
        else:
            reasons["duplicate"] += 1
    return list(best.values())


def choose_pool(rows, size, genre_order, min_per_genre=60, must_have_ids=()):
    """Mark the browse pool: the `size` most popular rows that have genres or themes, topped up so no genre is thin.

    `rows` are BookRow objects already sorted by popularity (best first). Rows without genres or themes can be searched
    but never browsed, because the carousels and the recommender have nothing to place them by. `must_have_ids`
    (famous books the seed builder spot-checks) are always in when they exist and qualify.
    """
    eligible = [r for r in rows if r.language == "en" and (r.genres or r.themes) and r.popularity >= POOL_MIN_POPULARITY]
    chosen = {r.id for r in eligible[:size]}
    counts = Counter(g for r in eligible[:size] for g in r.genres)
    for genre in genre_order:
        if counts[genre] >= min_per_genre:
            continue
        for r in eligible[size:]:
            if counts[genre] >= min_per_genre:
                break
            if genre in r.genres and r.id not in chosen:
                chosen.add(r.id)
                for g in r.genres:
                    counts[g] += 1
    for r in eligible:
        if r.id in must_have_ids:
            chosen.add(r.id)
    for r in rows:
        r.in_pool = r.id in chosen
    return len(chosen)
