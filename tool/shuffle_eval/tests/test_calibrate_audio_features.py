import hashlib
import os
import sqlite3
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import calibrate_audio_features as C  # noqa: E402
import finalize_spotify_features as F  # noqa: E402


def build(d, n=300, labelled=150, noise=0.05, seed=2, csv_mode=False):
    """A catalog of n songs whose features are a (noisy) linear function of a 32-number embedding. The labels come
    from spotify_details.db, or (csv_mode) from an Exportify-style CSV with the real column names."""
    rng = np.random.default_rng(seed)
    dim = 32
    W = rng.normal(size=(dim, 6))
    E = rng.normal(size=(n, dim)).astype(np.float32)
    raw = E @ W
    Y = 1 / (1 + np.exp(-(raw / raw.std(0) + rng.normal(scale=noise, size=raw.shape))))
    cat, det = os.path.join(d, "catalog.db"), os.path.join(d, "spotify_details.db")
    csvp = os.path.join(d, "My_playlist.csv")
    c = sqlite3.connect(cat)
    c.execute("create table songs(id,title,artist,feature_source,isrc,duration,composer,language,year,genre_display,genre_primary,"
              "energy,valence,danceability,acousticness,bpm,loudness,missing)")
    c.execute("create table embeddings(song_id,model,dim,vec)")
    s = sqlite3.connect(det)
    s.execute("create table spotify_details(song_id,energy,valence,danceability,acousticness,tempo,loudness)")
    rows = []
    for i in range(n):
        sid = "s%d" % i
        cur = np.clip(Y[i] + rng.normal(scale=0.25, size=6), 0, 1)           # a weaker current estimate
        tempo, loud = 60 + 120 * Y[i][4], -30 + 25 * Y[i][5]
        c.execute("insert into songs values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0)",
                  (sid, "Title %d" % i, "Artist %d" % (i % 20), "essentia_calibrated", "INS%09d" % i, 200.0 + i % 30,
                   "C%d" % (i % 15), "ta", 2000 + i % 25, "Pop", None, *map(float, cur[:4]), float(60 + 120 * cur[4]),
                   float(-30 + 25 * cur[5])))
        c.execute("insert into embeddings values(?,?,?,?)", (sid, "effnet_discogs", dim, E[i].tobytes()))
        if i < labelled:
            if csv_mode:
                rows.append({"Track URI": "spotify:track:%d" % i, "ISRC": "INS%09d" % i if i % 7 else "", "Track Name": "Title %d" % i,
                             "Artist Name(s)": "Artist %d;Guest" % (i % 20), "Duration (ms)": int((200 + i % 30) * 1000) + 800,
                             "Added By": "SECRET-USER", "Danceability": Y[i][2], "Energy": Y[i][0], "Valence": Y[i][1],
                             "Acousticness": Y[i][3], "Tempo": tempo, "Loudness": loud})
            else:
                s.execute("insert into spotify_details values(?,?,?,?,?,?,?)", (sid, *map(float, Y[i][:4]), float(tempo), float(loud)))
    c.commit()
    c.close()
    s.commit()
    s.close()
    if csv_mode:
        import csv
        with open(csvp, "w", encoding="utf-8-sig", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
    return cat, det


def sha(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


class CalibrateTests(unittest.TestCase):
    def test_cross_validated_gain_all_songs_proposed_and_inputs_untouched(self):
        with tempfile.TemporaryDirectory() as d:
            cat, det = build(d)
            before = (sha(cat), sha(det))
            out = os.path.join(d, "out")
            self.assertEqual(C.main(["--catalog", cat, "--details", det, "--out", out]), 0)
            self.assertEqual(before, (sha(cat), sha(det)))                   # read-only
            import json
            rep = json.load(open(os.path.join(out, "calibration_report.json"), encoding="utf-8"))
            for f in ("energy", "valence", "danceability", "acousticness"):
                r = rep["features"][f]
                self.assertGreater(r["after_cv"]["r"], 0.9)
                self.assertGreater(r["same_songs_after_cv"]["r"], r["before_catalog_estimate"]["r"])
                self.assertLess(r["same_songs_after_cv"]["mae"], r["before_catalog_estimate"]["mae"])
            with open(os.path.join(out, "proposed_features.csv"), encoding="utf-8-sig") as f:
                rows = f.read().strip().splitlines()
            self.assertEqual(len(rows), 300 + 1)                              # every song with an embedding
            self.assertEqual(rep["features"]["tempo"]["labelled"], 150)
            self.assertIn("energy_proposed", rows[0])

    def test_exportify_csv_is_matched_without_a_server_import(self):
        import json
        with tempfile.TemporaryDirectory() as d:
            cat, _ = build(d, csv_mode=True)
            out = os.path.join(d, "out")
            self.assertEqual(C.main(["--catalog", cat, "--exportify", os.path.join(d, "My_playlist.csv"), "--out", out]), 0)
            rep = json.load(open(os.path.join(out, "calibration_report.json"), encoding="utf-8"))
            m = rep["csv_matches"][0]
            self.assertEqual((m["rows"], m["matched"]), (150, 150))
            self.assertGreater(m["by_isrc"], 100)
            self.assertGreater(m["by_title"], 15)                              # rows with no ISRC: title + artist + length
            for f in ("energy", "valence", "danceability", "acousticness", "loudness"):
                r = rep["features"][f]
                self.assertGreater(r["after_cv"]["r"], 0.9, f)
                self.assertGreater(r["same_songs_after_cv"]["r"], r["before_catalog_estimate"]["r"], f)
            cov = rep["coverage"]
            self.assertEqual(cov["labelled"], 150)
            self.assertEqual(sum(cov["energy_quartiles_low_to_high"]), 150)
            self.assertIn("embedding_space", cov)
            with open(os.path.join(out, "calibration_report.json"), encoding="utf-8") as f:
                self.assertNotIn("SECRET-USER", f.read())                       # Added By is never read

    def test_finalize_keeps_real_and_predicted_apart_and_explains_the_rest(self):
        import csv
        with tempfile.TemporaryDirectory() as d:
            cat, _ = build(d, csv_mode=True)
            res = os.path.join(d, "results_Navivibe sample 02.csv")
            with open(res, "w", encoding="utf-8-sig", newline="") as f:
                w = csv.writer(f)
                w.writerow(["title", "artist", "album", "isrc", "isFound"])
                w.writerow(["Title 200", "Artist 0", "", "", "0"])        # sent without ISRC, not found
                w.writerow(["Title 201", "Artist 1", "", "INS000000201", "1"])
            out = os.path.join(d, "out")
            self.assertEqual(F.main(["--catalog", cat, "--exportify", os.path.join(d, "My_playlist.csv"), "--results", res, "--out", out]), 0)
            rd = lambda n: list(csv.DictReader(open(os.path.join(out, n), encoding="utf-8-sig")))  # noqa: E731
            real, rest, pred = rd("real_spotify_features.csv"), rd("remaining_songs.csv"), rd("predicted_features_remaining.csv")
            self.assertEqual((len(real), len(rest), len(pred)), (150, 150, 150))
            self.assertFalse({r["song_id"] for r in real} & {r["song_id"] for r in pred})        # never mixed
            self.assertTrue(all(r["feature_source"] == "spotify" for r in real))
            self.assertTrue(all(r["feature_source"] == "predicted" for r in pred))
            self.assertTrue(all(0 <= float(r["energy_predicted"]) <= 1 for r in pred))
            why = {r["title"]: r["reason"] for r in rest}
            self.assertIn("did not find it on Spotify", why["Title 200"])
            self.assertIn("found it", why["Title 201"])
            self.assertIn("never sent", why["Title 250"])
            self.assertIn("84.8" if False else "real Spotify features: 150", open(os.path.join(out, "summary.txt"), encoding="utf-8").read())

    def test_too_few_labels_refuses(self):
        with tempfile.TemporaryDirectory() as d:
            cat, det = build(d, n=80, labelled=20)
            self.assertEqual(C.main(["--catalog", cat, "--details", det, "--out", os.path.join(d, "o")]), 2)

    def test_oof_predictions_never_use_the_song_itself(self):
        rng = np.random.default_rng(0)
        X = rng.normal(size=(60, 40))
        y = rng.random(60)                                                   # pure noise: nothing to learn
        oof = np.zeros(60)
        for te in C.folds(60, 5, 1):
            tr = np.setdiff1d(np.arange(60), te)
            oof[te] = C.fit_predict(X[tr], y[tr], X[te], 1.0)
        self.assertLess(abs(np.corrcoef(oof, y)[0, 1]), 0.4)                 # no leakage: noise stays noise


if __name__ == "__main__":
    unittest.main()
