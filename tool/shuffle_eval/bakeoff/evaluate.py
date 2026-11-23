"""Time-ordered held-out evaluation of v3, blend and hybrid on a COPIED snapshot.

  python evaluate.py --snapshot DIR --end-days-ago 0 --out runs/w0.jsonl

DIR holds navivibe/ (server code), catalog.db, logs/ (*_listening_log.db) and optionally
mood_tags.json + mood_admin.json. Output: one JSON line per kept play, listeners
anonymised. It holds listening history: keep it out of the repo.
"""
import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta

ap = argparse.ArgumentParser()
ap.add_argument("--snapshot", required=True)
ap.add_argument("--end-days-ago", type=int, default=0)
ap.add_argument("--holdout-days", type=int, default=30)
ap.add_argument("--audio-mood", action="store_true", help="also train the all-feature variant")
ap.add_argument("--out", required=True)
a = ap.parse_args()
S = os.path.abspath(a.snapshot)
os.environ["NAVIVIBE_LOG_DIR"] = os.path.join(S, "logs")
os.environ["NAVIVIBE_CATALOG_DB"] = os.path.join(S, "catalog.db")
os.environ["NAVIVIBE_V3_DIR"] = os.path.join(S, "unused_v3")
sys.path.insert(0, S)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np                                          # noqa: E402
from navivibe.catalog import store                          # noqa: E402
from navivibe.recsys import train as T                      # noqa: E402
from navivibe.recsys.data import IST, Catalog, load_all     # noqa: E402
import hybrid as H                                          # noqa: E402

T.LGB_PARAMS.update(deterministic=True, force_row_wise=True, num_threads=2)
t0 = time.time()
np.random.seed(0)
catalog = Catalog.from_rows(store.load_catalog())
events, _ = load_all(catalog, None)
if a.end_days_ago:
    end = max(e.ts for e in events) - a.end_days_ago * 86400
    events = [e for e in events if e.ts < end]
last = datetime.fromtimestamp(max(e.ts for e in events), IST).replace(hour=0, minute=0, second=0)
cutoff = (last - timedelta(days=a.holdout_days - 1)).timestamp()
arrays, co, au, pca, fb = T.build_world(events, catalog, cutoff)
N = len(catalog)

# v3, trained as the server's own backtest does
online = T.Replay(catalog, arrays, fb, history=events)
ts, consumed = T.collect_training(online, events, stop_ts=cutoff)
v3 = T.fit_ranker(ts)
del ts
online.history = None
print(f"v3 trained {time.time()-t0:.0f}s", flush=True)


def moods():
    p = os.path.join(S, "mood_tags.json")
    if not os.path.exists(p):
        return None
    m = {k: v[0] for k, v in json.load(open(p, encoding="utf-8")).items() if v}
    q = os.path.join(S, "mood_admin.json")
    if os.path.exists(q):
        admin = json.load(open(q, encoding="utf-8"))
        m.update({k: v["moods"][0] for k, v in admin.items() if v.get("moods")})
    return m


fm = H.FeatureMatrix(catalog, arrays, moods())


def request(rep, e, s):
    X = rep.features(e, s)
    hb, M = fm.build(X, rep.user(e.user), s.ctx.kept, e.ts, e.hour, e.month)
    allowed = np.ones(N, bool)
    allowed[list(s.ctx.played)] = False
    return X, hb, M, allowed


# Hybrid: second pass over the same history, groups from the last TRAIN_DAYS before the
# cutoff, all listeners pooled. Co-listen vectors are refit from past events only.
rep, groups, seen = T.Replay(catalog, arrays, fb, history=events), [], 0
for e in events[:consumed]:
    s, i = rep.session_for(e), catalog.index[e.song]
    if e.ts >= cutoff - H.TRAIN_DAYS * 86400 and not e.skipped and i not in s.ctx.played:
        rep.maybe_refit(e.ts)
        _, hb, M, allowed = request(rep, e, s)
        seen += 1
        g = H.training_group(M, hb, i, allowed)
        if g:
            groups.append(g)
    rep.apply(e, s)
del rep
fb.co = co                       # test time: vectors fit on all pre-cutoff events
t1 = time.time()
models = {"hybrid_no_audio_mood": H.Reranker.fit(groups)}
print(f"fit {time.time()-t1:.1f}s rounds={models['hybrid_no_audio_mood'].model.num_trees()}")
if a.audio_mood:
    models["hybrid_all"] = H.Reranker.fit(groups, H.ALL_COLS)
print(f"re-ranker: {len(groups)} groups of {seen} plays, {time.time()-t0:.0f}s", flush=True)
del groups

names = sorted({e.user for e in events}, key=lambda u: (u != "admin", u))
users = {u: "u%02d" % k for k, u in enumerate(names)}
lat, lat_x, n = [], [], 0
with open(a.out, "w") as out:
    for e in events[consumed:]:
        s, i = online.session_for(e), catalog.index[e.song]
        if not e.skipped and i not in s.ctx.played:
            q0 = time.perf_counter()
            X = online.features(e, s)
            q1 = time.perf_counter()
            _, hb, M, allowed = request(online, e, s)
            q2 = time.perf_counter()
            hb, M = fm.build(X, online.user(e.user), s.ctx.kept, e.ts, e.hour, e.month)
            sc = models["hybrid_no_audio_mood"].scores(M, hb, allowed)
            lat.append(time.perf_counter() - q2)      # blend + extras + re-rank; X already built
            lat_x.append(q1 - q0)                     # the feature build v3 already pays for

            def rank(v):
                v = np.where(allowed, v, -np.inf)
                return 1 + float((v > v[i]).sum()) + 0.5 * float((v == v[i]).sum() - 1)   # ties: half

            R = {"v3": rank(v3.predict(X, not s.ctx.kept)), "blend": rank(hb), "hybrid_no_audio_mood": rank(sc)}
            if "hybrid_all" in models:
                R["hybrid_all"] = rank(models["hybrid_all"].scores(M, hb, allowed))
            R["router"] = R["hybrid_no_audio_mood"] if s.ctx.kept else R["v3"]
            out.write(json.dumps(dict(u=users[e.user], task="next" if s.ctx.kept else "start",
                                      sess=e.session.split(":")[-1], R=R)) + "\n")
            n += 1
        online.apply(e, s)
p = lambda v, k: 1e3 * np.percentile(v, k)
print(f"done {n} plays {time.time()-t0:.0f}s; per play ms p50/p95: features {p(lat_x,50):.2f}/{p(lat_x,95):.2f}, "
      f"hybrid extra {p(lat,50):.2f}/{p(lat,95):.2f}", flush=True)
