"""server-fixes-v1 #2: a song search is `in_library` only when the text names
the song AND its artist; a title alone still asks the bot and returns the owned
song as owned_hint. A user's newer search supersedes their older one."""

import asyncio
from dataclasses import replace

import pytest
from fastapi.testclient import TestClient

from tgfetch import db, search_owned
from tgfetch.config import settings
from tgfetch.api import create_app
from tgfetch.worker import Worker

from test_api import TOKEN, cfg, h  # noqa: F401  (fixture: cfg)
from test_worker import ROWDY, FakeSource, _no_llm, _search, fakes  # noqa: F401  (autouse fixture)


@pytest.fixture
def wcfg(tmp_path):
    return replace(settings, staging_dir=tmp_path / "staging", library_dir=tmp_path / "music",
                   llm_api_key="", watch_wait_s=0, scan_wait_s=0)

LIB = [
    {"id": "p1", "title": "Pondatti", "artist": "Anirudh Ravichander • Arivu", "album": "Pondatti",
     "suffix": "flac", "duration": 220.0},
    {"id": "d1", "title": "Daavudi", "artist": "Anirudh Ravichander, Deepthi Suresh", "album": "Devara",
     "suffix": "flac", "duration": 200.0},
    {"id": "k1", "title": "Kanne Kanne", "artist": "Sam Cs", "album": "Kanne Kanne", "suffix": "flac", "duration": 240.0},
]


def test_title_alone_is_not_clearly_named():
    assert search_owned.clearly_named("pondatti", LIB) is None
    assert search_owned.clearly_named("daavudi", LIB) is None


def test_title_and_artist_name_the_song():
    assert search_owned.clearly_named("pondatti anirudh", LIB)["id"] == "p1"
    assert search_owned.clearly_named("anirudh pondatti", LIB)["id"] == "p1"
    assert search_owned.clearly_named("daavudi deepthi suresh", LIB)["id"] == "d1"
    assert search_owned.clearly_named("kanne kanne sam cs", LIB)["id"] == "k1"


def test_other_artist_words_do_not_name_it():
    assert search_owned.clearly_named("pondatti sid sriram", LIB) is None
    assert search_owned.clearly_named("pondatti remix", LIB) is None


def test_title_search_asks_the_bot_and_returns_the_owned_hint(conn, wcfg):
    src = FakeSource(ROWDY)
    w = Worker(src, conn, wcfg, library_loader=lambda: [dict(r) for r in LIB], verify=_no_llm)
    s = _search(conn, w, "pondatti")
    assert s["status"] != "in_library"
    assert src.searches > 0                                       # the bot was asked
    assert s["library"]["hint"] == {"song_id": "p1", "title": "Pondatti",
                                    "artist": "Anirudh Ravichander • Arivu", "album": "Pondatti"}


def test_title_and_artist_search_ends_owned_without_the_bot(conn, wcfg):
    src = FakeSource(ROWDY)
    w = Worker(src, conn, wcfg, library_loader=lambda: [dict(r) for r in LIB], verify=_no_llm)
    s = _search(conn, w, "pondatti anirudh")
    assert s["status"] == "in_library" and src.searches == 0
    assert s["library"]["verdict"] == "in_library" and s["library"]["matches"][0]["id"] == "p1"


def test_api_sends_owned_hint(conn, cfg):
    client = TestClient(create_app(cfg, conn, {"telegram": lambda: True, "worker": lambda: True}))
    sid = client.post("/searches", json={"query": "pondatti"}, headers=h()).json()["search_id"]
    db.claim_search(conn)
    db.finish_search(conn, sid, "done", library=search_owned.with_hint(
        {"query": "pondatti", "artist": "", "verdict": "in_library",
         "matches": [{"id": "p1", "title": "Pondatti", "artist": "Anirudh", "album": "P", "score": 100.0}]}))
    got = client.get(f"/searches/{sid}", headers=h()).json()
    assert got["owned_hint"] == {"song_id": "p1", "title": "Pondatti", "artist": "Anirudh", "album": "P"}
    sid2 = client.post("/searches", json={"query": "rowdy baby"}, headers=h()).json()["search_id"]
    assert client.get(f"/searches/{sid2}", headers=h()).json()["owned_hint"] is None


def test_newer_search_supersedes_the_users_older_one(conn, cfg):
    cfg = replace(cfg, searches_per_day=0)
    client = TestClient(create_app(cfg, conn, {"telegram": lambda: True, "worker": lambda: True}))
    first = client.post("/searches", json={"query": "daavudi"}, headers=h()).json()["search_id"]
    other = client.post("/searches", json={"query": "daavudi"}, headers=h("subi")).json()["search_id"]
    link = db.create_search(conn, "admin", "https://www.deezer.com/playlist/1", kind="link")
    second = client.post("/searches", json={"query": "daavudi", "kind": "album"}, headers=h()).json()["search_id"]
    status = {r["id"]: r["status"] for r in conn.execute("SELECT id, status FROM searches")}
    assert status[first] == "superseded"
    assert status[other] == "queued"            # another user's search is untouched
    assert status[link] == "queued"             # a playlist link preview is not a type switch
    assert status[second] == "queued"
    assert client.get(f"/searches/{first}", headers=h()).json()["status"] == "superseded"


def test_superseded_search_stops_before_asking_the_bot(conn, wcfg):
    src = FakeSource(ROWDY)
    w = Worker(src, conn, wcfg, library_loader=lambda: [dict(r) for r in LIB], verify=_no_llm)
    sid = db.create_search(conn, "admin", "rowdy baby")
    row = db.claim_search(conn)
    search_owned.supersede_older(conn, "admin", sid + 1)
    asyncio.run(w.run_search(row))
    assert src.searches == 0
    assert db.get_search(conn, sid)["status"] == "superseded"


def test_finish_and_requeue_never_overwrite_superseded(conn):
    sid = db.create_search(conn, "admin", "x")
    db.claim_search(conn)
    search_owned.supersede_older(conn, "admin", sid + 1)
    db.finish_search(conn, sid, "done")
    db.requeue_search(conn, sid, 1, "slow")
    assert db.get_search(conn, sid)["status"] == "superseded"
    assert db.claim_search(conn) is None
