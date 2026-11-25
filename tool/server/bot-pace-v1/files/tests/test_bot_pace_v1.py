"""bot-pace-v1: bot searches are spaced out and fewer per song."""
import asyncio
import time

from tgfetch import bot_pace, youtube_batch as yb

from test_channels_primary_v1 import Src, _env, song_job, worker  # noqa: F401
from test_worker import _no_llm, cfg, fakes  # noqa: F401


def fresh(monkeypatch, gap):
    monkeypatch.setenv("BOT_SEARCH_GAP_S", str(gap))
    monkeypatch.setattr(bot_pace, "_lock", None)
    monkeypatch.setattr(bot_pace, "_next_at", 0.0)


def test_two_searches_are_a_gap_apart(monkeypatch):
    fresh(monkeypatch, 0.2)

    async def go():
        t = time.monotonic()
        await bot_pace.wait()
        first = time.monotonic() - t
        await bot_pace.wait()
        return first, time.monotonic() - t
    first, second = asyncio.run(go())
    assert first < 0.1 and second >= 0.19


def test_a_zero_gap_means_as_before(monkeypatch):
    fresh(monkeypatch, 0)

    async def go():
        t = time.monotonic()
        for _ in range(5):
            await bot_pace.wait()
        return time.monotonic() - t
    assert asyncio.run(go()) < 0.1


def test_defaults_and_bad_values(monkeypatch):
    monkeypatch.delenv("BOT_SEARCH_GAP_S", raising=False)
    monkeypatch.delenv("BOT_QUERIES_PER_SONG", raising=False)
    assert bot_pace.gap_s() == 0                       # under pytest, unpaced unless set
    monkeypatch.delenv("PYTEST_CURRENT_TEST")
    assert bot_pace.gap_s() == 4 and bot_pace.max_queries() == 2
    monkeypatch.setenv("BOT_SEARCH_GAP_S", "x")
    monkeypatch.setenv("BOT_QUERIES_PER_SONG", "0")
    assert bot_pace.gap_s() == 4 and bot_pace.max_queries() == 1


class Counting(Src):
    def __init__(self):
        super().__init__()
        self.asked = []

    async def search(self, query, kind="song"):
        self.asked.append(query)
        return []


def test_only_the_first_spellings_are_asked_of_the_bot(conn, cfg, monkeypatch):
    monkeypatch.setenv("BOT_QUERIES_PER_SONG", "2")
    src = Counting()
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn, title="Adadaa Ithuyenna", artist="Haricharan", link="https://music.youtube.com/x")
    asyncio.run(yb.fetch_one(w, jid, cand))
    assert len(src.asked) == 2
