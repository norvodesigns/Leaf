"""The dump pipeline: Open Library dumps in, catalog database out.

Order matters, because each step shrinks what the next one has to look at:

1. redirects      merged works and authors, so popularity and editions land on the surviving record
2. popularity     reading-log and ratings counts per work; works below `min_popularity` never get further
3. works          titles, first author, cover, subjects, only for works that passed step 2
4. editions       page counts, language, cover and year, only for works that passed step 3 (the 12 GB dump)
5. authors        names, only for authors of works that passed step 3
6. build          quality rules, dedupe, genres and themes, the browse pool, then the database

Steps 3 to 5 write to a disk-backed SQLite file (the "work dir"), never to Python dicts, and each marks itself done
there, so `--resume` after an interrupted run skips the finished steps. Only small things live in memory: the set of
candidate work numbers and the redirect maps.
"""

import json
import os
import sqlite3
import time
from collections import Counter
from dataclasses import dataclass

from catalog import legacy, quality, records, schema
from catalog.streams import log

PROGRESS_EVERY = 2_000_000


@dataclass
class Options:
    source: object                      # streams.DumpSource
    out: str
    work_dir: str
    languages: tuple = ("en",)
    min_popularity: int = 3
    max_books: int = 250_000
    pool_size: int = 25_000
    min_per_genre: int = 60
    resume: bool = False
    keep_work_dir: bool = True


STAGING_DDL = """
CREATE TABLE IF NOT EXISTS stage (name TEXT PRIMARY KEY, info TEXT);
CREATE TABLE IF NOT EXISTS popularity (work INTEGER PRIMARY KEY, readers INTEGER NOT NULL, ratings INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS work (
    work INTEGER PRIMARY KEY, title TEXT NOT NULL, author INTEGER, author_count INTEGER NOT NULL,
    year INTEGER, cover INTEGER, subjects TEXT NOT NULL, wants_title INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS ed (work INTEGER NOT NULL, lang TEXT NOT NULL, pages INTEGER NOT NULL, cover INTEGER);
CREATE TABLE IF NOT EXISTS yr (work INTEGER NOT NULL, year INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS en_title (work INTEGER NOT NULL, title TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS author (author INTEGER PRIMARY KEY, name TEXT NOT NULL);
"""


def open_staging(work_dir):
    os.makedirs(work_dir, exist_ok=True)
    # SQLite spills big sorts to temp files; keep them beside the staging file, where we know there is room.
    os.environ.setdefault("SQLITE_TMPDIR", work_dir)
    db = sqlite3.connect(os.path.join(work_dir, "staging.sqlite"))
    db.execute("PRAGMA journal_mode = OFF")
    db.execute("PRAGMA synchronous = OFF")
    db.execute("PRAGMA temp_store = FILE")
    db.execute("PRAGMA cache_size = -200000")
    db.executescript(STAGING_DDL)
    return db


def stage_done(db, name):
    row = db.execute("SELECT info FROM stage WHERE name = ?", (name,)).fetchone()
    return None if row is None else json.loads(row[0])


def mark_done(db, name, info):
    db.execute("INSERT OR REPLACE INTO stage(name, info) VALUES (?, ?)", (name, json.dumps(info)))
    db.commit()


def resolve(mapping, number, hops=8):
    """Follow merge redirects (A -> B -> C) to the surviving record."""
    for _ in range(hops):
        nxt = mapping.get(number)
        if nxt is None:
            break
        number = nxt
    return number


def tick(name, count, started, every=PROGRESS_EVERY):
    if count and count % every == 0:
        rate = count / max(time.time() - started, 0.001)
        log("  %s: %s lines (%.0f k/s)" % (name, format(count, ","), rate / 1000))


# --------------------------------------------------------------------------------------------------------------
# 1. redirects
# --------------------------------------------------------------------------------------------------------------

def load_redirects(source):
    works, authors = {}, {}
    started = time.time()
    for n, line in enumerate(source.lines("redirects", big=False), 1):
        if not (line.startswith(b"/type/redirect\t/works/") or line.startswith(b"/type/redirect\t/authors/")):
            continue
        parsed = records.parse_redirect_line(line)
        if parsed:
            kind, src, dst = parsed
            (works if kind == "work" else authors)[src] = dst
    log("redirects: %s works, %s authors (%.0fs)" % (format(len(works), ","), format(len(authors), ","), time.time() - started))
    return works, authors


# --------------------------------------------------------------------------------------------------------------
# 2. popularity
# --------------------------------------------------------------------------------------------------------------

def load_popularity(source, work_redirects):
    """({work: (readers, ratings)} for every work seen}). Reading-log rows and ratings are each one vote."""
    readers, ratings = Counter(), Counter()
    started = time.time()
    n = 0
    for n, line in enumerate(source.lines("reading-log", big=False), 1):
        parsed = records.parse_reading_log_line(line)
        if parsed:
            readers[resolve(work_redirects, parsed[0])] += 1
        tick("reading-log", n, started)
    for n, line in enumerate(source.lines("ratings", big=False), 1):
        work = records.parse_rating_line(line)
        if work is not None:
            ratings[resolve(work_redirects, work)] += 1
    log("popularity: %s works with a reading-log entry, %s with a rating (%.0fs)"
        % (format(len(readers), ","), format(len(ratings), ","), time.time() - started))
    return readers, ratings


def pick_candidates(readers, ratings, minimum):
    return {w: (readers.get(w, 0), ratings.get(w, 0)) for w in set(readers) | set(ratings)
            if readers.get(w, 0) + ratings.get(w, 0) >= minimum}


# --------------------------------------------------------------------------------------------------------------
# 3. works
# --------------------------------------------------------------------------------------------------------------

def stage_works(db, source, candidates, reasons):
    rules = legacy.rules()
    kept = 0
    batch = []
    started = time.time()
    n = 0
    for n, line in enumerate(source.lines("works"), 1):
        t1 = line.find(b"\t")
        t2 = line.find(b"\t", t1 + 1)
        key = line[t1 + 1:t2]
        if not (key.startswith(b"/works/OL") and key.endswith(b"W")):
            continue
        try:
            number = int(key[9:-1])
        except ValueError:
            continue
        if number not in candidates:
            continue
        cols = line.split(b"\t", 4)
        if cols[0] != b"/type/work" or len(cols) < 5:
            continue
        try:
            parsed = records.parse_work(json.loads(cols[4]))
        except ValueError:
            reasons["bad_json"] += 1
            continue
        if parsed is None:
            reasons["not_a_work"] += 1
            continue
        title, author, author_count, year, cover, subjects = parsed
        if author is None:
            reasons["no_author"] += 1
            continue
        if rules.JUNK_TITLE.search(title):
            reasons["junk_title"] += 1
            continue
        wants_title = 1 if rules.looks_foreign(title) else 0
        batch.append((number, title, author, author_count, year, cover, json.dumps(subjects, ensure_ascii=False), wants_title))
        kept += 1
        if len(batch) >= 20000:
            db.executemany("INSERT OR REPLACE INTO work VALUES (?,?,?,?,?,?,?,?)", batch)
            batch = []
        tick("works", n, started)
    if batch:
        db.executemany("INSERT OR REPLACE INTO work VALUES (?,?,?,?,?,?,?,?)", batch)
    db.commit()
    log("works: read %s lines, kept %s candidates (%.0fs)" % (format(n, ","), format(kept, ","), time.time() - started))
    return {"lines": n, "kept": kept}


# --------------------------------------------------------------------------------------------------------------
# 4. editions
# --------------------------------------------------------------------------------------------------------------

def stage_editions(db, source, work_redirects, languages):
    """Collect per-edition facts for candidate works: (work, language, pages, cover) and publication years.

    Every edition of a candidate work is parsed, because an old edition without a page count still tells us the book is
    old. Editions in a language nobody asked for are skipped, and so are audio and other non-book formats.
    """
    wanted = {row[0] for row in db.execute("SELECT work FROM work")}
    wants_title = {row[0] for row in db.execute("SELECT work FROM work WHERE wants_title = 1")}
    allowed = {records.LANG2_TO_3.get(code, code) for code in languages}
    rows, years, titles = [], set(), []
    kept = seen = 0
    started = time.time()
    n = 0

    def flush():
        nonlocal rows, years, titles
        if rows:
            db.executemany("INSERT INTO ed VALUES (?,?,?,?)", rows)
        if years:
            db.executemany("INSERT INTO yr VALUES (?,?)", years)
        if titles:
            db.executemany("INSERT INTO en_title VALUES (?,?)", titles)
        rows, years, titles = [], set(), []

    for n, line in enumerate(source.lines("editions"), 1):
        number = records.edition_work_number(line)
        if number is None:
            continue
        if number in work_redirects:
            number = resolve(work_redirects, number)
        if number not in wanted:
            continue
        cols = line.split(b"\t", 4)
        if len(cols) < 5:
            continue
        try:
            parsed = records.parse_edition(json.loads(cols[4]))
        except ValueError:
            continue
        if parsed is None:
            continue
        work, langs, pages, cover, year, title = parsed
        work = resolve(work_redirects, work)
        if work not in wanted:
            continue
        chosen = next((code for code in langs if code in allowed), None)
        if langs and chosen is None:
            continue   # tagged with a language we were not asked for
        seen += 1
        if year:
            years.add((work, year))
        if pages:
            rows.append((work, chosen or "", pages, cover))
            kept += 1
            if chosen and title and work in wants_title:
                titles.append((work, title))
        if len(rows) >= 50000 or len(years) >= 200000:
            flush()
        tick("editions", n, started, every=5_000_000)
    flush()
    db.commit()
    log("editions: read %s lines, %s belong to candidates, %s with page counts (%.0fs)"
        % (format(n, ","), format(seen, ","), format(kept, ","), time.time() - started))
    return {"lines": n, "candidate_editions": seen, "with_pages": kept}


# --------------------------------------------------------------------------------------------------------------
# 5. authors
# --------------------------------------------------------------------------------------------------------------

def stage_authors(db, source, author_redirects):
    needed = {resolve(author_redirects, row[0]) for row in db.execute("SELECT DISTINCT author FROM work WHERE author IS NOT NULL")}
    batch = []
    found = 0
    started = time.time()
    n = 0
    for n, line in enumerate(source.lines("authors"), 1):
        t1 = line.find(b"\t")
        t2 = line.find(b"\t", t1 + 1)
        key = line[t1 + 1:t2]
        if not (key.startswith(b"/authors/OL") and key.endswith(b"A")):
            continue
        try:
            number = int(key[11:-1])
        except ValueError:
            continue
        if number not in needed:
            continue
        try:
            name = records.parse_author(json.loads(line.split(b"\t", 4)[4]))
        except (ValueError, IndexError):
            continue
        if name:
            batch.append((number, name))
            found += 1
        if len(batch) >= 20000:
            db.executemany("INSERT OR REPLACE INTO author VALUES (?,?)", batch)
            batch = []
        tick("authors", n, started)
    if batch:
        db.executemany("INSERT OR REPLACE INTO author VALUES (?,?)", batch)
    db.commit()
    log("authors: read %s lines, %s of %s needed names found (%.0fs)"
        % (format(n, ","), format(found, ","), format(len(needed), ","), time.time() - started))
    return {"lines": n, "needed": len(needed), "found": found}


# --------------------------------------------------------------------------------------------------------------
# 6. build
# --------------------------------------------------------------------------------------------------------------

def english_titles(db):
    """{work: most common title among its English editions}, for works whose own title looks foreign."""
    out = {}
    for work, title in db.execute("SELECT work, title FROM en_title GROUP BY work, title ORDER BY work, COUNT(*) DESC, title"):
        out.setdefault(work, title)
    return out


def edition_groups(db):
    """(work, {language: [(pages, cover)]}) for each work that has page counts, in work order."""
    current, groups = None, {}
    for work, lang, pages, cover in db.execute("SELECT work, lang, pages, cover FROM ed ORDER BY work"):
        if work != current:
            if current is not None:
                yield current, groups
            current, groups = work, {}
        groups.setdefault(lang, []).append((pages, cover))
    if current is not None:
        yield current, groups


def publication_years(db):
    """{work: sorted distinct years of its editions}."""
    out = {}
    for work, year in db.execute("SELECT DISTINCT work, year FROM yr ORDER BY work, year"):
        out.setdefault(work, []).append(year)
    return out


def collect_candidates(db, author_redirects, preferred, reasons):
    """Every work that passes the quality rules, as quality.Candidate objects."""
    names = dict(db.execute("SELECT author, name FROM author"))
    popularity = {w: r + s for w, r, s in db.execute("SELECT work, readers, ratings FROM popularity")}
    en_titles = english_titles(db)
    all_years = publication_years(db)
    prefs3 = [records.LANG2_TO_3.get(code, code) for code in preferred]
    out = []
    seen = 0
    started = time.time()
    for number, groups in edition_groups(db):
        seen += 1
        choice = quality.choose_edition_rows(groups, prefs3)
        if choice is None:
            reasons["no_pages_in_language"] += 1
            continue
        code, rows, tier = choice
        row = db.execute("SELECT work, title, author, author_count, year, cover, subjects FROM work WHERE work = ?", (number,)).fetchone()
        if row is None:
            continue
        work_row = (row[0], row[1], row[3], row[4], row[5], json.loads(row[6]))
        author_key = resolve(author_redirects, row[2]) if row[2] is not None else None
        summary = quality.summarize_pages([p for p, _c in rows])
        years = all_years.get(number, [])
        covers = [c for _p, c in rows if c]
        language = records.LANG3_TO_2.get(code, code)
        candidate = quality.evaluate(
            work_row, names.get(author_key), author_key, popularity.get(number, 0), summary, years,
            max(covers) if covers else None, tier, en_titles.get(number), language, reasons)
        if candidate is not None:
            out.append(candidate)
        if seen % 200_000 == 0:
            log("  build: %s works examined, %s accepted" % (format(seen, ","), format(len(out), ",")))
    staged = db.execute("SELECT COUNT(*) FROM work").fetchone()[0]
    reasons["no_edition_pages"] += max(0, staged - seen)   # candidates with no edition that has a usable page count
    log("build: %s works with pages, %s passed the rules (%.0fs)" % (format(seen, ","), format(len(out), ","), time.time() - started))
    return out


def load_subjects(db, wanted):
    """{work number: subjects} for the selected works only."""
    out = {}
    for work, subjects in db.execute("SELECT work, subjects FROM work"):
        if work in wanted:
            out[work] = json.loads(subjects)
    return out


def must_have_ids(rows):
    """Ids of the seed builder's spot-check books (famous titles) found among `rows`, best match first."""
    rules = legacy.rules()
    index = {}
    for r in rows:
        index.setdefault(rules.norm_title(r.title), []).append(r)
    found = set()
    for title, surname in rules.MUST_HAVE:
        options = [r for r in index.get(rules.norm_title(title), [])
                   if not surname or rules.fold(surname).split()[-1] in rules.fold(r.author)]
        if options:
            found.add(max(options, key=lambda r: r.popularity).id)
    return found


def build_rows(candidates, subjects_by_work, max_books, pool_size, min_per_genre, reasons):
    """Select, classify and theme the best `max_books` candidates; returns BookRow objects in popularity order."""
    themes = legacy.themes()
    ordered = sorted(quality.dedupe(candidates, reasons), key=lambda c: (-c.popularity, c.work))[:max_books]
    log("selected %s books (cut at popularity %s)" % (format(len(ordered), ","), ordered[-1].popularity if ordered else "-"))

    per_book = []
    for c in ordered:
        per_book.append(themes.themes_for_subjects(subjects_by_work.get(c.work)))
    df = themes.document_frequency(per_book)

    rows = []
    for c, (hits, universes) in zip(ordered, per_book):
        genres, known_words = quality.genres_and_words(c, subjects_by_work.get(c.work) or [])
        rows.append(schema.BookRow(
            id=c.id, title=c.title, author=c.author, pages=c.pages, year=c.year, words=known_words, cover_id=c.cover,
            genres=genres, themes=themes.choose_themes(hits, universes, df, len(ordered)),
            popularity=c.popularity, language=c.language, page_counts=c.page_counts, page_sources=c.page_sources))
    pool = quality.choose_pool(rows, pool_size, legacy.rules().GENRES, min_per_genre, must_have_ids(rows))
    log("pool: %s books" % format(pool, ","))
    return rows


def run(options):
    """Run every step and write `options.out`. Returns the statistics that go in the metadata table and the log."""
    source = options.source
    started = time.time()
    db = open_staging(options.work_dir)
    if not options.resume:
        for table in ("popularity", "work", "ed", "yr", "en_title", "author", "stage"):
            db.execute("DELETE FROM %s" % table)
        db.commit()
    reasons = Counter()
    stats = {}

    work_redirects, author_redirects = load_redirects(source)

    done = stage_done(db, "popularity")
    if done is None:
        readers, ratings = load_popularity(source, work_redirects)
        candidates = pick_candidates(readers, ratings, options.min_popularity)
        db.executemany("INSERT OR REPLACE INTO popularity VALUES (?,?,?)", [(w, r, s) for w, (r, s) in candidates.items()])
        mark_done(db, "popularity", {"candidates": len(candidates), "with_reading_log": len(readers), "with_ratings": len(ratings)})
        stats["popularity"] = stage_done(db, "popularity")
        del readers, ratings
    else:
        log("popularity: resumed (%s candidates)" % format(done["candidates"], ","))
        candidates = {w: None for (w,) in db.execute("SELECT work FROM popularity")}
        stats["popularity"] = done
    log("%s candidate works with popularity >= %d" % (format(len(candidates), ","), options.min_popularity))

    for name, func in (
            ("works", lambda: stage_works(db, source, candidates, reasons)),
            ("editions", lambda: stage_editions(db, source, work_redirects, options.languages)),
            ("authors", lambda: stage_authors(db, source, author_redirects))):
        done = stage_done(db, name)
        if done is None:
            done = func()
            mark_done(db, name, done)
        else:
            log("%s: resumed" % name)
        stats[name] = done
    del candidates

    candidates = collect_candidates(db, author_redirects, options.languages, reasons)
    wanted = {c.work for c in candidates}
    rows = build_rows(candidates, load_subjects(db, wanted), options.max_books, options.pool_size,
                      options.min_per_genre, reasons)
    meta = {
        "source": "Open Library data dumps",
        "source_dump": source.dump_date(),
        "source_url": "https://openlibrary.org/developers/dumps",
        "truncated_sample": "yes" if source.truncated else "no",
        "languages": ",".join(options.languages),
        "min_popularity": str(options.min_popularity),
        "pipeline": "scripts/catalog/build_catalog_db.py",
        "license": "Open Library metadata; see https://openlibrary.org/developers/licensing",
    }
    result = schema.write_database(options.out, rows, legacy.rules().GENRES, meta=meta, progress=log)
    stats["rejected"] = dict(reasons.most_common())
    stats["result"] = result
    stats["seconds"] = round(time.time() - started)
    db.close()
    log("rejected by the rules: %s" % dict(reasons.most_common()))
    log("done: %s books, %s in the pool, %.1f MB, %ds" % (
        format(result["books"], ","), format(result["pool"], ","), result["bytes"] / 1e6, stats["seconds"]))
    return stats
