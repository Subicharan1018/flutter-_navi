"""flow-v1: Flow stops serving the same songs in every session.

What changes in navivibe/flow.py (exact-match edits; nothing is written if the file
is not the expected one):
  * a song served to a listener (any session) is off limits for COOLDOWN_S (5 days);
    when that leaves too few familiar songs the cooldown relaxes, it never returns nothing;
  * the "last plays" window grows with the library (50 .. 150 songs);
  * familiar songs are ranked by a blend of how much you play them and how long since
    you last did, so play count alone no longer decides.

usage: python patch_flow.py <flow.py>
exit 0: patched or already patched; exit 2: not the expected file (nothing written).
"""
import sys

MARK = "# flow-v1"

EDITS = [
    (
        "RECENT_PLAYS = 50\n",
        "RECENT_PLAYS = 50\n"
        "RECENT_PLAYS_MAX = 150                                  # flow-v1\n"
        "COOLDOWN_S = 5 * 86400                                  # flow-v1: a served song rests this long\n"
        "RECENCY_W = 0.5                                         # flow-v1: weight of time-since-last-play\n",
    ),
    (
        "def next_batch(engine,",
        '''def recent_n(taste) -> int:  # flow-v1
    """How many of the last plays to keep out: a third of what you have played, 50 to 150."""
    return min(RECENT_PLAYS_MAX, max(RECENT_PLAYS, len(taste.play) // 3))


def cooled(st, user: str, now: float) -> set:  # flow-v1
    """Songs Flow served this listener in the last COOLDOWN_S, in any session."""
    try:
        with st._db() as c:
            return {r["song"] for r in c.execute("SELECT DISTINCT song FROM flow_seen WHERE user=? AND ts>?",
                                                 (user, now - COOLDOWN_S))}
    except Exception:
        return set()


def _fam_base(songs: list, taste, last_play: dict, now: float) -> np.ndarray:  # flow-v1
    """z(log plays) blended with z(log days since last play): favourites first, but the ones
    you have not heard for a while get their turn."""
    plays = discover._z(np.log1p(np.array([taste.play[s] for s in songs])))
    days = discover._z(np.log1p(np.array([max(0.0, now - last_play.get(s, 0.0)) / 86400 for s in songs])))
    return (1 - RECENCY_W) * plays + RECENCY_W * days


def next_batch(engine,''',
    ),
    (
        "               | set(recent_plays(mine, user, now)) | {f[\"id\"] for f in feedback})\n    known = taste.known\n",
        "               | set(recent_plays(mine, user, now, recent_n(taste))) | {f[\"id\"] for f in feedback})\n"
        "    known = taste.known\n"
        "    hard = set(blocked)                                    # flow-v1\n"
        "    cool = cooled(st, user, now) if st is not None else set()\n"
        "    blocked = blocked | cool\n",
    ),
    (
        "    blocked = blocked | ex_ids\n",
        "    blocked = blocked | ex_ids\n    hard = hard | ex_ids\n",
    ),
    (
        """    fam = [s for s, v in taste.play.items()
           if v > 0 and s in cat.index and s in meta and s in pool and s not in blocked
           and last_play.get(s, 0.0) < recent_cut
           and taste.skip.get(s, 0.0) / (taste.skip.get(s, 0.0) + v) < discover.NEG_MIN_RATE]
    fam_scores = tune(fam, np.log1p(np.array([taste.play[s] for s in fam]))) if fam else np.array([])
""",
        """    def _fam(banned: set) -> list:                          # flow-v1
        return [s for s, v in taste.play.items()
                if v > 0 and s in cat.index and s in meta and s in pool and s not in banned
                and last_play.get(s, 0.0) < recent_cut
                and taste.skip.get(s, 0.0) / (taste.skip.get(s, 0.0) + v) < discover.NEG_MIN_RATE]

    fam = _fam(hard | cool)
    if cool and len(fam) < count:                           # a small pool relaxes the cooldown
        fam = _fam(hard)
    fam_scores = tune(fam, _fam_base(fam, taste, last_play, now)) if fam else np.array([])
""",
    ),
]


TEST_OLD = (
    '    assert {i["navidrome_id"] for i in other["items"]} == {i["navidrome_id"] for i in a["items"]}'
    "   # a new session starts fresh\n"
)
TEST_NEW = (
    '    assert not {i["navidrome_id"] for i in other["items"]} & {i["navidrome_id"] for i in a["items"]}'
    "   # flow-v1: a new session no longer replays the last one\n"
)


def patch_test(path: str) -> int:
    """The one old test that pinned 'a new session starts fresh' now pins the opposite."""
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if TEST_NEW in text:
        return 0
    if text.count(TEST_OLD) != 1:
        print(f"!! {path}: expected test line not found; nothing changed.")
        return 2
    with open(path, "w", encoding="utf-8") as f:
        f.write(text.replace(TEST_OLD, TEST_NEW))
    print(f"   {path}: patched")
    return 0


def main(path: str) -> int:
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if MARK in text:
        print(f"   {path}: already")
        return 0
    for old, _ in EDITS:
        if text.count(old) != 1:
            print(f"!! {path}: not the flow.py this patch expects; nothing changed.")
            return 2
    for old, new in EDITS:
        text = text.replace(old, new)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"   {path}: patched")
    return 0


if __name__ == "__main__":
    # patch_flow.py <flow.py>                 -> the code
    # patch_flow.py --test <tests/test_flow.py> -> the one test line
    sys.exit(patch_test(sys.argv[2]) if sys.argv[1] == "--test" else main(sys.argv[1]))
