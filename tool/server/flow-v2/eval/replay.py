"""replay.py <label> : build Flow queues for each listener x mood with the Flow code in $FLOW_TREE, save json."""
import json, os, sys, tempfile, time
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_world as w
import flow_metrics as fm
from navivibe import discover, explore, flow

label = sys.argv[1]
SEEDS = int(os.environ.get("SEEDS", "2"))
MOODS = [None, "sad", "romantic", "happy", "energetic", "calm", "devotional", "angry", "gym"]
eng = w.build()
now = max(e.ts for e in eng.events) + 1
discover._events.update(at=now, events=eng.events)
users = [u for u in w.listeners(eng, int(os.environ.get("MINPLAYS", "150")))]
queues, langs, info = [], {}, []
for u in users:
    mine = [e for e in eng.events if e.user == u]
    taste = discover.build_taste(mine, eng.cat.meta, {}, now)
    tot, acc, keep = 0, 0, set()
    for l, v in sorted(taste.language.items(), key=lambda kv: -kv[1]):
        keep.add(l); acc += v
        if acc >= 0.9:
            break
    langs[u] = keep
    for mood in MOODS:
        for seed in range(SEEDS):
            d = tempfile.mkdtemp()
            st = explore.Store(os.path.join(d, "state.db"))
            rng = np.random.default_rng(seed)
            ids, details = [], []
            for k, cnt in enumerate([10, 8, 8, 8, 8]):
                try:
                    out = flow.next_batch(eng, u, count=cnt, mood=mood, seen=ids, feedback=[], session=f"{u}-{mood}-{seed}",
                                          now=now, rng=rng, store=st)
                except Exception as e:                     # a failing batch is recorded, never hidden
                    info.append({"user": u, "mood": mood, "seed": seed, "error": repr(e)})
                    break
                if not out["items"]:
                    break
                ids += [i["navidrome_id"] for i in out["items"]]
                details += [{"id": i["navidrome_id"], "kind": i.get("kind"), "why": i.get("why"), "batch": k} for i in out["items"]]
            queues.append({"user": u, "mood": mood, "seed": seed, "ids": ids, "details": details})
json.dump({"label": label, "now": now, "users": users, "langs": {u: sorted(v) for u, v in langs.items()},
           "queues": queues, "errors": info}, open(os.path.join(w.SCR, f"replay_{label}.json"), "w"))
print("queues", len(queues), "empty", sum(1 for q in queues if not q["ids"]), "errors", len(info))
