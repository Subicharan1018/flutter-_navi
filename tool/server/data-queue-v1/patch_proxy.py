"""data-queue-v1: patch the shuffle server so it serves the admin's data queue.

  server.py   registers navivibe/data_queue.py (admin only, checked against ADMIN_USERS) and allows a 12 MB body on
              /data-queue (an Exportify CSV, JSON-wrapped; the route itself caps the file at 8 MB / 20,000 rows)

Every patch is an exact text match: a file already patched is left alone, a file that is not the version this
package was built on stops the run before anything is written.

usage: python patch_proxy.py <navivibe dir>      (e.g. /opt/shuffle-server/navivibe)
"""
import sys
from pathlib import Path

PATCHES = [   # (file, old (exactly once), new)
    ("server.py",
     '    ("/intent", 4 * 1024),\n',
     '    ("/data-queue", 12 * 1024 * 1024),        # data-queue-v1: an Exportify CSV (JSON-wrapped)\n'
     '    ("/intent", 4 * 1024),\n'),
    ("server.py",
     "register_mood_editor_routes(app, require_auth, lambda: ADMIN_USERS, lambda: NAVIDROME_URL)\n",
     "register_mood_editor_routes(app, require_auth, lambda: ADMIN_USERS, lambda: NAVIDROME_URL)\n"
     "\n"
     "# data-queue-v1: the admin's weekly data queue (navivibe/data_queue.py)\n"
     "from navivibe.data_queue import register_data_queue_routes  # noqa: E402\n"
     "register_data_queue_routes(app, require_auth, lambda: ADMIN_USERS)\n"),
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
