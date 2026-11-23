"""Predicted skip risk of replayed Flow queues: a logistic model on song-level features fitted on each listener's own plays
(time split for quality; refit on all of it to score queues). Transition features are left OUT on purpose: in the
owner's data a bigger jump does not predict a skip (see docs/flow-better.md)."""
import json, math, os, sys
from collections import defaultdict
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_world as w, flow_metrics as fm, skipmodel as sm

NAMES = sm.NAMES
KEEP = [NAMES.index(n) for n in ("log_prior_plays", "prior_skip_rate", "log_days_since", "lang_share", "short")]


def state_at(eng, user, now):
    meta = eng.cat.meta
    plays, skips, last = defaultdict(int), defaultdict(int), {}
    lang, total = defaultdict(int), 0
    for e in sorted((e for e in eng.events if e.user == user and e.source == "live" and e.song in meta), key=lambda e: e.ts):
        plays[e.song] += 1; skips[e.song] += e.ratio < 0.3; last[e.song] = e.ts
        lang[meta[e.song].get("language") or "und"] += 1; total += 1
    return plays, skips, last, lang, total


def feat(eng, st, s, now):
    plays, skips, last, lang, total = st
    r = eng.cat.meta[s]
    n = plays[s]
    days = (now - last[s]) / 86400 if s in last else 365.0
    return [math.log1p(n), skips[s] / n if n else 0.0, math.log1p(min(days, 365.0)),
            lang[r.get("language") or "und"] / max(total, 1), float((r.get("duration") or 200) < 120)]


if __name__ == "__main__":
    labels = sys.argv[1:]
    eng = w.build(); F = fm.feats(eng)
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler
    data = {l: json.load(open(os.path.join(w.SCR, f"replay_{l}.json"))) for l in labels}
    now = data[labels[0]]["now"]
    for u in ["admin", "vijay", "sandeep"]:
        X, y, ts = sm.rows_for_user(eng, F, u)
        X = X[:, KEEP]
        k = int(len(y) * 0.7)
        from sklearn.metrics import roc_auc_score
        sc = StandardScaler().fit(X[:k]); m = LogisticRegression(max_iter=500).fit(sc.transform(X[:k]), y[:k])
        auc = roc_auc_score(y[k:], m.predict_proba(sc.transform(X[k:]))[:, 1])
        sc = StandardScaler().fit(X); m = LogisticRegression(max_iter=500).fit(sc.transform(X), y)
        st = state_at(eng, u, now)
        out = {}
        for l in labels:
            P = []
            for q in data[l]["queues"]:
                if q["user"] != u or not q["ids"]:
                    continue
                Xq = np.array([feat(eng, st, s, now) for s in q["ids"]])
                P.append(m.predict_proba(sc.transform(Xq))[:, 1].mean())
            out[l] = round(float(np.mean(P)), 4)
        print(u, "held-out AUC", round(float(auc), 3), "plays", len(y), "base skip", round(float(y.mean()), 3), "predicted mean skip risk of a queue:", out)
