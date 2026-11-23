"""hybrid-shadow-v1, the nightly fit.

    cd /opt/shuffle-server && venv/bin/python -m navivibe.hybrid_train [--out PATH] [--days 60]

Same recipe as the harness (tool/shuffle_eval/bakeoff/evaluate.py), with the server's own
artifacts so the features are the ones the live ranker serves with:
  * the world is v3's saved one (co-listen, name and audio vectors from models/v3), loaded the
    way V3Engine loads them; the co-listen vectors are refit from past events only as the replay
    walks forward (as v3's own training does)
  * every listener's history is replayed in time order; each qualifying play of the last
    `--days` days (default 60) becomes one group: 100 blend candidates, label 1 on the played song
  * a play whose song is not among the 100 candidates makes NO group (never forced in)
  * LightGBM settings and the 45 `NO_AUDIO_MOOD_COLS` come from navivibe/hybrid.py, the harness file

Excluded from the groups (still replayed into the state): rows tagged suspect_burst,
synthetic_time, impossible, clock_clamped (matched by user and timestamp); `import:*` sessions;
Apple / legacy history. Navidrome-sync rows never reach the replay. Logs from before the data
pipeline (no `quality` column) are used as they are.

Run after the v3 retrain (the scheduler does, 03:54 IST): the model records the v3 artifact
version it was fitted against and is not used if v3 is retrained afterwards.

Deterministic (seeded numpy, fixed LightGBM params); the model file is replaced atomically.
Exit 0 on success or "not enough data" (nothing replaced), 1 on a real failure. Prints JSON.
"""
import argparse
import json
import os
import sqlite3
import sys
import time

import numpy as np

from navivibe import hybrid as H
from navivibe import hybrid_store as store

BAD_QUALITY = ("suspect_burst", "synthetic_time", "impossible", "clock_clamped")
MIN_GROUPS = 200
MAX_GROUPS = int(float(os.getenv("HYBRID_MAX_GROUPS", "6000")))   # 6000 x 100 rows x 45 cols ~ 108 MB
SEED = 7


def tagged_timestamps(db_path):
    """Epoch seconds of this user's rows tagged bad. Read-only; no `quality` column -> empty."""
    if not os.path.exists(db_path):
        return set()
    conn = sqlite3.connect("file:%s?mode=ro" % db_path.replace("\\", "/"), uri=True, timeout=10)
    try:
        marks = ",".join("?" * len(BAD_QUALITY))
        rows = conn.execute("SELECT played_at FROM play_events WHERE quality IN (%s)" % marks, BAD_QUALITY).fetchall()
        return {int(r[0]) for r in rows if r[0] is not None}
    except sqlite3.OperationalError:
        return set()
    finally:
        conn.close()


def usable_as_target(event, bad_ts):
    if event.source != "live":
        return False                                   # Apple / legacy history
    if str(getattr(event, "session_raw", "") or "").startswith("import:"):
        return False
    if int(event.ts) in bad_ts.get(event.user, ()):
        return False
    return True


def collect_groups(events, replay, fm, bad_ts, since_ts, max_groups=None):
    """Walk `events` in order; groups for plays after `since_ts`. `replay` is a
    navivibe.recsys.train.Replay, `fm` a hybrid.FeatureMatrix. Returns (groups, counts)."""
    groups, counts = [], {"events": 0, "targets": 0, "groups": 0, "missed": 0, "excluded": 0}
    for e in events:
        counts["events"] += 1
        replay.maybe_refit(e.ts)
        s = replay.session_for(e)
        i = replay.cat.index[e.song]
        if e.ts >= since_ts and not e.skipped and i not in s.ctx.played:
            counts["targets"] += 1
            if not usable_as_target(e, bad_ts):
                counts["excluded"] += 1
            else:
                X = replay.features(e, s)
                hb, M = fm.build(X, replay.user(e.user), s.ctx.kept, e.ts, e.hour, e.month)
                allowed = np.ones(X.shape[0], bool)
                allowed[list(s.ctx.played)] = False
                g = H.training_group(M, hb, i, allowed)
                if g is None:
                    counts["missed"] += 1
                else:
                    groups.append(g)
                    counts["groups"] += 1
                    if max_groups and len(groups) > max_groups:
                        groups.pop(0)                  # keep the newest
        replay.apply(e, s)
    return groups, counts


def build_world(catalog, v3_dir=None):
    """(arrays, FeatureBuilder) from v3's saved artifacts, the way V3Engine builds them."""
    from navivibe.recsys.features import FeatureBuilder
    from navivibe.recsys.recommender import ARTIFACT_DIR, V3Engine
    from navivibe.recsys.state import CatalogArrays
    d = v3_dir or ARTIFACT_DIR
    helper = V3Engine.__new__(V3Engine)            # only its loaders; no state replay
    helper.cat = catalog
    arrays = CatalogArrays(catalog)
    fb = FeatureBuilder(arrays, helper._align_colisten(d), helper._audio_vectors(d), helper._name_vectors(d))
    return arrays, fb


def train(out_path=None, days=H.TRAIN_DAYS, now=None):
    from navivibe import feedback, hybrid_shadow
    from navivibe.catalog import store as catalog_store
    from navivibe.recsys.data import Catalog, load_all
    from navivibe.recsys.train import Replay

    out_path = out_path or hybrid_shadow.MODEL_PATH
    t0 = time.time()
    np.random.seed(SEED)
    now = now or time.time()
    v3_version = store.v3_trained_at()
    if v3_version is None:
        return {"status": "no_v3_artifacts"}
    catalog = Catalog.from_rows(catalog_store.load_catalog())
    events, _ = load_all(catalog)
    users = sorted({e.user for e in events})
    bad_ts = {u: tagged_timestamps(feedback.get_db_path(u)) for u in users}
    arrays, fb = build_world(catalog)
    fm = H.FeatureMatrix(catalog, arrays)
    replay = Replay(catalog, arrays, fb, history=events)
    groups, counts = collect_groups(events, replay, fm, bad_ts, now - days * 86400.0, MAX_GROUPS)
    result = {"events": len(events), **counts, "users": len(users), "window_days": days, "v3_trained_at": v3_version}
    if len(groups) < MIN_GROUPS:
        result.update(status="not_enough_data", needed=MIN_GROUPS, seconds=round(time.time() - t0, 1))
        return result
    t1 = time.time()
    rr = H.Reranker.fit(groups)
    metrics = {**counts, "groups_used": len(groups), "rounds": rr.model.num_trees(),
               "fit_seconds": round(time.time() - t1, 2), "stage1_recall": round(counts["groups"] / max(1, counts["groups"] + counts["missed"]), 4)}
    meta = store.save(out_path, rr, metrics, v3_version, extra={"users": len(users)})
    result.update(status="ok", model_version=meta["version"], metrics=metrics, path=out_path,
                  seconds=round(time.time() - t0, 1))
    return result


def main(argv=None):
    ap = argparse.ArgumentParser(description="Fit the hybrid re-ranker (shadow model)")
    ap.add_argument("--out", default=None)
    ap.add_argument("--days", type=int, default=H.TRAIN_DAYS)
    a = ap.parse_args(argv)
    try:
        r = train(a.out, a.days)
    except Exception as e:  # noqa: BLE001
        print(json.dumps({"status": "error", "error": "%s: %s" % (type(e).__name__, e)}))
        return 1
    print(json.dumps(r, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
