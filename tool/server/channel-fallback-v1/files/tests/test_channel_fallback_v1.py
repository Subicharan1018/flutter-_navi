import asyncio
import time
from types import SimpleNamespace as NS

from tgfetch import channel_fallback as cf
from tgfetch import db


class DocumentAttributeAudio:
    def __init__(self, title="", performer=""):
        self.title, self.performer, self.duration = title, performer, 200


class DocumentAttributeFilename:
    def __init__(self, file_name):
        self.file_name = file_name


def post(mid=1, title="", performer="", fname="", text="", mime="audio/flac"):
    attrs = [DocumentAttributeAudio(title, performer)]
    if fname:
        attrs.append(DocumentAttributeFilename(fname))
    doc = NS(id=mid * 10, mime_type=mime, size=1000, attributes=attrs)
    return NS(id=mid, document=doc, raw_text=text, message=text, out=False)


def test_norm_drops_brackets_and_format_words():
    assert cf.norm('Kanne Kanne (From "Soorarai") FLAC') == "kanne kanne"
    assert cf.norm("Veyyon Silli [Lossless]") == "veyyon silli"


def test_matches_title_and_artist():
    m = post(title="Veyyon Silli", performer="G.V. Prakash Kumar")
    assert cf.score("Veyyon Silli", "G.V.Prakash Kumar", m) >= 90


def test_wrong_artist_is_not_taken():
    m = post(title="Veyyon Silli", performer="Someone Else")
    assert cf.score("Veyyon Silli", "G.V.Prakash Kumar", m) == 0


def test_other_song_is_not_taken():
    m = post(title="Thozhi", performer="Govind Vasantha")
    assert cf.score("Veyyon Silli", "Govind Vasantha", m) == 0


def test_not_flac_is_not_taken():
    m = post(title="Veyyon Silli", performer="Prakash", mime="audio/mpeg", fname="a.mp3")
    assert cf.score("Veyyon Silli", "Prakash", m) == 0


def test_flac_by_file_name_when_mime_is_generic():
    m = post(fname="Veyyon Silli - Prakash Kumar.flac", mime="application/octet-stream")
    assert cf.is_flac(m)
    assert cf.score("Veyyon Silli", "Prakash Kumar", m) >= 90


def test_title_can_sit_in_the_caption():
    m = post(text="Veyyon Silli\nArtist: G.V. Prakash\n#flac", fname="x.flac")
    assert cf.score("Veyyon Silli", "G.V. Prakash", m) >= 90


def test_best_match_picks_the_highest():
    a = post(1, title="Veyyon Silli (Remix)", performer="Prakash")
    b = post(2, title="Veyyon Silli", performer="Prakash")
    s, m = cf.best_match("Veyyon Silli", "Prakash", [a, b])
    assert m.id == 2 and s >= 90


def test_queries():
    q = cf.queries('Veyyon Silli (From "SP")', "G.V.Prakash Kumar")
    assert q[0] == "Veyyon Silli" and len(q) == 2


def failed_job(conn, title, artist, status="failed"):
    sid = conn.execute("INSERT INTO searches (user, query, kind, status, created_at, updated_at) "
                       "VALUES ('u', ?, 'song', 'done', ?, ?)", (title, time.time(), time.time())).lastrowid
    cid = conn.execute("INSERT INTO candidates (search_id, idx, result_id, title, artist, album, score, kind, "
                       "reasons) VALUES (?,0,'r',?,?,'',1,'song','')", (sid, title, artist)).lastrowid
    return conn.execute("INSERT INTO jobs (user, candidate_id, status, error, created_at, updated_at) "
                        "VALUES ('u', ?, ?, 'no', ?, ?)", (cid, status, time.time(), time.time())).lastrowid


def test_untried_skips_tried_and_recent(conn):
    a = failed_job(conn, "A", "x")
    b = failed_job(conn, "B", "x")
    cf.untried(conn)
    cf.mark(conn, a, "none")
    ids = [s["id"] for s in cf.untried(conn)]
    assert ids == [b]
    assert a in [s["id"] for s in cf.untried(conn, now=time.time() + cf.RETRY_AFTER_S + 5)]


class FakeSource:
    def __init__(self, posts):
        self.posts = posts

    async def _call(self, fn, *a, **k):
        return await fn(*a, **k)


class FakeClient:
    def __init__(self, by_channel):
        self.by_channel = by_channel

    async def get_entity(self, name):
        return name

    async def get_messages(self, ent, search=None, limit=0):
        return self.by_channel.get(ent, [])


class FakeWorker:
    def __init__(self, conn, ok=True):
        self.conn, self.ok, self.taken, self.source = conn, ok, [], FakeSource([])

    async def _take(self, jid, cand, picked):
        self.taken.append((jid, picked.file_key, picked.mime))
        if self.ok:
            db.update_job(self.conn, jid, status="downloaded", error=None)
        return self.ok

    async def import_job(self, jid):
        db.update_job(self.conn, jid, status="ready")


def run(coro):
    return asyncio.run(coro)


def test_sweep_finds_and_imports(conn, monkeypatch):
    monkeypatch.setenv("CHANNEL_FALLBACK_CHANNELS", "one,two")
    jid = failed_job(conn, "Veyyon Silli", "G.V.Prakash Kumar")
    hit = post(7, title="Veyyon Silli", performer="G.V. Prakash Kumar")
    w = FakeWorker(conn)
    fb = cf.ChannelFallback(w, FakeClient({"two": [hit]}), gap_s=0)
    out = run(fb.sweep_once())
    assert out["found"] == 1
    assert db.get_job(conn, jid)["status"] == "ready"
    assert w.taken == [(jid, "ch:two:7", "audio/flac")]
    assert conn.execute("SELECT result, channel FROM channel_tries").fetchone()[:] == ("found", "two")


def test_sweep_marks_none_when_nothing_matches(conn, monkeypatch):
    monkeypatch.setenv("CHANNEL_FALLBACK_CHANNELS", "one")
    jid = failed_job(conn, "Veyyon Silli", "Prakash")
    fb = cf.ChannelFallback(FakeWorker(conn), FakeClient({"one": [post(3, title="Other", performer="Prakash")]}),
                            gap_s=0)
    assert run(fb.sweep_once())["none"] == 1
    assert db.get_job(conn, jid)["status"] == "failed"
    assert cf.untried(conn) == []


def test_rejected_download_leaves_the_old_failure(conn, monkeypatch):
    monkeypatch.setenv("CHANNEL_FALLBACK_CHANNELS", "one")
    jid = failed_job(conn, "Veyyon Silli", "Prakash")
    w = FakeWorker(conn, ok=False)
    fb = cf.ChannelFallback(w, FakeClient({"one": [post(3, title="Veyyon Silli", performer="Prakash")]}), gap_s=0)
    out = run(fb.sweep_once())
    assert out["error"] == 1 and db.get_job(conn, jid)["status"] != "ready"


def test_channels_default_and_off(monkeypatch):
    monkeypatch.delenv("CHANNEL_FALLBACK_CHANNELS", raising=False)
    assert cf.channels() == ["retroaudios", "HiResTrackscom"]
    monkeypatch.setenv("CHANNEL_FALLBACK", "0")
    assert not cf.enabled()
