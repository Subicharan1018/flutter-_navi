"""A simple skip-risk model fitted on one listener's own plays (time split). Features describe what a Flow queue
decides: how familiar the song is, whether it is in the listener's language, and how far it jumps from the song before."""
import math, os, sys, json
from collections import defaultdict, Counter
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_world as w
import flow_metrics as fm

NAMES = ["log_prior_plays", "prior_skip_rate", "log_days_since", "lang_share", "d_energy", "d_valence", "d_tempo", "d_key", "has_prev",
         "short", "log_pos", "energy", "valence"]


def song_row(meta, F, s):
    r = meta[s]; f = F[s]
    return r, f


def rows_for_user(eng, F, user, events=None):
    meta = eng.cat.meta
    ev = sorted([e for e in (events or eng.events) if e.user == user and e.source == "live" and e.song in meta], key=lambda e: e.ts)
    plays = defaultdict(int); skips = defaultdict(int); last = {}
    lang = Counter(); total = 0
    X, y, ts = [], [], []
    prev = None; pos = 0; cur = None
    for e in ev:
        if e.session != cur:
            cur, prev, pos = e.session, None, 0
        r, f = meta[e.song], F[e.song]
        n = plays[e.song]
        days = (e.ts - last[e.song]) / 86400 if e.song in last else 365.0
        ls = lang[r.get("language") or "und"] / max(total, 1)
        has_prev = prev is not None and e.ts - prev.ts <= 1200
        dE = dV = dT = dK = 0.0
        if has_prev:
            t = fm.transitions([prev.song, e.song], F)[0]
            dE, dV, dT, dK = t.get("d_energy", 0.0), t.get("d_valence", 0.0), t.get("d_tempo", 0.0), t.get("d_key", 0) / 6.0
        X.append([math.log1p(n), skips[e.song] / n if n else 0.0, math.log1p(min(days, 365.0)), ls, dE, dV, dT, dK,
                  float(has_prev), float((r.get("duration") or 200) < 120), math.log1p(pos), f["energy"] or 0.5, f["valence"] or 0.5])
        y.append(1 if e.ratio < 0.3 else 0)
        ts.append(e.ts)
        plays[e.song] += 1; skips[e.song] += y[-1]; last[e.song] = e.ts
        lang[r.get("language") or "und"] += 1; total += 1
        prev = e; pos += 1
    return np.array(X), np.array(y), np.array(ts)


def fit(X, y, split=0.7, C=1.0):
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
    from sklearn.metrics import roc_auc_score, log_loss
    k = int(len(y) * split)
    sc = StandardScaler().fit(X[:k])
    m = LogisticRegression(C=C, max_iter=500).fit(sc.transform(X[:k]), y[:k])
    p = m.predict_proba(sc.transform(X[k:]))[:, 1]
    base = np.full(len(p), y[:k].mean())
    return m, sc, {"n_train": int(k), "n_test": int(len(y) - k), "skip_rate_test": round(float(y[k:].mean()), 3),
                   "auc": round(float(roc_auc_score(y[k:], p)), 3), "logloss": round(float(log_loss(y[k:], p)), 3),
                   "logloss_base": round(float(log_loss(y[k:], base)), 3)}


if __name__ == "__main__":
    eng = w.build(); F = fm.feats(eng)
    for u in ["admin", "sandeep", "vijay"]:
        X, y, ts = rows_for_user(eng, F, u)
        m, sc, q = fit(X, y)
        print(u, q)
        print("  ", {n: round(float(c), 2) for n, c in zip(NAMES, m.coef_[0])})
        # without the transition features
        keep = [i for i, n in enumerate(NAMES) if not n.startswith("d_") and n != "has_prev"]
        m2, sc2, q2 = fit(X[:, keep], y)
        print("   without transitions:", q2["auc"], q2["logloss"])
