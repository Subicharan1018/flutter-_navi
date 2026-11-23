import os, sys, collections, json
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_world as w
import flow_metrics as fm
from navivibe.catalog import mood_tags
eng = w.build()
meta = eng.cat.meta
F = fm.feats(eng)
eff = mood_tags.load()
raw = mood_tags.load_raw()
print("songs", len(meta), "raw labelled", sum(1 for s in meta if raw.get(s)), "effective labelled", sum(1 for s in meta if eff.get(s)),
      "no effective label", sum(1 for s in meta if not eff.get(s)))
print("real feature songs", sum(1 for s in meta if F[s]["real"]), "predicted only", sum(1 for s in meta if not F[s]["real"] and F[s]["energy"] is not None),
      "none", sum(1 for s in meta if F[s]["energy"] is None))
unl = [s for s in meta if not eff.get(s)]
print("unlabelled: with lyrics", sum(1 for s in unl if meta[s].get("has_lyrics")), "instrumental", sum(1 for s in unl if meta[s].get("instrumental")),
      "real", sum(1 for s in unl if F[s]["real"]))
per = {}
for m in mood_tags.FLOW_MOODS:
    fit = [s for s in meta if mood_tags.flow_fit(meta[s], eff.get(s) or [], m)]
    per[m] = len(fit)
print("chip counts", per)
# a song can sit in several chips; songs in no chip at all
inany = {s for s in meta for m in mood_tags.FLOW_MOODS if mood_tags.flow_fit(meta[s], eff.get(s) or [], m)}
print("songs in no chip", len(meta) - len(inany))
# of the chip songs, how many with real numbers disagree (independent rules)
for m in mood_tags.FLOW_MOODS:
    fit = [s for s in meta if mood_tags.flow_fit(meta[s], eff.get(s) or [], m) and F[s]["real"] and F[s]["energy"] is not None]
    ok = sum(1 for s in fit if fm.RULES[m](F[s]))
    en = np.mean([F[s]["energy"] for s in fit]); va = np.mean([F[s]["valence"] for s in fit])
    print(m, "chip songs with real nums", len(fit), "agree", round(ok / max(len(fit), 1), 3), "mean real energy", round(float(en), 2), "valence", round(float(va), 2))
# second-opinion: catalog (predicted) energy vs real energy on songs with both: how often the chip filter used the wrong side
bad = 0; tot = 0
for s in meta:
    f = F[s]; r = meta[s]
    if f["real"] and r.get("feature_source") != "spotify" and r.get("energy") is not None:
        tot += 1; bad += abs(f["energy"] - r["energy"]) > 0.2
print("songs where catalog (used by Flow) energy differs from real energy by >0.2:", bad, "of", tot)
# random baseline for transitions
rng = np.random.default_rng(0)
ids = list(meta)
qs = [("x", None, list(rng.choice(ids, 42, replace=False))) for _ in range(60)]
print("random queue baseline:", json.dumps(fm.summarize(qs, eng)))
# duration of old flow songs vs library
lib = np.array([meta[s].get("duration") or 0 for s in meta])
print("library <2min", round((lib < 120).mean(), 3), ">7min", round((lib > 420).mean(), 3), "instrumental", round(np.mean([bool(meta[s].get("instrumental")) for s in meta]), 3))
