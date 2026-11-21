"""exportify-v1: three small anchored patches to tg-fetcher's existing files.

The feature lives in new files (tgfetch/exportify.py, tgfetch/exportify_api.py); these only hook it in:

  api.py     the /exportify/* routes are registered with the other routes
  worker.py  a batch whose link starts with "exportify:" is fetched by name, exactly like a
             YouTube list (youtube_batch.run): search the bot per song, score by title, version
             words, artist and length, take the best, never a guess
  db.py      those batches do not count against a user's cap of pasted playlist links

Needs server-fixes-v1 (youtube_batch.py, library_sweep.py, titles.py) to be installed first.

usage: python patch_tgfetch.py <tg-fetcher root>
exit 0: patched or already patched; exit 2: a file is not the expected one (nothing is written).
"""
import sys
from pathlib import Path

P = [   # (relative file, old, new)
    ("tgfetch/api.py",
     "    trending.register_routes(app, settings, conn)   # GET /trending, /trending/{chart}\n    return app",
     "    trending.register_routes(app, settings, conn)   # GET /trending, /trending/{chart}\n"
     "    from tgfetch import exportify_api               # exportify-v1: /exportify/*\n"
     "    exportify_api.register_routes(app, settings, conn, user)\n"
     "    return app"),
    ("tgfetch/worker.py",
     '        if youtube_list.is_youtube_link(b.get("link") or ""):\n',
     '        if youtube_list.is_youtube_link(b.get("link") or "") or \\\n'
     '                (b.get("link") or "").startswith("exportify:"):      # exportify-v1: by name, like YouTube\n'),
    ("tgfetch/db.py",
     "WHERE user=? AND link IS NOT NULL AND status IN ('queued', 'listing', 'running')\"",
     "WHERE user=? AND link IS NOT NULL AND link NOT LIKE 'exportify:%' \"\n"
     "        \"AND status IN ('queued', 'listing', 'running')\""),
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
