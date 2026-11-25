"""import-limit-v1: the number of Exportify imports a user keeps is a setting (EXPORTIFY_MAX_IMPORTS, default 20).

prune_old() deletes a user's OLDEST imports (and their songs) past the limit every time they import something, so a user who
has loaded 62 playlists would lose 42 of them on the next import, including older ones with fetched songs. Anchored patch to
tgfetch/exportify.py; the anchor must be found exactly once, or nothing is written.
usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not the expected file.
"""
import sys
from pathlib import Path

EX = "tgfetch/exportify.py"

P = [
    (EX,
     "MAX_IMPORTS = 20                 # per user\n",
     "MAX_IMPORTS = max(1, int(os.getenv(\"EXPORTIFY_MAX_IMPORTS\", \"20\")))   # per user (import-limit-v1: a setting)\n"),
]


def main(root: str) -> int:
    base = Path(root)
    texts: dict[str, str] = {}
    for rel, old, new in P:
        text = texts.get(rel)
        if text is None:
            text = (base / rel).read_text(encoding="utf-8")
        if new in text:
            texts[rel] = text
            continue
        if text.count(old) != 1:
            print(f"!! {rel}: expected anchor not found exactly once:\n{old[:140]!r}")
            return 2
        texts[rel] = text.replace(old, new)
    for rel, text in texts.items():
        (base / rel).write_text(text, encoding="utf-8")
    print("import-limit-v1: exportify.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
