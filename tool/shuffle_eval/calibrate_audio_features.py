#!/usr/bin/env python3
"""Calibrate energy / valence / danceability from the audio embedding, using Spotify's true values as the labels.

READ-ONLY on COPIES of the server data; writes only to --out. It never touches the server and never applies
anything: it proposes predicted values for every song and the owner decides.

Inputs (copy them first):
    scp subi@100.99.105.51:/opt/shuffle-server/catalog.db .
    scp subi@100.99.105.51:/opt/shuffle-server/spotify_details.db .          (after the Exportify CSV import)

    python tool/shuffle_eval/calibrate_audio_features.py --catalog catalog.db --details spotify_details.db --out calibration_out

Labels (Spotify's own numbers): rows of spotify_details.db that carry features (the Exportify import), plus songs the catalog
already marks feature_source = 'spotify'. Model: ridge regression on the standardised embedding (default
effnet_discogs, 1280 numbers, float32 blobs in catalog.db `embeddings`), the strength chosen by an inner cross-validation.
Report: for each feature, 5-fold cross-validated (out-of-fold, so every labelled song is predicted by a model that never saw
it) Pearson r / MAE / R2, next to the catalog's CURRENT estimate on the songs where that estimate is independent of Spotify
(feature_source = essentia_calibrated). Output: calibration_report.json and proposed_features.csv (all songs).
numpy only.
"""
import argparse
import csv
import json
import os
import sqlite3
import sys

import numpy as np

FEATURES = ("energy", "valence", "danceability")
ALPHAS = (1.0, 10.0, 100.0, 1000.0, 10000.0)


def ro(path):
    return sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=10)


def load_catalog(path, model):
    c = ro(path)
    try:
        songs = {r[0]: {"id": r[0], "title": r[1], "artist": r[2], "source": r[3],
                        **dict(zip(FEATURES, r[4:7]))}
                 for r in c.execute("SELECT id, title, artist, feature_source, energy, valence, danceability "
                                    "FROM songs WHERE COALESCE(missing,0)=0")}
        emb = {sid: np.frombuffer(b, dtype=np.float32) for sid, b in
               c.execute("SELECT song_id, vec FROM embeddings WHERE model=?", (model,)) if sid in songs}
    finally:
        c.close()
    return songs, emb


def load_truth(songs, details_path):
    """{song_id: {feature: spotify value}}: the Exportify rows first, then catalog rows that are Spotify's own."""
    truth = {}
    for sid, s in songs.items():
        if s["source"] == "spotify" and all(s[f] is not None for f in FEATURES):
            truth[sid] = {f: float(s[f]) for f in FEATURES}
    if details_path and os.path.exists(details_path):
        c = ro(details_path)
        try:
            for sid, e, v, d in c.execute("SELECT song_id, energy, valence, danceability FROM spotify_details "
                                          "WHERE energy IS NOT NULL AND valence IS NOT NULL"):
                if sid in songs:
                    truth[sid] = {"energy": float(e), "valence": float(v),
                                  "danceability": float(d) if d is not None else songs[sid]["danceability"]}
        finally:
            c.close()
    return {k: v for k, v in truth.items() if all(x is not None for x in v.values())}


def ridge_fit(X, y, alpha):
    d = X.shape[1]
    return np.linalg.solve(X.T @ X + alpha * np.eye(d), X.T @ y)


def folds(n, k, seed):
    idx = np.random.default_rng(seed).permutation(n)
    return [idx[i::k] for i in range(k)]


def standardise(train):
    mu, sd = train.mean(0), train.std(0)
    sd[sd < 1e-6] = 1.0
    return mu, sd


def fit_predict(Xtr, ytr, Xte, alpha):
    mu, sd = standardise(Xtr)
    ym = ytr.mean()
    w = ridge_fit((Xtr - mu) / sd, ytr - ym, alpha)
    return np.clip(((Xte - mu) / sd) @ w + ym, 0.0, 1.0)


def pick_alpha(X, y, seed, k=4):
    best, best_err = ALPHAS[0], 1e18
    for a in ALPHAS:
        err = 0.0
        for te in folds(len(y), k, seed + 1):
            tr = np.setdiff1d(np.arange(len(y)), te)
            err += float(np.sum((fit_predict(X[tr], y[tr], X[te], a) - y[te]) ** 2))
        if err < best_err:
            best, best_err = a, err
    return best


def metrics(pred, y):
    pred, y = np.asarray(pred, float), np.asarray(y, float)
    if len(y) < 3 or np.std(pred) < 1e-9 or np.std(y) < 1e-9:
        return {"n": int(len(y)), "r": None, "mae": float(np.mean(np.abs(pred - y))) if len(y) else None, "r2": None}
    r = float(np.corrcoef(pred, y)[0, 1])
    ss = float(np.sum((y - y.mean()) ** 2))
    return {"n": int(len(y)), "r": round(r, 4), "mae": round(float(np.mean(np.abs(pred - y))), 4),
            "r2": round(1 - float(np.sum((y - pred) ** 2)) / ss, 4)}


def calibrate(songs, emb, truth, k=5, seed=1):
    ids = sorted(i for i in truth if i in emb)
    X = np.stack([emb[i] for i in ids]).astype(np.float64)
    report = {"labelled_with_embedding": len(ids), "songs": len(songs), "songs_with_embedding": len(emb), "features": {}}
    all_ids = sorted(emb)
    Xall = np.stack([emb[i] for i in all_ids]).astype(np.float64)
    proposed = {i: {} for i in songs}
    for f in FEATURES:
        y = np.array([truth[i][f] for i in ids])
        alpha = pick_alpha(X, y, seed)
        oof = np.zeros(len(ids))
        for te in folds(len(ids), k, seed):
            tr = np.setdiff1d(np.arange(len(ids)), te)
            oof[te] = fit_predict(X[tr], y[tr], X[te], alpha)
        # the catalog's current estimate, only where it is NOT itself Spotify's number
        indep = [j for j, i in enumerate(ids) if songs[i]["source"] != "spotify" and songs[i][f] is not None]
        before = metrics([songs[ids[j]][f] for j in indep], y[indep]) if indep else None
        report["features"][f] = {"alpha": alpha, "after_cv": metrics(oof, y), "before_catalog_estimate": before,
                                 "same_songs_after_cv": metrics(oof[indep], y[indep]) if indep else None}
        pred = fit_predict(X, y, Xall, alpha)
        for i, p in zip(all_ids, pred):
            proposed[i][f] = round(float(p), 4)
    return report, proposed


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--catalog", required=True, help="a COPY of catalog.db")
    ap.add_argument("--details", help="a COPY of spotify_details.db (the Exportify import)")
    ap.add_argument("--model", default="effnet_discogs")
    ap.add_argument("--out", default="calibration_out")
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args(argv)
    songs, emb = load_catalog(a.catalog, a.model)
    truth = load_truth(songs, a.details)
    print("songs %d; with embedding %d; Spotify-labelled %d (with embedding %d)" % (
        len(songs), len(emb), len(truth), sum(1 for i in truth if i in emb)))
    if sum(1 for i in truth if i in emb) < 50:
        print("too few labelled songs with an embedding (need at least 50): import the Exportify CSV first", file=sys.stderr)
        return 2
    report, proposed = calibrate(songs, emb, truth, a.folds, a.seed)
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "calibration_report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    with open(os.path.join(a.out, "proposed_features.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["song_id", "title", "artist", "spotify_labelled"] + [x for ft in FEATURES for x in
                   ("%s_current" % ft, "%s_proposed" % ft, "%s_spotify" % ft)])
        for sid, s in songs.items():
            if sid not in emb:
                continue
            row = [sid, s["title"], s["artist"], int(sid in truth)]
            for ft in FEATURES:
                row += [s[ft], proposed[sid][ft], truth[sid][ft] if sid in truth else ""]
            w.writerow(row)
    for ft, r in report["features"].items():
        b, af = r["before_catalog_estimate"], r["after_cv"]
        s_ = r["same_songs_after_cv"]
        print("%-12s after (cross-validated) r=%s MAE=%s | catalog now r=%s MAE=%s -> same songs after r=%s" % (
            ft, af["r"], af["mae"], b and b["r"], b and b["mae"], s_ and s_["r"]))
    print("wrote %s (nothing was applied to the server)" % os.path.abspath(a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
