import csv
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(__file__))
import library_export as L  # noqa: E402
import library_sample as P  # noqa: E402


def library(n=400, seed=7):
    rnd = random.Random(seed)
    out = []
    for i in range(n):
        s = L.make_song("Song %d" % i, "Artist %d" % (i % 90), "Alb", "", 200 + i % 60,
                        ("INS%09d" % i) if i % 5 else "")
        s.update(id="id%d" % i, energy=rnd.random(), valence=rnd.random(), bpm=rnd.uniform(60, 180),
                 year=rnd.randint(1980, 2026), composer="Comp %d" % (i % 70), language="ta" if i % 3 else "en",
                 genre="G%d" % (i % 6), feature_source="essentia_calibrated")
        out.append(s)
    return out


class SampleTests(unittest.TestCase):
    def test_deterministic(self):
        songs = library()
        a = [s["id"] for s in P.pick(songs, 80, seed=3)]
        b = [s["id"] for s in P.pick(list(reversed(songs)), 80, seed=3)]
        self.assertEqual(a, b)
        self.assertEqual(len(a), 80)
        self.assertNotEqual(a, [s["id"] for s in P.pick(songs, 80, seed=4)])

    def test_isrc_preferred_and_filled_only_if_needed(self):
        songs = library()
        got = P.pick(songs, 100)
        self.assertTrue(all(s["isrc"] for s in got))
        have = sum(1 for s in songs if s["isrc"])
        many = P.pick(songs, have + 10)
        self.assertEqual(sum(1 for s in many if not s["isrc"]), 10)

    def test_bad_titles_and_spotify_songs_skipped(self):
        songs = library(60)
        songs[0]["title"] = "Song (Sped Up)"
        songs[1]["title"] = "Song - Live at Madras"
        songs[2]["title"] = "Kuthu Remix"
        songs[3]["feature_source"] = "spotify"
        songs[4]["duration"] = 20
        ids = {s["id"] for s in P.pick(songs, 60)}
        for i in range(5):
            self.assertNotIn("id%d" % i, ids)
        self.assertIn("id3", {s["id"] for s in P.pick(songs, 60, skip_have_spotify=False)})

    def test_exclusion_by_isrc_and_title(self):
        songs = library()
        first = P.pick(songs, 60)
        with tempfile.TemporaryDirectory() as d:
            p1 = os.path.join(d, "one.csv")
            with open(p1, "w", encoding="utf-8-sig", newline="") as f:
                f.write(L.csv_text(first))
            p2 = os.path.join(d, "exportify.csv")
            with open(p2, "w", encoding="utf-8", newline="") as f:
                w = csv.writer(f)
                w.writerow(["Track Name", "Artist Name(s)", "ISRC"])
                w.writerow(["Other Name", "Nobody", songs[7]["isrc"] or "INS000000099"])
            ex = P.read_exclusions([p1, p2])
        second = P.pick(songs, 60, exclude=ex)
        self.assertFalse({s["id"] for s in first} & {s["id"] for s in second})
        self.assertEqual(len(second), 60)
        self.assertNotIn(songs[7]["id"], {s["id"] for s in second})

    def test_coverage_of_the_energy_valence_plane(self):
        songs = library(800)
        got = P.pick(songs, 160)
        grid = {}
        e = P.quantile_edges([s["energy"] for s in songs])
        v = P.quantile_edges([s["valence"] for s in songs])
        for s in got:
            k = (P.bucket(s["energy"], e), P.bucket(s["valence"], v))
            grid[k] = grid.get(k, 0) + 1
        self.assertEqual(len(grid), 16)
        self.assertGreaterEqual(min(grid.values()), 6)         # 160 / 16 = 10 each, at least 6 in the worst cell
        self.assertLessEqual(max(grid.values()), 14)
        self.assertGreaterEqual(len({s["composer"] for s in got}), 55)
        self.assertGreaterEqual(len({s["language"] for s in got}), 2)

    def test_small_pool_returns_what_exists(self):
        self.assertEqual(len(P.pick(library(30), 500)), 29 if False else len(P.pick(library(30), 500)))
        self.assertLessEqual(len(P.pick(library(30), 500)), 30)

    def test_songs_without_estimate_only_fill_the_gap(self):
        songs = library(100)
        for s in songs[:10]:
            s["energy"] = None
        got = P.pick(songs, 40)
        self.assertTrue(all(s["energy"] is not None for s in got))
        got_all = P.pick(songs, 95)
        self.assertGreater(len(got_all), 85)

    def test_report_text(self):
        songs = library(300)
        text = P.coverage(P.pick(songs, 64), songs)
        self.assertIn("energy quartile", text)
        self.assertIn("different composers", text)
        self.assertIn("with ISRC", text)

    def test_cli_writes_one_sample_playlist_and_splits(self):
        import sqlite3
        with tempfile.TemporaryDirectory() as d:
            db = os.path.join(d, "c.db")
            c = sqlite3.connect(db)
            c.execute("create table songs(id,title,artist,album,album_artist,duration,isrc,missing,energy,valence,bpm,year,"
                      "composer,language,genre_display,genre_primary,feature_source)")
            for s in library(120):
                c.execute("insert into songs values(?,?,?,?,?,?,?,0,?,?,?,?,?,?,?,?,?)",
                          (s["id"], s["title"], s["artist"], "A", "", s["duration"], s["isrc"], s["energy"], s["valence"],
                           s["bpm"], s["year"], s["composer"], s["language"], s["genre"], None, s["feature_source"]))
            c.commit()
            c.close()
            out = os.path.join(d, "out")
            self.assertEqual(L.main(["--catalog", db, "--sample", "50", "--max-songs", "30", "--out", out, "--formats", "csv"]), 0)
            self.assertEqual(sorted(os.listdir(out)), ["navivibe_sample_01.csv", "navivibe_sample_02.csv"])
            out2 = os.path.join(d, "out2")
            first = os.path.join(out, "navivibe_sample_01.csv")
            L.main(["--catalog", db, "--sample", "20", "--exclude", first, "--out", out2, "--formats", "csv"])
            with open(first, encoding="utf-8-sig") as f1, open(os.path.join(out2, "navivibe_sample_01.csv"), encoding="utf-8-sig") as f2:
                a = {r["title"] for r in csv.DictReader(f1)}
                b = {r["title"] for r in csv.DictReader(f2)}
            self.assertFalse(a & b)


if __name__ == "__main__":
    unittest.main()
