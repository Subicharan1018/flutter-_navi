"""weekly-exploration-v1: patch the shuffle server so it serves /weekly/exploration* (and forwards to tg-fetcher).

  server.py      registers navivibe/weekly_exploration.py (it is given `_v3_engine` to read the listener's taste)
  hardening.py   /weekly/exploration counts as the "fetch" route class (same rate limits as /fetch)

Every patch is an exact text match: a file already patched is left alone, a file that is not
the version this package was built on stops the run before anything is written.
Needs exportify-v1 (its lines are the anchors).

usage: python patch_proxy.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
"""
import sys
from pathlib import Path

PATCHES = [   # (file, old (exactly once), new)
    ("server.py",
     "register_exportify_routes(app, require_auth)\n",
     "register_exportify_routes(app, require_auth)\n"
     "\n"
     "# weekly-exploration-v1: Weekly Exploration (navivibe/weekly_exploration.py)\n"
     "from navivibe.weekly_exploration import register_weekly_routes  # noqa: E402\n"
     "register_weekly_routes(app, require_auth, lambda: _v3_engine())\n"),
    ("hardening.py",
     '    if path.startswith("/fetch") or path.startswith("/exportify"):      # exportify-v1\n',
     '    if path.startswith("/fetch") or path.startswith("/exportify") or path.startswith("/weekly/exploration"):'
     '      # exportify-v1, weekly-exploration-v1\n'),
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
        if new in text:
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
