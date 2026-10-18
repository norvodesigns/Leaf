"""Leaf's offline book catalog: the pipeline that turns Open Library data into the bundled SQLite database.

Entry points (run from the repo root with `python3 scripts/catalog/<name>.py`):

    build_catalog_db.py   build Leaf/Resources/catalog.sqlite from the Open Library dumps, or --from-json a seed file
    check_catalog.py      sanity checks on a built database (row counts, size, search latency, empty fields)

See docs/CATALOG.md for the architecture, the schema and how to run the full build.
"""

import os
import sys

SCRIPTS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_ROOT = os.path.dirname(SCRIPTS_DIR)

# `python3 -I` does not put the script's folder on sys.path, so make `import catalog.x` and the sibling scripts
# (build_catalog.py, add_themes.py) importable from anywhere.
if SCRIPTS_DIR not in sys.path:
    sys.path.insert(0, SCRIPTS_DIR)
