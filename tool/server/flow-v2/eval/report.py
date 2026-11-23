import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import flow_world as w
import flow_metrics as fm
eng = w.build()
labels = sys.argv[1:]
for lab in labels:
    d = json.load(open(os.path.join(w.SCR, f"replay_{lab}.json")))
    langs = {u: set(v) for u, v in d["langs"].items()}
    qs = [(q["user"], q["mood"], q["ids"]) for q in d["queues"] if q["ids"]]
    print("=====", lab, "queues", len(qs), "songs", sum(len(q[2]) for q in qs))
    print(json.dumps(fm.summarize(qs, eng, langs), indent=None))
    mq = [q for q in qs if q[1]]
    print("mood agreement (real numbers):", fm.mood_agreement(mq, eng))
    print("no-mood:", json.dumps(fm.summarize([q for q in qs if not q[1]], eng, langs)))
    for m in ["sad", "romantic", "happy", "energetic", "calm", "devotional", "angry", "gym"]:
        sub = [q for q in qs if q[1] == m]
        print(" ", m, "queues", len(sub), "songs", sum(len(q[2]) for q in sub), fm.mood_agreement(sub, eng),
              "dE", fm.summarize(sub, eng).get("d_energy", {}).get("mean") if sub else None)
    kinds = {}
    for q in d["queues"]:
        for x in q["details"]:
            kinds[x["kind"]] = kinds.get(x["kind"], 0) + 1
    print("kinds", kinds)
    short = [(q["user"], q["mood"], len(q["ids"])) for q in d["queues"] if len(q["ids"]) < 42]
    print("queues shorter than 42:", short[:20], len(short))
