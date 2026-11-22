"""rotation-v1: patch the shuffle server so rested and out-of-season songs are left out, and /rotation* exists.

  taste_exclusions.py  blocked_ids() also returns rotation.hidden_ids(); the old body becomes _excluded_ids().
                       Discover, Weekly mix, Flow and Smart Shuffle all ask blocked_ids, so all of them obey.
  discover.py          user_context() (shared by Discover, Weekly mix and Flow) looks at the listener's plays
                       every few hours: rests worn-out songs, finds seasonal ones.
  server.py            registers the /rotation* routes (navivibe/rotation.py).

Every patch is an exact text match: a file already patched is left alone, a file that is not
the version this package was built on stops the run before anything is written.

usage: python patch_server.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
"""
import sys
from pathlib import Path

PATCHES = [   # (file, old (exactly once), new)
    ("taste_exclusions.py",
     'def blocked_ids(user: str, meta: dict, entries: list = None) -> set:\n'
     '    """Catalog song ids the listener has excluded, directly or through a name."""\n',
     'def blocked_ids(user: str, meta: dict, entries: list = None) -> set:  # rotation-v1\n'
     '    """Catalog song ids the listener has excluded, directly or through a name, plus the songs that are\n'
     '    resting or out of season for them (navivibe/rotation.py)."""\n'
     '    out = _excluded_ids(user, meta, entries)\n'
     '    try:\n'
     '        from navivibe import rotation\n'
     '        out = out | rotation.hidden_ids(user, meta)\n'
     '    except Exception:                                  # never let a rotation fault stop a recommendation\n'
     '        import logging\n'
     '        logging.getLogger("navivibe.rotation").exception("rotation skipped for %s", user)\n'
     '    return out\n'
     '\n'
     '\n'
     'def _excluded_ids(user: str, meta: dict, entries: list = None) -> set:\n'
     '    """Catalog song ids the listener has excluded, directly or through a name."""\n'),
    ("discover.py",
     "    return taste, events, meta, moods, emb\n",
     "    try:                                                # rotation-v1: rest worn-out songs, find seasonal ones\n"
     "        from navivibe import rotation\n"
     "        rotation.refresh(user, events, meta, now)\n"
     "    except Exception:\n"
     "        import logging\n"
     '        logging.getLogger("navivibe.rotation").exception("rotation refresh skipped for %s", user)\n'
     "    return taste, events, meta, moods, emb\n"),
    ("server.py",
     "register_pair_routes(app, require_auth)\n",
     "register_pair_routes(app, require_auth)\n"
     "\n"
     "# rotation-v1: rest a song, seasonal songs, back in rotation (navivibe/rotation.py)\n"
     "from navivibe.rotation import register_rotation_routes  # noqa: E402\n"
     "register_rotation_routes(app, require_auth, lambda: _v3_engine())\n"),
]


def main(root: str) -> int:
    base = Path(root)
    texts, done = {}, []
    for rel, old, new in PATCHES:
        p = base / rel
        if not p.exists():
            print(f"!! {p} not found")
            return 2
        texts.setdefault(rel, p.read_text(encoding="utf-8"))
    for rel, old, new in PATCHES:
        text = texts[rel]
        if "rotation-v1" in new and new in text:
            continue
        if text.count(old) != 1:
            print(f"!! {rel}: expected text found {text.count(old)} times: {old.strip().splitlines()[0][:70]!r}")
            print("!! not the version this package was built on: nothing written")
            return 2
        texts[rel] = text.replace(old, new)
        done.append(rel)
    for rel in dict.fromkeys(done):
        (base / rel).write_text(texts[rel], encoding="utf-8")
    print(f"patched: {', '.join(dict.fromkeys(done)) or 'nothing (already patched)'}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
