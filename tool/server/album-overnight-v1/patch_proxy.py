"""album-overnight-v1: patch the shuffle server so it serves /exportify/album-overnight* (and forwards to tg-fetcher).

  server.py      registers navivibe/album_overnight_proxy.py after exportify's routes

Nothing else: the paths are under /exportify/, which hardening.py already counts as the "fetch" route class
and the 12 MB body rule only raises a limit. Every patch is an exact text match: a file already patched is
left alone, a file that is not the version this package was built on stops the run before anything is written.
Needs exportify-v1 (its line is the anchor). Order-independent with weekly-exploration-v1 (same anchor line).

usage: python patch_proxy.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
"""
import sys
from pathlib import Path

PATCHES = [   # (file, anchor (exactly once), text added after it, marker that says it is done)
    ("server.py",
     "register_exportify_routes(app, require_auth)\n",
     "\n"
     "# album-overnight-v1: Complete the album overnight (navivibe/album_overnight_proxy.py)\n"
     "from navivibe.album_overnight_proxy import register_album_overnight_routes  # noqa: E402\n"
     "register_album_overnight_routes(app, require_auth)\n",
     "register_album_overnight_routes(app, require_auth)"),
]


def main(root: str) -> int:
    base = Path(root)
    texts, done = {}, []
    for rel, old, new, marker in PATCHES:
        p = base / rel
        if not p.exists():
            print(f"!! {p} not found")
            return 2
        texts.setdefault(rel, p.read_text(encoding="utf-8"))
    for rel, old, new, marker in PATCHES:
        text = texts[rel]
        if marker in text:
            continue
        if text.count(old) != 1:
            print(f"!! {rel}: expected text found {text.count(old)} times: {old.strip().splitlines()[0][:70]!r}")
            print("!! not the version this package was built on: nothing written")
            return 2
        texts[rel] = text.replace(old, old + new)
        done.append(rel)
    for rel in dict.fromkeys(done):
        (base / rel).write_text(texts[rel], encoding="utf-8")
    print(f"patched: {', '.join(dict.fromkeys(done)) or 'nothing (already patched)'}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
