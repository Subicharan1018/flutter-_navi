#!/usr/bin/env python3
"""Calibrate Spotify-style audio features from the audio embedding, using Spotify's true values as the labels.

READ-ONLY: it reads a COPY of the catalog (and optionally of spotify_details.db) and Exportify CSVs, writes only to --out and
never touches the server. It proposes predicted values for every song; the owner decides what to apply.

    scp subi@100.99.105.51:/opt/shuffle-server/catalog.db .
    python tool/shuffle_eval/calibrate_audio_features.py --catalog catalog.db --exportify My_playlist.csv --out calibration_out

Labels (Spotify's own numbers), any mix of:
  --exportify CSV     an Exportify export, matched to the catalog without any server import: ISRC first, then clean title +
                      same version words + an artist in common + length within 5 s (the exportify-v1 rules). Repeatable.
  --details FILE      a copy of spotify_details.db (what the app's importer stored)
  and the catalog's own rows with feature_source = 'spotify'.
Features: energy, valence, danceability, acousticness, tempo, loudness (a feature is fitted when at least 50 labelled songs have it).
Model: ridge regression on the standardised embedding (default effnet_discogs), strength chosen by an inner cross-validation.
Report: per feature, K-fold out-of-fold Pearson r / MAE / R2 (every labelled song is predicted by a model that never saw it)
next to the catalog's CURRENT estimate for the same songs (where that estimate is not itself Spotify's number); how many CSV rows
matched; and how well the labelled songs cover the library (energy / valence quartiles, composers, decades, languages and the
audio-embedding space) so you can tell whether another batch is needed and where.
Output: calibration_report.json, proposed_features.csv (every song), coverage.txt. numpy only.
"""
import argparse
import csv
import json
import os
import sqlite3
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "exportify"))
import embedding_gap  # noqa: E402
import spotify_match  # noqa: E402

# feature -> catalog column holding the current estimate
FEATURES = {"energy": "energy", "valence": "valence", "danceability": "danceability", "acousticness": "acousticness",
            "tempo": "bpm", "loudness": "loudness"}
ALPHAS = (1.0, 10.0, 100.0, 1000.0, 10000.0)
MIN_LABELS = 50


def ro(path):
    return sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=10)


def load_catalog(path, model):
    c = ro(path)
    try:
        cols = ", ".join(FEATURES.values())
        songs = {}
        for r in c.execute("SELECT id, title, artist, feature_source, isrc, duration, composer, language, year, "
                           "COALESCE(genre_display, genre_primary), %s FROM songs WHERE COALESCE(missing,0)=0" % cols):
            d = dict(zip(("id", "title", "artist", "source", "isrc", "duration", "composer", "language", "year", "genre"), r[:10]))
            d.update(dict(zip(FEATURES, r[10:])))
            songs[r[0]] = d
        emb = embedding_gap.load_embeddings(path, model)
        emb = {k: v for k, v in emb.items() if k in songs}
    finally:
        c.close()
    return songs, emb


def load_truth(songs, details_path=None, exportify_paths=()):
    """({song_id: {feature: spotify value}}, match stats). Later sources win: catalog Spotify rows < details < CSVs."""
    truth, stats = {}, {"csv": []}
    for sid, s in songs.items():
        if s["source"] == "spotify":
            t = {f: float(s[f]) for f in FEATURES if s[f] is not None}
            if t:
                truth[sid] = t
    if details_path and os.path.exists(details_path):
        c = ro(details_path)
        try:
            for sid, *vals in c.execute("SELECT song_id, %s FROM spotify_details WHERE energy IS NOT NULL" % ", ".join(FEATURES)):
                if sid in songs:
                    truth[sid] = {f: float(v) for f, v in zip(FEATURES, vals) if v is not None}
        finally:
            c.close()
    for p in exportify_paths:
        rows = spotify_match.parse_exportify(p)
        got = spotify_match.match_rows(rows, list(songs.values()))
        stats["csv"].append({"rows": len(rows), "matched": len(got),
                             "by_isrc": sum(1 for *_, h in got if h == "isrc"), "by_title": sum(1 for *_, h in got if h == "title"),
                             "unmatched_titles_sample": [r["title"] for r in rows if r["title"] not in {g[0]["title"] for g in got}][:5]})
        for r, s, _ in got:
            if "energy" in r["features"]:
                truth[s["id"]] = {f: r["features"][f] for f in FEATURES if f in r["features"]}
    return truth, stats


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


def metrics(pred, y):
    pred, y = np.asarray(pred, float), np.asarray(y, float)
    if len(y) < 3 or np.std(pred) < 1e-9 or np.std(y) < 1e-9:
        return {"n": int(len(y)), "r": None, "mae": float(np.mean(np.abs(pred - y))) if len(y) else None, "r2": None}
    ss = float(np.sum((y - y.mean()) ** 2))
    return {"n": int(len(y)), "r": round(float(np.corrcoef(pred, y)[0, 1]), 4), "mae": round(float(np.mean(np.abs(pred - y))), 4),
            "r2": round(1 - float(np.sum((y - pred) ** 2)) / ss, 4)}


def calibrate(songs, emb, truth, k=5, seed=1):
    all_ids = sorted(emb)
    Xall = np.stack([emb[i] for i in all_ids]).astype(np.float64)
    pos = {i: j for j, i in enumerate(all_ids)}
    report = {"songs": len(songs), "songs_with_embedding": len(emb), "features": {}}
    proposed = {i: {} for i in all_ids}
    for f, col in FEATURES.items():
        ids = sorted(i for i in truth if i in emb and f in truth[i])
        if len(ids) < MIN_LABELS:
            report["features"][f] = {"skipped": "only %d labelled songs with this feature" % len(ids)}
            continue
        X = Xall[[pos[i] for i in ids]]
        y = np.array([truth[i][f] for i in ids])
        lo, hi = (0.0, 1.0) if f not in ("tempo", "loudness") else (float(y.min()), float(y.max()))
        alpha = pick_alpha(X, y, seed, lo, hi)
        oof = np.zeros(len(ids))
        for te in folds(len(ids), k, seed):
            tr = np.setdiff1d(np.arange(len(ids)), te)
            oof[te] = fit_predict(X[tr], y[tr], X[te], alpha, lo, hi)
        indep = [j for j, i in enumerate(ids) if songs[i]["source"] != "spotify" and songs[i][f] is not None]
        entry = {"labelled": len(ids), "alpha": alpha, "after_cv": metrics(oof, y)}
        if indep:
            cur = [songs[ids[j]][f] for j in indep]
            entry["before_catalog_estimate"] = metrics(cur, y[indep])
            entry["same_songs_after_cv"] = metrics(oof[indep], y[indep])
            if f == "tempo":      # a tempo that is half or double is the same beat: also compare ignoring that
                fold = [min((c, c * 2, c / 2), key=lambda v: abs(v - t)) if c else c for c, t in zip(cur, y[indep])]
                entry["before_catalog_estimate_octave_free"] = metrics(fold, y[indep])
        report["features"][f] = entry
        pred = fit_predict(X, y, Xall, alpha, lo, hi)
        for i, p in zip(all_ids, pred):
            proposed[i][f] = round(float(p), 4)
    return report, proposed


# ── how well the labelled songs cover the library ────────────────────────────

def quartile_counts(values, edges):
    out = [0] * 4
    for v in values:
        out[sum(1 for e in edges if v >= e)] += 1
    return out


def coverage(songs, emb, labelled_ids, dims=40):
    lab = [i for i in labelled_ids if i in songs]
    lib = list(songs.values())
    cov = {"labelled": len(lab), "library": len(lib)}
    ev = [s for s in lib if s["energy"] is not None and s["valence"] is not None]
    e_edges = sorted(s["energy"] for s in ev)
    v_edges = sorted(s["valence"] for s in ev)
    e_edges = [e_edges[len(e_edges) * q // 4] for q in (1, 2, 3)]
    v_edges = [v_edges[len(v_edges) * q // 4] for q in (1, 2, 3)]
    L = [songs[i] for i in lab if songs[i]["energy"] is not None and songs[i]["valence"] is not None]
    cov["energy_quartiles_low_to_high"] = quartile_counts([s["energy"] for s in L], e_edges)
    cov["valence_quartiles_low_to_high"] = quartile_counts([s["valence"] for s in L], v_edges)
    grid = np.zeros((4, 4), int)
    libgrid = np.zeros((4, 4), int)
    for s in L:
        grid[sum(1 for e in e_edges if s["energy"] >= e), sum(1 for v in v_edges if s["valence"] >= v)] += 1
    for s in ev:
        libgrid[sum(1 for e in e_edges if s["energy"] >= e), sum(1 for v in v_edges if s["valence"] >= v)] += 1
    cov["cells_labelled_per_library_song_min_max"] = [round(float((grid / np.maximum(libgrid, 1)).min()), 3),
                                                      round(float((grid / np.maximum(libgrid, 1)).max()), 3)]
    cov["emptiest_cells_energy_valence"] = [{"energy_q": int(a) + 1, "valence_q": int(b) + 1, "labelled": int(grid[a, b]),
                                             "library": int(libgrid[a, b])}
                                            for a, b in sorted(np.ndindex(4, 4), key=lambda ab: grid[ab] / max(1, libgrid[ab]))[:3]]
    key = lambda s: (s.get("composer") or s["artist"] or "").split(";")[0].split(",")[0].strip().casefold()  # noqa: E731
    lab_comp = {key(songs[i]) for i in lab}
    cov["composers"] = {"labelled_distinct": len(lab_comp), "library_distinct": len({key(s) for s in lib}),
                        "library_songs_whose_composer_is_labelled": round(sum(1 for s in lib if key(s) in lab_comp) / len(lib), 3)}
    dec = lambda s: ("%ds" % (s["year"] // 10 * 10)) if s.get("year") else "?"  # noqa: E731
    cov["decades_labelled_vs_library_percent"] = {d: [round(100.0 * sum(1 for i in lab if dec(songs[i]) == d) / max(1, len(lab)), 1),
                                                       round(100.0 * sum(1 for s in lib if dec(s) == d) / len(lib), 1)]
                                                  for d in sorted({dec(s) for s in lib})}
    langs = sorted({s["language"] or "?" for s in lib}, key=lambda l: -sum(1 for s in lib if (s["language"] or "?") == l))[:6]
    cov["languages_labelled_vs_library_percent"] = {l: [round(100.0 * sum(1 for i in lab if (songs[i]["language"] or "?") == l) / max(1, len(lab)), 1),
                                                         round(100.0 * sum(1 for s in lib if (s["language"] or "?") == l) / len(lib), 1)]
                                                    for l in langs}
    have = [i for i in sorted(emb)]
    if len(lab) and len(have) > 10:
        P = embedding_gap.reduce(np.stack([emb[i] for i in have]).astype(np.float64), dims)
        pos = {i: j for j, i in enumerate(have)}
        li = [pos[i] for i in lab if i in pos]
        d = embedding_gap.dist_to_set(P, li)
        # a labelled song's distance to its nearest OTHER labelled song: what "well covered" looks like
        ref = []
        for j in li:
            others = [x for x in li if x != j]
            ref.append(float(np.sqrt(((P[others] - P[j]) ** 2).sum(1)).min()))
        thr = float(np.median(ref))
        unl = [j for j in range(len(have)) if j not in set(li)]
        du = d[unl]
        cov["embedding_space"] = {"typical_gap_between_labelled": round(thr, 3),
                                  "library_songs_closer_than_that_to_a_labelled_song_percent": round(100.0 * float((du <= thr).mean()), 1),
                                  "nearest_labelled_distance_percentiles_50_90_99": [round(float(np.percentile(du, q)), 3) for q in (50, 90, 99)]}
        groups = {}
        for j in unl:
            s = songs[have[j]]
            for g in (("genre", s.get("genre") or "?"), ("decade", dec(s)), ("language", s["language"] or "?")):
                groups.setdefault(g, []).append(float(d[j]))
        worst = sorted(((sum(v) / len(v), g, len(v)) for g, v in groups.items() if len(v) >= 25), reverse=True)[:6]
        cov["weakest_groups_by_mean_distance_to_labelled"] = [{"group": "%s=%s" % g, "songs": n, "mean_distance": round(m, 3)}
                                                              for m, g, n in worst]
    return cov


def coverage_text(c):
    es = c.get("embedding_space")
    lines = ["labelled songs: %d of %d in the library" % (c["labelled"], c["library"]),
             "energy quartiles (low..high, by the catalog's current estimate): %s" % c["energy_quartiles_low_to_high"],
             "valence quartiles (low..high): %s" % c["valence_quartiles_low_to_high"],
             "emptiest energy x valence cells: %s" % c["emptiest_cells_energy_valence"],
             "composers: %d labelled of %d in the library; %d%% of library songs have a labelled composer" % (
                 c["composers"]["labelled_distinct"], c["composers"]["library_distinct"],
                 round(100 * c["composers"]["library_songs_whose_composer_is_labelled"])),
             "decades (labelled %% / library %%): %s" % c["decades_labelled_vs_library_percent"],
             "languages (labelled %% / library %%): %s" % c["languages_labelled_vs_library_percent"]]
    if es:
        lines.append("embedding space: %s%% of the other library songs are as close to a labelled song as labelled songs are to each other; "
                     "nearest-distance percentiles 50/90/99 = %s (typical labelled gap %s)" % (
                         es["library_songs_closer_than_that_to_a_labelled_song_percent"],
                         es["nearest_labelled_distance_percentiles_50_90_99"], es["typical_gap_between_labelled"]))
        lines.append("weakest groups: " + "; ".join("%s (%d songs, mean distance %s)" % (g["group"], g["songs"], g["mean_distance"])
                                                    for g in c["weakest_groups_by_mean_distance_to_labelled"]))
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--catalog", required=True, help="a COPY of catalog.db")
    ap.add_argument("--details", help="a COPY of spotify_details.db")
    ap.add_argument("--exportify", action="append", default=[], metavar="CSV", help="an Exportify export; repeatable")
    ap.add_argument("--model", default="effnet_discogs")
    ap.add_argument("--out", default="calibration_out")
    ap.add_argument("--folds", type=int, default=5)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args(argv)
    songs, emb = load_catalog(a.catalog, a.model)
    truth, stats = load_truth(songs, a.details, a.exportify)
    n_lab = sum(1 for i in truth if i in emb)
    print("songs %d; with embedding %d; Spotify-labelled %d (with embedding %d)" % (len(songs), len(emb), len(truth), n_lab))
    for p, s in zip(a.exportify, stats["csv"]):
        print("%s: %d rows, %d matched the catalog (%d by ISRC, %d by title + artist + length)" % (
            os.path.basename(p), s["rows"], s["matched"], s["by_isrc"], s["by_title"]))
    if n_lab < MIN_LABELS:
        print("too few labelled songs with an embedding (need at least %d)" % MIN_LABELS, file=sys.stderr)
        return 2
    report, proposed = calibrate(songs, emb, truth, a.folds, a.seed)
    report["csv_matches"] = stats["csv"]
    report["coverage"] = coverage(songs, emb, [i for i in truth if i in emb])
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "calibration_report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    with open(os.path.join(a.out, "coverage.txt"), "w", encoding="utf-8") as f:
        f.write(coverage_text(report["coverage"]) + "\n")
    fitted = [f for f in FEATURES if "after_cv" in report["features"][f]]
    with open(os.path.join(a.out, "proposed_features.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["song_id", "title", "artist", "spotify_labelled"] + [x for ft in fitted for x in
                   ("%s_current" % ft, "%s_proposed" % ft, "%s_spotify" % ft)])
        for sid in sorted(emb):
            s = songs[sid]
            row = [sid, s["title"], s["artist"], int(sid in truth)]
            for ft in fitted:
                row += [s[ft], proposed[sid][ft], truth.get(sid, {}).get(ft, "")]
            w.writerow(row)
    for ft in fitted:
        r = report["features"][ft]
        b, s_ = r.get("before_catalog_estimate"), r.get("same_songs_after_cv")
        aft = s_ or r["after_cv"]
        print("%-12s labelled %d | on the %d songs whose current value is not Spotify's: catalog now r=%s MAE=%s -> embedding model "
              "(cross-validated) r=%s MAE=%s | all %d labelled: r=%s" % (
                  ft, r["labelled"], (b or {}).get("n", 0), b and b["r"], b and b["mae"], aft["r"], aft["mae"], r["labelled"], r["after_cv"]["r"]))
        if "before_catalog_estimate_octave_free" in r:
            o = r["before_catalog_estimate_octave_free"]
            print("             (tempo, catalog value folded to the nearest of x1 / x2 / x0.5: r=%s MAE=%s: the catalog's bpm is right "
                  "up to half / double time, keep it)" % (o["r"], o["mae"]))
    print()
    print(coverage_text(report["coverage"]))
    print("wrote %s (nothing was applied to the server)" % os.path.abspath(a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
