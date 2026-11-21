"""weekly-exploration-v1: two small anchored patches to tg-fetcher's existing files.

The feature lives in new files (tgfetch/weekly_exploration.py, tgfetch/weekly_exploration_api.py); these only hook it in:

  api.py        the /weekly/* routes are registered with the other routes (after exportify's)
  exportify.py  the timer's pass (`python -m tgfetch.exportify tick`) first lets Keeps that were over the
                weekly cap go to the queue and expires old picks. Fetching itself stays `tick()`: the same
                night window, per-night cap, disk floor and one-batch-at-a-time rule. No second scheduler.

Needs exportify-v1 (and server-fixes-v1, which it needs) to be installed first.

usage: python patch_tgfetch.py <tg-fetcher root>
exit 0: patched or already patched; exit 2: a file is not the expected one (nothing is written).
"""
import sys
from pathlib import Path

P = [   # (relative file, old (exactly once), new)
    ("tgfetch/api.py",
     "    exportify_api.register_routes(app, settings, conn, user)\n    return app",
     "    exportify_api.register_routes(app, settings, conn, user)\n"
     "    from tgfetch import weekly_exploration_api     # weekly-exploration-v1: /weekly/*\n"
     "    weekly_exploration_api.register_routes(app, settings, conn, user)\n"
     "    return app"),
    ("tgfetch/exportify.py",
     "    ensure_schema(conn)\n"
     "    n = conn.execute(\"SELECT COUNT(*) FROM exportify_plans WHERE status IN ('active','paused_disk')\").fetchone()[0]\n",
     "    ensure_schema(conn)\n"
     "    try:                                        # weekly-exploration-v1: Keeps over the weekly cap, old picks\n"
     "        from tgfetch import weekly_exploration as _wx\n"
     "        _wx.ensure_schema(conn)\n"
     "        _wx.expire(conn)\n"
     "        _wx.release_waiting(conn)\n"
     "    except Exception as e:                      # bookkeeping: never stops the Spotify wishlist\n"
     "        log.warning(\"weekly: pass failed (%s)\", type(e).__name__)\n"
     "    n = conn.execute(\"SELECT COUNT(*) FROM exportify_plans WHERE status IN ('active','paused_disk')\").fetchone()[0]\n"),
]


def main(root: str) -> int:
    base = Path(root)
    texts, todo = {}, []
    for rel, old, new in P:
        path = base / rel
        if rel not in texts:
            if not path.exists():
                print(f"!! {path} not found")
                return 2
            texts[rel] = path.read_text(encoding="utf-8")
        text = texts[rel]
        if new in text:
            continue                                   # already patched
        n = text.count(old)
        if n != 1:
            print(f"!! {rel}: expected text found {n} times (not the version this package was built on)")
            print("   first line: " + old.strip().splitlines()[0][:100])
            return 2
        texts[rel] = text.replace(old, new)
        todo.append(rel)
    for rel in dict.fromkeys(todo):
        (base / rel).write_text(texts[rel], encoding="utf-8")
    print(f"patched: {', '.join(dict.fromkeys(todo)) or 'nothing (already patched)'}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
