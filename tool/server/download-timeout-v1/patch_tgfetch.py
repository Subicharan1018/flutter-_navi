"""download-timeout-v1: a channel download that hangs no longer freezes the worker.

On 25 Nov 2026 a download from a channel sat on "Connecting to DC5" from 05:09 UTC for six hours: no timeout, so the
worker never took another job while every health check stayed green. Now the download is cancelled after
CHANNEL_DOWNLOAD_TIMEOUT_S (default: 5 minutes, or 60 s + 5 s per MB when the file is bigger), the job goes back to
`waiting`, and the song falls through to the bot or the next run like any failed download.

Anchored patch to tgfetch/channels_first.py; each anchor must be found exactly once, or nothing is written.
usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not the expected file.
"""
import sys
from pathlib import Path

CH = "tgfetch/channels_first.py"

P = [
    (CH,
     "async def take_from_channel(worker, jid: int, cand: dict, channel: str, post: dict) -> bool:\n",
     "def download_timeout_s(post: dict) -> float:\n"
     "    \"\"\"How long one channel download may take before it is cancelled.   download-timeout-v1\"\"\"\n"
     "    env = os.getenv(\"CHANNEL_DOWNLOAD_TIMEOUT_S\")\n"
     "    if env:\n"
     "        return float(env)\n"
     "    return max(300.0, 60.0 + (post.get(\"size\") or 0) / 1e6 * 5)\n\n\n"
     "async def take_from_channel(worker, jid: int, cand: dict, channel: str, post: dict) -> bool:\n"),
    (CH,
     "        try:\n"
     "            if await take_from_channel(worker, jid, cand, ch, post):\n"
     "                STATS[\"hit\"] += 1\n",
     "        try:\n"
     "            if await asyncio.wait_for(take_from_channel(worker, jid, cand, ch, post), download_timeout_s(post)):\n"
     "                STATS[\"hit\"] += 1\n"),
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
    print("download-timeout-v1: channels_first.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
