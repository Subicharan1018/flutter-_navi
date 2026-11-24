"""smart-pick-v1 offline evaluation: playlist Smart Shuffle, the OLD way versus the NEW way.

  python smart_pick_eval.py --snapshot DIR --owner admin --out DIR/smart_pick.json

DIR is the same copied snapshot the bake-off harness uses (navivibe/ server code, catalog.db,
logs/*_listening_log.db). Read-only, offline; the output holds listening history: keep it out of
the repo. v3 is trained on everything before the cutoff and the last --holdout-days are replayed.

For every owner session in the held-out window a synthetic playlist (the pool) is built:
the songs of that session + filler = 75% songs the owner had played before, 25% songs they never
played, 196 songs in all (the size of the owner's real playlist). Pools use fixed seeds.

OLD  = the app as it was: a random seed song, a random 16 of the rest sent as candidates, v3 samples
       and orders them (v3's own sampler, temperature, explore slot, film-marathon rule).
NEW  = smart-pick-v1: v3's opener model on the FAMILIAR songs of the whole pool, then v3 on the
       familiar songs, then the cold ones (one closes the batch), see navivibe/smart_pick.py.
Not simulated: the listener-memory re-order (AI_ORDER=memory) and artist spacing: same for both.

Metrics (first batch of 17 = what a Shuffle tap queues): cold share of positions 1-7, familiarity
of the first song, expected skips; and, per held-out kept play, HR@10 of the played song among the pool.
"""
import argparse
import json
import os
import sys
import time
from datetime import datetime, timedelta

ap = argparse.ArgumentParser()
ap.add_argument("--snapshot", required=True)
ap.add_argument("--owner", default="admin")
ap.add_argument("--end-days-ago", type=int, default=0)
ap.add_argument("--holdout-days", type=int, default=30)
ap.add_argument("--pool", type=int, default=196)
ap.add_argument("--seeds", type=int, default=3)
ap.add_argument("--filler", choices=["uniform", "weighted"], default="uniform",
                help="played-before filler songs: uniform over songs, or weighted by the owner's play counts (a curated playlist)")
ap.add_argument("--cold-plays", type=int, default=3)
ap.add_argument("--stale-days", type=float, default=30.0)
ap.add_argument("--out", required=True)
a = ap.parse_args()
S = os.path.abspath(a.snapshot)
os.environ["NAVIVIBE_LOG_DIR"] = os.path.join(S, "logs")
os.environ["NAVIVIBE_CATALOG_DB"] = os.path.join(S, "catalog.db")
os.environ["NAVIVIBE_V3_DIR"] = os.path.join(S, "unused_v3")
sys.path.insert(0, S)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "bakeoff"))

import numpy as np                                                   # noqa: E402
from navivibe.catalog import store                                   # noqa: E402
from navivibe.recsys import recommender as R, train as T             # noqa: E402
from navivibe.recsys.data import IST, Catalog, load_all              # noqa: E402
from navivibe.recsys.features import SessionCtx                      # noqa: E402
import hybrid as H                                                   # noqa: E402

DAY = 86400.0
T.LGB_PARAMS.update(deterministic=True, force_row_wise=True, num_threads=2)
np.random.seed(0)
t0 = time.time()
catalog = Catalog.from_rows(store.load_catalog())
events, _ = load_all(catalog, None)
if a.end_days_ago:
    end = max(e.ts for e in events) - a.end_days_ago * 86400
    events = [e for e in events if e.ts < end]
last = datetime.fromtimestamp(max(e.ts for e in events), IST).replace(hour=0, minute=0, second=0)
cutoff = (last - timedelta(days=a.holdout_days - 1)).timestamp()
arrays, co, au, pca, fb = T.build_world(events, catalog, cutoff)
N = len(catalog)
online = T.Replay(catalog, arrays, fb, history=events)
ts, consumed = T.collect_training(online, events, stop_ts=cutoff)
v3 = T.fit_ranker(ts)
del ts
online.history = None
fm = H.FeatureMatrix(catalog, arrays, None)
print("v3 trained %.0fs; held-out events %d" % (time.time() - t0, len(events) - consumed), flush=True)


def familiar_mask(us, t):
    fam = us.raw >= a.cold_plays
    old = ~np.isnan(us.last_ts) & ((t - us.last_ts) / DAY > a.stale_days)
    return fam & ~old


def sim_pick(us, t, hour, wd, kept0, played0, allowed, n, rng, explore_ok=True):
    """The recommender's own loop (recommend()) over a pool: same features, sampler, explore slot."""
    sim = SessionCtx(kept=list(kept0), played=set(played0))
    allowed = allowed.copy()
    X_static = fb.build_static(us, online.gs, t, hour, wd)
    explore_slot = R.EXPLORE_MIN_POS + 1 if R.EXPLORE_SLOTS and n > R.EXPLORE_MIN_POS + 2 and explore_ok else -1
    out = []
    for slot in range(n):
        if not allowed.any():
            break
        X = fb.build_session(X_static, us, sim)
        empty = not sim.kept
        scores = v3.predict(X, empty, num_threads=2)
        temp = R.TEMPERATURE_START if empty else R.TEMPERATURE
        mask, explore = allowed.copy(), False
        if slot == explore_slot and (allowed & (us.raw == 0)).any():
            mask, explore = allowed & (us.raw == 0), True
        if len(sim.kept) >= 2 and arrays.film_of[sim.kept[-1]] == arrays.film_of[sim.kept[-2]]:
            same = arrays.film_of == arrays.film_of[sim.kept[-1]]
            m2 = mask & ~(same & (X[:, R.F["p_next"]] <= 0))
            if m2.any():
                mask = m2
        j = R.V3Engine._sample(scores, mask, temp, rng)
        out.append(j)
        allowed[j] = False
        sim.played.add(j)
        if not explore:
            sim.kept.append(j)
    return out


def make_pool(us, t, truth, rng):
    pool = set(truth)
    played_before = np.flatnonzero(us.raw > 0)
    never = np.flatnonzero(us.raw == 0)
    need = a.pool - len(pool)
    n_cold = int(round(need * 0.25))
    pb = np.setdiff1d(played_before, list(pool))
    nv = np.setdiff1d(never, list(pool))
    w = None
    if a.filler == "weighted":
        w = us.raw[pb] / us.raw[pb].sum()
    pool.update(rng.choice(pb, size=min(len(pb), need - n_cold), replace=False, p=w).tolist())
    pool.update(rng.choice(nv, size=min(len(nv), n_cold), replace=False).tolist())
    m = np.zeros(N, bool)
    m[list(pool)] = True
    return m


def old_batch(us, t, hour, wd, pool, rng):
    """App as it was: random seed (played), random 16 of the rest, v3 picks all of them."""
    idx = np.flatnonzero(pool)
    seed = int(rng.choice(idx))
    rest = np.setdiff1d(idx, [seed])
    cand = rng.choice(rest, size=min(16, len(rest)), replace=False)
    allowed = np.zeros(N, bool)
    allowed[cand] = True
    return [seed] + sim_pick(us, t, hour, wd, [seed], {seed}, allowed, 16, rng)


def new_batch(us, t, hour, wd, pool, rng, count=17):
    fam = familiar_mask(us, t)
    famp, coldp = pool & fam, pool & ~fam
    if not famp.any():
        return sim_pick(us, t, hour, wd, [], set(), pool, count, rng)          # graceful: model order
    opener = sim_pick(us, t, hour, wd, [], set(), famp, 1, rng)[0]
    famp[opener] = False
    need = count - 1
    close = coldp.any() and famp.sum() >= need and need >= 3
    n_fam = int(min(famp.sum(), need - (1 if close else 0)))
    n_cold = int(min(coldp.sum(), need - n_fam))
    main = sim_pick(us, t, hour, wd, [opener], {opener}, famp, n_fam, rng) if n_fam else []
    tail = []
    if n_cold:
        kept = [opener] + main[-1:]
        tail = sim_pick(us, t, hour, wd, kept, {opener, *main}, coldp, n_cold, rng)
    return [opener] + main + tail


# ── held-out sessions of the owner ───────────────────────────────────────────
sess_truth = {}
for e in events[consumed:]:
    if e.user == a.owner and not e.skipped:
        i = catalog.index[e.song]
        l = sess_truth.setdefault(e.session, [])
        if i not in l:
            l.append(i)

# prior skip rates by group (before the cutoff, owner, session positions 1-7), for the "expected skip" line
hist = {"fam": [0, 0], "cold": [0, 0]}
rep0 = T.Replay(catalog, arrays, fb, history=None)
for e in events[:consumed]:
    s = rep0.session_for(e)
    if e.user == a.owner and e.source == "live" and len(s.ctx.played) < 7:   # the app's own plays (no imports)
        us = rep0.user(e.user)
        i = catalog.index[e.song]
        fam = bool(familiar_mask(us, e.ts)[i])
        hist["fam" if fam else "cold"][0] += int(e.skipped)
        hist["cold" if not fam else "fam"][1] += 1
    rep0.apply(e, s)
del rep0
rate = {k: (v[0] / v[1] if v[1] else float("nan")) for k, v in hist.items()}
print("owner skip rate in session slots 1-7 before the cutoff: familiar %.3f (n=%d), cold %.3f (n=%d)" % (
    rate["fam"], hist["fam"][1], rate["cold"], hist["cold"][1]), flush=True)

res = {"taps": [], "plays": [], "real_first": [], "rate": rate, "args": vars(a)}
rng_master = np.random.default_rng(7)
pools = {}
for e in events[consumed:]:
    s, i = online.session_for(e), catalog.index[e.song]
    if e.user == a.owner:
        first = not s.ctx.played
        us = online.user(e.user)
        truth = sess_truth.get(e.session, [])
        if first:                                           # a tap: simulate the first batch both ways
            fam_now = bool(familiar_mask(us, e.ts)[i])
            res["real_first"].append({"skip": bool(e.skipped), "familiar": fam_now})
            for sd in range(a.seeds):
                rng = np.random.default_rng(1000 * sd + len(res["taps"]))
                pool = make_pool(us, e.ts, truth, rng)
                pools[(e.session, sd)] = pool
                fam = familiar_mask(us, e.ts)
                row = {"seed": sd}
                for name, fn in (("old", old_batch), ("new", new_batch)):
                    seq = fn(us, e.ts, e.hour, e.weekday, pool, np.random.default_rng(5000 + 17 * sd + len(res["taps"])))
                    cold = [0 if fam[j] else 1 for j in seq]
                    first7 = cold[:7]
                    sm = [(us.skips[j] + 3 * rate["fam"]) / (us.raw[j] + 3) if us.raw[j] else rate["cold"] for j in seq]
                    row[name] = {"pool_cold": float(1 - fam[np.flatnonzero(pool)].mean()), "cold7": sum(first7) / max(1, len(first7)), "cold_first": cold[0],
                                 "cold_all": sum(cold) / max(1, len(cold)), "plays_first": float(us.raw[seq[0]]),
                                 "exp_skip_group7": float(np.mean([rate["cold" if c else "fam"] for c in first7])),
                                 "exp_skip_group_first": rate["cold" if cold[0] else "fam"],
                                 "exp_skip_song_first": float(sm[0]), "n": len(seq),
                                 "cold_in_2_7": sum(cold[1:7])}
                res["taps"].append(row)
        # HR@10 of the played song inside the pool
        if not e.skipped and i not in s.ctx.played and truth:
            sd = 0
            pool = pools.get((e.session, sd))
            if pool is None:
                pool = make_pool(us, e.ts, truth, np.random.default_rng(99))
                pools[(e.session, sd)] = pool
            allowed = pool.copy()
            allowed[list(s.ctx.played)] = False
            X = online.features(e, s)
            empty = not s.ctx.kept
            sc = v3.predict(X, empty)
            hb, _ = fm.build(X, us, s.ctx.kept, e.ts, e.hour, e.month)
            fam = familiar_mask(us, e.ts)

            def rank(v, mask):
                v = np.where(mask, v, -np.inf)
                return 1 + float((v > v[i]).sum()) + 0.5 * float((v == v[i]).sum() - 1)

            r_v3 = rank(sc, allowed)
            r_blend = rank(hb, allowed)
            fa = allowed & fam
            r_guard = rank(sc, fa) if fam[i] else int(fa.sum()) + rank(sc, allowed & ~fam)
            A = np.flatnonzero(allowed)
            rr = np.random.default_rng(31 + len(res["plays"]))
            hit_old = []
            for _ in range(20):
                smp = rr.choice(A, size=min(16, len(A)), replace=False)
                hit_old.append(float(i in smp and 1 + (sc[smp] > sc[i]).sum() <= 10))
            res["plays"].append({"task": "start" if empty else "next", "pool_allowed": int(allowed.sum()),
                                 "cold": bool(not fam[i]), "old": float(np.mean(hit_old)),
                                 "v3_pool": float(r_v3 <= 10), "guard_pool": float(r_guard <= 10),
                                 "blend_pool": float(r_blend <= 10),
                                 "blend_guard_pool": float((rank(hb, fa) if fam[i] else int(fa.sum()) + rank(hb, allowed & ~fam)) <= 10)})
    online.apply(e, s)

json.dump(res, open(a.out, "w"))


def mean(rows, *path):
    v = []
    for r in rows:
        x = r
        for p in path:
            x = x[p]
        v.append(x)
    return float(np.mean(v)) if v else float("nan")


T_ = res["taps"]
print("\n== first batch of 17 on %d simulated taps (%d owner sessions x %d pool seeds, pool %d)" % (
    len(T_), len(sess_truth), a.seeds, a.pool))
print("%-44s %10s %10s" % ("", "OLD", "NEW"))
print("%-44s %10.3f" % ("cold share of the pool itself", mean(T_, "old", "pool_cold")))
for label, key in (("cold songs in positions 1-7 (share)", "cold7"), ("first song is cold (share)", "cold_first"),
                   ("cold songs in the whole batch (share)", "cold_all"), ("plays of the first song (mean)", "plays_first"),
                   ("cold songs in positions 2-7 (mean count)", "cold_in_2_7"),
                   ("expected skip, slots 1-7 (owner group rates)", "exp_skip_group7"),
                   ("expected skip, first song (owner group rates)", "exp_skip_group_first"),
                   ("expected skip, first song (its own history)", "exp_skip_song_first")):
    print("%-44s %10.3f %10.3f" % (label, mean(T_, "old", key), mean(T_, "new", key)))
rf = res["real_first"]
if rf:
    print("\nreal held-out first songs: n=%d skipped %.1f%% (familiar first songs %.1f%% of n=%d, cold %.1f%% of n=%d)" % (
        len(rf), 100 * np.mean([r["skip"] for r in rf]),
        100 * np.mean([r["skip"] for r in rf if r["familiar"]] or [float("nan")]), sum(r["familiar"] for r in rf),
        100 * np.mean([r["skip"] for r in rf if not r["familiar"]] or [float("nan")]), sum(not r["familiar"] for r in rf)))
P_ = res["plays"]
print("\n== HR@10 of the song really played, inside the pool (%d held-out kept plays)" % len(P_))
for task in ("start", "next", None):
    rows = [p for p in P_ if task is None or p["task"] == task]
    if rows:
        print("%-6s n=%4d  OLD(random16) %.3f | NEW whole pool, v3 plain %.3f | NEW + familiar-first %.3f | blend plain %.3f | blend + familiar-first %.3f" % (
            task or "all", len(rows), mean(rows, "old"), mean(rows, "v3_pool"), mean(rows, "guard_pool"),
            mean(rows, "blend_pool"), mean(rows, "blend_guard_pool")))
print("share of played songs that were cold: %.3f" % mean(P_, "cold"))
print("done %.0fs" % (time.time() - t0))
