"""server-fixes-v1 #4: YouTube / YouTube Music playlist links, read as a list of
names only (recorded ytmusicapi get_playlist answers, no network), cleaned,
owned-checked, and fetched one by one from the music bot by name. The bot is
never sent the YouTube link and nothing is ever requested from YouTube except
the list itself."""

import asyncio
import json
from pathlib import Path

import pytest

from tgfetch import db, links, titles, youtube_batch, youtube_list
from tgfetch.rank import Candidate

from test_links import BotSource, _file, quick  # noqa: F401  (fixture: quick)
from test_worker import _no_llm, cfg, fakes  # noqa: F401  (fixtures)
from tgfetch.worker import Worker

FIX = json.loads((Path(__file__).parent / "fixtures" / "yt_get_playlist.json").read_text(encoding="utf-8"))
ANIRUDH = "PLi5FjsAgn0124KxL4lV8MZffBSCsru-N9"      # YouTube Music tracks (ATV/OMV)
MOTIVATION = "PLvx1Z92uzO9PhwqcXbMml-14j-ALCkXVY"   # plain lyric / video uploads mixed in
LEO = "OLAK5uy_lz6hivsJCRUSB4wYdCUhRCqOVZEL89ccs"   # an album
BREEZY = "PL-LE57BzcmzHZ1c--Q1QYBV3kopk992jQ"       # mostly label uploads, one unavailable


class FakeYT:
    calls = []

    def get_playlist(self, pid, limit=None):
        FakeYT.calls.append((pid, limit))
        if pid not in FIX:
            raise Exception("not found")
        return FIX[pid]


@pytest.fixture(autouse=True)
def no_youtube(monkeypatch):
    """No test may reach YouTube: the client is always the recorded one."""
    FakeYT.calls = []
    monkeypatch.setattr(youtube_list, "_client", lambda: FakeYT())


# ── links ────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("url", [
    f"https://www.youtube.com/playlist?list={ANIRUDH}",
    f"https://youtube.com/playlist?list={ANIRUDH}&si=abc",
    f"https://m.youtube.com/playlist?list={ANIRUDH}",
    f"https://music.youtube.com/playlist?list={ANIRUDH}&feature=share",
    f"https://www.youtube.com/watch?v=dQw4w9WgXcQ&list={ANIRUDH}&index=3",
    f"https://youtu.be/dQw4w9WgXcQ?list={ANIRUDH}",
    f"  https://music.youtube.com/playlist?list={ANIRUDH}#frag  ",
    f"https://user:pw@www.youtube.com/playlist?list={ANIRUDH}",
])
def test_accepted_youtube_links(url):
    assert links.parse_link(url) == ("youtube", ANIRUDH)
    assert links.canonical(*links.parse_link(url)) == f"https://music.youtube.com/playlist?list={ANIRUDH}"


def test_album_playlist_link():
    assert links.parse_link(f"https://music.youtube.com/playlist?list={LEO}") == ("youtube", LEO)


@pytest.mark.parametrize("url,says", [
    ("https://www.youtube.com/playlist?list=RDCLAK5uy_kmPRjHDECIcuVwnKsx2Ng7fyNgFKWNJFs", "mixes"),
    ("https://www.youtube.com/playlist?list=LL", "private"),
    ("https://music.youtube.com/playlist?list=LM", "private"),
    ("https://www.youtube.com/playlist?list=WL", "private"),
    ("https://www.youtube.com/playlist?list=UUabcdefghijklmnopqrstuv", "channel"),
    (f"http://www.youtube.com/playlist?list={ANIRUDH}", "https://"),
    ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "isn't a playlist"),
    (f"https://www.youtube.com/channel/UC123?list={ANIRUDH}", "isn't a playlist"),
    (f"https://www.youtube.com/playlist?list={ANIRUDH}&list=PLaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "isn't a playlist"),
    ("https://www.youtube.com/playlist?list=PL<script>alert(1)</script>", "doesn't look right"),
    ("https://www.youtube.com/playlist?list=PL%27%3B--aaaaaaaaaaaa", "doesn't look right"),
    (f"https://www.youtube.com.evil.example/playlist?list={ANIRUDH}", "Only Deezer, Spotify and YouTube"),
    (f"https://music.apple.com/in/playlist/x/pl.u-123", "doesn't take this site"),
])
def test_refused_youtube_links_say_why(url, says):
    with pytest.raises(links.LinkError, match=says):
        links.parse_link(url)


# ── reading the list (names only) ────────────────────────────────────────────

def test_track_list_from_youtube_music():
    name, songs = asyncio.run(links.fetch_tracks("youtube", ANIRUDH))
    assert name == "Anirudh Hits" and len(songs) == 31
    assert FakeYT.calls == [(ANIRUDH, youtube_list.MAX_TRACKS)]
    vaathi = next(c for c in songs if c.title == "Vaathi Coming")
    assert vaathi.artist == "Anirudh Ravichander, Gana Balachandar" and vaathi.album == "Master"
    assert vaathi.duration_s == 229 and vaathi.cover_url is None and vaathi.link is None
    assert youtube_batch.meta(vaathi)["raw"] == 'Vaathi Coming (From "Master")'


def test_unavailable_items_are_left_out():
    _, songs = asyncio.run(links.fetch_tracks("youtube", BREEZY))
    assert len(songs) == 21 and "Thirakkaatha" not in [c.title for c in songs]


def test_list_is_capped_at_300(monkeypatch):
    big = {"title": "Big", "tracks": [{"videoId": f"v{i:05d}", "title": f"Song {i}", "artists": [{"name": "A"}],
                                       "duration_seconds": 200, "videoType": "MUSIC_VIDEO_TYPE_ATV"}
                                      for i in range(450)]}
    FIX["big"] = big
    try:
        _, songs = asyncio.run(youtube_list.fetch("big", client_factory=FakeYT))
        assert len(songs) == 300
    finally:
        FIX.pop("big")


def test_private_or_missing_playlist_is_a_clear_error():
    with pytest.raises(links.LinkError, match="private or no longer exists"):
        asyncio.run(links.fetch_tracks("youtube", "PLdoesnotexist000000000"))


def test_titles_are_untrusted_text():
    data = {"title": "x\x00y", "tracks": [{"videoId": "v1", "title": "Song‮\x07 One" + "a" * 400,
                                           "artists": [{"name": "Some\x1bOne"}], "videoType": "MUSIC_VIDEO_TYPE_ATV"}]}
    name, songs = youtube_list.to_candidates(data)
    assert "\x00" not in name and "‮" not in youtube_batch.meta(songs[0])["raw"]
    assert len(youtube_batch.meta(songs[0])["raw"]) <= 300 and youtube_batch.meta(songs[0])["unreadable"]


# ── cleaning titles (real ones from the recorded lists) ──────────────────────

KNOWN = titles.Known(artists={"anirudh ravichander", "ar rahman", "harris jayaraj", "g v prakash kumar",
                              "hiphop tamizha", "sam cs", "vidyasagar"},
                     films={"master", "kadhalan"})


@pytest.mark.parametrize("raw,artists,vt,title,film,artist_has", [
    ('Raga of Revenge | Leo | Anirudh | Lyric Video', ["Sony Music South"], "MUSIC_VIDEO_TYPE_UGC",
     "Raga of Revenge", "", None),
    ('Vaathi Coming (From "Master")', ["Anirudh Ravichander"], "MUSIC_VIDEO_TYPE_ATV",
     "Vaathi Coming", "Master", "Anirudh Ravichander"),
    ("Porkkalam Tamil Lyric Video | Dhanush | G.V. Prakash Kumar", ["Kay Kay"], "MUSIC_VIDEO_TYPE_OMV",
     "Porkkalam", None, "G.V. Prakash Kumar"),
    ("Petta - Ilamai Thirumbudhe Official Video (Tamil) | Rajinikanth, Simran | Anirudh Ravichander",
     ["Sony Music South"], "MUSIC_VIDEO_TYPE_UGC", "Ilamai Thirumbudhe", "Petta", "Anirudh Ravichander"),
    ("Rasaali - Video Song | Achcham Yenbadhu Madamaiyada | STR | A R Rahman", ["Ondraga Entertainment"],
     "MUSIC_VIDEO_TYPE_UGC", "Rasaali", "Achcham Yenbadhu Madamaiyada", "A R Rahman"),
    ("Sillunu Oru Kadhal Tamil Movie Songs HD | Munbe Vaa Song | Suriya | Bhumika | Jyothika | AR Rahman",
     ["Star Music India"], "MUSIC_VIDEO_TYPE_UGC", "Munbe Vaa", "Sillunu Oru Kadhal", "AR Rahman"),
    ("Kollayile Thennai | Kadhalan (1994) | A.R. Rahman [HD]", ["Kejinsan Ayathurai"], "MUSIC_VIDEO_TYPE_UGC",
     "Kollayile Thennai", "Kadhalan", "A.R. Rahman"),
    ("Takkaru takkaru song by hip hop tamizha Hd", ["Santhosh Kumaran"], "MUSIC_VIDEO_TYPE_UGC",
     "Takkaru takkaru", "", "hip hop tamizha"),
    ("Veesum Soorai Katre Full Video Song | KGF Tamil Movie | Yash | Prashanth Neel | Hombale Films",
     ["Lahari Music"], "MUSIC_VIDEO_TYPE_UGC", "Veesum Soorai Katre", "KGF", None),
    ("Tamil Songs | இளங்காத்து வீசுதே | Elangaathu Veesudhey | Ilaiyaraja Songs",
     ["Movie World Tamil Film Songs"], "MUSIC_VIDEO_TYPE_UGC", "Elangaathu Veesudhey", None, None),
    ("nimirnthu nil from saroja", ["Manimekalai Tamil"], "MUSIC_VIDEO_TYPE_UGC", "nimirnthu nil", "saroja", None),
    ("Arabic Kuthu - Halamithi Habibo (From \"Beast\")", ["Anirudh Ravichander", "Jonita Gandhi"],
     "MUSIC_VIDEO_TYPE_ATV", "Arabic Kuthu", "Beast", "Jonita Gandhi"),
])
def test_clean_real_titles(raw, artists, vt, title, film, artist_has):
    c = titles.clean(raw, artists, vt, "", KNOWN)
    assert c["title"] == title or title in c["alts"] or c["title"].startswith(title)
    if film is not None:
        assert c["film"] == film
    if artist_has:
        assert artist_has in c["artists"]
    assert not any(titles.is_label(a) for a in c["artists"])        # labels are never artists
    assert c["raw"] == raw


@pytest.mark.parametrize("raw", ["Official Video", "Lyrical Video | Official", "", "|||", "x" * 130])
def test_unreadable_titles(raw):
    assert titles.clean(raw, [], "MUSIC_VIDEO_TYPE_UGC")["unreadable"]


@pytest.mark.parametrize("raw,word", [("Verappa (Female Version) | Lyric Video", "female"),
                                     ("Kaavaalaa - Remix | Official Video", "remix"),
                                     ("Usure Pogudhey Unplugged | Full Song", "unplugged")])
def test_version_words_are_kept(raw, word):
    assert word in titles.clean(raw, [], "MUSIC_VIDEO_TYPE_UGC")["title"].lower()


# ── matching a bot result ────────────────────────────────────────────────────

def _song(**k):
    base = {"title": "Vaathi Coming", "alts": [], "artist": "Anirudh Ravichander", "film": "Master",
            "duration_s": 229, "video_type": "MUSIC_VIDEO_TYPE_ATV"}
    return {**base, **k}


def test_matcher_takes_title_artist_and_length():
    good = Candidate(0, "a", 'Vaathi Coming (From "Master")', "Anirudh Ravichander, Gana Balachandar", "Master",
                     duration_s=228)
    remix = Candidate(1, "b", "Vaathi Coming - Remix", "Anirudh Ravichander", "x", duration_s=229)
    other = Candidate(2, "c", "Vaathi Coming", "Someone Else", "x", duration_s=150)
    longer = Candidate(3, "d", "Vaathi Coming", "Anirudh Ravichander", "x", duration_s=300)
    assert youtube_batch.score(_song(), good) is not None
    assert youtube_batch.score(_song(), remix) is None
    assert youtube_batch.score(_song(), other) is None
    assert youtube_batch.score(_song(), longer) is None
    assert youtube_batch.best(_song(), [remix, other, good, longer])[0] is good


def test_plain_video_may_be_a_little_longer_than_the_song():
    song = _song(video_type="MUSIC_VIDEO_TYPE_UGC", duration_s=270)
    track = Candidate(0, "a", "Vaathi Coming", "Anirudh Ravichander", "Master", duration_s=229)
    assert youtube_batch.score(song, track) is not None
    assert youtube_batch.score(_song(duration_s=270), track) is None      # an ATV track must be the same length


def test_no_artist_needs_length_or_film():
    song = _song(artist="", duration_s=None, film="")
    assert youtube_batch.score(song, Candidate(0, "a", "Vaathi Coming", "X", "", duration_s=229)) is None
    assert youtube_batch.score(_song(artist="", film=""), Candidate(0, "a", "Vaathi Coming", "X", "",
                                                                    duration_s=230)) is not None


def test_film_breaks_a_tie():
    a = Candidate(0, "a", "Anbenum", "Anirudh Ravichander", "Some Compilation", duration_s=215)
    b = Candidate(1, "b", "Anbenum", "Anirudh Ravichander", "Leo (Original Motion Picture Soundtrack)", duration_s=215)
    assert youtube_batch.best(_song(title="Anbenum", film="Leo", duration_s=215), [a, b])[0] is b


# ── preview and download through the worker ──────────────────────────────────

URL = f"https://music.youtube.com/playlist?list={LEO}"
LIBRARY = [{"id": "nd-naa", "title": 'Naa Ready (From "Leo")', "artist": "Anirudh Ravichander, Vijay",
            "album": "Leo", "suffix": "flac", "duration": 249.0}]


def _worker(conn, cfg, src):
    return Worker(src, conn, cfg, library_loader=lambda: [dict(r) for r in LIBRARY], verify=_no_llm)


def _preview(conn, w):
    sid = db.create_search(conn, "admin", URL, kind="link")
    asyncio.run(w.run_search(db.claim_search(conn)))
    return db.get_search(conn, sid)


def test_preview_lists_the_album_and_marks_owned_without_telegram(conn, cfg):
    src = BotSource()
    s = _preview(conn, _worker(conn, cfg, src))
    assert s["status"] == "done" and s["title"] == "Leo (Original Motion Picture Soundtrack)"
    got = {c["title"]: c["library"] for c in s["candidates"]}
    assert got["Naa Ready"] == "in_library" and got["Badass"] == "not_found"
    assert src.started == [] and src.searches == 0


def test_api_shows_source_title_and_unreadable(conn, cfg):
    from fastapi.testclient import TestClient
    from tgfetch.api import create_app
    from test_api import h
    from dataclasses import replace as rp
    s = _preview(conn, _worker(conn, cfg, BotSource()))
    client = TestClient(create_app(rp(cfg, internal_token="t0ken", allowed_users=("admin",)), conn,
                                   {"telegram": lambda: True, "worker": lambda: True}))
    got = client.get(f'/searches/{s["id"]}', headers=h()).json()
    c = got["candidates"][0]
    assert c["source_title"] and c["unreadable"] is False and got["owned_hint"] is None


def test_youtube_batch_never_sends_the_link_and_fetches_by_name(conn, cfg, quick):
    src = BotSource()
    found = {"badass": Candidate(0, "r-badass", "Badass", "Anirudh Ravichander, Vishnu Edavan",
                                 "Leo (Original Motion Picture Soundtrack)", link="track/1", duration_s=230)}
    queries = []

    async def search(q, kind="song"):
        queries.append(q)
        src.searches += 1
        return [found[k] for k in found if k in q.lower()]
    src.search = search

    async def pick_link(link):
        return _file(900, "Badass", 230)
    src.pick_link = pick_link
    w = _worker(conn, cfg, src)
    s = _preview(conn, w)
    ids = [c["id"] for c in sorted(s["candidates"], key=lambda c: c["idx"])]
    bid = db.create_batch(conn, "admin", "playlist", s["title"], ids, link=s["query"])

    async def go():
        await w.run_batch(db.claim_batch(conn))
        await w.drain()
    asyncio.run(go())
    b = db.get_batch(conn, bid)
    by_title = {j["title"]: j for j in b["jobs"]}
    assert src.started == []                                    # the bot never got the YouTube link
    assert by_title["Naa Ready"]["status"] == "duplicate"       # owned: settled, never searched
    assert by_title["Badass"]["status"] == "ready" and src.downloads == 1
    assert by_title["Bloody Sweet"]["status"] == "failed"
    assert "not found on the music bot" in by_title["Bloody Sweet"]["error"]
    assert "YouTube" in by_title["Bloody Sweet"]["error"]
    assert not any("naa ready" in q.lower() for q in queries)
    assert all(len([q for q in queries if j.lower() in q.lower()]) <= youtube_batch.MAX_QUERIES
               for j in by_title)


def test_youtube_batch_waits_when_the_bot_is_silent(conn, cfg, quick):
    from tgfetch.sources.base import SourceError
    src = BotSource()

    async def search(q, kind="song"):
        raise SourceError("The music bot didn't answer in time")
    src.search = search
    w = _worker(conn, cfg, src)
    s = _preview(conn, w)
    bid = db.create_batch(conn, "admin", "playlist", s["title"], [c["id"] for c in s["candidates"]], link=s["query"])
    asyncio.run(w.run_batch(db.claim_batch(conn)))
    b = db.get_batch(conn, bid)
    assert db.batch_status(conn, bid) == "queued"               # deferred, tried again later
    assert {j["status"] for j in b["jobs"]} <= {"waiting", "duplicate"}
