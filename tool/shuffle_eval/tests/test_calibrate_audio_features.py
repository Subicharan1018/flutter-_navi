import hashlib
import os
import sqlite3
import sys
import tempfile
import unittest

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import calibrate_audio_features as C  # noqa: E402


def build(d, n=300, labelled=150, noise=0.05, seed=2):
    rng = np.random.default_rng(seed)
    dim = 32
    W = rng.normal(size=(dim, 3))
    E = rng.normal(size=(n, dim)).astype(np.float32)
    raw = E @ W
    Y = 1 / (1 + np.exp(-(raw / raw.std(0) + rng.normal(scale=noise, size=raw.shape))))
    cat, det = os.path.join(d, "catalog.db"), os.path.join(d, "spotify_details.db")
    c = sqlite3.connect(cat)
    c.execute("create table songs(id,title,artist,feature_source,energy,valence,danceability,missing)")
    c.execute("create table embeddings(song_id,model,dim,vec)")
    s = sqlite3.connect(det)
    s.execute("create table spotify_details(song_id,energy,valence,danceability)")
    for i in range(n):
        sid = "s%d" % i
        cur = np.clip(Y[i] + rng.normal(scale=0.25, size=3), 0, 1)           # a weaker current estimate
        c.execute("insert into songs values(?,?,?,?,?,?,?,0)", (sid, "T%d" % i, "A", "essentia_calibrated", *map(float, cur)))
        c.execute("insert into embeddings values(?,?,?,?)", (sid, "effnet_discogs", dim, E[i].tobytes()))
        if i < labelled:
            s.execute("insert into spotify_details values(?,?,?,?)", (sid, *map(float, Y[i])))
    c.commit()
    c.close()
    s.commit()
    s.close()
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
            for f in C.FEATURES:
                r = rep["features"][f]
                self.assertGreater(r["after_cv"]["r"], 0.9)
                self.assertGreater(r["same_songs_after_cv"]["r"], r["before_catalog_estimate"]["r"])
                self.assertLess(r["same_songs_after_cv"]["mae"], r["before_catalog_estimate"]["mae"])
            with open(os.path.join(out, "proposed_features.csv"), encoding="utf-8-sig") as f:
                rows = f.read().strip().splitlines()
            self.assertEqual(len(rows), 300 + 1)                              # every song with an embedding
            self.assertIn("energy_proposed", rows[0])

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
