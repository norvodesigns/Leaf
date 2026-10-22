"""Helpers shared by the catalog tests: put scripts/ on sys.path and write tiny gzip dumps."""

import gzip
import json
import os
import sys
import tempfile

SCRIPTS = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
if SCRIPTS not in sys.path:
    sys.path.insert(0, SCRIPTS)


def tsv(kind, key, obj):
    return "%s\t%s\t1\t2020-01-01T00:00:00\t%s" % (kind, key, json.dumps(obj, ensure_ascii=False))


def write_gz(path, lines):
    with gzip.open(path, "wb") as fh:
        fh.write(("\n".join(lines) + "\n").encode("utf-8"))


def work(num, title, author_num, subjects=(), covers=None, date=None, authors=None):
    obj = {"key": "/works/OL%dW" % num, "type": {"key": "/type/work"}, "title": title,
           "authors": [{"type": {"key": "/type/author_role"}, "author": {"key": "/authors/OL%dA" % a}}
                       for a in (authors if authors is not None else [author_num])],
           "subjects": list(subjects)}
    if covers is not None:
        obj["covers"] = covers
    if date:
        obj["first_publish_date"] = date
    return tsv("/type/work", obj["key"], obj)


def edition(num, work_num, pages=None, langs=("eng",), cover=None, date=None, fmt=None, title=None, isbn13=(), isbn10=()):
    obj = {"key": "/books/OL%dM" % num, "type": {"key": "/type/edition"}, "works": [{"key": "/works/OL%dW" % work_num}],
           "languages": [{"key": "/languages/%s" % c} for c in langs]}
    if pages is not None:
        obj["number_of_pages"] = pages
    if cover:
        obj["covers"] = [cover]
    if date:
        obj["publish_date"] = date
    if fmt:
        obj["physical_format"] = fmt
    if title:
        obj["title"] = title
    if isbn13:
        obj["isbn_13"] = list(isbn13)
    if isbn10:
        obj["isbn_10"] = list(isbn10)
    return tsv("/type/edition", obj["key"], obj)


def author(num, name):
    return tsv("/type/author", "/authors/OL%dA" % num, {"key": "/authors/OL%dA" % num, "name": name})


def redirect(kind, src, dst):
    letter = {"works": "W", "authors": "A"}[kind]
    key = "/%s/OL%d%s" % (kind, src, letter)
    return tsv("/type/redirect", key, {"key": key, "type": {"key": "/type/redirect"}, "location": "/%s/OL%d%s" % (kind, dst, letter)})


def shelf(work_num, name="Want to Read"):
    return "/works/OL%dW\t\\N\t%s\t2020-01-01" % (work_num, name)


def rating(work_num, stars=5):
    return "/works/OL%dW\t\\N\t%d\t2020-01-01" % (work_num, stars)


def temp_dir():
    return tempfile.TemporaryDirectory(prefix="leaf-catalog-test-")
