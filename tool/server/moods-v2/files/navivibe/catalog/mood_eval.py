"""
navivibe/catalog/mood_eval.py   (moods-v2)
─────────────────────────────
How often a song's FIRST mood is one a listener would accept, on the reference sample in
tests/fixtures/mood_reference.json (54 songs judged by hand). Read-only.

    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m navivibe.catalog.mood_eval

It scores the labeller's raw labels and the labels the server uses (moods-v2 rules, admin labels).
Run it again after relabel_moods.sh to see the change.
"""

import json
import os
import sys

REFERENCE = os.path.join(os.path.dirname(__file__), "..", "tests", "fixtures", "mood_reference.json")


def load_reference(path: str = None) -> dict:
    with open(path or REFERENCE, encoding="utf-8") as f:
        return json.load(f)["songs"]


def score(labels: dict, reference: dict) -> dict:
    """right: first label acceptable; wrong: first label not acceptable; none: no label."""
    right = wrong = none = 0
    misses = []
    for sid, ref in reference.items():
        tags = labels.get(sid) or []
        if not tags:
            none += 1
        elif tags[0] in ref["ok"]:
            right += 1
        else:
            wrong += 1
            misses.append(f"{ref['title']}: {tags} (ok: {ref['ok']})")
    labelled = right + wrong
    return {"songs": len(reference), "right": right, "wrong": wrong, "unlabelled": none,
            "accuracy": round(right / len(reference), 3) if reference else 0.0,
            "precision": round(right / labelled, 3) if labelled else 0.0, "misses": misses}


def main(out=print) -> int:
    from navivibe.catalog import mood_quality, mood_tags
    ref = load_reference()
    raw = mood_tags.load_raw()
    for name, labels in (("raw labeller labels", raw), ("labels in use (moods-v2)", mood_quality.load_effective())):
        s = score(labels, ref)
        out(f"{name}: {s['right']}/{s['songs']} right, {s['wrong']} wrong, {s['unlabelled']} unlabelled "
            f"(precision {s['precision']:.0%})")
        for m in s["misses"]:
            out(f"    {m}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
