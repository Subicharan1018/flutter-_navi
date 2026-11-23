"""
navivibe/catalog/mood_review.py   (moods-v3)
────────────────────────────────────────────
The owner is the judge. Builds a page of about 100 songs to mark, and scores labels against the marks.

    venv/bin/python -m navivibe.catalog.mood_review build review.html      # reads only
    venv/bin/python -m navivibe.catalog.mood_review score marks.json       # the file the page saves

The sample (seeded, so it can be rebuilt):
  random    40 songs drawn evenly from every labelled song: the ONLY part that estimates library accuracy
  conflict  45 songs whose current label contradicts Spotify's numbers
  changed   15 more songs the v3 rules would change
  pinned    songs a listener reported
The page shows them shuffled, without saying which group a song is in. The marks become the reference
set; the 54 songs the moods-v2 session judged by itself are not used.
"""

import json
import math
import os
import random
import sys

from navivibe.catalog import mood_fusion

PAGE = os.path.join(os.path.dirname(__file__), "mood_review_page.html")
PINNED = ["5jgSSq10B3IU1FI6SfR5KC"]          # Thalaivane (Kanguva)
MOODS = mood_fusion.MOODS + ["gym"]


def pick(rows: list, seed: int = 23, n_random: int = 40, n_conflict: int = 45, n_changed: int = 15, pinned=None) -> list:
    """rows: mood_relabel.table rows. Returns the chosen rows with a `group`, shuffled."""
    rnd = random.Random(seed)
    pinned = PINNED if pinned is None else pinned
    by = {r["id"]: r for r in rows if r["v2"]}
    left, out = sorted(by), []

    def take(group, pool, n):
        chosen = rnd.sample(pool, min(n, len(pool)))
        out.extend({**by[s], "group": group} for s in chosen)
        for s in chosen:
            left.remove(s)

    take("random", list(left), n_random)          # first, from everything: stays an even sample
    take("pinned", [s for s in left if s in pinned], len(pinned))
    take("conflict", [s for s in left if mood_fusion.disagreements(by[s]["v2"], by[s]["sound"])], n_conflict)
    take("changed", [s for s in left if by[s]["v2"] != by[s]["v3"]], n_changed)
    rnd.shuffle(out)
    return out


def items(picked: list, info: dict) -> list:
    """What the page needs per song. info: {id: {"title", "artist", "film"}}."""
    out = []
    for r in picked:
        s, i = r["sound"], info.get(r["id"]) or {}
        out.append({"id": r["id"], "group": r["group"], "title": i.get("title") or "", "artist": i.get("artist") or "",
                    "film": i.get("film") or "", "current": r["v2"], "proposed": r["v3"], "confidence": r["confidence"],
                    "why": [f"{m}: {w}" for m, w in r["dropped"]], "src": s.get("src"),
                    "energy": s.get("energy"), "valence": s.get("valence"), "tempo": s.get("tempo"),
                    "lyrics": bool(s.get("has_lyrics"))})
    return out


def build(songs: list) -> str:
    with open(PAGE, encoding="utf-8") as f:
        page = f.read()
    data = json.dumps({"songs": songs, "moods": MOODS}, ensure_ascii=False).replace("<", "\\u003c")
    return page.replace("__DATA__", data)


def wilson(k: int, n: int, z: float = 1.96) -> tuple:
    if n == 0:
        return (0.0, 1.0)
    p, d = k / n, 1 + z * z / n
    mid, half = (p + z * z / (2 * n)) / d, z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (round(max(0.0, mid - half), 3), round(min(1.0, mid + half), 3))


def score(marks: dict, labels: dict = None) -> dict:
    """marks: the page's saved file. A label set is right when the owner ticked it; `labels` ({id: moods})
    re-scores OTHER labels against the owner's correct moods: right = not empty and every mood is one of them."""
    out = {}
    songs = [s for s in marks.get("songs", []) if s.get("mark") and not s["mark"].get("skip")]
    for group in ("random", "conflict", "changed", "pinned"):
        g = [s for s in songs if s["group"] == group]
        res = {"marked": len(g)}
        for side in ("current", "proposed"):
            judged = [s for s in g if s["mark"].get(side) in ("right", "wrong") and s[side]]
            ok = sum(s["mark"][side] == "right" for s in judged)
            res[side] = {"judged": len(judged), "right": ok, "no_label": sum(not s[side] for s in g),
                         "range95": wilson(ok, len(judged))}
        if labels is not None:
            truth = [s for s in g if s["mark"].get("moods")]
            have = [s for s in truth if labels.get(s["id"])]
            ok = sum(set(labels[s["id"]]) <= set(s["mark"]["moods"]) for s in have)
            res["now"] = {"judged": len(have), "right": ok, "no_label": len(truth) - len(have), "range95": wilson(ok, len(have))}
        out[group] = res
    return out


def main(argv=None, out=print) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 2 or argv[0] not in ("build", "score"):
        out(__doc__)
        return 2
    from navivibe.catalog import mood_relabel, mood_tags, store
    if argv[0] == "build":
        songs = items(pick(mood_relabel.live_rows()), store.load_catalog())
        with open(argv[1], "w", encoding="utf-8") as f:
            f.write(build(songs))
        out(f"{len(songs)} songs -> {argv[1]}")
        return 0
    with open(argv[1], encoding="utf-8") as f:
        marks = json.load(f)
    for group, r in score(marks, mood_tags.load()).items():
        out(f"{group}: {r['marked']} marked" + ("   <- the estimate for the whole library" if group == "random" else ""))
        for side in ("current", "proposed", "now"):
            x = r[side]
            pct = f"{x['right'] / x['judged']:.0%}" if x["judged"] else "-"
            out(f"   {side:9} {x['right']} of {x['judged']} right ({pct}, 95% range {x['range95'][0]:.0%}-{x['range95'][1]:.0%}), {x['no_label']} without a label")
    return 0


if __name__ == "__main__":
    sys.exit(main())
