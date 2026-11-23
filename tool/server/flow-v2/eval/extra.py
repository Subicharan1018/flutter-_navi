import json, os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_world as w, flow_metrics as fm
eng = w.build(); F = fm.feats(eng); meta = eng.cat.meta
def load(l): return json.load(open(os.path.join(w.SCR, f"replay_{l}.json")))
for lab in sys.argv[1:]:
    d = load(lab)
    seam, inner = [], []
    freshpos, famfirst = [], 0
    arcs = {"up": [], "down": []}
    adj = []
    nb = 0
    for q in d["queues"]:
        ids = q["ids"]; det = q["details"]
        bounds = [10, 18, 26, 34]
        for i in range(1, len(ids)):
            t = fm.transitions([ids[i-1], ids[i]], F)[0].get("d_energy")
            if t is None: continue
            (seam if i in bounds else inner).append(t)
        # relative position of cold songs in their batch
        by = {}
        for i, x in enumerate(det): by.setdefault(x["batch"], []).append(x)
        for b, xs in by.items():
            n = len(xs)
            for j, x in enumerate(xs):
                if x["kind"] != "familiar" and n > 1: freshpos.append(j / (n - 1))
            famfirst += xs[0]["kind"] == "familiar"; nb += 1
        m = q["mood"]
        if m in ("energetic", "gym", "angry", "calm", "sad", "romantic", "devotional") and len(ids) > 10:
            e = [F[s]["energy"] for s in ids if F[s]["energy"] is not None]
            slope = np.polyfit(np.arange(len(e)), e, 1)[0] * 40  # change over 40 songs
            arcs["up" if m in ("energetic", "gym", "angry") else "down"].append(slope)
        for i in range(1, len(ids)):
            a, b = meta[ids[i-1]], meta[ids[i]]
            if a.get("artist") and a.get("artist") == b.get("artist"): adj.append((i, a["artist"], q["mood"]))
    print(lab, "seam d_energy", round(float(np.mean(seam)), 3), "inner", round(float(np.mean(inner)), 3),
          "| fresh rel pos", round(float(np.mean(freshpos)), 3), "| batches opening familiar", f"{famfirst}/{nb}",
          "| energy slope /40 songs up", round(float(np.mean(arcs['up'])), 3), "down", round(float(np.mean(arcs['down'])), 3),
          "| adjacent same-artist", len(adj), [x[0] for x in adj][:12])
