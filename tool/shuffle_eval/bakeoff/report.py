"""HR@10 with session-cluster bootstrap CIs, paired deltas, and plays needed to see an effect.

  python report.py runs/w0.jsonl runs/w30.jsonl runs/w60.jsonl
"""
import json
import sys

import numpy as np

rows = []
for w, p in enumerate(sys.argv[1:]):
    for line in open(p):
        r = json.loads(line)
        r["cl"] = (w, r["u"], r["sess"])
        rows.append(r)


def boot(rs, f, n=1000):
    ids = {}
    ix = np.array([ids.setdefault(r["cl"], len(ids)) for r in rs])
    v = np.array([f(r) for r in rs], float)
    C = len(ids)
    s, c = np.bincount(ix, v, C), np.bincount(ix, minlength=C)
    rng = np.random.default_rng(0)
    b = []
    for _ in range(n):
        k = rng.integers(0, C, C)
        b.append(s[k].sum() / c[k].sum())
    return v.mean(), np.percentile(b, 2.5), np.percentile(b, 97.5), float(np.std(b)), C


def hit(m):
    return lambda r: float(r["R"][m] <= 10)


for who, sel in (("owner", lambda r: r["u"] == "u00"), ("others", lambda r: r["u"] != "u00")):
    for task in ("next", "start"):
        rs = [r for r in rows if sel(r) and r["task"] == task]
        if not rs:
            continue
        print(f"\n{who} {task}: {len(rs)} plays")
        for m in rs[0]["R"]:
            x = boot(rs, hit(m))
            print(f"  {m:22s} HR@10 {100*x[0]:.1f} [{100*x[1]:.1f}, {100*x[2]:.1f}]  sessions {x[4]}")
        for base in ("v3", "blend"):
            m = "hybrid_no_audio_mood"
            x = boot(rs, lambda r: hit(m)(r) - hit(base)(r))
            need = len(rs) * (x[3] / (0.03 / 2.8)) ** 2      # 80% power, two-sided 5%, true effect 3 points
            print(f"  {m} - {base}: {100*x[0]:+.1f} [{100*x[1]:+.1f}, {100*x[2]:+.1f}] SE {100*x[3]:.2f}; "
                  f"plays to see +3 points at 80% power: {need:.0f}")
