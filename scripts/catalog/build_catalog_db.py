#!/usr/bin/env python3
"""Build Leaf's bundled catalog database (Leaf/Resources/catalog.sqlite).

Two ways in:

  Full build from the Open Library data dumps (what CI runs; streams about 17 GB, stores none of it):
      python3 -I scripts/catalog/build_catalog_db.py

  Quick build from the seed JSON (5,265 books, a few seconds, no network):
      python3 -I scripts/catalog/build_catalog_db.py --from-json scripts/data/books.seed.json

Useful flags for trying things out:
  --limit-lines N      read only the first N lines of the big dumps (works, editions, authors)
  --max-bytes N        read only the first N compressed bytes of each big dump
  --dump-dir DIR       use local copies of the dumps (also for truncated sample files; add --sample)
  --dump-date DATE     pin to one monthly release, e.g. 2026-09-30 (default: whatever `latest` is today)
  --out PATH           where to write (default Leaf/Resources/catalog.sqlite)
  --resume             keep the work directory and skip steps that already finished

See docs/CATALOG.md.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from catalog import REPO_ROOT, legacy, pipeline, schema, streams  # noqa: E402
from catalog.from_json import load_rows  # noqa: E402

DEFAULT_OUT = os.path.join(REPO_ROOT, "Leaf", "Resources", "catalog.sqlite")


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--from-json", metavar="PATH", help="build from a seed JSON instead of the dumps")
    ap.add_argument("--dump-dir", metavar="DIR", help="read local dump files from DIR instead of the network")
    ap.add_argument("--dump-date", metavar="YYYY-MM-DD")
    ap.add_argument("--sample", action="store_true", help="local dump files may be truncated (sample prefixes)")
    ap.add_argument("--limit-lines", type=int, metavar="N")
    ap.add_argument("--max-bytes", type=int, metavar="N")
    ap.add_argument("--work-dir", default=os.path.join(REPO_ROOT, "scripts", ".cache", "catalog-work"))
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--languages", default="en", help="comma separated ISO 639-1 codes, most preferred first")
    ap.add_argument("--min-popularity", type=int, default=3, help="reading-log entries plus ratings a work needs")
    ap.add_argument("--max-books", type=int, default=250_000)
    ap.add_argument("--pool-size", type=int, default=25_000)
    ap.add_argument("--min-per-genre", type=int, default=60)
    return ap.parse_args(argv)


def build_from_json(args):
    rows = load_rows(args.from_json)
    meta = {
        "source": "Open Library search API crawl (scripts/build_catalog.py)",
        "source_dump": "seed",
        "source_url": "https://openlibrary.org/developers/api",
        "truncated_sample": "no",
        "languages": "en",
        "pipeline": "scripts/catalog/build_catalog_db.py --from-json",
        "license": "Open Library metadata; see https://openlibrary.org/developers/licensing",
    }
    result = schema.write_database(args.out, rows, legacy.rules().GENRES, meta=meta, progress=streams.log)
    streams.log("wrote %s: %d books, %d in the pool, %.2f MB" % (args.out, result["books"], result["pool"], result["bytes"] / 1e6))
    return result


def main(argv=None):
    args = parse_args(argv)
    if args.from_json:
        build_from_json(args)
        return 0
    source = streams.DumpSource(
        directory=args.dump_dir, date=args.dump_date, max_bytes=args.max_bytes, limit_lines=args.limit_lines,
        allow_truncated=args.sample)
    options = pipeline.Options(
        source=source, out=args.out, work_dir=args.work_dir,
        languages=tuple(c.strip() for c in args.languages.split(",") if c.strip()),
        min_popularity=args.min_popularity, max_books=args.max_books, pool_size=args.pool_size,
        min_per_genre=args.min_per_genre, resume=args.resume)
    pipeline.run(options)
    return 0


if __name__ == "__main__":
    sys.exit(main())
