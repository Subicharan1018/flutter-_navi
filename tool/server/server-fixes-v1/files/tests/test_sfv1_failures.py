"""server-fixes-v1 #3: the download queue's failed list leaves out songs that
are in the library now (by any route: the bot later, a dropped file)."""

from fastapi.testclient import TestClient

from tgfetch import db, library_sweep as ls
from tgfetch.api import create_app
from tgfetch.rank import Candidate

from test_api import TOKEN, cfg, h  # noqa: F401  (fixture: cfg)

LIBRARY = [
    {"id": "kk", "title": "Kannala Kannala", "artist": "Hiphop Tamizha • Kaushik Krish • Padmalatha",
     "album": "Thani Oruvan (Original Motion Picture Soundtrack)", "suffix": "flac", "duration": 215.46},
    {"id": "io", "title": "Idhazhin Oram", "artist": "Anirudh Ravichander • Ajesh • Aishwarya R Dhanush",
     "album": "3 (Original Motion Picture Soundtrack)", "suffix": "flac", "duration": 204.87},
    {"id": "un", "title": "Untouchable (No)", "artist": "Loretz", "album": "x", "suffix": "flac", "duration": 190.0},
    {"id": "th", "title": "Thozhi", "artist": "Govind Vasantha", "album": "Thozhi", "suffix": "flac", "duration": 200.0},
]


def _failed(conn, title, artist, duration=None, status="failed", error="the music bot didn't send this song",
            user="admin"):
    sid = db.create_search(conn, user, "x", kind="tracks", status="done")
    db.save_candidates(conn, sid, [Candidate(0, "r", title, artist, "", duration_s=duration)])
    cid = db.get_search(conn, sid)["candidates"][0]["id"]
    jid = db.create_job(conn, user, cid)
    db.update_job(conn, jid, status=status, error=error)
    return jid


def _titles(conn):
    return [f["title"] for f in db.failed_songs(conn)]


def test_owned_songs_leave_the_failed_list(conn):
    _failed(conn, "Kannala Kannala - The Melting Point of Love", "Hiphop Tamizha, Padmalatha", 216)
    _failed(conn, "Idhazhin Oram - The Innocence of Love", "Anirudh Ravichander", 205)
    keep = [
        _failed(conn, "Untouchable (No) - Sped Up", "Loretz", 174),          # a sped-up cut is another song
        _failed(conn, "Thozhi", "Someone Else"),                             # same title, nobody in common
        _failed(conn, "Idhazhin Oram", "Anirudh Ravichander", 120),         # 85 s shorter: another cut
        _failed(conn, "Paalaabhishegam", "Unnikrishnan", 300),              # not in the library
    ]
    assert len(_titles(conn)) == 6
    assert ls.sweep_failures(conn, LIBRARY) == {"resolved": 2}
    assert sorted(_titles(conn)) == ["Idhazhin Oram", "Paalaabhishegam", "Thozhi", "Untouchable (No) - Sped Up"]
    assert {r[0] for r in conn.execute("SELECT nd_song_id FROM resolved_failures")} == {"kk", "io"}
    assert len(keep) == 4


def test_sweep_is_idempotent_and_skips_cancelled(conn):
    _failed(conn, "Kannala Kannala", "Hiphop Tamizha")
    _failed(conn, "Idhazhin Oram", "Anirudh Ravichander", error="cancelled")
    assert ls.sweep_failures(conn, LIBRARY) == {"resolved": 1}
    assert ls.sweep_failures(conn, LIBRARY) == {"resolved": 0}
    assert _titles(conn) == []


def test_queue_endpoint_drops_resolved_failures(conn, cfg):
    _failed(conn, "Kannala Kannala - The Melting Point of Love", "Hiphop Tamizha")
    _failed(conn, "Paalaabhishegam", "Unnikrishnan")
    client = TestClient(create_app(cfg, conn, {"telegram": lambda: True, "worker": lambda: True}))
    before = client.get("/queue", headers=h()).json()["failures"]
    ls.sweep(conn, LIBRARY)
    after = client.get("/queue", headers=h()).json()["failures"]
    assert len(before) == 2 and [f["title"] for f in after] == ["Paalaabhishegam"]
