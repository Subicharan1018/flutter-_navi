"""fetch-waits-v1: songs wait for the owner's verify, wake at once, and titles with a version suffix are searched by name."""
import time

from tgfetch import bot_verify as bv
from tgfetch import channels_first as chf
from tgfetch import db, human_check as hc, youtube_batch as yb
from tgfetch.worker import MAINT_TEXT

from test_channels_primary_v1 import Bot, Src, _env, run, song_job, worker  # noqa: F401
from test_worker import _no_llm, cfg, fakes  # noqa: F401


def test_a_song_the_channels_lack_waits_for_the_verify_instead_of_failing(conn, cfg):
    src = Src({"one": [], "two": []})
    src.human = hc.HumanCheck(None, probe_s=1000)
    src.human.set()
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    bot = Bot()
    assert run(chf.fetch_one(w, b, jid, cand, bot)) == "later"
    j = db.get_job(conn, jid)
    assert bot.calls == [] and j["status"] == "waiting" and "verify" in j["error"]


def test_a_song_found_in_a_channel_still_downloads_while_the_bot_waits_for_a_check(conn, cfg):
    from test_channels_primary_v1 import HIT
    src = Src({"two": HIT})
    src.human = hc.HumanCheck(None, probe_s=1000)
    src.human.set()
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    bot = Bot()
    async def take(w_, jid_, cand_, ch, post):
        db.update_job(conn, jid_, status="ready")
        return True
    orig, chf.take_from_channel = chf.take_from_channel, take
    try:
        assert run(chf.fetch_one(w, b, jid, cand, bot)) == "done"
    finally:
        chf.take_from_channel = orig
    assert bot.calls == []


def test_a_batch_waiting_for_the_verify_does_not_give_up_after_a_day(conn, cfg):
    src = Src({})
    src.human = hc.HumanCheck(None)
    w = worker(conn, cfg, src)
    assert yb._give_up_s(w, 86400) == 86400
    src.human.set()
    assert yb._give_up_s(w, 86400) >= 3 * 86400


def test_verifying_wakes_the_deferred_batches_at_once(conn):
    b, jid, cand = song_job(conn)
    db.defer_batch(conn, b["id"], 1800, MAINT_TEXT)
    assert db.claim_batch(conn) is None                           # parked for 30 minutes
    assert bv.wake_waiting(conn) == 1
    assert db.claim_batch(conn)["id"] == b["id"]
    other, _, _ = song_job(conn, title="Another")
    db.defer_batch(conn, other["id"], 1800, "some other reason")
    assert bv.wake_waiting(conn) == 0                             # only the bot-silent ones


def test_clearing_the_flag_calls_the_wake_up():
    seen = []
    hc.ON_CLEAR.append(lambda: seen.append(1))
    try:
        h = hc.HumanCheck(None)
        h.clear()                                                 # not flagged: nothing
        h.set()
        h.clear()
    finally:
        hc.ON_CLEAR.pop()
    assert seen == [1]


def test_a_failing_wake_up_never_breaks_clearing():
    def boom():
        raise RuntimeError("x")
    hc.ON_CLEAR.append(boom)
    try:
        h = hc.HumanCheck(None)
        h.set()
        h.clear()
    finally:
        hc.ON_CLEAR.pop()
    assert not h.flagged


def test_a_version_suffix_is_not_searched_for():
    assert chf.queries("Laali Laali - Tamil", "Ghibran")[:2] == ["Laali Laali ghibran", "Laali Laali"]
    assert chf.queries("Você Não Cuidou - Ao Vivo", "Fred & Fabrício")[1] == "Você Não Cuidou"
    assert chf.queries("Anbe Anbe", "Hesham Abdul Wahab") == ["Anbe Anbe hesham", "Anbe Anbe"]
    assert chf.queries("", "x") == []
    assert chf.queries("- Live", "x")[-1] == "- Live"             # nothing left of the title: keep it whole
