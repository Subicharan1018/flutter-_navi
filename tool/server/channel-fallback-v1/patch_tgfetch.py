"""channel-fallback-v1: one anchored patch to tg-fetcher's main.py.

The feature is the new file tgfetch/channel_fallback.py; main.py only starts it next to the worker and
stops it with the others.

usage: python patch_tgfetch.py <tg-fetcher root>
exit 0: patched or already patched; exit 2: a file is not the expected one (nothing is written).
"""
import sys
from pathlib import Path

P = [   # (relative file, old (exactly once), new)
    ("tgfetch/main.py",
     '    trending_task = asyncio.create_task(charts.run_forever(), name="trending")\n',
     '    trending_task = asyncio.create_task(charts.run_forever(), name="trending")\n'
     '    from tgfetch import channel_fallback          # channel-fallback-v1: failed songs from public channels\n'
     '    channel_task = asyncio.create_task(channel_fallback.ChannelFallback(worker, client, settings).run_forever(),\n'
     '                                       name="channel-fallback")\n'),
    ("tgfetch/main.py",
     "        trending_task.cancel()\n",
     "        trending_task.cancel()\n        channel_task.cancel()\n"),
]


def main(root: str) -> int:
    base = Path(root)
    texts = {}
    for rel, old, new in P:
        text = texts.get(rel)
        if text is None:
            text = (base / rel).read_text(encoding="utf-8")
        if new in text and old not in text.replace(new, ""):
            texts[rel] = text
            continue
        if text.count(old) != 1:
            print(f"!! {rel}: expected anchor not found exactly once")
            return 2
        texts[rel] = text.replace(old, new)
    for rel, text in texts.items():
        (base / rel).write_text(text, encoding="utf-8")
    print("channel-fallback-v1: main.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
