#!/usr/bin/env python3
"""After ALL the Exportify batches: what is really known, what is still missing and why, and predictions for ONLY the rest.

READ-ONLY (a COPY of catalog.db, Exportify CSVs, optional transfer-service result files); writes only to --out and
never touches the server. Real Spotify values and predicted values are never mixed: `real_spotify_features.csv` holds
Spotify's numbers, `predicted_features_remaining.csv` holds model values for the songs with none, each row marked
feature_source = predicted.

    python tool/shuffle_eval/finalize_spotify_features.py --catalog catalog.db \\
        --exportify Navivibe_sample_01.csv --exportify Navivibe_sample_02.csv ... \\
        --results "results_Navivibe sample 07.csv" ... --out final_out

Writes: summary.txt / summary.json (matched per file, real coverage, learning curve, remaining coverage gaps),
real_spotify_features.csv, remaining_songs.csv (every library song without real features + a short reason),
predicted_features_remaining.csv. Needs numpy; imports calibrate_audio_features.py next to it.
"""
import argparse
import csv
import json
import os
import re
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "exportify"))
import calibrate_audio_features as C  # noqa: E402
import library_sample  # noqa: E402
import spotify_match as M  # noqa: E402

MODEL_FEATURES = ("energy", "valence", "danceability", "acousticness", "loudness")      # tempo: keep the catalog's bpm


def read_results(paths):
    """[(file name, [{title, artist, isrc, found}])] from the transfer service's result files (isFound 1 / 0)."""
    out = []
    for p in paths:
        with open(p, encoding="utf-8-sig", newline="") as f:
            rows = [{"title": (r.get("title") or "").strip(), "artist": (r.get("artist") or "").replace("·", ",").replace("·", ","),
                     "isrc": M.norm_isrc(r.get("isrc")), "found": (r.get("isFound") or "").strip() == "1", "duration_s": None,
                     "features": {}} for r in csv.DictReader(f)]
        out.append((os.path.basename(p), rows))
    return out


def per_file(songs, paths):
    stats = []
    for p in paths:
        rows = M.parse_exportify(p)
        got = M.match_rows(rows, list(songs.values()))
        stats.append({"file": os.path.basename(p), "rows": len(rows), "with_energy": sum(1 for r in rows if "energy" in r["features"]),
                      "matched": len(got), "by_isrc": sum(1 for *_, h in got if h == "isrc"),
                      "by_title": sum(1 for *_, h in got if h == "title"),
                      "unmatched": len(rows) - len(got) if rows else 0})
    return stats


def learning_curve(emb, truth, old_ids, songs, k=5, seed=1):
    """Same folds, same held-out songs: train on the earlier labels only vs on all labels. Pearson r per feature."""
    ids = sorted(i for i in truth if i in emb)
    X = np.stack([emb[i] for i in ids]).astype(np.float64)
    out = {}
    for f in MODEL_FEATURES:
        have = [j for j, i in enumerate(ids) if f in truth[i]]
        y = np.array([truth[ids[j]][f] for j in have])
        Xf = X[have]
        old = np.array([ids[j] in old_ids for j in have])
        alpha = C.pick_alpha(Xf, y, seed, 0.0 if f != "loudness" else float(y.min()), 1.0 if f != "loudness" else float(y.max()))
        lo, hi = (0.0, 1.0) if f != "loudness" else (float(y.min()), float(y.max()))
        p_all, p_old = np.zeros(len(y)), np.zeros(len(y))
        for te in C.folds(len(y), k, seed):
            tr = np.setdiff1d(np.arange(len(y)), te)
            p_all[te] = C.fit_predict(Xf[tr], y[tr], Xf[te], alpha, lo, hi)
            tro = tr[old[tr]]
            p_old[te] = C.fit_predict(Xf[tro], y[tro], Xf[te], alpha, lo, hi)
        cur = [songs[ids[j]][f] for j in have]
        indep = [n for n, j in enumerate(have) if songs[ids[j]]["source"] != "spotify" and cur[n] is not None]
        out[f] = {"labelled": len(y), "earlier_labels_only": C.metrics(p_old, y), "all_labels": C.metrics(p_all, y),
                  "catalog_now_on_songs_where_it_is_an_estimate": C.metrics([cur[n] for n in indep], y[indep]) if indep else None,
                  "all_labels_same_songs": C.metrics(p_all[indep], y[indep]) if indep else None}
    return out


def reasons(songs, truth, csv_rows, results, export_rows=None):
    """{song_id: short reason} for every library song without real Spotify features. `export_rows` = {batch number: rows in the
    Exportify file for that batch}, to tell "found but the export is empty" from "found but the row would not match"."""
    import re
    never = {}
    idx = M.Index(list(songs.values()))
    status = {}                                    # song_id -> reason from the transfer results
    for name, rows in results:
        num = re.search(r"(\d+)", name)
        n_export = (export_rows or {}).get(int(num.group(1))) if num else None
        for r in rows:
            s, how = idx.find(r)
            if s and s["id"] not in truth:
                if not r["found"]:
                    status[s["id"]] = ("the transfer service did not find it on Spotify (searched by title and artist%s)"
                                       % ("" if r["isrc"] else ", it has no ISRC"))
                elif n_export == 0:
                    status[s["id"]] = "the transfer service found it, but the Exportify file for this batch is empty (%s): export that playlist again" % name
                else:
                    status[s["id"]] = ("the transfer service found it; the Spotify row has another title or version, so it did not match "
                                       "(check by hand) (%s)" % name)
    for sid, s in songs.items():
        if sid in truth:
            continue
        if sid in status:
            never[sid] = status[sid]
        elif not s.get("isrc"):
            never[sid] = "no ISRC in the library and never sent to Spotify"
        elif library_sample.BAD_TITLE.search(s["title"] or ""):
            never[sid] = "remix / live / sped-up / version title: left out of the batches on purpose (Spotify's values would be for another recording)"
        elif not (library_sample.MIN_S <= (s.get("duration") or 0) <= library_sample.MAX_S):
            never[sid] = "length under 1 or over 10 minutes: left out of the batches"
        else:
            never[sid] = "never sent to Spotify (not picked for any batch), or sent and not returned by Exportify"
    return never


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--catalog", required=True)
    ap.add_argument("--exportify", action="append", default=[], metavar="CSV")
    ap.add_argument("--results", action="append", default=[], metavar="CSV", help="transfer-service result files (title, artist, isrc, isFound)")
    ap.add_argument("--earlier", action="append", default=[], metavar="CSV",
                    help="the Exportify files that existed before this larger set (for the learning curve); default: the first --exportify file")
    ap.add_argument("--model", default="effnet_discogs")
    ap.add_argument("--out", default="final_out")
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args(argv)
    songs, emb = C.load_catalog(a.catalog, a.model)
    catalog_spotify = {i for i, s in songs.items() if s["source"] == "spotify"}
    truth, _ = C.load_truth(songs, None, a.exportify)
    stats = per_file(songs, a.exportify)
    lines = ["library songs: %d (with embedding %d)" % (len(songs), len(emb)),
             "real Spotify features: %d distinct library songs = %.1f%% of the library (%d already in the catalog from Spotify, %d new from the files)" % (
                 len(truth), 100.0 * len(truth) / len(songs), len(catalog_spotify), len(set(truth) - catalog_spotify)),
             "", "per file (rows / with energy / matched to the library / by ISRC / by title+artist+length / unmatched):"]
    for s in stats:
        lines.append("  %-26s %4d / %4d / %4d / %4d / %3d / %3d" % (s["file"], s["rows"], s["with_energy"], s["matched"], s["by_isrc"], s["by_title"], s["unmatched"]))
    earlier_paths = a.earlier or a.exportify[:1]
    earlier_truth, _ = C.load_truth(songs, None, earlier_paths)
    curve = learning_curve(emb, truth, set(earlier_truth), songs, 5, a.seed)
    lines += ["", "cross-validated Pearson r (same folds): earlier labels only (%d songs) -> all labels (%d songs); catalog's current estimate, where it is an estimate:" % (
        len(earlier_truth), len(truth))]
    for f, c in curve.items():
        b = c["catalog_now_on_songs_where_it_is_an_estimate"]
        lines.append("  %-13s %s -> %s   (catalog now %s on %d songs; model on those songs %s)" % (
            f, c["earlier_labels_only"]["r"], c["all_labels"]["r"], b and b["r"], (b or {}).get("n", 0), c["all_labels_same_songs"] and c["all_labels_same_songs"]["r"]))
    lines.append("  tempo: keep the catalog's bpm (the embedding cannot learn it; bpm agrees with Spotify's tempo up to half/double time)")
    cov = C.coverage(songs, emb, [i for i in truth if i in emb])
    lines += ["", "what the real labels cover now:", C.coverage_text(cov)]
    results = read_results(a.results)
    rows_all = [r for p in a.exportify for r in M.parse_exportify(p)]
    export_rows = {int(re.search(r'(\d+)', s['file']).group(1)): s['rows'] for s in stats if re.search(r'(\d+)', s['file'])}
    why = reasons(songs, truth, rows_all, results, export_rows)
    summary = {"files": stats, "real": len(truth), "library": len(songs), "learning_curve": curve, "coverage": cov,
               "remaining": len(why)}
    counts = {}
    for r in why.values():
        counts[r] = counts.get(r, 0) + 1
    lines += ["", "library songs still WITHOUT real Spotify features: %d" % len(why)]
    for r, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        lines.append("  %4d  %s" % (n, r))
    if results:
        lines += ["", "transfer-service result files (rows / found / not found / with ISRC):"]
        for name, rows in results:
            lines.append("  %-30s %4d / %4d / %4d / %4d" % (name, len(rows), sum(r["found"] for r in rows), sum(not r["found"] for r in rows),
                                                          sum(1 for r in rows if r["isrc"])))
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "summary.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    with open(os.path.join(a.out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)
    feats = ("energy", "valence", "danceability", "acousticness", "loudness", "tempo")
    with open(os.path.join(a.out, "real_spotify_features.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["song_id", "title", "artist", "isrc", "feature_source"] + list(feats))
        for sid in sorted(truth):
            s = songs[sid]
            w.writerow([sid, s["title"], s["artist"], s["isrc"] or "", "spotify"] + [truth[sid].get(x, "") for x in feats])
    with open(os.path.join(a.out, "remaining_songs.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["song_id", "title", "artist", "isrc", "reason"])
        for sid in sorted(why):
            s = songs[sid]
            w.writerow([sid, s["title"], s["artist"], s["isrc"] or "", why[sid]])
    # predictions for the songs WITHOUT real values only, model fitted on the real ones
    ids = sorted(i for i in truth if i in emb)
    rest = sorted(i for i in why if i in emb)
    Xl = np.stack([emb[i] for i in ids]).astype(np.float64)
    Xr = np.stack([emb[i] for i in rest]).astype(np.float64) if rest else np.zeros((0, Xl.shape[1]))
    preds = {}
    for ft in MODEL_FEATURES:
        have = [j for j, i in enumerate(ids) if ft in truth[i]]
        y = np.array([truth[ids[j]][ft] for j in have])
        lo, hi = (0.0, 1.0) if ft != "loudness" else (float(y.min()), float(y.max()))
        alpha = C.pick_alpha(Xl[have], y, a.seed, lo, hi)
        preds[ft] = C.fit_predict(Xl[have], y, Xr, alpha, lo, hi) if len(rest) else []
    with open(os.path.join(a.out, "predicted_features_remaining.csv"), "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["song_id", "title", "artist", "isrc", "feature_source"] + ["%s_predicted" % x for x in MODEL_FEATURES] + ["bpm_catalog", "reason_no_real_values"])
        for n, sid in enumerate(rest):
            s = songs[sid]
            w.writerow([sid, s["title"], s["artist"], s["isrc"] or "", "predicted"] + [round(float(preds[x][n]), 4) for x in MODEL_FEATURES] +
                       [s.get("tempo") or "", why[sid]])
    print("\n".join(lines))
    print("\nwrote %s (nothing was applied to the server; real and predicted values are in separate files)" % os.path.abspath(a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
