"""spotify-history-import-v1: patch the shuffle server so it forwards /spotify-import/* to tg-fetcher.

  server.py      registers navivibe/spotify_import_proxy.py after the /history-import routes, and gives
                 /spotify-import a 1 MB body cap (a page of 1,000 plays is about 150 KB; the default is 512 KB)
  hardening.py   a rate class "spotify_import" (burst 20, 1 a second: a 50 MB export is ~300 pages) so the import
                 is not held to the 12-a-minute "fetch_write" class

Every patch is an exact text match: a file already patched is left alone, a file that is not the version
this package was built on stops the run before anything is written.

usage: python patch_proxy.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
"""
import sys
from pathlib import Path

PATCHES = [   # (file, old (exactly once), new, marker that says it is done)
    ("server.py",
     "register_history_import_routes(app, require_auth)\n",
     "register_history_import_routes(app, require_auth)\n"
     "\n"
     "# spotify-history-import-v1: import a Spotify Extended Streaming History (navivibe/spotify_import_proxy.py)\n"
     "from navivibe.spotify_import_proxy import register_spotify_import_routes  # noqa: E402\n"
     "register_spotify_import_routes(app, require_auth)\n",
     "register_spotify_import_routes(app, require_auth)"),
    ("server.py",
     '    ("/exportify", 12 * 1024 * 1024),',
     '    ("/spotify-import", 1024 * 1024),        # spotify-history-import-v1: a page of cleaned plays\n'
     '    ("/exportify", 12 * 1024 * 1024),',
     '("/spotify-import", 1024 * 1024)'),
    ("hardening.py",
     '    "fetch_write": (12, 12 / 60),\n',
     '    "fetch_write": (12, 12 / 60),\n'
     '    "spotify_import": (20, 1.0),     # spotify-history-import-v1: pages of a Spotify export, ~1 a second\n',
     '"spotify_import": (20, 1.0)'),
    ("hardening.py",
     '    if path.startswith("/fetch") or path.startswith("/exportify")',
     '    if path.startswith("/spotify-import"):          # spotify-history-import-v1\n'
     '        return "spotify_import"\n'
     '    if path.startswith("/fetch") or path.startswith("/exportify")',
     'return "spotify_import"'),
]


def main(root: str) -> int:
    base = Path(root)
    texts, done = {}, []
    for rel, old, new, mark in PATCHES:
        p = base / rel
        if not p.exists():
            print(f"!! {p} not found")
            return 2
        texts.setdefault(rel, p.read_text(encoding="utf-8"))
    for rel, old, new, mark in PATCHES:
        text = texts[rel]
        if mark in text:
            continue
        if text.count(old) != 1:
            print(f"!! {rel}: expected text found {text.count(old)} times: {old.strip().splitlines()[0][:70]!r}")
            print("!! not the version this package was built on (is history-import-v1 installed?): nothing written")
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
