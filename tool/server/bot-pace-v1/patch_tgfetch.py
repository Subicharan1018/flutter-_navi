"""bot-pace-v1: space the bot's inline searches out and try fewer spellings per song.

Anchored patches to tgfetch/sources/deezload.py and tgfetch/youtube_batch.py; each anchor must be found exactly once, or
nothing is written. usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not expected.
"""
import sys
from pathlib import Path

DZ = "tgfetch/sources/deezload.py"
YB = "tgfetch/youtube_batch.py"

P = [
    (DZ,
     "        extra = {\"offset\": offset} if offset else {}\n"
     "        results = await self._call(self.client.inline_query,",
     "        extra = {\"offset\": offset} if offset else {}\n"
     "        from tgfetch import bot_pace            # bot-pace-v1: not back to back\n"
     "        await bot_pace.wait()\n"
     "        results = await self._call(self.client.inline_query,"),
    (YB,
     "    for q in queries(song):\n        asked += 1\n",
     "    from tgfetch import bot_pace            # bot-pace-v1\n"
     "    for q in queries(song)[:bot_pace.max_queries()]:\n        asked += 1\n"),
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
    print("bot-pace-v1: deezload.py, youtube_batch.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
