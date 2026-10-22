#!/usr/bin/env python3
"""Sanity-check a built catalog database; exit code 1 if any check fails.

    python3 -I scripts/catalog/check_catalog.py Leaf/Resources/catalog.sqlite
    python3 -I scripts/catalog/check_catalog.py scripts/catalog/seed-check.sqlite --min-rows 1000
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from catalog import checks  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("database")
    ap.add_argument("--min-rows", type=int, default=150_000)
    ap.add_argument("--max-mb", type=float, default=70.0)
    ap.add_argument("--max-p95-ms", type=float, default=30.0)
    ap.add_argument("--probes", type=int, default=300)
    ap.add_argument("--require-full", action="store_true", help="fail if built from a truncated sample")
    args = ap.parse_args()
    report = checks.check(args.database, args.min_rows, args.max_mb, args.max_p95_ms, args.probes, require_full=args.require_full)
    print(report.text())
    print("OK" if report.ok else "FAILED: %d check(s)" % len(report.failures))
    return 0 if report.ok else 1


if __name__ == "__main__":
    sys.exit(main())
