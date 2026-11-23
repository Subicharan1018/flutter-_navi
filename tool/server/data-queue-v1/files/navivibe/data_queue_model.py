"""
navivibe/data_queue_model.py   (data-queue-v1)
──────────────────────────────────────────────
Predicts Spotify-style energy / valence / danceability / acousticness for songs Spotify does not have, from the
audio embedding (effnet_discogs), trained on the songs Spotify DID label.

The maths is the ridge regression of tool/shuffle_eval/calibrate_audio_features.py, copied function for function
(ridge_fit, folds, fit_predict, pick_alpha; a test in the repo checks they give identical numbers). numpy only.
Read-only: catalog.db and spotify_details.db are only read; the result is returned to the caller, which stores it
in data_queue.db with feature_source='predicted'.
"""
import os
import sqlite3

import numpy as np

FEATURES = ("energy", "valence", "danceability", "acousticness")
ALPHAS = (1.0, 10.0, 100.0, 1000.0, 10000.0)
MIN_LABELS = 50
MODEL = "effnet_discogs"


def ro(path):
    return sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=10)


# ── copied from tool/shuffle_eval/calibrate_audio_features.py ────────────────

def ridge_fit(X, y, alpha):
    return np.linalg.solve(X.T @ X + alpha * np.eye(X.shape[1]), X.T @ y)


def folds(n, k, seed):
    idx = np.random.default_rng(seed).permutation(n)
    return [idx[i::k] for i in range(k)]


def fit_predict(Xtr, ytr, Xte, alpha, lo=0.0, hi=1.0):
    mu, sd = Xtr.mean(0), Xtr.std(0)
    sd[sd < 1e-6] = 1.0
    ym = ytr.mean()
    w = ridge_fit((Xtr - mu) / sd, ytr - ym, alpha)
    return np.clip(((Xte - mu) / sd) @ w + ym, lo, hi)


def pick_alpha(X, y, seed, lo, hi, k=4):
    best, best_err = ALPHAS[0], 1e18
    for a in ALPHAS:
        err = 0.0
        for te in folds(len(y), k, seed + 1):
            tr = np.setdiff1d(np.arange(len(y)), te)
            err += float(np.sum((fit_predict(X[tr], y[tr], X[te], a, lo, hi) - y[te]) ** 2))
        if err < best_err:
            best, best_err = a, err
    return best


# ── data ─────────────────────────────────────────────────────────────────────

def load_embeddings(catalog_path: str, model: str = MODEL) -> dict:
    try:
        c = ro(catalog_path)
    except sqlite3.Error:
        return {}
    try:
        return {sid: np.frombuffer(b, dtype=np.float32) for sid, b in
                c.execute("SELECT song_id, vec FROM embeddings WHERE model=?", (model,))}
    except sqlite3.Error:
        return {}
    finally:
        c.close()


def load_truth(catalog_path: str, details_path: str) -> dict:
    """{song_id: {feature: Spotify's value}}: the catalog's rows marked feature_source='spotify', then
    spotify_details rows with energy and valence (these win)."""
    truth = {}
    try:
        c = ro(catalog_path)
        try:
            for r in c.execute("SELECT id, %s FROM songs WHERE feature_source='spotify' AND COALESCE(missing,0)=0"
                               % ", ".join(FEATURES)):
                t = {f: float(v) for f, v in zip(FEATURES, r[1:]) if v is not None}
                if "energy" in t and "valence" in t:
                    truth[r[0]] = t
        finally:
            c.close()
    except sqlite3.Error:
        pass
    if details_path and os.path.exists(details_path):
        try:
            c = ro(details_path)
            try:
                for r in c.execute("SELECT song_id, %s FROM spotify_details WHERE energy IS NOT NULL AND valence IS NOT NULL"
                                   % ", ".join(FEATURES)):
                    truth[r[0]] = {f: float(v) for f, v in zip(FEATURES, r[1:]) if v is not None}
            finally:
                c.close()
        except sqlite3.Error:
            pass
    return truth


def predict(song_ids, emb: dict, truth: dict, seed: int = 1) -> tuple:
    """({song_id: {feature: value, 'model': text}}, report). A song with no embedding gets nothing; a feature with
    fewer than MIN_LABELS labelled songs is not predicted at all."""
    want = [s for s in song_ids if s in emb]
    report = {"asked": len(list(song_ids)), "with_embedding": len(want), "features": {}}
    out = {s: {} for s in want}
    wanted = set(want)
    if not want:
        return out, report
    for f in FEATURES:
        ids = sorted(i for i in truth if i in emb and f in truth[i] and i not in wanted)
        if len(ids) < MIN_LABELS:
            report["features"][f] = {"skipped": "only %d labelled songs" % len(ids)}
            continue
        X = np.stack([emb[i] for i in ids]).astype(np.float64)
        y = np.array([truth[i][f] for i in ids])
        alpha = pick_alpha(X, y, seed, 0.0, 1.0)
        pred = fit_predict(X, y, np.stack([emb[s] for s in want]).astype(np.float64), alpha, 0.0, 1.0)
        for s, p in zip(want, pred):
            out[s][f] = round(float(p), 4)
        report["features"][f] = {"labelled": len(ids), "alpha": alpha}
    tag = "ridge-%s:n=%d" % (MODEL, len(truth))
    for s in out:
        if out[s]:
            out[s]["model"] = tag
    return {s: v for s, v in out.items() if v}, report
