"""bot-breaker-v1: do not wait on a silent bot; rest it for an hour after repeated silence, and try again after.

25 Nov 2026: a bot that did not answer cost every song about three minutes (4 tries of 45 s) and a pasted playlist waited
20 minutes for a first file, while the channels could have been working. Now:
  - one bot request gets BOT_ATTEMPTS (2) tries of CALL_TIMEOUT_S (20 s): under a minute, not three;
  - BOT_FAILS_BEFORE_REST (3) requests in a row with no answer rest the bot for BOT_REST_S (3600 s): every bot call in that
    hour fails at once with "didn't answer ... will retry", so the song just waits (and the batch retries it later) while the
    channel searches carry on; when the hour is up the bot is tried again, and one answer closes the breaker;
  - a pasted link waits LINK_FIRST_FILE_S (300 s) for its first file and LINK_IDLE_S (240 s) of silence, not 20 and 10 minutes
    (the songs then go to the by-name route and, if the bot is resting, to the retry queue).

Anchored patches to tgfetch/bot_pace.py, sources/deezload.py and worker.py; each anchor must be found exactly once, or nothing
is written. Needs bot-pace-v1.
usage: python patch_tgfetch.py <tg-fetcher root>   exit 0 patched/already patched; exit 2 not the expected file.
"""
import sys
from pathlib import Path

BP = "tgfetch/bot_pace.py"
DZ = "tgfetch/sources/deezload.py"
WK = "tgfetch/worker.py"

BREAKER = '''import logging as _logging

_log = _logging.getLogger(__name__)
_fails = 0
_rest_until = 0.0            # time.time() until which the bot is not asked


def fails_before_rest() -> int:
    """0 = the breaker is off (also under pytest unless a test sets BOT_FAILS_BEFORE_REST)."""
    if os.getenv("PYTEST_CURRENT_TEST") and "BOT_FAILS_BEFORE_REST" not in os.environ:
        return 0
    try:
        return max(0, int(os.getenv("BOT_FAILS_BEFORE_REST", "3")))
    except ValueError:
        return 3


def rest_s() -> float:
    try:
        return max(0.0, float(os.getenv("BOT_REST_S", "3600")))
    except ValueError:
        return 3600.0


def resting() -> float:
    """Seconds the bot is still resting for (0 = ask it)."""
    return max(0.0, _rest_until - time.time())


def record(ok: bool) -> None:
    """One finished bot request: answered, or ran out of tries without an answer."""
    global _fails, _rest_until
    if ok:
        _fails = 0
        return
    limit = fails_before_rest()
    if not limit:
        return
    _fails += 1
    if _fails >= limit and resting() == 0:
        _fails = 0
        _rest_until = time.time() + rest_s()
        _log.warning("bot-breaker: the music bot gave no answer %d times in a row: resting it for %.0f min "
                     "(songs wait and are retried, the channels carry on)", limit, rest_s() / 60)


def rest_message(left: float) -> str:
    until = time.strftime("%H:%M", time.gmtime(_rest_until))
    return f"The music bot didn't answer: resting until {until} UTC after repeated silence — will retry"


async def wait() -> None:'''

P = [
    (BP, "async def wait() -> None:", BREAKER),
    (DZ,
     "BOT_ATTEMPTS = 4           # v2: was 2. A slow bot gets three more chances before the search is re-queued\n",
     "BOT_ATTEMPTS = int(__import__(\"os\").getenv(\"BOT_ATTEMPTS\", \"2\"))   # bot-breaker-v1: was 4 (v2), 2 again: a silent bot costs under a minute\n"),
    (DZ,
     "CALL_TIMEOUT_S = 45        # v2: one Telegram request never hangs longer than this (then it counts as \"no answer\")\n",
     "CALL_TIMEOUT_S = int(__import__(\"os\").getenv(\"CALL_TIMEOUT_S\", \"20\"))   # bot-breaker-v1: was 45: one Telegram request never hangs longer\n"),
    (DZ,
     "        for attempt in range(1, BOT_ATTEMPTS + 1):\n            pause = self._flood_until - time.monotonic()\n",
     "        from tgfetch import bot_pace            # bot-breaker-v1: a bot that went silent rests, nobody waits on it\n"
     "        left = bot_pace.resting()\n"
     "        if left:\n"
     "            raise SourceError(bot_pace.rest_message(left))\n"
     "        for attempt in range(1, BOT_ATTEMPTS + 1):\n            pause = self._flood_until - time.monotonic()\n"),
    (DZ,
     "                self._wait.record(time.monotonic() - began)\n                return result\n",
     "                self._wait.record(time.monotonic() - began)\n                bot_pace.record(True)\n                return result\n"),
    (DZ,
     "                if attempt == BOT_ATTEMPTS:\n                    raise SourceError(\"The music bot didn't answer in time — try again\") from e\n",
     "                if attempt == BOT_ATTEMPTS:\n                    bot_pace.record(False)\n                    raise SourceError(\"The music bot didn't answer in time — try again\") from e\n"),
    (WK,
     "LINK_FIRST_FILE_S = 1200.0  # the bot queues requests (\"position 66\"): wait long for the first file\n",
     "LINK_FIRST_FILE_S = float(os.getenv(\"LINK_FIRST_FILE_S\", \"300\"))  # bot-breaker-v1: was 1200; the songs then take the by-name route / the retry queue\n"),
    (WK,
     "LINK_IDLE_S = 600.0         # then give up when it sends nothing for this long\n",
     "LINK_IDLE_S = float(os.getenv(\"LINK_IDLE_S\", \"240\"))         # bot-breaker-v1: was 600; then give up when it sends nothing for this long\n"),
    # the old test of four tries: a slow bot now gets two (BOT_ATTEMPTS)
    ("tests/test_fallbacks.py",
     "    src = source([timeout(), timeout(), timeout(), []], monkeypatch)\n    assert asyncio.run(src.search(\"kanave\")) == []\n    assert src.client.calls == 4\n",
     "    src = source([timeout(), []], monkeypatch)                  # bot-breaker-v1: two tries, not four\n"
     "    assert asyncio.run(src.search(\"kanave\")) == []\n    assert src.client.calls == 2\n"),
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
    print("bot-breaker-v1: bot_pace.py, deezload.py, worker.py patched")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
