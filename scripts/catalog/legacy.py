"""The two older scripts whose rules the dump pipeline reuses, loaded by path.

`scripts/build_catalog.py` owns the quality rules and the subject-to-genre mapping; `scripts/add_themes.py` owns the
theme lexicon. Loading them here (instead of copying) means one edit changes both pipelines.
"""

import importlib.util
import os

from catalog import SCRIPTS_DIR

_CACHE = {}


def _load(name):
    if name not in _CACHE:
        spec = importlib.util.spec_from_file_location(name, os.path.join(SCRIPTS_DIR, name + ".py"))
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        _CACHE[name] = module
    return _CACHE[name]


def rules():
    """scripts/build_catalog.py: fold, clean_title, classify, JUNK_TITLE, GENRES and friends."""
    return _load("build_catalog")


def themes():
    """scripts/add_themes.py: the theme lexicon and `themes_for_subjects` / `choose_themes`."""
    module = _load("add_themes")
    if not module._BUILD_CATALOG:
        module._BUILD_CATALOG.append(rules())  # share one copy of the rules instead of loading a second
    return module
