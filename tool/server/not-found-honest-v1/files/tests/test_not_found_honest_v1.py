"""not-found-honest-v1: one unanswered query is "we do not know", not "not found"."""
import asyncio

from tgfetch import db, youtube_batch as yb
from tgfetch.sources.base import SourceError

from test_channels_primary_v1 import Src, _env, song_job, worker  # noqa: F401
from test_worker import _no_llm, cfg, fakes  # noqa: F401


class Scripted(Src):
    """search() answers from a script: a list of results, or an exception to raise."""

    def __init__(self, script):
        super().__init__()
        self.script, self.asked = list(script), []

    async def search(self, query, kind="song"):
        self.asked.append(query)
        step = self.script.pop(0) if self.script else []
        if isinstance(step, Exception):
            raise step
        return step


def run_one(conn, cfg, script):
    src = Scripted(script)
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn, title="Param Sundari", artist="Shreya Ghoshal", link="https://music.youtube.com/x")
    out = asyncio.run(yb.fetch_one(w, jid, cand))
    return out, db.get_job(conn, jid), src


def test_every_query_answered_and_empty_is_not_found(conn, cfg):
    out, j, src = run_one(conn, cfg, [[], [], [], []])
    assert out == "done" and j["status"] == "failed" and "not found on the music bot" in j["error"]


def test_one_unanswered_query_waits_instead_of_failing(conn, cfg):
    out, j, src = run_one(conn, cfg, [SourceError("The music bot didn't answer in time"), [], [], []])
    assert out == "later" and j["status"] == "waiting" and "didn't answer" in j["error"]


def test_all_queries_unanswered_still_waits(conn, cfg):
    err = SourceError("The music bot didn't answer in time")
    out, j, src = run_one(conn, cfg, [err, err, err, err])
    assert out == "later" and j["status"] == "waiting"
