"""album-overnight-v1: two small anchored patches to tg-fetcher's existing files.

The feature lives in new files (tgfetch/album_overnight.py, tgfetch/album_overnight_api.py); these only hook it in:

  api.py        the /album-overnight/* routes are registered with the other routes
  exportify.py  the timer's pass (`python -m tgfetch.exportify tick`) first looks at songs that just landed and
                queues their albums' missing tracks. Fetching itself stays `tick()`: the same night window,
                per-night cap, disk floor and one-batch-at-a-time rule. No second scheduler.

Needs exportify-v1 (and server-fixes-v1, which it needs). Order-independent with weekly-exploration-v1.

usage: python patch_tgfetch.py <tg-fetcher root>
exit 0: patched or already patched; exit 2: a file is not the expected one (nothing is written).
"""
import sys
from pathlib import Path

# (relative file, anchor (exactly once), text added next to it, marker that says it is done, after?)
# Where the text goes keeps weekly-exploration-v1's own anchors intact, so the two install in either order.
P = [
    ("tgfetch/api.py",
     "    exportify_api.register_routes(app, settings, conn, user)\n",
     "    from tgfetch import album_overnight_api        # album-overnight-v1: /album-overnight/*\n"
     "    album_overnight_api.register_routes(app, settings, conn, user)\n",
     "album_overnight_api.register_routes", False),
    ("tgfetch/exportify.py",
     "    n = conn.execute(\"SELECT COUNT(*) FROM exportify_plans WHERE status IN ('active','paused_disk')\").fetchone()[0]\n",
     "    from tgfetch import album_overnight as _ao   # album-overnight-v1: queue the albums of songs that just landed\n"
     "    _ao.run_pass(conn, settings)                 # never raises; fetching stays tick()\n",
     "_ao.run_pass", True),
]


def main(root: str) -> int:
    base = Path(root)
    texts, todo = {}, []
    for rel, old, new, marker, after in P:
        path = base / rel
        if rel not in texts:
            if not path.exists():
                print(f"!! {path} not found")
                return 2
            texts[rel] = path.read_text(encoding="utf-8")
        text = texts[rel]
        if marker in text:
            continue                                   # already patched
        n = text.count(old)
        if n != 1:
            print(f"!! {rel}: expected text found {n} times (not the version this package was built on)")
            print("   first line: " + old.strip().splitlines()[0][:100])
            return 2
        texts[rel] = text.replace(old, old + new if after else new + old)
        todo.append(rel)
    for rel in dict.fromkeys(todo):
        (base / rel).write_text(texts[rel], encoding="utf-8")
    print(f"patched: {', '.join(dict.fromkeys(todo)) or 'nothing (already patched)'}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
