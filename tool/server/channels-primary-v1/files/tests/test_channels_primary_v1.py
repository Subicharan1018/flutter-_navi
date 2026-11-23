"""channels-primary-v1 scratch tests: no Telegram, fake channels and a fake bot."""
import asyncio
import time
from types import SimpleNamespace as NS

import pytest

from tgfetch import channel_fallback as cf
from tgfetch import channels_first as chf
from tgfetch import db, exportify as ex, human_check as hc, youtube_batch as yb
from tgfetch.rank import Candidate
from tgfetch.sources.base import SourceError
from tgfetch.worker import Worker

from test_exportify_v1 import LIB, NIGHT, imp, plan_of, queue, states  # noqa: F401  (fixture: imp)
from test_links import BotSource, _file, quick  # noqa: F401  (fixture: quick)
from test_worker import _no_llm, cfg, fakes  # noqa: F401  (fixtures)


class Audio:
    pass


class DocumentAttributeAudio:
    def __init__(self, title="", performer=""):
        self.title, self.performer, self.duration = title, performer, 240


class DocumentAttributeFilename:
    def __init__(self, file_name):
        self.file_name = file_name


def post(mid, title, performer, mime="audio/flac", size=40_000_000):
    doc = NS(id=mid * 10, mime_type=mime, size=size,
             attributes=[DocumentAttributeAudio(title, performer), DocumentAttributeFilename(f"{title}.{'flac' if 'flac' in mime else 'mp3'}")])
    return NS(id=mid, document=doc, raw_text=f"{title} - {performer}", message="", out=False)


class FakeClient:
    """Search = every query word is in the post's text. get_messages(ids=) returns that post."""

    def __init__(self, by_channel):
        self.by_channel, self.searches, self.fail = by_channel, [], []

    async def get_entity(self, name):
        return name

    async def get_messages(self, ent, search=None, limit=0, ids=None, **k):
        if ids is not None:
            return next((m for m in self.by_channel.get(ent, []) if m.id == ids), None)
        self.searches.append((ent, search, time.monotonic()))
        if self.fail:
            raise self.fail.pop(0)
        words = (search or "").lower().split()
        return [m for m in self.by_channel.get(ent, []) if all(w in m.raw_text.lower() for w in words)][:limit]


class Src(BotSource):
    """The bot (FakeSource) plus what DeezloadSource has: client, _call, human."""

    def __init__(self, by_channel=None):
        super().__init__()
        self.client = FakeClient(by_channel or {})
        self.human = hc.HumanCheck(None)
        self.bot_searches = []

    async def _call(self, fn, *a, **k):
        return await fn(*a, **k)

    async def search(self, query, kind="song"):
        self.bot_searches.append(query)
        return []


@pytest.fixture(autouse=True)
def _env(monkeypatch, tmp_path):
    monkeypatch.setenv("CHANNEL_FALLBACK_CHANNELS", "one,two")
    monkeypatch.setenv("CHANNEL_SEARCH_GAP_S", "0")
    for k in ("CHANNEL_FALLBACK", "FETCH_PRIMARY", "FETCH_BOT_FALLBACK", "CHANNEL_MAX_MB", "CHANNEL_MIN_FREE_GB"):
        monkeypatch.delenv(k, raising=False)
    monkeypatch.setenv("CHANNEL_MIN_FREE_GB", "0")
    monkeypatch.setattr(chf, "_ents", {})
    monkeypatch.setattr(chf, "_next_at", 0.0)
    for k in chf.STATS:
        chf.STATS[k] = 0


def song_job(conn, title="Oru Pudhu Paadal", artist="Sample Singer", link="exportify:1"):
    sid = db.create_search(conn, "alice", title, kind="tracks")
    db.save_candidates(conn, sid, [Candidate(0, "r", title, artist, "Album", duration_s=240.0)])
    cid = db.get_search(conn, sid)["candidates"][0]["id"]
    bid = db.create_batch(conn, "alice", "songs", "t", [cid], link=link)
    jid = db.create_job(conn, "alice", cid, batch_id=bid, status="waiting")
    return db.get_batch(conn, bid), jid, db.get_candidate(conn, cid)


def worker(conn, cfg, src):
    return Worker(src, conn, cfg, library_loader=lambda: [], verify=_no_llm)


HIT = [post(7, "Oru Pudhu Paadal", "Sample Singer")]


class Bot:
    """bot_fetch stand-in: records the call and gives the song to the bot's own route."""

    def __init__(self, result="done"):
        self.calls, self.result = [], result

    async def __call__(self, w, jid, cand):
        self.calls.append(jid)
        db.update_job(w.conn, jid, status="failed", error="not found on the music bot")
        return self.result


def run(coro):
    return asyncio.run(coro)


# ── channels first ───────────────────────────────────────────────────────────

def test_a_channel_hit_never_touches_the_bot(conn, cfg):
    src = Src({"two": HIT})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    bot = Bot()
    assert run(chf.fetch_one(w, b, jid, cand, bot)) == "done"
    j = db.get_job(conn, jid)
    assert j["status"] == "ready" and j["source"] == "channel:two" and src.downloads == 1
    assert bot.calls == [] and src.bot_searches == []
    assert chf.STATS["hit"] == 1


def test_the_specific_query_goes_first_and_the_title_alone_second(conn, cfg):
    src = Src({"one": [], "two": []})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn, title='Oru Pudhu Paadal (From "Film")', artist="Sample Singer;Other")
    run(chf.fetch_one(w, b, jid, cand, Bot()))
    assert [(c, q) for c, q, _ in src.client.searches] == [
        ("one", "Oru Pudhu Paadal sample"), ("two", "Oru Pudhu Paadal sample"),
        ("one", "Oru Pudhu Paadal"), ("two", "Oru Pudhu Paadal")]


def test_same_acceptance_as_the_fallback(conn, cfg):
    wrong = [post(1, "Oru Pudhu Paadal (Remix)", "Sample Singer"), post(2, "Oru Pudhu Paadal", "Someone Else"),
             post(3, "Oru Pudhu Paadal", "Sample Singer", mime="audio/mpeg")]
    src = Src({"one": wrong, "two": []})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    bot = Bot()
    run(chf.fetch_one(w, b, jid, cand, bot))
    assert bot.calls == [jid]                                    # none accepted: the bot is asked


def test_a_post_over_the_size_cap_is_not_taken(conn, cfg, monkeypatch):
    monkeypatch.setenv("CHANNEL_MAX_MB", "100")
    src = Src({"one": [post(7, "Oru Pudhu Paadal", "Sample Singer", size=150 * 1048576)]})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    bot = Bot()
    run(chf.fetch_one(w, b, jid, cand, bot))
    assert bot.calls == [jid]


def test_a_miss_asks_the_bot(conn, cfg):
    src = Src({"one": [], "two": []})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    bot = Bot()
    assert run(chf.fetch_one(w, b, jid, cand, bot)) == "done"
    assert bot.calls == [jid] and chf.STATS["miss"] == 1 and chf.STATS["bot"] == 1
    assert conn.execute("SELECT result FROM channel_tries WHERE job_id=?", (jid,)).fetchone()[0] == "none"


def test_bot_fallback_off_skips_the_bot_entirely(conn, cfg, monkeypatch):
    monkeypatch.setenv("FETCH_BOT_FALLBACK", "0")
    src = Src({"one": [], "two": []})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    bot = Bot()
    assert run(chf.fetch_one(w, b, jid, cand, bot)) == "done"
    j = db.get_job(conn, jid)
    assert bot.calls == [] and j["status"] == "failed" and chf.NOT_ON_CHANNELS in j["error"] and "FETCH_BOT_FALLBACK" in j["error"]


def test_bot_waiting_for_a_human_check_is_skipped_but_probed_now_and_then(conn, cfg):
    src = Src({"one": [], "two": []})
    src.human = hc.HumanCheck(None, probe_s=1000)
    src.human.set()
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    bot = Bot()
    run(chf.fetch_one(w, b, jid, cand, bot))
    j = db.get_job(conn, jid)
    assert bot.calls == [] and j["status"] == "failed" and "human check" in j["error"]
    b, jid2, cand2 = song_job(conn, title="Another Song")
    src.human._next_probe = 0                                    # the probe is due: this song goes to the bot
    run(chf.fetch_one(w, b, jid2, cand2, bot))
    assert bot.calls == [jid2]


def test_a_check_that_appears_during_the_bot_call_does_not_hold_the_batch(conn, cfg):
    src = Src({"one": [], "two": []})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)

    async def bot(w_, jid_, cand_):
        src.human.set()
        db.update_job(conn, jid_, status="waiting", error="the music bot didn't answer — will retry")
        return "later"
    assert run(chf.fetch_one(w, b, jid, cand, bot)) == "done"
    assert "human check" in db.get_job(conn, jid)["error"]


def test_the_channels_failing_is_not_a_miss(conn, cfg):
    src = Src({})
    src.client.fail = [SourceError("The music bot didn't answer in time")] * 20
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    bot = Bot()
    src.human.set()                                              # bot not allowed, channels erroring: ask again later
    assert run(chf.fetch_one(w, b, jid, cand, bot)) == "later"
    assert bot.calls == [] and db.get_job(conn, jid)["status"] == "waiting"
    conn.executescript(cf.SCHEMA)
    assert conn.execute("SELECT COUNT(*) FROM channel_tries WHERE job_id=?", (jid,)).fetchone()[0] == 0


def test_other_lists_and_bot_mode_are_untouched(conn, cfg, monkeypatch):
    src = Src({"two": HIT})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn, link="https://music.youtube.com/playlist?list=PL1")
    bot = Bot()
    run(chf.fetch_one(w, b, jid, cand, bot))
    assert bot.calls == [jid] and src.client.searches == []
    monkeypatch.setenv("FETCH_PRIMARY", "bot")
    b, jid, cand = song_job(conn, title="X Song")
    run(chf.fetch_one(w, b, jid, cand, bot))
    assert len(bot.calls) == 2 and src.client.searches == []


def test_race_mode_lets_a_channel_win_and_cancels_the_bot(conn, cfg, monkeypatch):
    monkeypatch.setenv("FETCH_PRIMARY", "race")
    src = Src({"two": HIT})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    seen = {}

    async def slow_bot(w_, jid_, cand_):
        try:
            await asyncio.sleep(30)
        except asyncio.CancelledError:
            seen["cancelled"] = True
            raise
    assert run(chf.fetch_one(w, b, jid, cand, slow_bot)) == "done"
    assert db.get_job(conn, jid)["status"] == "ready" and seen == {"cancelled": True}


# ── scale: pacing, cache, flood, resume, cancel ──────────────────────────────

def test_searches_are_paced_one_gap_apart(conn, cfg, monkeypatch):
    monkeypatch.setenv("CHANNEL_SEARCH_GAP_S", "0.05")
    src = Src({"one": [], "two": []})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    run(chf.fetch_one(w, b, jid, cand, Bot()))
    times = [t for _, _, t in src.client.searches]
    assert len(times) == 4 and all(b_ - a >= 0.045 for a, b_ in zip(times, times[1:]))


def test_the_same_query_is_never_asked_twice_and_survives_a_restart(conn, cfg):
    src = Src({"one": [], "two": []})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    run(chf.fetch_one(w, b, jid, cand, Bot()))
    assert len(src.client.searches) == 4
    # the service restarts: new objects, same fetch.db. The same song again (a retry) asks nothing.
    src2 = Src({"one": [], "two": []})
    w2 = worker(conn, cfg, src2)
    b, jid2, cand2 = song_job(conn)
    run(chf.fetch_one(w2, b, jid2, cand2, Bot()))
    assert src2.client.searches == [] and chf.STATS["cached"] >= 4


def test_a_cached_hit_still_scores_the_same_and_downloads_by_id(conn, cfg):
    src = Src({"one": HIT})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    run(chf.fetch_one(w, b, jid, cand, Bot()))
    assert db.get_job(conn, jid)["status"] == "ready"
    rows = chf.cache_get(conn, "one", "oru pudhu paadal sample")
    assert rows and rows[0]["id"] == 7 and rows[0]["performer"] == "Sample Singer"


def test_empty_answers_expire_sooner_than_hits(conn):
    chf.cache_put(conn, "one", "a", [])
    chf.cache_put(conn, "one", "b", [{"id": 1, "mime": "", "size": 0, "title": "", "performer": "", "fname": "", "text": "", "dur": 0}])
    later = time.time() + 4 * 86400
    assert chf.cache_get(conn, "one", "a", now=later) is None and chf.cache_get(conn, "one", "b", now=later)


def test_flood_wait_is_waited_out_and_the_search_repeated(conn, cfg):
    src = Src({"two": HIT})
    src.client.fail = [SourceError("Telegram rate limit: wait 0s")]
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    assert run(chf.fetch_one(w, b, jid, cand, Bot())) == "done"
    assert db.get_job(conn, jid)["status"] == "ready"


def test_a_cancelled_batch_stops_before_the_next_search(conn, cfg):
    src = Src({"one": [], "two": []})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    conn.execute("UPDATE batches SET status='cancelled' WHERE id=?", (b["id"],))
    bot = Bot()
    assert run(chf.fetch_one(w, b, jid, cand, bot)) == "done"
    assert src.client.searches == [] and bot.calls == []


def test_low_disk_holds_the_song_instead_of_downloading(conn, cfg, monkeypatch):
    monkeypatch.setenv("CHANNEL_MIN_FREE_GB", "25")
    monkeypatch.setattr(chf, "_free_gb", lambda w: 10.0)
    src = Src({"two": HIT})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn)
    assert run(chf.fetch_one(w, b, jid, cand, Bot())) == "later"
    assert db.get_job(conn, jid)["status"] == "waiting" and src.downloads == 0


# ── the whole wishlist path ──────────────────────────────────────────────────

def test_a_wishlist_batch_is_fetched_from_channels_first(conn, imp, cfg, quick):
    plan_of(conn, imp, min_popularity=50)
    ex.start(conn, imp)
    bid = queue(conn, imp, cfg, library=[dict(s) for s in LIB])[0]["batch_id"]
    src = Src({"retroaudios": [], "two": HIT})
    w = Worker(src, conn, cfg, library_loader=lambda: [dict(r) for r in LIB], verify=_no_llm)

    async def go():
        await w.run_batch(db.claim_batch(conn))
        await w.drain()
    import os
    os.environ["CHANNEL_FALLBACK_CHANNELS"] = "retroaudios,two"
    asyncio.run(go())
    by = {j["title"]: j for j in db.get_batch(conn, bid)["jobs"]}
    assert by["Oru Pudhu Paadal"]["status"] == "ready" and by["Oru Pudhu Paadal"]["source"] == "channel:two"
    assert by["Thendral Vandhu"]["status"] == "failed"                  # no channel, the bot has nothing either
    assert src.bot_searches and all("oru pudhu" not in q.lower() for q in src.bot_searches)
    assert src.started == []
    ex.settle(conn, imp, NIGHT + 900)
    st = states(conn, imp)
    assert st[6] == "downloaded" and st[10] == "failed"                 # one song, one state


def test_the_disk_guard_still_pauses_and_resumes(conn, imp, cfg):
    plan_of(conn, imp, disk_floor_gb=40)
    ex.start(conn, imp)
    out = queue(conn, imp, cfg, free=40.0)
    assert out[0]["queued"] == 0 and ex.get_plan(conn, imp)["status"] == "paused_disk"
    assert queue(conn, imp, cfg, free=120.0)[0]["queued"] > 0
    assert ex.get_plan(conn, imp)["status"] == "active"


def test_batch_size_and_gb_per_hour_follow_the_environment():
    import importlib
    import os
    old = dict(os.environ)
    try:
        os.environ["EXPORTIFY_BATCH_SIZE"], os.environ["EXPORTIFY_GB_PER_HOUR"] = "100", "0.77"
        m = importlib.reload(ex)
        assert m.BATCH_SIZE == 100 and m.GB_PER_HOUR == 0.77
    finally:
        os.environ.clear()
        os.environ.update(old)
        importlib.reload(ex)


def test_sped_up_edits_skip_the_channels(conn, cfg, monkeypatch):
    src = Src({"one": [post(7, "Wannabe Sped Up", "Sample Singer")]})
    w = worker(conn, cfg, src)
    b, jid, cand = song_job(conn, title="Wannabe - Sped Up Version", artist="Sample Singer")
    bot = Bot()
    run(chf.fetch_one(w, b, jid, cand, bot))
    assert src.client.searches == [] and bot.calls == [jid]
    monkeypatch.setenv("CHANNEL_SKIP_EDITS", "0")
    b, jid2, cand2 = song_job(conn, title="Wannabe Sped Up", artist="Sample Singer")
    run(chf.fetch_one(w, b, jid2, cand2, bot))
    assert src.client.searches
