"""flow-v2: hooks in navivibe/flow.py for the sound-aware Flow in navivibe/flow_v2.py.

Exact-text edits: when the file is not the text this package was made for, NOTHING is written and the exit
code is 2 (a loud failure, never a guess). Every edit is marked `# flow-v2`, so a file that already has them
is left as it is (exit 0).

With FLOW_V2 unset or `off` the patched flow.py gives the same answers as before (a test checks it).

usage: python patch_flow.py <flow.py>
"""
import sys

MARK = "# flow-v2"

EDITS = [
    (   # 1. the module
        "from navivibe import discover, explore, flow_prefs, mood_overrides, taste_exclusions\n",
        "from navivibe import discover, explore, flow_prefs, flow_v2, mood_overrides, taste_exclusions  # flow-v2\n",
    ),
    (   # 2. the ordering step, defined before next_batch
        "def next_batch(engine,",
        '''def _v2_order(v2, items: list, cat, emb) -> list:  # flow-v2
    """shadow: log how v2 would order these songs and return them as they are. on: return v2's order."""
    kinds = {p["navidrome_id"]: p.get("kind") for p in items}
    old = [p["navidrome_id"] for p in items]
    try:
        new_items = v2.sequence(items, kinds, emb["audio"], cat.index)
        new = [p["navidrome_id"] for p in new_items]
        flow_v2.record(v2, old, new, kinds, emb["audio"], cat.index)
        if not v2.on:
            return items
        v2.explain(new_items, kinds)
        return new_items
    except Exception as e:                                   # old order is served, the reason is logged and returned
        import logging
        logging.getLogger("navivibe.flow").exception("flow v2 ordering failed, serving the old order")
        v2.error = f"{type(e).__name__}: {e}"
        return items


def next_batch(engine,''',
    ),
    (   # 3. sound numbers from Spotify, the run
        "    taste, events, meta, moods, emb = discover.user_context(engine, user, now)\n    cat = engine.cat\n",
        "    taste, events, meta, moods, emb = discover.user_context(engine, user, now)\n"
        "    cat = engine.cat\n"
        "    v2 = flow_v2.begin(user, mood, taste, meta, now, session, seen, count)  # flow-v2\n"
        "    if v2 is not None:\n"
        "        v2.start_labels(mood_tags.load(), now)\n"
        "        meta = v2.meta                                     # Spotify's numbers where there are any (on)\n",
    ),
    (   # 4. the chip: songs whose real sound is far from the chip are dropped
        "        ids = [s for s in ids if s not in not_this\n"
        "               and mood_tags.flow_fit(meta.get(s) or {}, moods.get(s) or [], mood)]\n",
        "        ids = [s for s in ids if s not in not_this\n"
        "               and mood_tags.flow_fit(meta.get(s) or {}, moods.get(s) or [], mood)]\n"
        "        if v2 is not None:                                 # flow-v2\n"
        "            ids = v2.keep(ids, count)\n",
    ),
    (   # 5. scores: chip fit, arc, skip history
        "    def tune(cands: list, base: np.ndarray) -> np.ndarray:\n",
        "    def tune(cands: list, base: np.ndarray, familiar: bool = False) -> np.ndarray:  # flow-v2\n",
    ),
    (
        "        return score + NOISE * rng.gumbel(size=len(cands))\n",
        "        if v2 is not None:                                 # flow-v2\n"
        "            score = score + v2.bonus(cands, familiar)\n"
        "        return score + NOISE * rng.gumbel(size=len(cands))\n",
    ),
    (
        "    fam_scores = tune(fam, _fam_base(fam, taste, last_play, now)) if fam else np.array([])\n",
        "    fam_scores = tune(fam, _fam_base(fam, taste, last_play, now), True) if fam else np.array([])  # flow-v2\n",
    ),
    (   # 5b. no artist fills a batch: a first pass with an artist cap, a second pass fills any gap
        "    def top(cands, scores, n, cap):\n"
        "        picked, per = [], {}\n"
        "        for i in np.argsort(-scores, kind=\"stable\"):\n"
        "            c = (composer_tokens(meta[cands[i]]) or [\"?\"])[0]\n"
        "            if per.get(c, 0) >= cap:\n"
        "                continue\n"
        "            per[c] = per.get(c, 0) + 1\n"
        "            picked.append(cands[i])\n"
        "            if len(picked) >= n:\n"
        "                break\n"
        "        return picked\n",
        "    def top(cands, scores, n, cap):\n"
        "        picked, per = [], {}\n"
        "        order = np.argsort(-scores, kind=\"stable\")\n"
        "        for strict in ((True, False) if v2 is not None and v2.on else (False,)):   # flow-v2\n"
        "            for i in order:\n"
        "                if len(picked) >= n:\n"
        "                    break\n"
        "                if cands[i] in picked:\n"
        "                    continue\n"
        "                c = (composer_tokens(meta[cands[i]]) or [\"?\"])[0]\n"
        "                if per.get(c, 0) >= cap or (strict and not v2.artist_room(cands[i])):\n"
        "                    continue\n"
        "                per[c] = per.get(c, 0) + 1\n"
        "                picked.append(cands[i])\n"
        "                if v2 is not None and v2.on:\n"
        "                    v2.artist_take(cands[i])\n"
        "        return picked\n",
    ),
    (   # 6. the order of the batch
        "    items = _spaced([familiar, fresh, explored])\n",
        "    items = _spaced([familiar, fresh, explored])\n"
        "    if v2 is not None:                                     # flow-v2\n"
        "        items = _v2_order(v2, items, cat, emb)\n",
    ),
    (   # 6b. two fallbacks that were silent now say why in the log (same answers as before)
        "    except Exception:                                      # no state file: Flow still works, less carefully\n"
        "        st = None\n",
        "    except Exception:                                      # no state file: Flow still works, less carefully\n"
        "        import logging  # flow-v2\n"
        "        logging.getLogger(\"navivibe.flow\").exception(\"flow state unreadable: no cooldown, no per-session memory\")\n"
        "        st = None\n",
    ),
    (
        "    except Exception:\n"
        "        return set()\n",
        "    except Exception:\n"
        "        import logging  # flow-v2\n"
        "        logging.getLogger(\"navivibe.flow\").exception(\"flow cooldown could not be read: nothing rests\")\n"
        "        return set()\n",
    ),
    (   # 7. the answer
        '    return {"items": items, "count": len(items), "mood": mood, "fresh_share": round(share, 2),\n',
        '    out = {"items": items, "count": len(items), "mood": mood, "fresh_share": round(share, 2),\n',
    ),
    (
        '            "languages": sorted(langs), "explore_on": prefs["explore"]}\n',
        '            "languages": sorted(langs), "explore_on": prefs["explore"]}\n'
        "    if v2 is not None:                                     # flow-v2\n"
        '        out["flow_v2"] = v2.summary()\n'
        "    return out\n",
    ),
]

# test_flow.py: the exact key set of a /flow/next answer is not pinned there, so no test edits are needed.


def apply(text: str) -> str:
    """The patched text, the same text when it is already patched; raises ValueError when it is not the expected file."""
    if MARK in text:
        return text
    for old, new in EDITS:
        if text.count(old) != 1:
            raise ValueError(f"expected text not found exactly once:\n{old!r}")
        text = text.replace(old, new)
    return text


def main(argv: list) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 1
    path = argv[1]
    with open(path, encoding="utf-8") as f:
        text = f.read()
    try:
        out = apply(text)
    except ValueError as e:
        print(f"!! {path} is not the flow.py this package was made for; nothing was changed.\n{e}")
        return 2
    if out != text:
        with open(path + ".tmp", "w", encoding="utf-8", newline="") as f:
            f.write(out)
        import os
        os.replace(path + ".tmp", path)
        print(f"patched {path}")
    else:
        print(f"{path}: already patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
