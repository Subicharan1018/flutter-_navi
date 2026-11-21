"""lyrics-v1: patch the shuffle server so it serves GET /lyrics/fetch (see README.md).

Every patch is an exact text match: a file already patched (it holds the marker) is left alone, a
file that is not the version this package was built on stops the run before anything is written.

usage: python patch_lyrics_v1.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
exit 0: patched or already patched; exit 2: not the expected file (nothing written).
"""
import sys
from pathlib import Path

MARKER = "lyrics-v1"

# (file, text that must appear exactly once, text that replaces it)
PATCHES = [
    ("server.py",
     "register_pair_routes(app, require_auth)\n",
     "register_pair_routes(app, require_auth)\n"
     "\n"
     "# lyrics-v1: GET /lyrics/fetch, synced lyrics from lrc.red / BetterLyrics (navivibe/lyrics_proxy.py)\n"
     "from navivibe.lyrics_proxy import register_lyrics_proxy_routes  # noqa: E402\n"
     "register_lyrics_proxy_routes(app, require_auth)\n"),
]


def main(root: str) -> int:
    base = Path(root)
    done = []
    texts = {}
    for rel, old, new in PATCHES:
        p = base / rel
        if not p.exists():
            print(f"!! {p} not found")
            return 2
        texts.setdefault(rel, p.read_text(encoding="utf-8"))
    for rel, old, new in PATCHES:
        text = texts[rel]
        if MARKER in text:
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
