"""
navivibe/catalog/mood_relabel.py   (moods-v3)
─────────────────────────────────────────────
What the moods-v3 rules would change, and the switch that turns them on.

    venv/bin/python -m navivibe.catalog.mood_relabel                 # dry run: reads only, prints the report
    venv/bin/python -m navivibe.catalog.mood_relabel --list 40       # also 40 changed songs
    venv/bin/python -m navivibe.catalog.mood_relabel --out FILE      # the full change list as JSON
    venv/bin/python -m navivibe.catalog.mood_relabel --write         # turn v3 on (asks nothing, backs up first)
    venv/bin/python -m navivibe.catalog.mood_relabel --off           # back to the moods-v2 rules

--write copies the labels in use to backups/ and writes mood_rules.json ({"rules": 3}) next to
mood_tags.json. The labeller's file (mood_tags.json), admin labels and "Not this mood" marks are never
changed. The labels in use are computed from the current numbers, so a later Spotify import moves them
by itself: nothing stored goes stale.
"""

import argparse
import json
import os
import sys
import time
from collections import Counter

from navivibe.catalog import mood_fusion, mood_quality, mood_tags


def table(raw: dict, fx: dict, meta: dict, admin: dict) -> list:
    """One row per song in the labels file that no admin has settled: v2 and v3 labels and why."""
    out = []
    for sid, tags in raw.items():
        if sid in admin:
            continue
        f = fx.get(sid)
        if f is None:                               # not in the catalog any more
            continue
        v3 = (f or {}).get("v3") or {}
        d = mood_fusion.decide(tags, v3, meta.get(sid))
        out.append({"id": sid, "raw": tags or [], "v2": mood_quality.sanity(tags or [], f, meta.get(sid)), "v3": d["moods"],
                    "confidence": d["confidence"], "dropped": d["dropped"], "added": d["added"], "sound": v3,
                    "rated": sid in meta})
    return out


def agreement(rows: list, key: str) -> dict:
    """Songs with Spotify's own numbers and a label: how many have no plain contradiction. CIRCULAR for v3."""
    lab = [r for r in rows if r["sound"].get("src") == "spotify" and r[key]]
    bad = sum(bool(mood_fusion.disagreements(r[key], r["sound"])) for r in lab)
    return {"labelled": len(lab), "disagree": bad, "agree": round(1 - bad / len(lab), 4) if lab else None}


def report(rows: list) -> dict:
    first = lambda m: m[0] if m else "-"
    changed = [r for r in rows if r["v2"] != r["v3"]]
    return {"songs": len(rows),
            "sources": dict(Counter(r["sound"].get("src") or "none" for r in rows)),
            "labels_from_before_the_rated_prompt": sum(not r["rated"] for r in rows if r["raw"]),
            "labelled_v2": sum(bool(r["v2"]) for r in rows), "labelled_v3": sum(bool(r["v3"]) for r in rows),
            "changed": len(changed), "first_label_changed": sum(first(r["v2"]) != first(r["v3"]) for r in changed),
            "lose_every_label": sum(bool(r["v2"]) and not r["v3"] for r in changed),
            "gain_energetic": sum("energetic" in r["added"] for r in rows),
            "first_v2": dict(Counter(first(r["v2"]) for r in rows).most_common()),
            "first_v3": dict(Counter(first(r["v3"]) for r in rows).most_common()),
            "agreement_v2": agreement(rows, "v2"), "agreement_v3": agreement(rows, "v3")}


def render(rep: dict, out=print) -> None:
    out(f"{rep['songs']} songs with no admin label; sound numbers: {rep['sources']}")
    out(f"{rep['labels_from_before_the_rated_prompt']} labels were given before the moods-v2 prompt and never asked again")
    out(f"would change: {rep['changed']} songs ({rep['first_label_changed']} first labels); "
        f"{rep['lose_every_label']} lose every label; {rep['gain_energetic']} gain 'energetic'")
    out(f"labelled songs: {rep['labelled_v2']} now -> {rep['labelled_v3']}")
    out(f"first label now: {rep['first_v2']}")
    out(f"first label v3:  {rep['first_v3']}")
    for k, name in (("agreement_v2", "now"), ("agreement_v3", "v3 ")):
        a = rep[k]
        pct = "n/a" if a["agree"] is None else f"{a['agree']:.1%}"
        out(f"agree with Spotify's numbers, {name}: {pct} ({a['disagree']} of {a['labelled']} contradict them)")
    out("That agreement is circular for v3 (its rules read the same numbers). It is not accuracy: the owner's marks are.")


def live_rows() -> list:
    return table(mood_tags.load_raw(), mood_quality.facts(), mood_quality.load_meta(), mood_quality.load_admin())


def main(argv=None, out=print) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--list", type=int, default=0, metavar="N")
    ap.add_argument("--out", metavar="FILE")
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--write", action="store_true")
    g.add_argument("--off", action="store_true")
    a = ap.parse_args(argv)
    switch = mood_quality.rules_path()
    if a.off:
        if os.path.exists(switch):
            os.remove(switch)
        out("moods-v3 rules are off: the moods-v2 rules are in use")
        return 0
    rows = live_rows()
    if not rows:
        out("!! no songs read (is catalog.db there?): nothing done")
        return 1
    render(report(rows), out)
    shown = 0
    for r in rows:
        if shown >= a.list:
            break
        if r["v2"] != r["v3"]:
            shown += 1
            out(f"  {r['id']}  {r['v2']} -> {r['v3']}  {'; '.join(f'{m}: {w}' for m, w in r['dropped'])}")
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            json.dump({"report": report(rows), "rows": rows}, f, ensure_ascii=False, indent=1)
        out(f"saved to {a.out}")
    if not a.write:
        out(f"dry run: nothing written. Rules in use now: v{mood_quality.rules_in_use()}")
        return 0
    folder = os.path.join(os.path.dirname(switch), "backups")
    os.makedirs(folder, exist_ok=True)
    bak = os.path.join(folder, f"mood-labels-in-use-{time.strftime('%Y%m%d-%H%M%S')}.json")
    with open(bak, "w", encoding="utf-8") as f:
        json.dump(mood_tags.load(), f, ensure_ascii=False)
    mood_quality._write(switch, {"rules": 3, "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())})
    out(f"moods-v3 rules are on. Labels in use before: {bak}. Undo: --off")
    return 0


if __name__ == "__main__":
    sys.exit(main())
