"""download-timeout-v1: a hung channel download is cancelled and the song moves on."""
import asyncio
import time

from tgfetch import channels_first as chf
from tgfetch import db

from test_channels_primary_v1 import Bot, HIT, Src, _env, run, song_job, worker  # noqa: F401
from test_worker import _no_llm, cfg, fakes  # noqa: F401


def test_the_timeout_grows_with_the_file_and_can_be_set(monkeypatch):
    monkeypatch.delenv("CHANNEL_DOWNLOAD_TIMEOUT_S", raising=False)
    assert chf.download_timeout_s({"size": 30_000_000}) == 300
    assert chf.download_timeout_s({"size": 140_000_000}) == 760
    assert chf.download_timeout_s({}) == 300
    monkeypatch.setenv("CHANNEL_DOWNLOAD_TIMEOUT_S", "7")
    assert chf.download_timeout_s({"size": 140_000_000}) == 7


def test_a_download_that_never_finishes_does_not_freeze_the_worker(conn, cfg, monkeypatch):
    monkeypatch.setenv("CHANNEL_DOWNLOAD_TIMEOUT_S", "0.2")
    src = Src({"two": HIT})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    bot = Bot()

    async def hang(*a, **k):
        await asyncio.sleep(3600)
    monkeypatch.setattr(chf, "take_from_channel", hang)
    t = time.monotonic()
    run(chf.fetch_one(w, b, jid, cand, bot))
    assert time.monotonic() - t < 5                     # not an hour
    assert bot.calls == [jid]                           # the song went on to the bot instead of hanging
