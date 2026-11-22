"""history-import-v1: patch the shuffle server so it forwards /history-import/* to tg-fetcher.

  server.py      registers navivibe/history_import_proxy.py after the /exportify routes
  hardening.py   /history-import counts as the "fetch" route class (the one /exportify uses)

Every patch is an exact text match: a file already patched is left alone, a file that is not the version
this package was built on stops the run before anything is written.

usage: python patch_proxy.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
"""
import sys
from pathlib import Path

PATCHES = [   # (file, old (exactly once), new, marker that says it is done)
    ("server.py",
     "register_exportify_routes(app, require_auth)\n",
     "register_exportify_routes(app, require_auth)\n"
     "\n"
     "# history-import-v1: import ListenBrainz / Last.fm history (navivibe/history_import_proxy.py)\n"
     "from navivibe.history_import_proxy import register_history_import_routes  # noqa: E402\n"
     "register_history_import_routes(app, require_auth)\n",
     "register_history_import_routes(app, require_auth)"),
    ("hardening.py",
     'path.startswith("/exportify")',
     'path.startswith("/exportify") or path.startswith("/history-import")',
     'path.startswith("/history-import")'),
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
            print("!! not the version this package was built on (is exportify-v1 installed?): nothing written")
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
