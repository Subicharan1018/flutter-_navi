import csv
import io
import os
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import library_export as L  # noqa: E402


def song(i, **kw):
    d = dict(title="Song %d" % i, artist="A", album="B", album_artist="A", duration=200 + i, isrc="")
    d.update(kw)
    return L.make_song(**d)


class SplitTests(unittest.TestCase):
    def test_split_sizes(self):
        parts = L.split([song(i) for i in range(20001)], 9500)
        self.assertEqual([len(p) for p in parts], [9500, 9500, 1001])

    def test_exact_multiple_and_empty(self):
        self.assertEqual(len(L.split([song(i) for i in range(9500)], 9500)), 1)
        self.assertEqual(L.split([], 9500), [])

    def test_bad_size(self):
        with self.assertRaises(ValueError):
            L.split([song(1)], 0)


class CsvTests(unittest.TestCase):
    def roundtrip(self, songs):
        return list(csv.DictReader(io.StringIO(L.csv_text(songs), newline="")))

    def test_commas_quotes_newlines(self):
        s = L.make_song('He said "hi", ok', "Bob, Jr.; Amy", "Alb\num", "AA", 201.6, "ins171100341")
        r = self.roundtrip([s])[0]
        self.assertEqual(r["title"], 'He said "hi", ok')
        self.assertEqual(r["artist"], "Bob, Jr.; Amy")
        self.assertEqual(r["album"], "Alb um")
        self.assertEqual(r["duration"], "202")
        self.assertEqual(r["isrc"], "INS171100341")

    def test_tamil_and_unicode(self):
        s = L.make_song("காதல் கண் கட்டுதே", "அனிருத் ரவிச்சந்தர்", "ராக்ஸ்டார் – ★", "", 250, "")
        with tempfile.TemporaryDirectory() as d:
            files = L.write_all([s], d, ("csv", "txt", "m3u8"))
            with open(files[0], encoding="utf-8-sig", newline="") as f:
                r = list(csv.DictReader(f))[0]
            self.assertEqual(r["title"], "காதல் கண் கட்டுதே")
            self.assertEqual(r["album"], "ராக்ஸ்டார் – ★")
            with open(files[1], encoding="utf-8") as f:
                self.assertEqual(f.read(), "அனிருத் ரவிச்சந்தர் - காதல் கண் கட்டுதே\n")

    def test_bad_isrc_dropped(self):
        self.assertEqual(L.norm_isrc("not-an-isrc"), "")
        self.assertEqual(L.norm_isrc("IN-S17-11-00341"), "INS171100341")


class FilesTests(unittest.TestCase):
    def test_numbered_files(self):
        with tempfile.TemporaryDirectory() as d:
            files = L.write_all([song(i) for i in range(5)], d, ("csv",), max_songs=2)
            self.assertEqual([os.path.basename(f) for f in files],
                             ["navivibe_library_01.csv", "navivibe_library_02.csv", "navivibe_library_03.csv"])

    def test_dedupe_and_details_merge(self):
        a = song(1, isrc="")
        a["id"] = "x"
        b = song(1, isrc="")
        b["id"] = "y"
        L.merge_isrcs([a], {"x": "INS171100341"})
        self.assertEqual(a["isrc"], "INS171100341")
        self.assertEqual(len(L.dedupe([a, dict(a)])), 1)
        self.assertEqual(len(L.dedupe([a, b])), 2)

    def test_summary(self):
        text = L.summary([song(1, isrc="INS171100341"), song(2)], 9500)
        self.assertIn("songs: 2", text)
        self.assertIn("with ISRC: 1", text)
        self.assertIn("playlists: 1", text)


class SourceTests(unittest.TestCase):
    def test_catalog_read(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "c.db")
            c = sqlite3.connect(p)
            c.execute("create table songs(id,title,artist,album,album_artist,duration,isrc,missing)")
            c.execute("insert into songs values('1','T','A','B','A',200.4,'INS171100341',0)")
            c.execute("insert into songs values('2','Gone','A','B','A',200,'',1)")
            c.commit()
            c.close()
            out = L.read_catalog(p)
            self.assertEqual([s["title"] for s in out], ["T"])

    def test_subsonic_paging_and_no_secret_in_output(self):
        pages = [[{"id": str(i), "title": "t%d" % i, "artist": "a", "duration": 10, "isrc": ["INS171100341"]}
                  for i in range(2)], [{"id": "9", "title": "last"}]]
        urls = []

        def fetch(url):
            urls.append(url)
            return {"subsonic-response": {"status": "ok", "searchResult3": {"song": pages[len(urls) - 1]}}}
        out = L.read_subsonic("http://x:4533/", "u", "secret-pass", fetch, page=2)
        self.assertEqual(len(out), 3)
        self.assertEqual(out[0]["isrc"], "INS171100341")
        self.assertTrue(all("secret-pass" not in u for u in urls))


if __name__ == "__main__":
    unittest.main()
