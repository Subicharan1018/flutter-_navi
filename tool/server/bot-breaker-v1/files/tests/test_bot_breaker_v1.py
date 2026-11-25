"""bot-breaker-v1: a bot that stops answering is rested for an hour; nobody waits on it meanwhile."""
import asyncio
from types import SimpleNamespace

import pytest

from tgfetch import bot_pace
from tgfetch.sources import deezload
from tgfetch.sources.base import SourceError


@pytest.fixture(autouse=True)
def _fresh(monkeypatch):
    monkeypatch.setenv("BOT_FAILS_BEFORE_REST", "3")
    monkeypatch.setenv("BOT_REST_S", "3600")
    monkeypatch.setattr(bot_pace, "_fails", 0)
    monkeypatch.setattr(bot_pace, "_rest_until", 0.0)


def test_three_failures_in_a_row_rest_the_bot_and_one_answer_resets_the_count():
    bot_pace.record(False)
    bot_pace.record(False)
    bot_pace.record(True)                                   # answered: the count starts again
    bot_pace.record(False)
    bot_pace.record(False)
    assert bot_pace.resting() == 0
    bot_pace.record(False)
    assert 3500 < bot_pace.resting() <= 3600
    assert "didn't answer" in bot_pace.rest_message(bot_pace.resting()) and "will retry" in bot_pace.rest_message(1)


def test_the_bot_is_tried_again_when_the_rest_is_over(monkeypatch):
    monkeypatch.setenv("BOT_REST_S", "0.05")
    for _ in range(3):
        bot_pace.record(False)
    assert bot_pace.resting() > 0
    asyncio.run(asyncio.sleep(0.1))
    assert bot_pace.resting() == 0


def test_the_breaker_is_off_under_pytest_unless_a_test_turns_it_on(monkeypatch):
    monkeypatch.delenv("BOT_FAILS_BEFORE_REST")
    for _ in range(10):
        bot_pace.record(False)
    assert bot_pace.resting() == 0


def source():
    return deezload.DeezloadSource(object(), SimpleNamespace(source="bot", search_prefix=".trk", pick_timeout_s=3))


def test_a_resting_bot_is_not_called_at_all(monkeypatch):
    for _ in range(3):
        bot_pace.record(False)
    called = []

    async def fn():
        called.append(1)
    with pytest.raises(SourceError, match="didn't answer"):
        asyncio.run(source()._call(fn))
    assert called == []


def test_requests_that_get_no_answer_open_the_breaker(monkeypatch):
    monkeypatch.setattr(deezload, "BOT_ATTEMPTS", 1)
    src = source()

    async def silent():
        raise ConnectionError("no answer")
    for _ in range(3):
        with pytest.raises(SourceError):
            asyncio.run(src._call(silent))
    assert bot_pace.resting() > 0


def test_an_answer_keeps_the_breaker_closed():
    src = source()

    async def fine():
        return "ok"
    for _ in range(5):
        assert asyncio.run(src._call(fine)) == "ok"
    assert bot_pace.resting() == 0


def test_the_waits_are_short_by_default():
    assert deezload.BOT_ATTEMPTS == 2 and deezload.CALL_TIMEOUT_S == 20
    from tgfetch import worker
    assert worker.LINK_FIRST_FILE_S == 300 and worker.LINK_IDLE_S == 240
