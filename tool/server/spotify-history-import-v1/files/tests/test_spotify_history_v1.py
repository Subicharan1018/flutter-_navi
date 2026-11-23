"""spotify-history-import-v1: validation, the skip rule, matching, the listening-log rows, idempotency, the
Wishlist, undo and the routes. Made-up songs and a made-up account; no network.

    cd /opt/tg-fetcher && venv/bin/python -m pytest tests/test_spotify_history_v1.py -q
"""

import sqlite3

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from tgfetch import db, history_import as hi, spotify_history as sh, spotify_history_api

B = 1_700_000_000                   # a play that ended at this time
NOW = B + 100_000
LIB = [
    {"id": "s1", "title": "Neela Megam", "artist": "Aarav Kumar • Meena Rao", "album": "Neela", "duration": 250.0,
     "isrc": ""},
    {"id": "s2", "title": 'Kaadhal Mazhai (From "Mazhai Kaalam")', "artist": "Diya Ram", "album": "Mazhai Kaalam",
     "duration": 200.0, "isrc": ""},
    {"id": "s3", "title": "Veera Nadai", "artist": "Karthik Sen", "album": "Veera", "duration": 180.0, "isrc": ""},
    {"id": "s4", "title": "Veera Nadai (Sped Up)", "artist": "Karthik Sen", "album": "Veera", "duration": 150.0,
     "isrc": ""},
]


def play(t=B, ms=250_000, title="Neela Megam", artist="Aarav Kumar", end="trackdone", sk=False, album="Neela"):
    return {"t": t, "ms": ms, "title": title, "artist": artist, "album": album, "end": end, "sk": sk}


@pytest.fixture(autouse=True)
def world(tmp_path, monkeypatch):
    monkeypatch.setenv("NAVIVIBE_LOG_DIR", str(tmp_path / "logs"))
    sh._IDX.update(key=None, idx=None, by_id=None)


@pytest.fixture
def conn():
    c = db.connect(":memory:")
    sh.ensure_schema(c)
    yield c
    c.close()


def job(conn, user="vijay", fmt="extended", total=None):
    return sh.create_job(conn, user, fmt, total, now=NOW)[0]


def rows(user="vijay"):
    c = hi.open_log(user)
    c.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in c.execute("SELECT * FROM play_events ORDER BY played_at, id")]
    finally:
        c.close()


# ── validation ───────────────────────────────────────────────────────────────

@pytest.mark.parametrize("raw,why", [
    ("x", "not_object"), (None, "not_object"), ([], "not_object"),
    (play(title=""), "missing_title"), (play(title=5), "missing_title"), (play(title="x" * 301), "title_too_long"),
    (play(artist=""), "missing_artist"), (play(artist=None), "missing_artist"),
    (play(artist="a" * 201), "artist_too_long"),
    (play(t=0), "bad_time"), (play(t=B + 10 ** 7), "bad_time"), (play(t="1700000000"), "bad_time"),
    (play(t=True), "bad_time"), (play(t=float("nan")), "bad_time"), (play(t=1_000_000_000), "bad_time"),
    (play(ms=-1), "bad_ms_played"), (play(ms=7 * 3600 * 1000), "bad_ms_played"), (play(ms="9"), "bad_ms_played"),
    (play(ms=None), "bad_ms_played"), (play(sk="yes"), "bad_skipped"),
])
def test_refused_rows_have_a_reason(raw, why):
    assert sh.clean_row(raw, NOW) == (None, why)


def test_a_good_row_keeps_only_the_needed_fields():
    raw = {**play(), "ip_addr": "1.2.3.4", "conn_country": "IN", "platform": "android", "spotify_track_uri": "x"}
    row, why = sh.clean_row(raw, NOW)
    assert why is None
    assert set(row) == {"t", "ms", "title", "artist", "album", "end", "sk"}
    assert "1.2.3.4" not in repr(row)


def test_odd_end_reason_becomes_other_and_text_is_trimmed():
    row, _ = sh.clean_row(play(title="  Neela   Megam ", end="Some Reason!"), NOW)
    assert row["title"] == "Neela Megam" and row["end"] == "other"
    assert sh.clean_row(play(end="FwdBtn"), NOW)[0]["end"] == "fwdbtn"
    assert sh.clean_row({**play(), "end": None}, NOW)[0]["end"] == ""


# ── the skip rule ────────────────────────────────────────────────────────────

@pytest.mark.parametrize("ms,end,sk,fmt,want", [
    (5_000, "fwdbtn", True, "extended", "skip"),
    (5_000, "backbtn", False, "extended", "skip"),
    (0, "fwdbtn", True, "extended", "skip"),
    (12_000, "endplay", True, "extended", "skip"),          # Spotify's own skipped flag, under 30 s
    (29_999, "fwdbtn", None, "extended", "skip"),
    (30_000, "fwdbtn", True, "extended", "listen"),         # 30 s or more is a listen, even ended by a button
    (45_000, "endplay", True, "extended", "listen"),
    (230_000, "trackdone", False, "extended", "listen"),
    (20_000, "trackdone", False, "extended", "listen"),     # a short song that really finished
    (0, "trackdone", False, "extended", "unclear"),
    (8_000, "logout", False, "extended", "unclear"),        # short, ended another way: not a decision
    (8_000, "unexpected-exit", False, "extended", "unclear"),
    (8_000, "remote", False, "extended", "unclear"),
    (8_000, "", None, "extended", "unclear"),
    (8_000, "", None, "basic", "skip"),                     # the basic export has no reason: short = skip
    (90_000, "", None, "basic", "listen"),
])
def test_skip_rule(ms, end, sk, fmt, want):
    assert sh.skip_decision(ms, end, sk, fmt) == want


def test_measure_uses_the_library_length():
    m = sh.measure("listen", 125_000, "trackdone", 250.0)
    assert m == {"secs": 125.0, "ratio": 0.5, "type": "complete", "reason": "natural"}
    assert sh.measure("listen", 60_000, "endplay", 250.0)["type"] == "skip"       # a partial listen (24 %)
    assert sh.measure("listen", 60_000, "endplay", 250.0)["reason"] == "partial"
    over = sh.measure("listen", 400_000, "trackdone", 250.0)
    assert over["secs"] == 250.0 and over["ratio"] == 1.0                          # never above the song's length
    sk = sh.measure("skip", 4_000, "backbtn", 250.0)
    assert sk["type"] == "skip" and sk["reason"] == "backbtn" and abs(sk["ratio"] - 0.016) < 1e-9
    assert sh.measure("listen", 100_000, "trackdone", None)["ratio"] == pytest.approx(100 / 240)


# ── a page ───────────────────────────────────────────────────────────────────

def test_matched_plays_are_written_with_real_seconds(conn):
    j = job(conn)
    s = sh.page(conn, j["id"], "vijay", LIB, [
        play(t=B, ms=250_000),                                                       # a listen
        play(t=B + 500, ms=4_000, end="fwdbtn", sk=True, title="Veera Nadai", artist="Karthik Sen"),   # a skip
        play(t=B + 900, ms=70_000, end="endplay", sk=False, title="Kaadhal Mazhai", artist="Diya Ram"),  # partial
    ], now=NOW)
    assert (s["imported"], s["listens"], s["skips"], s["wished"], s["rejected_total"]) == (3, 2, 1, 0, 0)
    r = rows()
    assert [x["track_title"] for x in r] == ["Neela Megam", "Veera Nadai", 'Kaadhal Mazhai (From "Mazhai Kaalam")']
    a, b, c = r
    assert a["file_path"] == "s1" and a["session_id"] == "import:spotify" and a["origin"] == "import"
    assert a["event_type"] == "complete" and a["end_reason"] == "natural" and a["listen_ratio"] == 1.0
    assert a["seconds_played"] == 250.0 and a["duration_s"] == 250 and a["schema_version"] == 2
    assert a["played_at"] == B - 250                       # Spotify's time is the END of the play
    assert a["play_id"].startswith("imp:spotify:") and a["quality"] is None and a["weather_code"] is None
    assert b["event_type"] == "skip" and b["end_reason"] == "fwdbtn" and b["seconds_played"] == 4.0
    assert b["listen_ratio"] == pytest.approx(4 / 180)
    assert c["event_type"] == "skip" and c["end_reason"] == "partial" and c["listen_ratio"] == pytest.approx(0.35)
    assert a["ist_hour"] is not None and a["local_hour"] == a["ist_hour"]


def test_a_remix_never_matches_the_plain_song(conn):
    j = job(conn)
    sh.page(conn, j["id"], "vijay", LIB, [play(title="Veera Nadai (Sped Up)", artist="Karthik Sen", ms=150_000)], now=NOW)
    assert [x["file_path"] for x in rows()] == ["s4"]
    sh.page(conn, j["id"], "vijay", LIB, [play(t=B + 5000, title="Veera Nadai (Slowed + Reverb)", artist="Karthik Sen",
                                              ms=150_000)], now=NOW)
    assert [x["file_path"] for x in rows()] == ["s4"]       # the slowed cut is not in the library: wished, not logged


def test_sending_a_page_again_adds_nothing(conn):
    j = job(conn)
    pg = [play(), play(t=B + 400, title="Nothing Like It", artist="Nobody", ms=200_000)]
    first = sh.page(conn, j["id"], "vijay", LIB, pg, now=NOW)
    again = sh.page(conn, j["id"], "vijay", LIB, pg, now=NOW)
    assert (first["imported"], first["wished"], again["imported"], again["wished"], again["already"]) == (1, 1, 1, 1, 2)
    assert len(rows()) == 1
    c = conn.execute("SELECT COUNT(*) FROM exportify_songs").fetchone()[0]
    assert c == 1


def test_the_same_play_twice_in_one_page_counts_once(conn):
    j = job(conn)
    s = sh.page(conn, j["id"], "vijay", LIB, [play(), play()], now=NOW)
    assert s["imported"] == 1 and s["already"] == 1 and len(rows()) == 1


def test_a_near_duplicate_of_a_live_play_is_left_out(conn):
    c = hi.open_log("vijay")
    c.execute("INSERT INTO play_events (track_title, played_at, session_id, play_id) VALUES (?,?,?,?)",
              ("Neela Megam", B - 250 + 60, "app-session", "live-1"))       # the app's own log, a minute off
    c.commit()
    c.close()
    j = job(conn)
    s = sh.page(conn, j["id"], "vijay", LIB, [play(), play(t=B + 3000, ms=250_000)], now=NOW)
    assert s["near_dups"] == 1 and s["imported"] == 1
    assert len(rows()) == 2                                                # live row + the far play


def test_unmatched_listens_go_to_the_wishlist_but_skips_do_not(conn):
    j = job(conn)
    s = sh.page(conn, j["id"], "vijay", LIB, [
        play(t=B, title="Lost Song", artist="Ghost", ms=180_000),
        play(t=B + 300, title="Lost Song", artist="Ghost", ms=181_000),
        play(t=B + 600, title="Only Skipped", artist="Ghost", ms=3_000, end="fwdbtn", sk=True),
        play(t=B + 700, title="Half Heard", artist="Ghost", ms=2_000, end="logout", sk=False),
    ], now=NOW)
    assert (s["wished"], s["skip_misses"], s["unclear"], s["imported"]) == (2, 1, 1, 0)
    assert s["songs_unmatched"] == 1
    songs = conn.execute("SELECT title, state, popularity FROM exportify_songs").fetchall()
    assert [(x["title"], x["state"], x["popularity"]) for x in songs] == [("Lost Song", "wishlist", 2)]
    imp = conn.execute("SELECT name FROM exportify_imports").fetchone()
    assert imp["name"] == "Spotify history"
    assert conn.execute("SELECT status FROM exportify_plans").fetchone()["status"] == "idle"   # nothing auto-fetches
    assert rows() == []


def test_unclear_plays_are_not_imported_or_remembered(conn):
    j = job(conn)
    s = sh.page(conn, j["id"], "vijay", LIB, [play(ms=3_000, end="remote", sk=False)], now=NOW)
    assert s["unclear"] == 1 and s["imported"] == 0 and rows() == []


def test_refused_rows_are_counted_by_reason_and_the_rest_goes_on(conn):
    j = job(conn)
    s = sh.page(conn, j["id"], "vijay", LIB, [play(), "junk", play(title=""), play(ms=-5), play(t=1)], now=NOW)
    assert s["imported"] == 1 and s["rejected_total"] == 4
    assert s["rejected"] == {"bad_ms_played": 1, "bad_time": 1, "missing_title": 1, "not_object": 1}
    s2 = sh.page(conn, j["id"], "vijay", LIB, [play(t=B + 9, title="")], now=NOW)
    assert s2["rejected"]["missing_title"] == 2


def test_basic_export_short_plays_are_skips(conn):
    j = job(conn, fmt="basic")
    s = sh.page(conn, j["id"], "vijay", LIB, [
        play(ms=5_000, end="", sk=None), play(t=B + 400, ms=200_000, end="", sk=None)], now=NOW)
    assert (s["skips"], s["listens"], s["format"]) == (1, 1, "basic")


def test_page_limit_and_shape(conn):
    j = job(conn)
    with pytest.raises(hi.HistoryError):
        sh.page(conn, j["id"], "vijay", LIB, [play()] * 1001, now=NOW)
    with pytest.raises(hi.HistoryError):
        sh.page(conn, j["id"], "vijay", LIB, {"plays": []}, now=NOW)


def test_dates_and_counts_in_the_summary(conn):
    j = job(conn, total=10)
    sh.page(conn, j["id"], "vijay", LIB, [play(t=B), play(t=B + 7200, ms=3_000, end="fwdbtn", sk=True)], now=NOW)
    s = sh.finish(conn, j["id"], "vijay", now=NOW)
    assert s["done"] and s["status"] == "done" and s["total"] == 10 and s["fetched"] == 2
    assert s["oldest_ts"] == B and s["newest_ts"] == B + 7200 and s["songs_matched"] == 1


def test_users_are_separate(conn):
    ja, jb = job(conn, "vijay"), job(conn, "other")
    sh.page(conn, ja["id"], "vijay", LIB, [play()], now=NOW)
    assert rows("other") == [] and len(rows("vijay")) == 1
    with pytest.raises(hi.HistoryError):
        sh.page(conn, ja["id"], "other", LIB, [play()], now=NOW)               # not their job
    sh.page(conn, jb["id"], "other", LIB, [play()], now=NOW)                    # the same play is theirs too
    assert len(rows("other")) == 1


def test_resume_returns_the_open_job_and_a_new_one_after_it_is_done(conn):
    j = job(conn)
    j2, created = sh.create_job(conn, "vijay", "extended", None, now=NOW)
    assert j2["id"] == j["id"] and not created
    sh.finish(conn, j["id"], "vijay")
    j3, created = sh.create_job(conn, "vijay", "extended", None, now=NOW)
    assert created and j3["id"] != j["id"]
    with pytest.raises(hi.HistoryError):
        sh.create_job(conn, "vijay", "csv", None)


def test_undo_takes_back_the_plays_and_the_wishlist(conn):
    j = job(conn)
    sh.page(conn, j["id"], "vijay", LIB, [play(), play(t=B + 400, title="Lost Song", artist="Ghost", ms=180_000)], now=NOW)
    live = hi.open_log("vijay")
    live.execute("INSERT INTO play_events (track_title, played_at, session_id, play_id) VALUES ('x', 1, 's', 'live-9')")
    live.commit()
    live.close()
    out = hi.undo(conn, hi.get_job(conn, j["id"], "vijay"))
    assert out == {"removed_plays": 1}
    assert [x["play_id"] for x in rows()] == ["live-9"]                       # the app's own play stays
    assert conn.execute("SELECT COUNT(*) FROM exportify_songs").fetchone()[0] == 0
    assert conn.execute("SELECT COUNT(*) FROM history_seen").fetchone()[0] == 0
    # importing again after undo works
    j2 = job(conn)
    assert sh.page(conn, j2["id"], "vijay", LIB, [play()], now=NOW)["imported"] == 1


def test_a_listenbrainz_import_and_a_spotify_import_do_not_undo_each_other(conn):
    j = job(conn)
    sh.page(conn, j["id"], "vijay", LIB, [play()], now=NOW)
    lb = hi.create_job(conn, "vijay", "listenbrainz", "someone")[0]
    hi.undo(conn, lb)
    assert len(rows()) == 1


def test_no_file_contents_in_the_log(conn, caplog):
    import logging
    caplog.set_level(logging.DEBUG)
    j = job(conn)
    sh.page(conn, j["id"], "vijay", LIB, [play(title="Secret Title Zed", artist="Secret Artist Zed")], now=NOW)
    assert "Secret" not in caplog.text


# ── routes ───────────────────────────────────────────────────────────────────

@pytest.fixture
def api(conn):
    app = FastAPI()
    who = {"u": "vijay"}
    spotify_history_api.register_routes(app, None, conn, lambda: who["u"], library_loader=lambda: LIB)
    from tgfetch import history_import_api
    history_import_api.register_routes(app, None, conn, lambda: who["u"], library_loader=lambda: LIB)
    return TestClient(app), who


def test_routes_end_to_end(api):
    client, who = api
    r = client.post("/spotify-import/jobs", json={"format": "extended", "total": 3})
    assert r.status_code == 201
    jid = r.json()["id"]
    assert client.post("/spotify-import/jobs", json={"format": "extended"}).status_code == 200   # the open one
    r = client.post(f"/spotify-import/jobs/{jid}/page", json={"plays": [play(), "junk"]})
    assert r.status_code == 200 and r.json()["imported"] == 1 and r.json()["rejected_total"] == 1
    assert client.get(f"/spotify-import/jobs/{jid}").json()["songs_matched"] == 1
    assert [j["id"] for j in client.get("/spotify-import/jobs").json()] == [jid]
    assert client.post(f"/spotify-import/jobs/{jid}/finish").json()["status"] == "done"
    assert client.post(f"/history-import/jobs/{jid}/undo").json() == {"removed_plays": 1}


def test_routes_refuse_bad_input_and_other_users(api):
    client, who = api
    assert client.post("/spotify-import/jobs", json={"format": "zip"}).status_code == 422
    assert client.post("/spotify-import/jobs", json={"format": "extended", "total": -1}).status_code == 422
    jid = client.post("/spotify-import/jobs", json={}).json()["id"]
    assert client.post(f"/spotify-import/jobs/{jid}/page", json={"plays": [play()] * 1001}).status_code == 422
    assert client.post(f"/spotify-import/jobs/{jid}/page", json={"plays": "x"}).status_code == 422
    who["u"] = "someone-else"
    assert client.get(f"/spotify-import/jobs/{jid}").status_code == 404
    assert client.post(f"/spotify-import/jobs/{jid}/page", json={"plays": [play()]}).status_code == 404
    assert client.post(f"/spotify-import/jobs/{jid}/finish").status_code == 404
    who["u"] = "vijay"
    assert client.get("/spotify-import/jobs/999").status_code == 404


def test_a_listenbrainz_job_is_not_reachable_through_the_spotify_routes(api, conn):
    client, who = api
    lb = hi.create_job(conn, "vijay", "listenbrainz", "someone")[0]
    assert client.get(f"/spotify-import/jobs/{lb['id']}").status_code == 404
    assert client.post(f"/spotify-import/jobs/{lb['id']}/page", json={"plays": []}).status_code == 404


def test_history_imports_own_routes_stay_closed_to_spotify(conn):
    """Registering the source for naming must not make `spotify` a source history-import can create or fetch."""
    with pytest.raises(hi.HistoryError):
        hi.create_job(conn, "vijay", "spotify", "x")
    with pytest.raises(hi.HistoryError):
        hi.create_job(conn, "vijay", "myspace", "x")
    job = sh.create_job(conn, "vijay", "extended", total=10)[0]
    with pytest.raises(hi.HistoryError):          # no Last.fm request is ever made for a Spotify job
        hi.step(conn, job["id"], "vijay", [])
    assert hi.create_job(conn, "vijay", "lastfm", "someone")[1] is True
    assert hi.undo(conn, hi.get_job(conn, job["id"], "vijay")) is not None
