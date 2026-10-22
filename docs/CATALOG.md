# The offline book catalog

Leaf ships a read-only SQLite database of up to 250,000 books and searches it without a connection. This doc is the
architecture, the schema, how to rebuild it, where the data comes from, and what was measured. The design brief is
`docs/NEXT.md` section 2.

## At a glance

| | |
|---|---|
| File | `Leaf/Resources/catalog.sqlite` (a synchronized group, so it is bundled automatically) |
| Today | 5,264 books built from the old JSON crawl (`scripts/data/books.seed.json`), about 1 MB. The full build replaces it |
| Full build | `.github/workflows/catalog.yml`, started by pushing `scripts/catalog/REBUILD`. 250,000 books, about 46 MB |
| App code | `Leaf/Services/CatalogDatabase.swift` (SQLite wrapper), `Leaf/Services/BookCatalog.swift` (unchanged public API), `Shared/CatalogQuery.swift` (query builder and ranking, tested on Linux) |
| Pipeline | `scripts/catalog/` (Python 3 standard library only) |
| Tests | `scripts/catalog/tests` (78, `python3 -I -m unittest discover -s scripts/catalog/tests`), `LeafTests/CatalogTests.swift` (15) |

## Architecture

```
Open Library dumps (streamed, never stored)             scripts/data/books.seed.json
  redirects, reading-log, ratings, works, editions, authors        |
        |                                                          |
        v        scripts/catalog/build_catalog_db.py               v
   staging.sqlite (disk, temporary)  ----->  quality rules  ----->  catalog.sqlite
                                              genres, themes, pool   (read-only, FTS5)
                                                                       |
                                                    CatalogDatabase (SQLite3, immutable)
                                                                       |
                                                BookCatalog  (pool in memory, everything by query)
```

* **The pool.** `BookCatalog.books` is the *browse pool*: about 25,000 of the best-known books that have genres or
  themes. The carousel builder and the recommender work on this in-memory list exactly as before (NEXT.md section 17),
  so they stay fast and every pick can be explained. Loading the pool, building its statistics and all 113 to 140
  carousels took under a second in an optimized Linux build on a 25,000 book pool.
* **Everything else is a query.** `search(_:limit:)` covers every book in the database, and `book(id:)` resolves any id
  (pool first, then a 256 entry cache, then SQL). Nothing decodes the whole table.
* **Threading.** `CatalogDatabase` is not main-actor bound. One connection, a lock around each statement, prepared
  statements cached. `BookCatalog.load()` reads the pool on a background task; `search` and `book(id:)` answer on the
  main actor, because a search is a few milliseconds.

## Schema (version 1)

`PRAGMA user_version` and `meta.schema_version` hold the version; the app refuses a newer one than it knows.

| Table | Contents |
|---|---|
| `books` | `id` TEXT primary key (Open Library work id, `OL27482W`), `title`, `author`, `year`, `pages`, `words` (NULL unless known), `cover_id`, `genres`, `themes`, `popularity`, `language` (ISO 639-1), `page_counts` (`330,366`, other editions' counts, most common first), `page_sources` (editions with a page count behind `pages`), `in_pool` |
| `books_fts` | FTS5 over `title` and `author`, `content='books'` (text is not stored twice), `unicode61 remove_diacritics 2`, `prefix='2 3 4'`, `detail=none` |
| `isbns` | `isbn` INTEGER primary key (the ISBN-13 as a number, so it is the rowid and needs no index), `book` (a `books` rowid). Added 2026-10-22; older files lack it and the app reads that as "not found" |
| `vocab` | `id`, `kind` (`genre` or `theme`), `name` |
| `meta` | `schema_version`, `built_at`, `source_dump` (release date, or `seed`), `books`, `pool`, `isbns`, `languages`, `min_popularity`, `truncated_sample`, `source`, `source_url`, `license`, `genres` |

Choices that matter:

* **`rowid` is the popularity rank** (1 is the most read). FTS5 returns matches in rowid order, so
  `ORDER BY rowid LIMIT 300` on a prefix query yields the 300 best-known matches without ranking everything that
  matches `th*`. This is why a two letter prefix costs about 2 ms instead of tens.
* **`genres` and `themes` are space separated `vocab` ids** (`"4 17"`), not names. A name list is about 60 bytes a book,
  an id list about 12; across 250,000 books that is most of the gap between a 35 MB and a 50 MB file. Genres take ids 1 to
  32 in the app's fixed order; themes follow, most used first.
* **`words` is NULL unless the word count is known** (famous books). The app then estimates pages times words per page by
  genre, exactly what the build scripts would have stored, so nothing is lost.
* **`language`** is stored as `en`; `BookCatalog` hands the app `nil` for English (the model's "English or unknown") and the
  code otherwise.
* **`detail=none`** removes word positions from the index. We only run "all of these prefixes" queries, bm25 still works,
  and it saves about a third of the file. Phrase and column queries are therefore unavailable; nothing uses them.
* **ISBNs make barcode scans offline.** Every printed edition in a wanted language contributes its `isbn_13` and
  `isbn_10` (checked, folded to 978), newest editions first: the copy someone scans is far more often a recent printing.
  The 10,000 most read keep up to 40, the next 40,000 up to 12, the rest 6 (`Options.isbn_tiers`). An ISBN two works
  claim goes to the more popular one. The first build (six for every work) had 724,730 ISBNs for 96% of the books
  and grew the file from 38.8 to 50.3 MB (about 16 bytes a row); the tiers add up to about 580,000 more, which is why
  the size budget in `catalog.yml` is 70 MB. `ISBNLookup` asks the catalog first and Open Library only on a miss.
* Optimised for one reader: no WAL, `journal_mode=DELETE`, vacuumed, opened with `immutable=1`.

## Search

`CatalogQuery.ftsExpression(for:)` turns what was typed into `"harry"* "pot"*`:

* text is folded (accents, case) and split on anything that is not a letter or digit, up to 6 words of 32 characters;
* every word is a quoted string, so typed FTS5 operators (`OR`, `NEAR(`, `title:`, `-`, `*`, quotes) are plain words and
  can neither change the query nor be a syntax error (2,000 random strings are checked in both test suites);
* a word of two or more characters is a prefix; a **one character word is an exact word**, because a one letter prefix
  must merge every index term starting with it (10 to 25 ms measured against 1 to 3 ms for everything else) and matches
  nearly everything anyway. "J. R. R. Tolkien" works because each `J`, `R` is an exact token.

`CatalogDatabase.search` runs the 300 popularity-ordered matches with their `bm25`, and `CatalogQuery.rank` orders them
the way the old in-memory search did: exact title (+40), title prefix (+20), title contains (+8), author contains (+10),
`log(popularity + 10)` as the tie-break, plus up to 4.5 from bm25 (specific matches) so near-ties order sensibly. An exact
title always beats bm25. Ties fall to popularity, then id, so results are deterministic.

Known limit: an exact title that is very obscure and shares a one or two letter prefix with hundreds of better-known books
can fall outside the 300 candidates. Typing more of it fixes it, because a longer prefix is more selective.

`scripts/catalog/query.py` is the Python twin of the builder (the build checks time the real SQL with it). Both test suites
share one table of cases, so changing one side fails the other.

## The pipeline

`python3 -I scripts/catalog/build_catalog_db.py` (see `--help`). Steps, in the order that makes each step smaller:

1. **redirects** (75 MB): merged works and authors, so reading-log entries, ratings and editions land on the surviving work.
2. **popularity**: popularity = reading-log entries (all shelves) + ratings. Works below `--min-popularity` (default 3)
   never go further. About 890,000 works pass.
3. **works** (4.1 GB): title, first author, cover, subjects, first publish year; junk titles dropped on sight.
4. **editions** (12.6 GB): for candidate works only, every edition's publication year, and for editions with a believable
   page count (40 to 2500) the page count, language and cover. Audio, video, microform and other non-book formats are ignored.
5. **authors** (0.8 GB): names for the authors of surviving works only.
6. **build**: quality rules, page counts, dedupe, genres, themes, pool, database.

Everything in steps 3 to 5 goes to a disk-backed SQLite file (`--work-dir`), never Python dicts; only the candidate id set and
the redirect maps are in memory. Each step marks itself done there, so `--resume` after an interrupted run skips finished
steps. Downloads resume mid-file with HTTP Range requests, so a dropped connection costs seconds, not the 12 GB.

**Quality rules** are the seed builder's own (`scripts/build_catalog.py` is imported, not copied): one entry per work; junk
titles and authors (study guides, summaries, box sets, omnibuses, publishers); textbook subjects; anthologies; foreign
titles and authors; require an author and a page count. Beyond the seed: a duplicate title and author surname keeps the most
popular work.

**Page counts** are the median over the work's editions in the chosen language, taking the lower middle value so it is a
count a real edition has. The next most common counts (up to 4; a count one edition reports is kept only when there are
five editions or fewer) are `page_counts`, for the edition picker. A translation's page count is never mixed in: with the
default `--languages en`, only English-tagged editions count, and untagged editions stand in only when the title does not
look foreign.

**Genres** are the seed builder's `classify` over the work's subjects. **Themes** come from the curated lexicon in
`scripts/add_themes.py`, which is now importable without side effects (`themes_for_subjects`, `choose_themes`) and memoises
per subject. With the crawl cache present, the refactored functions reproduce the shipped seed's themes byte for byte (a test
checks it). Document frequencies are computed over the selected books, as in the seed. Books with neither genres nor themes
stay searchable and are never in the pool.

**The pool** (`--pool-size`, default 25,000) is the most popular English books with genres or themes and at least 5 readers,
topped up so no genre has fewer than `--min-per-genre` (60) books, plus the famous books the seed builder spot-checks.

**Local trials.** `--limit-lines N` and `--max-bytes N` cut the big dumps short; `--dump-dir DIR --sample` reads local copies
(even truncated ones); `--dump-date` pins a release; `--from-json PATH` builds from a seed in seconds with no network.

## Rebuilding

What the lead does to run the full build:

1. (Optional) set the repository variable `CATALOG_CONTACT` to an email address, so Open Library can reach you (their API
   guidelines ask bulk users to identify themselves).
2. Edit `scripts/catalog/REBUILD` (bump the number at the bottom) and push to `main`; or Actions, **Catalog**, Run workflow
   (inputs: dump date, minimum popularity, whether to commit).
3. Wait one to two hours (timeout 330 minutes). The run does the unit tests, the build, then the checks: at least 150,000
   rows, at most 60 MB, p95 search under 30 ms, no empty titles or authors, ids and page ranges valid, vocab complete, rowid
   in popularity order, not built from a truncated sample.
4. If every check passes, it commits `Leaf/Resources/catalog.sqlite` to `main` as `Catalog: rebuild (N books)`. The database
   and logs are also attached to the run as an artifact, pass or fail.
5. The commit is made with `GITHUB_TOKEN`, which by design does not start the iOS workflow. Push anything (or run the iOS
   workflow) to build and test the app against the new database.

If the row count check fails, lower the minimum popularity (input on the manual run; 1 admits every work anyone has shelved).
The workflow cannot loop: only `REBUILD` triggers it, and the commit does not touch that file.

Check any database locally: `python3 -I scripts/catalog/check_catalog.py Leaf/Resources/catalog.sqlite --min-rows 1000`.

## Data and licence

* Source: Open Library's monthly data dumps (https://openlibrary.org/developers/dumps, hosted on archive.org). The dumps page
  says nothing about licence terms. The developer licensing page (https://openlibrary.org/developers/licensing, last edited
  June 27, 2021, re-read on 2026-10-18) says: *"The Internet Archive does not assert any new copyright or other proprietary
  rights over any of the material in the Open Library database. There may be existing rights issues on some contributions
  and in some jurisdictions."* The API page (https://openlibrary.org/developers/api, read the same day) says the APIs are not a
  bulk data backend ("For bulk access, please download our free monthly data dumps") and asks bulk users to identify themselves
  with a `User-Agent` carrying an application name and contact. The pipeline sends one (`LEAF_CATALOG_CONTACT`) and uses
  only the dumps, never the API.
* What this means: the catalog contains facts about books (titles, authors, years, page counts, subjects-derived tags,
  cover ids, aggregate popularity counts), no descriptions, no reviews, no user data and no images. Covers stay remote by
  cover id from covers.openlibrary.org, as before.
* Attribution is not demanded by anything read above, but it is the decent thing and cheap: the Settings privacy copy already
  names Open Library; add "Book data from Open Library, a project of the Internet Archive" to the About or credits screen.
* The reading-log and ratings dumps are used only as anonymous counts per work. Their rows carry no usernames.
* The dumps are not legal advice; ask a lawyer before commercial release if the "existing rights issues" line worries you.

## Measured

**Size.** The real 5,264 book catalog (with themes) is 974,848 bytes: 185 bytes a book, which is 46 MB at 250,000. A
synthetic 250,000 row catalog (shorter titles than real ones) is 37.1 MB: `books` 23.7, FTS data 5.8, id index 4.6, FTS
docsize 2.8, pool index 0.2. Without `detail=none` the same synthetic file is 49.5 MB, and real titles (about five words) would
push that past 65 MB, which is why `detail=none` is the default. The check budget is 60 MB.

**Latency** (the app's exact search SQL, Python `sqlite3`, this sandbox, 250,000 synthetic rows, 958 typing-like queries):
median 1.5 ms, p95 3.1 ms, p99 4.5 ms, max 6.5 ms. On the real 5,264 book catalog: median 0.1 ms, max 1.5 ms. A one letter
prefix (not issued by the app) took 10 to 25 ms. Ranking 300 candidates in Swift takes about 1.5 ms (debug build). The Swift
wrapper, compiled on Linux against the same file, returned 300 rows in 7 to 8 ms in a debug build including row decoding;
release builds on a phone are well under the 30 ms budget.

**Pipeline throughput** (this sandbox, 4 cores, single process, streaming from archive.org at over 50 MB/s):

| Step | Rate | Full dump estimate |
|---|---|---|
| reading-log, ratings | 280,000 lines/s | 1 minute |
| works | 130,000 lines/s | 5 minutes |
| editions | 65,000 to 175,000 lines/s | 6 to 14 minutes |
| authors | 280,000 lines/s | 3 minutes |
| popularity staging, build, database | | 5 to 10 minutes |

The GitHub runner's network is the unknown; at 10 MB/s the downloads alone are about 30 minutes. Staging uses about 1 to 2 GB
of disk and a few hundred MB of memory.

## What the real dumps look like (release 2026-09-30)

Findings from streaming prefixes of the real dumps through the real pipeline (counts only; no records are reproduced here).

* **Sizes** (compressed): works 4,073,320,823 bytes, editions 12,617,475,043, authors 782,352,949, reading-log 122,565,618,
  ratings 9,323,906, redirects 75,098,970. The old estimate for the authors dump was missing: **names are not in the works
  dump**, only author keys, so the authors dump is required (and every key must be resolved).
* **Format.** Five tab separated columns: type, key, revision, last modified, JSON. Reading-log and ratings are four columns
  (`work key`, `edition key or \N`, `shelf or rating`, `date`). Files are one gzip stream that supports HTTP Range.
* **Order.** Neither works nor editions are sorted by key: a prefix is a scattered subset, not "the oldest records". A 250 MB
  works prefix holds 2,672,059 works; a 300 MB editions prefix holds 1,406,068 editions (1,095 bytes each, about 5 to 1 gzip).
* **Reading-log.** 12,961,546 rows over 3.3 million works: Want to Read 10,655,319, Already Read 1,691,633, Currently
  Reading 612,675, Stopped Reading 1,919. **Ratings.** 1,060,973 rows over about 710,000 works (stars: 1: 33,835; 2: 35,385;
  3: 109,803; 4: 594,858; 5: 287,092). After merging redirects, 3,306,031 works have a reading-log entry and 704,956 a rating;
  891,997 reach popularity 3, roughly 450,000 reach 5, 183,000 reach 10, 77,000 reach 20. The 250,000th book is therefore
  expected near popularity 6 to 8 before quality filters. Not verified on the full dump: if the row check fails, lower
  `--min-popularity`.
* **Redirects.** 1,818,521 records: 1,150,009 works, 552,522 authors, 115,947 editions. The authors dump contains only
  `/type/author` records, so author merges are only visible in the redirects dump. Without them, popularity of merged works
  would be lost.
* **Works** (of the works with popularity of at least 3): an author on 98.9%, a cover list on 84.5% (the list can contain
  `-1`), subjects on 83.0%, `first_publish_date` on only 20.5%, so most years come from editions. Subjects are noisy: other
  languages, `nyt:` tags with dates, series markers, library flags. Fictitious-character series markers are in `subjects`
  (about 3.5% of those works), far more than in `subject_people`.
* **Editions.** 60.7% have `number_of_pages`; 11.6% of those are outside 40 to 2500 (zeros, ones, ISBN-like numbers). In the
  sample the field was always an integer; the parser also accepts digit strings and whole floats. 13.8% have no language
  tag, 56% are tagged English. 3.7% have no work key and none had two. 96.6% have a publication date with a year, 23% a cover.
  Formats: paperback and hardcover dominate; microform (1.7%), audio CD, cassette, MP3 CD, CD-ROM, maps and calendars exist
  and are ignored.
* **Sample run** (`--dump-dir` with the prefixes above, defaults): 891,997 candidates, 54,341 found in the works prefix, 5,029
  with an edition in the editions prefix, 8,443 of 41,820 author names found, **491 books** (the prefixes overlap little, so
  this validates the mechanics and the rules, not the yield). Rejections: 51,760 candidates with no usable edition in the
  sample, 2,642 junk titles, 2,060 author names not in the prefix, 711 works with no author, 22 textbooks, 4 foreign authors.
* **Known imperfections.** Years come from edition publication dates when the work has none, then pass the seed builder's
  outlier rule (an isolated early edition date is dropped). Obscure works can carry a wrong year. Page counts of works with a
  single edition are only as good as that edition.

## Decisions and risks

* Languages: English only by default. The `language` column and `--languages en,fr` exist; a "show other languages" setting
  needs a build with them and a filter on `Book.language`.
* The seed JSON had one edition id (`OL…M`) among its work ids; it is skipped, so the interim database has 5,264 books.
* `ios.yml` still prints `books.json bundled` at the end of the archive step (it only echoes; nothing fails).
* The pool is chosen at build time. Changing `--pool-size` is a rebuild, not an app change.
* `NEXT.md` sections 17.1 and 17.7 still say `books.json`; the seed now lives at `scripts/data/books.seed.json`, and
  `scripts/showrows` and `RecommenderTests` read it from there.
