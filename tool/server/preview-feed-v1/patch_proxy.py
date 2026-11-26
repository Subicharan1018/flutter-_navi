"""preview-feed-v1: patch the shuffle server so it serves /preview-feed.

  server.py   registers navivibe/preview_feed.py right after the Weekly Exploration routes (it needs weekly-exploration-v1's
              line as its anchor), with fetch_access.has_access as the gate

Every patch is an exact text match: a file already patched is left alone, a file that is not the version this package was
built on stops the run before anything is written.

usage: python patch_proxy.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
"""
import sys
from pathlib import Path

ANCHOR = "register_weekly_routes(app, require_auth, lambda: _v3_engine())\n"
PATCHES = [   # (file, old (exactly once), new)
    ("server.py", ANCHOR,
     ANCHOR + "\n"
     "# preview-feed-v1: Swipe to fetch, 30 s previews of songs not in the library (navivibe/preview_feed.py)\n"
     "from navivibe import fetch_access as _pf_access  # noqa: E402\n"
     "from navivibe.preview_feed import register_preview_feed_routes  # noqa: E402\n"
     "register_preview_feed_routes(app, require_auth, _pf_access.has_access)\n"),
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
            print("!! not the version this package was built on (is weekly-exploration-v1 installed?): nothing written")
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
