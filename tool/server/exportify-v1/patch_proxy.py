"""exportify-v1: patch the shuffle server so it forwards /exportify/* to tg-fetcher.

  server.py      registers navivibe/exportify_proxy.py and allows a 12 MB body on /exportify
  hardening.py   /exportify counts as the "fetch" route class (same rate limits as /fetch)

Every patch is an exact text match: a file already patched is left alone, a file that is not
the version this package was built on stops the run before anything is written.

usage: python patch_proxy.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
"""
import sys
from pathlib import Path

PATCHES = [   # (file, old (exactly once), new)
    ("server.py",
     '    ("/fetch", 16 * 1024),\n',
     '    ("/fetch", 16 * 1024),\n'
     '    ("/exportify", 12 * 1024 * 1024),        # exportify-v1: an Exportify CSV (JSON-wrapped)\n'),
    ("server.py",
     "register_pair_routes(app, require_auth)\n",
     "register_pair_routes(app, require_auth)\n"
     "\n"
     "# exportify-v1: Import a Spotify playlist from an Exportify CSV (navivibe/exportify_proxy.py)\n"
     "from navivibe.exportify_proxy import register_exportify_routes  # noqa: E402\n"
     "register_exportify_routes(app, require_auth)\n"),
    ("hardening.py",
     '    if path.startswith("/fetch"):\n',
     '    if path.startswith("/fetch") or path.startswith("/exportify"):      # exportify-v1\n'),
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
