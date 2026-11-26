"""blocked-memory-v1: a song the author withdrew is remembered across jobs and candidates."""

import asyncio

import pytest

from tgfetch import blocked, blocked_memory as bm, db
from tgfetch.rank import Candidate
from tgfetch.worker import Worker

from test_blocked import ALERTS, BlockingSource, NEW, _job_for, _no_llm  # noqa: F401
from test_worker import cfg, fakes  # noqa: F401

@pytest.fixture(autouse=True)
def _reset():
    BlockingSource.pick_link_calls = 0


REASON = (f"{blocked.BLOCKED_TEXT} (https://www.deezer.com/track/2546118092 The song's author has prohibited "
          "listening to it in most countries)")


def test_the_same_song_has_one_key_whatever_the_spelling():
    k = bm.song_key("Pulled Song (From “Film”)", "Artist B, Other Artist")
    assert k == bm.song_key("pulled song", "Artist B & Someone")
    assert k != bm.song_key("Pulled Song", "Artist C")
    assert bm.song_key("", "Artist B") is None


def test_deezer_id_is_read_from_the_reply():
    assert bm.deezer_id(REASON) == "2546118092"
    assert bm.deezer_id("https://www.deezer.com/en/track/55 gone") == "55"
    assert bm.deezer_id("no link here") is None


def test_remember_and_lookup(conn):
    assert bm.lookup(conn, "Pulled Song", "Artist B") is None
    assert bm.remember(conn, "Pulled Song", "Artist B", REASON) is True
    assert bm.remember(conn, "Pulled Song", "Artist B", "another reason") is False     # first one is kept
    assert bm.lookup(conn, "Pulled Song", "Artist B") == REASON
    assert bm.lookup(conn, "Pulled Song", "Artist C") is None
    row = conn.execute("SELECT deezer_id FROM blocked_tracks").fetchone()
    assert row[0] == "2546118092"


def test_a_broken_database_never_raises():
    class Broken:
        def execute(self, *a, **k):
            raise RuntimeError("disk gone")

        commit = execute
    assert bm.lookup(Broken(), "A", "B") is None
    assert bm.remember(Broken(), "A", "B", "r") is False


def test_a_blocked_song_is_not_asked_again_under_a_new_candidate(conn, library, cfg):
    w = Worker(BlockingSource(), conn, cfg, library_loader=lambda: library, verify=_no_llm)
    _job_for(conn, NEW[1])
    asyncio.run(w.run_job(db.claim_job(conn)))
    assert BlockingSource.pick_link_calls == 1
    # the next night: the same song, a new search and a new candidate (a new job id)
    again = Candidate(0, "99", NEW[1].title, NEW[1].artist, "", link="track/2", duration_s=210)
    _, _, jid2 = _job_for(conn, again)
    asyncio.run(w.run_job(db.claim_job(conn)))
    j = db.get_job(conn, jid2)
    assert j["status"] == "blocked" and blocked.BLOCKED_TEXT in j["error"]
    assert BlockingSource.pick_link_calls == 1                    # the bot was not asked a second time


def test_a_song_that_was_never_blocked_is_still_asked(conn, library, cfg):
    w = Worker(BlockingSource(), conn, cfg, library_loader=lambda: library, verify=_no_llm)
    _job_for(conn, NEW[1])
    asyncio.run(w.run_job(db.claim_job(conn)))
    _, _, jid = _job_for(conn, NEW[0])
    asyncio.run(w.run_job(db.claim_job(conn)))
    assert db.get_job(conn, jid)["status"] != "blocked"
    assert BlockingSource.pick_link_calls == 2
