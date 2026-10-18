"""Reading the Open Library dumps without ever storing one.

A dump is a multi-gigabyte gzip of tab separated records. We read it as a stream: bytes come from a local file or a
URL, go through zlib, and come out as lines. Nothing is written to disk, a dropped connection resumes with a Range
request, and a truncated stream (a sample prefix, or --limit-lines) is accepted only when the caller says it expects
one.
"""

import glob
import os
import re
import sys
import time
import urllib.error
import urllib.request
import zlib

# Open Library asks bulk users to say who they are: an application name and a way to reach someone. Set
# LEAF_CATALOG_CONTACT (an email address is best) in the environment of a real run.
USER_AGENT = "LeafCatalogBuilder/1.0 (%s)" % os.environ.get("LEAF_CATALOG_CONTACT", "https://github.com/norvodesigns/leaf/issues")
DUMP_BASE = "https://openlibrary.org/data/ol_dump_%s_latest.txt.gz"
DATED_BASE = "https://archive.org/download/ol_dump_%(date)s/ol_dump_%(kind)s_%(date)s.txt.gz"
DATE_RX = re.compile(r"ol_dump_(?:[a-z\-]+_)?(\d{4}-\d{2}-\d{2})")
CHUNK = 1 << 20

KINDS = ("works", "editions", "authors", "ratings", "reading-log", "redirects")


class TruncatedStream(Exception):
    """The gzip stream ended before its end marker and the caller did not expect that."""


def log(message):
    print(time.strftime("[%H:%M:%S] ") + message, file=sys.stderr, flush=True)


class HttpChunks:
    """Chunks of a (possibly huge) HTTP body that survive dropped connections.

    On a read error it reconnects with `Range: bytes=<offset>-` and carries on, so a 12 GB download does not have to
    start over because of one reset. `max_bytes` stops early (used for sample runs). `final_url` is where redirects
    ended up, which is how the dump date is learnt from `..._latest.txt.gz`.
    """

    def __init__(self, url, max_bytes=None, retries=12, timeout=120):
        self.url = url
        self.max_bytes = max_bytes
        self.retries = retries
        self.timeout = timeout
        self.offset = 0
        self.total = None
        self.final_url = url

    def _open(self):
        headers = {"User-Agent": USER_AGENT, "Accept-Encoding": "identity"}
        if self.offset:
            headers["Range"] = "bytes=%d-" % self.offset
        resp = urllib.request.urlopen(urllib.request.Request(self.url, headers=headers), timeout=self.timeout)
        self.final_url = resp.geturl()
        length = resp.headers.get("Content-Length")
        if length and self.total is None:
            self.total = int(length) + self.offset
        if self.offset and resp.status != 206:
            resp.close()
            raise OSError("server ignored the Range request (HTTP %s)" % resp.status)
        return resp

    def resolve(self):
        """Open the URL just long enough to learn where redirects lead (`final_url`)."""
        self._open().close()
        return self.final_url

    def __iter__(self):
        failures = 0
        resp = None
        while True:
            try:
                if resp is None:
                    resp = self._open()
                want = CHUNK
                if self.max_bytes is not None:
                    want = min(want, self.max_bytes - self.offset)
                    if want <= 0:
                        break
                data = resp.read(want)
                if not data:
                    break
                self.offset += len(data)
                failures = 0
                yield data
            except (OSError, urllib.error.URLError) as exc:
                if resp is not None:
                    resp.close()
                    resp = None
                failures += 1
                if failures > self.retries:
                    raise
                wait = min(60, 2 ** failures)
                log("download interrupted at %d MB (%s); retry %d in %ds" % (self.offset >> 20, exc, failures, wait))
                time.sleep(wait)
        if resp is not None:
            resp.close()


def file_chunks(path, max_bytes=None):
    done = 0
    with open(path, "rb") as fh:
        while True:
            want = CHUNK if max_bytes is None else min(CHUNK, max_bytes - done)
            if want <= 0:
                return
            data = fh.read(want)
            if not data:
                return
            done += len(data)
            yield data


def gunzip_lines(chunks, allow_truncated=False, limit_lines=None, counters=None):
    """Lines (bytes, no newline) of a gzip stream given as an iterable of byte chunks.

    Handles concatenated gzip members. At the end, a stream that did not reach its gzip trailer raises
    TruncatedStream unless `allow_truncated` (or `limit_lines`, which stops early on purpose) is set.
    `counters`, if given, is a dict that receives `compressed` and `lines`.
    """
    d = zlib.decompressobj(zlib.MAX_WBITS | 16)
    tail = b""
    count = 0
    compressed = 0
    finished = False
    for chunk in chunks:
        compressed += len(chunk)
        while chunk:
            data = d.decompress(chunk)
            chunk = b""
            if d.eof:
                chunk = d.unused_data
                d = zlib.decompressobj(zlib.MAX_WBITS | 16)
                finished = True
            else:
                finished = False
            if not data:
                continue
            parts = (tail + data).split(b"\n")
            tail = parts.pop()
            for line in parts:
                count += 1
                yield line
                if limit_lines is not None and count >= limit_lines:
                    if counters is not None:
                        counters.update(compressed=compressed, lines=count)
                    return
    if tail:
        count += 1
        yield tail
    if counters is not None:
        counters.update(compressed=compressed, lines=count)
    if not finished and not allow_truncated:
        raise TruncatedStream("gzip stream ended early after %d lines" % count)


def local_dump(directory, kind):
    """A local copy of a dump in `directory`, if there is one: ol_dump_<kind>*.gz, <kind>*.gz or *<kind>*.gz."""
    for pattern in ("ol_dump_%s_*.gz", "ol_dump_%s.*gz", "%s*.gz", "*%s*.gz"):
        found = sorted(glob.glob(os.path.join(directory, pattern % kind)))
        if found:
            return found[-1]
    return None


class DumpSource:
    """Where each dump comes from, and how much of it to read.

    * `directory`: use local files there (tests, or sample prefixes) and never touch the network.
    * otherwise `date`: pin every dump to one monthly release (YYYY-MM-DD); with no date, ask Open Library which
      release `latest` is, once, and pin the rest to it so a release published mid-run cannot mix two snapshots.
    * `max_bytes` / `limit_lines`: read only that much of each big dump (sample runs), and `allow_truncated` accepts
      local files that are already cut short; a truncated stream is only fine when one of these says so.
    """

    def __init__(self, directory=None, date=None, max_bytes=None, limit_lines=None, allow_truncated=False):
        self.directory = directory
        self.date = date
        self.max_bytes = max_bytes
        self.limit_lines = limit_lines
        self.truncated = allow_truncated or max_bytes is not None or limit_lines is not None

    def resolve_date(self):
        if self.date or self.directory:
            return self.date
        final = HttpChunks(DUMP_BASE % "ratings").resolve()
        m = DATE_RX.search(final)
        if not m:
            raise RuntimeError("could not learn the latest dump date from %s" % final)
        self.date = m.group(1)
        return self.date

    def describe(self, kind):
        if self.directory:
            path = local_dump(self.directory, kind)
            if not path:
                raise FileNotFoundError("no %s dump in %s" % (kind, self.directory))
            return path
        return DATED_BASE % {"kind": kind, "date": self.resolve_date()}

    def lines(self, kind, big=True, counters=None):
        """Lines of one dump. Small dumps (ratings, reading-log, redirects) are always read whole."""
        source = self.describe(kind)
        limit = self.max_bytes if big else None
        if self.directory:
            chunks = file_chunks(source, limit)
        else:
            chunks = HttpChunks(source, max_bytes=limit)
        log("reading %s%s" % (source, "" if limit is None else " (first %d MB)" % (limit >> 20)))
        return gunzip_lines(
            chunks, allow_truncated=self.truncated and big,
            limit_lines=self.limit_lines if big else None, counters=counters)

    def dump_date(self):
        """The release these dumps belong to, for the metadata table."""
        if self.date:
            return self.date
        if self.directory:
            for kind in KINDS:
                path = local_dump(self.directory, kind)
                m = DATE_RX.search(os.path.basename(path or ""))
                if m:
                    return m.group(1)
            return "local"
        return self.resolve_date()
