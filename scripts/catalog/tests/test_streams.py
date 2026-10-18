import gzip
import os
import unittest

import support
from catalog import streams


def gz(text):
    return gzip.compress(text.encode("utf-8"))


class GunzipLinesTests(unittest.TestCase):
    def test_lines_across_chunk_boundaries(self):
        data = gz("".join("line %d\n" % i for i in range(5000)))
        chunks = [data[i:i + 97] for i in range(0, len(data), 97)]
        lines = list(streams.gunzip_lines(chunks))
        self.assertEqual(len(lines), 5000)
        self.assertEqual(lines[0], b"line 0")
        self.assertEqual(lines[-1], b"line 4999")

    def test_last_line_without_newline(self):
        self.assertEqual(list(streams.gunzip_lines([gz("a\nb")])), [b"a", b"b"])

    def test_truncated_stream_is_an_error_unless_expected(self):
        data = gz("".join("row %d\n" % i for i in range(20000)))[:-30]
        with self.assertRaises(streams.TruncatedStream):
            list(streams.gunzip_lines([data]))
        lines = list(streams.gunzip_lines([data], allow_truncated=True))
        self.assertGreater(len(lines), 100)
        self.assertEqual(lines[0], b"row 0")

    def test_empty_input_counts_as_truncated(self):
        with self.assertRaises(streams.TruncatedStream):
            list(streams.gunzip_lines([]))

    def test_concatenated_members(self):
        data = gz("a\nb\n") + gz("c\nd\n")
        self.assertEqual(list(streams.gunzip_lines([data[:7], data[7:]])), [b"a", b"b", b"c", b"d"])

    def test_limit_lines_stops_early_without_error(self):
        data = gz("".join("x%d\n" % i for i in range(1000)))[:200]
        self.assertEqual(len(list(streams.gunzip_lines([data], limit_lines=3))), 3)

    def test_counters(self):
        counters = {}
        data = gz("1\n2\n3\n")
        list(streams.gunzip_lines([data], counters=counters))
        self.assertEqual(counters, {"compressed": len(data), "lines": 3})


class SourceTests(unittest.TestCase):
    def test_local_files_and_truncation_rules(self):
        with support.temp_dir() as tmp:
            support.write_gz(os.path.join(tmp, "ol_dump_works_2026-09-30.txt.gz"), ["a", "b", "c"])
            support.write_gz(os.path.join(tmp, "reading-log.txt.gz"), ["r"])
            source = streams.DumpSource(directory=tmp)
            self.assertEqual(list(source.lines("works")), [b"a", b"b", b"c"])
            self.assertEqual(list(source.lines("reading-log", big=False)), [b"r"])
            self.assertEqual(source.dump_date(), "2026-09-30")
            with self.assertRaises(FileNotFoundError):
                source.lines("authors")
            self.assertEqual(len(list(streams.DumpSource(directory=tmp, limit_lines=2).lines("works"))), 2)
            # a prefix cut mid-stream: an error normally, fine when the caller said it expects a sample
            path = os.path.join(tmp, "ol_dump_editions_2026-09-30.txt.gz")
            with gzip.open(path, "wb") as fh:
                fh.write(os.urandom(50000))
            with open(path, "rb") as fh:
                raw = fh.read()
            with open(path, "wb") as fh:
                fh.write(raw[:20000])
            with self.assertRaises(streams.TruncatedStream):
                list(streams.DumpSource(directory=tmp).lines("editions"))
            self.assertGreater(len(list(streams.DumpSource(directory=tmp, allow_truncated=True).lines("editions"))), 0)
            self.assertEqual(len(list(streams.DumpSource(directory=tmp, max_bytes=20000).lines("editions"))) > 0, True)

    def test_dated_urls(self):
        url = streams.DATED_BASE % {"kind": "works", "date": "2026-09-30"}
        self.assertEqual(url, "https://archive.org/download/ol_dump_2026-09-30/ol_dump_works_2026-09-30.txt.gz")
        self.assertEqual(streams.DATE_RX.search(url).group(1), "2026-09-30")


if __name__ == "__main__":
    unittest.main()
