"""data-queue-v1: tg-fetcher's hook (a job that becomes `ready` joins the hidden queue) and its isolation."""
import sqlite3

import pytest

from navivibe import data_queue_store as store
from tgfetch import data_queue_hook, db


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(store, "PATH", str(tmp_path / "q.db"))
    monkeypatch.setattr(store, "DETAILS_PATH", str(tmp_path / "details.db"))
    store.forget_paths()
    monkeypatch.setattr(data_queue_hook, "_catalog_row", lambda sid: {"isrc": "INA000000001", "duration": 201})
    monkeypatch.delenv("DATA_QUEUE_OFF", raising=False)
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(db.SCHEMA)
    db._migrate(conn)
    return conn


def make_job(conn, link=None, title="Song", artist="Artist"):
    sid = conn.execute("INSERT INTO searches (user, query, created_at, updated_at) VALUES ('u','q',1,1)").lastrowid
    cid = conn.execute("INSERT INTO candidates (search_id, idx, result_id, title, artist, album, score, kind, reasons) "
                       "VALUES (?,0,'r',?,?,'Alb',1,'song','')", (sid, title, artist)).lastrowid
    bid = None
    if link:
        bid = conn.execute("INSERT INTO batches (user, kind, title, candidate_ids, link, status, created_at, updated_at) VALUES ('u','playlist','t','[]',?,'running',1,1)",
                           (link,)).lastrowid
    return conn.execute("INSERT INTO jobs (user, candidate_id, batch_id, status, created_at, updated_at) "
                        "VALUES ('u',?,?,'scanning',1,1)", (cid, bid)).lastrowid


def waiting():
    c = store.connect()
    return [dict(r) for r in c.execute("SELECT * FROM queue")]


def test_ready_job_joins_the_queue(env):
    j = make_job(env)
    db.update_job(env, j, status="ready", nd_song_id="nd1")
    rows = waiting()
    assert len(rows) == 1 and rows[0]["song_id"] == "nd1" and rows[0]["source"] == "request"
    assert rows[0]["isrc"] == "INA000000001"


def test_other_statuses_and_no_song_id_do_nothing(env):
    j = make_job(env)
    db.update_job(env, j, status="imported")
    db.update_job(env, j, status="ready")
    assert waiting() == []


def test_source_comes_from_the_batch_link(env):
    db.update_job(env, make_job(env, "https://music.youtube.com/playlist?list=x"), status="ready", nd_song_id="a")
    db.update_job(env, make_job(env, "exportify:7", title="Other"), status="ready", nd_song_id="b")
    assert {r["song_id"]: r["source"] for r in waiting()} == {"a": "youtube", "b": "exportify"}


def test_a_song_with_real_features_is_not_queued(env, tmp_path):
    c = sqlite3.connect(str(tmp_path / "details.db"))
    c.execute("CREATE TABLE spotify_details (song_id TEXT PRIMARY KEY, energy REAL, valence REAL)")
    c.execute("INSERT INTO spotify_details VALUES ('nd1', .5, .5)")
    c.commit()
    c.close()
    db.update_job(env, make_job(env), status="ready", nd_song_id="nd1")
    assert waiting() == []


def test_a_queue_failure_never_fails_the_update(env, monkeypatch, tmp_path):
    monkeypatch.setattr(store, "PATH", str(tmp_path))                  # a folder, not a file
    j = make_job(env)
    db.update_job(env, j, status="ready", nd_song_id="nd1")
    assert db.get_job(env, j)["status"] == "ready"
    monkeypatch.setattr(data_queue_hook, "on_ready", lambda *a: 1 / 0)
    db.update_job(env, j, status="ready", nd_song_id="nd2")
    assert db.get_job(env, j)["nd_song_id"] == "nd2"


def test_the_kill_switch(env, monkeypatch):
    monkeypatch.setenv("DATA_QUEUE_OFF", "1")
    db.update_job(env, make_job(env), status="ready", nd_song_id="nd1")
    assert waiting() == []
