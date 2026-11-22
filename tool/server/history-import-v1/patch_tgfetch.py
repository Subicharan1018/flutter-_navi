"""history-import-v1: one anchored patch to tg-fetcher's api.py: the /history-import/* routes are registered
right after the /exportify ones (so exportify-v1 must be installed first: it holds the Wishlist).

usage: python patch_tgfetch.py <tg-fetcher root>
exit 0: patched or already patched; exit 2: a file is not the expected one (nothing is written).
"""
import sys
from pathlib import Path

P = [   # (relative file, old, new)
    ("tgfetch/api.py",
     "    exportify_api.register_routes(app, settings, conn, user)\n",
     "    exportify_api.register_routes(app, settings, conn, user)\n"
     "    from tgfetch import history_import_api          # history-import-v1: /history-import/*\n"
     "    history_import_api.register_routes(app, settings, conn, user)\n"),
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
            continue
        n = text.count(old)
        if n != 1:
            print(f"!! {rel}: expected text found {n} times (is exportify-v1 installed? not the version this was built on)")
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
