import json, os, sys, collections
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_world as w, flow_metrics as fm
eng = w.build(); F = fm.feats(eng); meta = eng.cat.meta
D = {l: json.load(open(os.path.join(w.SCR, f"replay_{l}.json"))) for l in ("old", "v2", "shadow")}
langs = {u: set(v) for u, v in D["old"]["langs"].items()}
print("listeners", D["old"]["users"], "queues each", len(D["old"]["queues"]))
# shadow serves exactly what off serves
same = sum(1 for a, b in zip(D["old"]["queues"], D["shadow"]["queues"]) if a["ids"] == b["ids"])
print("shadow == old queues (song by song):", same, "of", len(D["old"]["queues"]))
lens = lambda l: collections.Counter(len(q["ids"]) for q in D[l]["queues"])
print("queue lengths old", dict(lens("old")), "v2", dict(lens("v2")))


def qs(l, mood="any"):
    out = []
    for q in D[l]["queues"]:
        if q["ids"] and (mood == "any" or (q["mood"] is None) == (mood == "none")):
            out.append((q["user"], q["mood"], q["ids"]))
    return out

for grp in ("any", "none"):
    for l in ("old", "v2"):
        s = fm.summarize(qs(l, grp), eng, langs)
        print(grp, l, json.dumps({k: (v["mean"] if isinstance(v, dict) else v) for k, v in s.items()}))
# mood agreement per chip + mean real energy / valence
for m in ["sad", "romantic", "happy", "energetic", "calm", "devotional", "angry", "gym"]:
    row = []
    for l in ("old", "v2"):
        sub = [(q["user"], q["mood"], q["ids"]) for q in D[l]["queues"] if q["mood"] == m and q["ids"]]
        a = fm.mood_agreement(sub, eng)
        real = [s for _, _, ids in sub for s in ids if F[s]["real"] and F[s]["energy"] is not None]
        row.append((l, a["agree"], a["judged"], round(float(np.mean([F[s]["energy"] for s in real])), 2), round(float(np.mean([F[s]["valence"] for s in real])), 2),
                    len({s for _, _, ids in sub for s in ids})))
    print(m, row)
allmood = {l: fm.mood_agreement([q for q in qs(l) if q[1]], eng) for l in ("old", "v2")}
print("agreement overall", allmood)
# diversity: distinct songs across all queues, overlap between seeds
for l in ("old", "v2"):
    allids = [s for q in D[l]["queues"] for s in q["ids"]]
    byk = collections.defaultdict(list)
    for q in D[l]["queues"]:
        byk[(q["user"], q["mood"])].append(set(q["ids"]))
    jac = []
    for k, sets in byk.items():
        for i in range(len(sets)):
            for j in range(i + 1, len(sets)):
                jac.append(len(sets[i] & sets[j]) / len(sets[i] | sets[j]))
    print(l, "distinct songs", len(set(allids)), "of", len(meta), "| mean overlap between two runs of the same listener+chip", round(float(np.mean(jac)), 3))
# kinds and position of cold songs, seams
for l in ("old", "v2"):
    seam, inner, fpos, op, nb = [], [], [], 0, 0
    kinds = collections.Counter()
    for q in D[l]["queues"]:
        ids = q["ids"]
        for i in range(1, len(ids)):
            t = fm.transitions([ids[i - 1], ids[i]], F)[0].get("d_energy")
            if t is not None:
                (seam if i in (10, 18, 26, 34) else inner).append(t)
        by = collections.defaultdict(list)
        for x in q["details"]:
            by[x["batch"]].append(x); kinds[x["kind"]] += 1
        for b, xs in by.items():
            n = len(xs)
            op += xs[0]["kind"] == "familiar"; nb += 1
            fpos += [j / (n - 1) for j, x in enumerate(xs) if x["kind"] != "familiar" and n > 1]
    print(l, "seam dE", round(float(np.mean(seam)), 3), "inner dE", round(float(np.mean(inner)), 3), "cold rel.pos", round(float(np.mean(fpos)), 3),
          "open familiar", f"{op}/{nb}", dict(kinds))
# predicted vs real sound in the queues
for l in ("old", "v2"):
    ids = [s for q in D[l]["queues"] for s in q["ids"]]
    print(l, "songs with real numbers", round(float(np.mean([F[s]["real"] for s in ids])), 3))
# the shadow log written by the v2/shadow replays
p = os.path.join(w.DATA, "logs", "flow_v2", "shadow.jsonl")
if os.path.exists(p):
    L = [json.loads(x) for x in open(p)]
    for md in ("shadow", "on"):
        sub = [x for x in L if x["mode"] == md]
        if sub:
            print("log", md, "lines", len(sub), "mean cost old", round(float(np.mean([x["cost_old"] for x in sub])), 3), "new", round(float(np.mean([x["cost_new"] for x in sub])), 3),
                  "ratio", round(float(np.sum([x["cost_new"] for x in sub]) / np.sum([x["cost_old"] for x in sub])), 3))
