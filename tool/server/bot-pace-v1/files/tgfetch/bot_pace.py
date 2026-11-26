"""
tgfetch/bot_pace.py  (bot-pace-v1)
──────────────────────────────────
The music bot was asked its inline searches back to back: three queries per song, about a second apart, hundreds of
songs in a row (25 Nov 2026, the 5,657-song import: [0, 0, 0] results for song after song). Fired that fast the bot
answers nothing. Two knobs, both in .env:

  BOT_SEARCH_GAP_S      4   seconds between two bot searches, whoever asks (0 = as before)
  BOT_QUERIES_PER_SONG  2   how many spellings of a song are tried on the bot (the plain title first, then title + artist)
"""

import asyncio
import os
import time

_lock = None
_next_at = 0.0


def gap_s() -> float:
    if os.getenv("PYTEST_CURRENT_TEST") and "BOT_SEARCH_GAP_S" not in os.environ:
        return 0.0                          # tests are not paced unless a test asks for it
    try:
        return max(0.0, float(os.getenv("BOT_SEARCH_GAP_S", "4")))
    except ValueError:
        return 4.0


def max_queries() -> int:
    try:
        return max(1, int(os.getenv("BOT_QUERIES_PER_SONG", "2")))
    except ValueError:
        return 2


async def wait() -> None:
    """Return when it is this search's turn: at least gap_s() after the previous one."""
    global _lock, _next_at
    gap = gap_s()
    if gap <= 0:
        return
    if _lock is None:
        _lock = asyncio.Lock()
    async with _lock:
        pause = _next_at - time.monotonic()
        if pause > 0:
            await asyncio.sleep(pause)
        _next_at = time.monotonic() + gap
