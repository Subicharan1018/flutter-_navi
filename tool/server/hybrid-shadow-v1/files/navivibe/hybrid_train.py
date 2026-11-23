"""hybrid-shadow-v1, the nightly fit.

    cd /opt/shuffle-server && venv/bin/python -m navivibe.hybrid_train [--out PATH] [--days 60]

Replays every listener's history in time order with the v3 machinery (so the features are the
ones v3 serves with, built from past events only), and turns each qualifying play of the last
`--days` days into one group: the blend's top 100 songs, label 1 for the song that was really
played. A play the blend did not have in its top 100 is skipped (counted as `missed`).

What is excluded from the groups (they still update the listener's state, like in v3):
  * rows tagged by the data pipeline: quality in (suspect_burst, synthetic_time, impossible,
    clock_clamped), matched to the replayed events by user and timestamp
  * navidrome_sync rows (the v3 loader already drops them)
  * imported history: `import:*` sessions and the Apple / legacy tables (their sessions are
    inferred; the research found they do not help the owner's own next-song ranking)
Rows from before the data pipeline (no `quality` column) are used as they are.

Deterministic: same data in, same model file out. Atomic: the model is one JSON file replaced
in a single rename; the previous one is kept beside it as `.prev`. Exit code 0 on success or
"not enough data" (nothing replaced), 1 on a real failure. Training metrics are printed as JSON.
"""
import argparse
import json
import os
import sqlite3
import sys
import time

import numpy as np

from navivibe import hybrid_core as core

BAD_QUALITY = ("suspect_burst", "synthetic_time", "impossible", "clock_clamped")
WINDOW_DAYS = int(float(os.getenv("HYBRID_TRAIN_DAYS", "60")))
MAX_GROUPS = int(float(os.getenv("HYBRID_MAX_GROUPS", "6000")))   # bounds memory: 6000 x 100 rows x 50 cols ~ 120 MB


def tagged_timestamps(db_path):
    """Epoch seconds of this user's rows that carry a bad `quality` tag. Read-only; an old
    database without the column gives an empty set (nothing is tagged yet)."""
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
    """True when this event may become a training group."""
    if event.source != "live":
        return False                                   # Apple / legacy history
    if str(getattr(event, "session_raw", "") or "").startswith("import:"):
        return False                                   # imported plays (inferred sessions)
    if int(event.ts) in bad_ts.get(event.user, ()):
        return False                                   # tagged bad rows
    return True


def collect_groups(events, replay, F, bad_ts, since_ts, weights=None, k=core.K_CANDIDATES):
    """Walk `events` in order; build the groups for plays after `since_ts`. Returns
    (groups, counts). `replay` is a navivibe.recsys.train.Replay."""
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
                allowed = np.ones(X.shape[0], bool)
                allowed[list(s.ctx.played)] = False
                g = core.make_group(X, F, i, allowed, weights, opener=not s.ctx.kept, k=k)
                if g is None:
                    counts["missed"] += 1
                else:
                    groups.append(g)
                    counts["groups"] += 1
        replay.apply(e, s)
    return groups, counts


def train(out_path=None, days=WINDOW_DAYS, now=None):
    from navivibe import feedback
    from navivibe.catalog import store
    from navivibe.recsys.data import Catalog, load_all
    from navivibe.recsys.features import F, FEATURES
    from navivibe.recsys.train import Replay, build_world

    from navivibe import hybrid_shadow
    out_path = out_path or hybrid_shadow.MODEL_PATH
    t0 = time.time()
    now = now or time.time()
    catalog = Catalog.from_rows(store.load_catalog())
    events, stats = load_all(catalog)
    users = sorted({e.user for e in events})
    bad_ts = {u: tagged_timestamps(feedback.get_db_path(u)) for u in users}
    arrays, co, au, pca, fb = build_world(events, catalog)
    replay = Replay(catalog, arrays, fb, history=events)
    groups, counts = collect_groups(events, replay, F, bad_ts, now - days * 86400.0)
    result = {"events": len(events), **counts, "users": len(users), "window_days": days,
              "tagged_rows_excluded_by_time": sum(len(v) for v in bad_ts.values())}
    fitted = core.fit(groups, FEATURES, max_groups=MAX_GROUPS)
    if fitted is None:
        result.update(status="not_enough_data", needed=core.MIN_GROUPS,
                      seconds=round(time.time() - t0, 1))
        return result
    booster, metrics = fitted
    meta = core.save_model(out_path, booster, {**metrics, **counts}, FEATURES,
                           extra={"window_days": days, "users": len(users)})
    result.update(status="ok", model_version=meta["version"], metrics=metrics, path=out_path,
                  seconds=round(time.time() - t0, 1))
    return result


def main(argv=None):
    ap = argparse.ArgumentParser(description="Fit the hybrid re-ranker (shadow model)")
    ap.add_argument("--out", default=None)
    ap.add_argument("--days", type=int, default=WINDOW_DAYS)
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
