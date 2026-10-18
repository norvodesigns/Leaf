"""Parsing Open Library dump lines into the few fields the catalog uses.

Every function takes one line (bytes) or one decoded JSON object and returns plain tuples, or None for anything to be
skipped. Dump records are messy (a missing field, a list where a string should be, `-1` cover ids), so nothing here
trusts a type without checking it.
"""

import json
import re

MIN_PAGES = 40
MAX_PAGES = 2500

_YEAR = re.compile(r"(?<!\d)(1[0-9]{3}|20[0-2][0-9])(?!\d)")
_NON_PRINT = re.compile(
    r"audio|cassette|\bcd\b|cd-rom|mp3|dvd|video|vhs|vinyl|record|slide|poster|\bmap\b|calendar|sheet music|"
    r"\bgame|\bcards?\b|microfil|microform|\bfilm\b|software|multimedia|\bkit\b|\btoy\b|diskette|floppy", re.I)

# Open Library's three letter language codes -> the two letter codes the app stores.
LANG3_TO_2 = {
    "eng": "en", "spa": "es", "fre": "fr", "ger": "de", "ita": "it", "por": "pt", "dut": "nl", "rus": "ru",
    "swe": "sv", "dan": "da", "nor": "no", "fin": "fi", "pol": "pl", "cze": "cs", "hun": "hu", "rum": "ro",
    "gre": "el", "tur": "tr", "heb": "he", "ara": "ar", "per": "fa", "hin": "hi", "ben": "bn", "tam": "ta",
    "chi": "zh", "jpn": "ja", "kor": "ko", "vie": "vi", "ind": "id", "tha": "th", "ukr": "uk", "bul": "bg",
    "hrv": "hr", "srp": "sr", "slv": "sl", "slo": "sk", "cat": "ca", "lat": "la", "lit": "lt", "lav": "lv",
    "est": "et", "ice": "is", "wel": "cy", "gle": "ga", "afr": "af",
}
LANG2_TO_3 = {v: k for k, v in LANG3_TO_2.items()}


def key_number(key):
    """38 for '/works/OL38W' (str or bytes), or None when the key does not end in OL<digits><letter>."""
    if isinstance(key, bytes):
        key = key.decode("utf-8", "replace")
    if not isinstance(key, str):
        return None
    m = re.search(r"/OL(\d+)[A-Z]$", key)
    return int(m.group(1)) if m else None


def split_record(line):
    """(type, key, json bytes) of a dump line, or None if it is not a five column record."""
    cols = line.split(b"\t", 4)
    if len(cols) != 5:
        return None
    return cols[0], cols[1], cols[4]


def parse_rating_line(line):
    """Work number of a ratings line `work, edition, rating, date`; ratings are counted, not averaged."""
    cols = line.split(b"\t", 3)
    if len(cols) < 3 or not cols[0].startswith(b"/works/OL"):
        return None
    return key_number(cols[0])


def parse_reading_log_line(line):
    """(work number, shelf) of a reading-log line `work, edition, shelf, date`."""
    cols = line.split(b"\t", 3)
    if len(cols) < 3 or not cols[0].startswith(b"/works/OL"):
        return None
    work = key_number(cols[0])
    if work is None:
        return None
    return work, cols[2].decode("utf-8", "replace")


def parse_redirect_line(line):
    """('work' | 'author', source number, target number) for a redirect record between two keys of one kind."""
    rec = split_record(line)
    if rec is None or rec[0] != b"/type/redirect":
        return None
    kind = b"/works/" if rec[1].startswith(b"/works/") else b"/authors/" if rec[1].startswith(b"/authors/") else None
    if kind is None:
        return None
    try:
        location = json.loads(rec[2]).get("location")
    except ValueError:
        return None
    src, dst = key_number(rec[1]), key_number(location)
    if src is None or dst is None or src == dst or not str(location).startswith(kind.decode()):
        return None
    return kind.decode().strip("/")[:-1], src, dst


def year_of(text):
    """First plausible four digit year in an Open Library date string ('June 26, 1997', 'c1997', '1997-06')."""
    if isinstance(text, int) and 1000 <= text <= 2029:
        return text
    if not isinstance(text, str):
        return None
    m = _YEAR.search(text)
    return int(m.group(1)) if m else None


def first_cover(covers):
    """The first positive cover id of a `covers` list (Open Library uses -1 for 'removed')."""
    if isinstance(covers, list):
        for c in covers:
            if isinstance(c, int) and not isinstance(c, bool) and c > 0:
                return c
    return None


def _key_of(item):
    if isinstance(item, dict):
        inner = item.get("author", item)
        if isinstance(inner, dict):
            return inner.get("key")
        if isinstance(inner, str):
            return inner
    return None


def parse_work(obj):
    """(title, first author number or None, author count, year, cover, subjects) of a work record, or None.

    None means "not a usable work": a redirect or delete record, or one with no title.
    """
    if not isinstance(obj, dict):
        return None
    kind = obj.get("type")
    if isinstance(kind, dict) and kind.get("key") not in (None, "/type/work"):
        return None
    title = obj.get("title")
    if not isinstance(title, str) or not title.strip():
        return None
    authors = []
    for item in obj.get("authors") or []:
        n = key_number(_key_of(item))
        if n is not None:
            authors.append(n)
    subjects = [s for s in (obj.get("subjects") or []) if isinstance(s, str)]
    return (title.strip(), authors[0] if authors else None, len(authors), year_of(obj.get("first_publish_date")),
            first_cover(obj.get("covers")), subjects)


def language_codes(obj):
    """OL three letter language codes of an edition, in order (empty when untagged)."""
    codes = []
    for item in obj.get("languages") or []:
        key = item.get("key") if isinstance(item, dict) else None
        if isinstance(key, str) and key.startswith("/languages/"):
            codes.append(key.rsplit("/", 1)[1])
    return codes


def pages_of(obj):
    """number_of_pages as an int in the believable range, else None."""
    value = obj.get("number_of_pages")
    if isinstance(value, str) and value.strip().isdigit():
        value = int(value.strip())
    if isinstance(value, float) and value.is_integer():
        value = int(value)
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value if MIN_PAGES <= value <= MAX_PAGES else None


def edition_work_number(line):
    """Work number an edition line points at, found without parsing the JSON (the cheap pre-filter).

    Plain `bytes.find` instead of a regex: it is several times faster on a kilobyte line, and this runs on all 55
    million editions.
    """
    i = line.find(b'"/works/OL')
    if i < 0:
        return None
    j = line.find(b'W"', i + 10)
    if j < 0:
        return None
    digits = line[i + 10:j]
    return int(digits) if digits.isdigit() else None


def parse_edition(obj):
    """(work number, language codes, pages or None, cover, year, title) of a printed edition, or None.

    Pages is None when the edition has no believable page count; the edition still counts for its publication year.
    Audio, video and other non-book formats return None: their page counts and dates say nothing about the book.
    """
    if not isinstance(obj, dict):
        return None
    fmt = obj.get("physical_format")
    if isinstance(fmt, str) and _NON_PRINT.search(fmt):
        return None
    works = obj.get("works")
    work = key_number(works[0].get("key")) if isinstance(works, list) and works and isinstance(works[0], dict) else None
    if work is None:
        return None
    title = obj.get("title")
    return (work, language_codes(obj), pages_of(obj), first_cover(obj.get("covers")), year_of(obj.get("publish_date")),
            title if isinstance(title, str) else None)


def parse_author(obj):
    """Display name of an author record, or None."""
    if not isinstance(obj, dict):
        return None
    name = obj.get("name") or obj.get("personal_name")
    if isinstance(name, str) and name.strip():
        return re.sub(r"\s+", " ", name).strip()
    return None
