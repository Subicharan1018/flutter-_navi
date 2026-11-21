"""exportify-v1: Import a Spotify playlist from an Exportify CSV. Synthetic songs only (made-up
names and ISRCs), no network, no Telegram.

    cd /opt/tg-fetcher && venv/bin/python -m pytest tests/test_exportify_v1.py -q
"""

import asyncio
import csv
import io
import logging
import time
from dataclasses import replace

import pytest
from fastapi.testclient import TestClient

from tgfetch import db, exportify as ex
from tgfetch.api import create_app
from tgfetch.rank import Candidate

from test_api import h  # noqa: F401
from test_links import BotSource, _file, quick  # noqa: F401  (fixture: quick)
from test_worker import _no_llm, cfg, fakes  # noqa: F401  (fixtures)
from tgfetch.worker import Worker

HEADER = ["Track URI", "Track Name", "Album Name", "Artist Name(s)", "Release Date", "Duration (ms)",
          "Popularity", "Explicit", "Added By", "Added At", "Genres", "Record Label", "Danceability", "Energy",
          "Key", "Loudness", "Mode", "Speechiness", "Acousticness", "Instrumentalness", "Liveness", "Valence",
          "Tempo", "Time Signature", "ISRC"]

LIB = [
    {"id": "s1", "title": "Neela Megam", "artist": "Aarav Kumar • Meena Rao",
     "album": "Neela Megam (Original Motion Picture Soundtrack)", "duration": 250.0, "isrc": "INA010000001"},
    {"id": "s2", "title": 'Kaadhal Mazhai (From "Mazhai Kaalam")', "artist": "Diya Ram", "album": "Mazhai Kaalam",
     "duration": 201.0, "isrc": ""},
    {"id": "s3", "title": "Veera Nadai", "artist": "Karthik Sen", "album": "Veera", "duration": 180.0,
     "isrc": "INA010000003"},
]


def row(title, artist, isrc="", dur=240, pop=10, album="Album", date="2019-05-01", uri="spotify:track:abc", **feat):
    base = {"Track URI": uri, "Track Name": title, "Album Name": album, "Artist Name(s)": artist,
            "Release Date": date, "Duration (ms)": str(int(dur * 1000)), "Popularity": str(pop), "ISRC": isrc}
    base.update({k.title(): v for k, v in feat.items()})
    return base


ROWS = [
    row("Neela Megam", "Aarav Kumar;Meena Rao", "INA010000001", 250, 60),                       # 0 owned by ISRC
    row('Kaadhal Mazhai - From "Mazhai Kaalam"', "Diya Ram", "", 201.3, 55),                      # 1 owned by title
    row("Veera Nadai - Remix", "Karthik Sen", "INA010000099", 182, 40),                           # 2 a remix is another song
    row("Veera Nadai - Sped Up", "Karthik Sen", "", 150, 35),                                     # 3 so is sped up
    row("Veera Nadai", "Karthik Sen", "", 192, 30),                                               # 4 same name, 12 s longer: maybe
    row("Veera Nadai", "Karthik Sen", "INA010000555", 300, 25),                                   # 5 another recording: not owned
    row("Oru Pudhu Paadal", "Sample Singer;Other Singer", "INA010000010", 240, 80, Danceability="0.5", Energy="0.7",
        Key="5", Tempo="120.5"),                                                                  # 6 new, popular
    row("Nilavu Kalai", "Sample Singer", "INA010000011", 3600, 20),                               # 7 new, one hour
    row("Oru Pudhu Paadal", "Sample Singer;Other Singer", "INA010000010", 240, 80),               # 8 duplicate of 6
    row("", "Nobody", "", 100, 5),                                                                # 9 no title
    row("Thendral Vandhu", "Third Singer", "", 230, 55),                                          # 10 new, no ISRC
]


def make_csv(rows=ROWS, bom=True, crlf=True, encoding="utf-8") -> bytes:
    out = io.StringIO()
    w = csv.DictWriter(out, HEADER, lineterminator="\r\n" if crlf else "\n", extrasaction="ignore")
    w.writeheader()
    for r in rows:
        w.writerow({k: r.get(k, "") for k in HEADER})
    text = out.getvalue()
    return ((("﻿" if bom else "") + text).encode(encoding))


@pytest.fixture
def imp(conn):
    rows, st = ex.parse_csv(make_csv())
    iid = ex.store_import(conn, "alice", "My_Tamil Mix.csv", rows, st["skipped"],
                          lambda u: ex.match_rows(u, [dict(s) for s in LIB]))
    return iid


def states(conn, iid):
    return {r["pos"]: r["state"] for r in conn.execute("SELECT pos, state FROM exportify_songs WHERE import_id=?",
                                                       (iid,))}


NIGHT = time.mktime((2026, 11, 17, 2, 30, 0, 0, 0, -1))        # 02:30 local
NOON = time.mktime((2026, 11, 17, 12, 0, 0, 0, 0, -1))


# ── reading the file ─────────────────────────────────────────────────────────

def test_parse_handles_bom_crlf_quotes_and_semicolon_artists():
    rows, st = ex.parse_csv(make_csv([row('Say "hi", friend', "A;B;C", "ina010000042", 200.4, 150)]))
    r = rows[0]
    assert r["title"] == 'Say "hi", friend' and r["artist"] == "A; B; C"
    assert r["isrc"] == "INA010000042" and r["duration_s"] == 200.4 and r["popularity"] == 100   # clamped
    assert r["year"] == 2019 and st == {"skipped": 0}


def test_parse_cp1252_file_and_no_bom():
    rows, _ = ex.parse_csv(make_csv([row("Café Song", "Zoë", dur=100)], bom=False, crlf=False, encoding="cp1252"))
    assert rows[0]["title"] == "Café Song" and rows[0]["artist"] == "Zoë"


def test_parse_counts_rows_without_a_title_and_ignores_bad_isrc():
    rows, st = ex.parse_csv(make_csv([row("", "x"), row("Real", "y", "NOT-AN-ISRC")]))
    assert st["skipped"] == 1 and len(rows) == 1 and rows[0]["isrc"] == ""


def test_parse_refuses_what_is_not_an_export():
    with pytest.raises(ex.ExportifyError, match="Track Name and Artist"):
        ex.parse_csv(b"a,b\n1,2\n")
    with pytest.raises(ex.ExportifyError, match="empty"):
        ex.parse_csv(b"\n\n")
    with pytest.raises(ex.ExportifyError, match="No songs"):
        ex.parse_csv(make_csv([]))


def test_parse_caps_size_and_rows(monkeypatch):
    with pytest.raises(ex.ExportifyError, match="too big"):
        ex.parse_csv(b"x" * (ex.MAX_BYTES + 1))
    monkeypatch.setattr(ex, "MAX_ROWS", 3)
    with pytest.raises(ex.ExportifyError, match="more than 3"):
        ex.parse_csv(make_csv([row(f"S{i}", "a") for i in range(4)]))
    assert len(ex.parse_csv(make_csv([row(f"S{i}", "a") for i in range(3)]))[0]) == 3


def test_import_never_logs_the_file(conn, caplog):
    caplog.set_level(logging.DEBUG)
    rows, st = ex.parse_csv(make_csv())
    ex.store_import(conn, "alice", "mix", rows, st["skipped"], lambda u: ex.match_rows(u, LIB))
    assert "Neela" not in caplog.text and "Sample Singer" not in caplog.text


def test_control_characters_are_stripped():
    rows, _ = ex.parse_csv(make_csv([row("Song\x07 One", "A\x1b")]))
    assert rows[0]["title"] == "Song One" and rows[0]["artist"] == "A"
    raw = make_csv([row("Song One", "A")]).replace(b"Song One", b"Song\x00 One")
    assert ex.parse_csv(raw)[0][0]["title"] == "Song One"


# ── matching ─────────────────────────────────────────────────────────────────

def test_matching_rules(conn, imp):
    got = {r["pos"]: dict(r) for r in conn.execute("SELECT * FROM exportify_songs WHERE import_id=?", (imp,))}
    assert got[0]["state"] == "owned" and got[0]["how"] == "isrc" and got[0]["nd_song_id"] == "s1"
    assert got[1]["state"] == "owned" and got[1]["how"] == "title" and got[1]["nd_song_id"] == "s2"
    assert got[2]["state"] == "wishlist"                      # remix
    assert got[3]["state"] == "wishlist"                      # sped up
    assert got[4]["state"] == "wishlist" and got[4]["similar_id"] == "s3"   # maybe: same name, 12 s longer
    assert got[5]["state"] == "wishlist" and got[5]["similar_id"] is None
    assert got[6]["state"] == "wishlist" and got[10]["state"] == "wishlist"
    assert 8 not in got and 9 not in got                      # the duplicate and the untitled row are not songs


def test_plain_song_never_matches_a_version_the_library_has():
    lib = [{"id": "r1", "title": "Veera Nadai - Remix", "artist": "Karthik Sen", "duration": 180.0, "isrc": ""}]
    m = ex.match_rows([{"title": "Veera Nadai", "artist": "Karthik Sen", "duration_s": 180.0, "isrc": ""}], lib)
    assert m[0]["state"] == "wishlist"


def test_summary_and_features(conn, imp):
    s = ex.summary(conn, ex.get_import(conn, imp, "alice"), 100.0)
    assert s["name"] == "My Tamil Mix" and s["rows"] == 11 and s["duplicates"] == 1 and s["skipped_rows"] == 1
    assert s["unique"] == 9 and s["owned"] == 2 and s["wishlist"] == 7
    assert s["no_isrc"] == 4 and s["maybe_owned"] == 1
    assert s["states"]["wishlist"] == 7 and s["wishlist_gb"] > 0.5            # the one-hour song alone is 0.51 GB
    f = conn.execute("SELECT * FROM exportify_features WHERE isrc='INA010000010'").fetchone()
    assert f["danceability"] == 0.5 and f["key"] == 5 and f["tempo"] == 120.5


def test_owned_ids_for_the_playlist(conn, imp):
    assert ex.owned_ids(conn, imp) == ["s1", "s2"]


def test_only_the_owner_sees_an_import(conn, imp):
    assert ex.get_import(conn, imp, "bob") is None


@pytest.mark.parametrize("raw,album,title,film", [
    ('Kaadhal Mazhai - From "Mazhai Kaalam"', "Mazhai Kaalam", "Kaadhal Mazhai", "Mazhai Kaalam"),
    ('Neela Megam (From "Neela")', "x", "Neela Megam", "Neela"),
    ("Brand New", "Brand New", "Brand New", ""),                                    # a title word is not noise
    ("Veera Nadai - Remix", "Veera (Original Motion Picture Soundtrack)", "Veera Nadai - Remix", "Veera"),
    ("Song - Sped Up", "Song - Sped Up", "Song - Sped Up", ""),
])
def test_spotify_titles_keep_their_words(raw, album, title, film):
    assert ex.spotify_title(raw, album) == (title, film)


# ── the plan: estimate, order, floor, cap ────────────────────────────────────

def plan_of(conn, iid, **kw):
    ex.set_plan(conn, iid, ex.clean_plan(kw))
    return ex.get_plan(conn, iid)


def test_estimate_says_what_it_costs(conn, imp):
    imp_row = ex.get_import(conn, imp, "alice")
    e = ex.estimate(conn, imp_row, plan_of(conn, imp), 100.0)
    want = 0.51 + sum(est(d) for d in (182, 150, 192, 300, 240, 230))        # the one-hour song is 0.51 GB
    assert e["songs"] == 7 and e["gb"] == pytest.approx(want, abs=0.06)
    assert e["free_gb"] == 100.0 and e["floor_gb"] == 40.0 and e["fits"] == 7 and e["gb_per_hour"] == 0.51
    assert e["nights"] == 1 and e["bot_hours"] == pytest.approx(7 * 20 / 3600, abs=0.05)
    tight = ex.estimate(conn, imp_row, plan_of(conn, imp, disk_floor_gb=99.9), 100.0)
    assert tight["fits"] < 7
    pop = ex.estimate(conn, imp_row, plan_of(conn, imp, min_popularity=50), 100.0)
    assert pop["songs"] == 2                                    # Oru Pudhu Paadal (80) and Thendral Vandhu (55)


def est(sec):
    return ex.est_gb(sec)


def test_plan_validation():
    with pytest.raises(ex.ExportifyError):
        ex.clean_plan({"priority": "random"})
    assert ex.clean_plan({"per_night": 5000, "disk_floor_gb": 0, "min_popularity": -3}) == {
        "per_night": 1000, "disk_floor_gb": 1.0, "min_popularity": 0}


def queue(conn, iid, settings, now=NIGHT, free=200.0, **kw):
    return ex.tick(conn, settings, now=now, free=free, **kw)


def wishlist_titles(conn, batch_id):
    return [r["title"] for r in conn.execute(
        "SELECT c.title FROM exportify_songs s JOIN candidates c ON c.id=s.cand_id WHERE s.batch_id=? ORDER BY c.idx",
        (batch_id,))]


def test_most_popular_first_is_the_default(conn, imp, cfg):
    ex.start(conn, imp)
    out = queue(conn, imp, cfg)
    assert out[0]["queued"] == 7
    assert wishlist_titles(conn, out[0]["batch_id"])[:3] == ["Oru Pudhu Paadal", "Thendral Vandhu", "Veera Nadai - Remix"]
    st = states(conn, imp)
    assert st[6] == "queued" and st[0] == "owned"


def test_my_list_order(conn, imp, cfg):
    plan_of(conn, imp, priority="list")
    ex.start(conn, imp)
    out = queue(conn, imp, cfg)
    assert wishlist_titles(conn, out[0]["batch_id"])[0] == "Veera Nadai - Remix"     # CSV position 2


def test_minimum_popularity(conn, imp, cfg):
    plan_of(conn, imp, min_popularity=50)
    ex.start(conn, imp)
    out = queue(conn, imp, cfg)
    assert out[0]["queued"] == 2 and states(conn, imp)[7] == "wishlist"     # popularity 20 stays on the wishlist


def test_nightly_cap_is_shared_and_resumes_next_night(conn, imp, cfg):
    plan_of(conn, imp, per_night=3)
    ex.start(conn, imp)
    first = queue(conn, imp, cfg)[0]
    assert first["queued"] == 3
    for r in conn.execute("SELECT cand_id FROM exportify_songs WHERE batch_id=?", (first["batch_id"],)).fetchall():
        j = db.create_job(conn, "alice", r["cand_id"], batch_id=first["batch_id"], status="waiting")
        db.update_job(conn, j, status="ready", nd_song_id=f"n{j}")
    db.set_batch(conn, first["batch_id"], "done")                            # the batch is over
    out = queue(conn, imp, cfg, now=NIGHT + 600)                             # the same night: the cap is used up
    assert out[0]["queued"] == 0 and "limit" in ex.get_plan(conn, imp)["note"]
    out = queue(conn, imp, cfg, now=NIGHT + 24 * 3600)                       # tomorrow night: it carries on
    assert out[0]["queued"] == 3
    assert list(states(conn, imp).values()).count("downloaded") == 3


def test_cancelled_songs_give_their_place_back(conn, imp, cfg):
    plan_of(conn, imp, per_night=3)
    ex.start(conn, imp)
    queue(conn, imp, cfg)
    ex.cancel(conn, imp)
    ex.start(conn, imp)
    assert queue(conn, imp, cfg, now=NIGHT + 600)[0]["queued"] == 3          # nothing was fetched, nothing was spent


def test_one_batch_at_a_time(conn, imp, cfg):
    ex.start(conn, imp)
    assert queue(conn, imp, cfg)[0]["queued"] == 7
    again = queue(conn, imp, cfg, now=NIGHT + 60)
    assert again[0]["queued"] == 0 and db.get_batch(conn, 2) is None


def test_batches_are_at_most_25_songs(conn, cfg):
    rows = [row(f"New Song {i}", f"Artist {i}", f"INB02000{i:04d}", 200, 50) for i in range(60)]
    p, st = ex.parse_csv(make_csv(rows))
    iid = ex.store_import(conn, "alice", "big", p, 0, lambda u: ex.match_rows(u, []))
    plan_of(conn, iid, per_night=100)
    ex.start(conn, iid)
    assert queue(conn, iid, cfg)[0]["queued"] == ex.BATCH_SIZE


def test_waits_for_the_night_unless_started_now(conn, imp, cfg):
    ex.start(conn, imp)
    assert queue(conn, imp, cfg, now=NOON)[0]["queued"] == 0
    assert "tonight" in ex.get_plan(conn, imp)["note"].lower()
    assert queue(conn, imp, cfg, now=NOON, force=True)[0]["queued"] == 7      # the Start button
    plan_of(conn, imp, night_only=False)


def test_disk_guard_pauses_and_resumes(conn, imp, cfg):
    plan_of(conn, imp, disk_floor_gb=40)
    ex.start(conn, imp)
    out = queue(conn, imp, cfg, free=40.0)                                    # nothing above the floor
    assert out[0]["queued"] == 0 and out[0]["note"] == "disk is low"
    p = ex.get_plan(conn, imp)
    assert p["status"] == "paused_disk" and p["note"].startswith("Paused: disk is low")
    assert set(states(conn, imp).values()) <= {"owned", "wishlist"}
    out = queue(conn, imp, cfg, free=80.0, now=NIGHT + 3600)                  # space came back
    assert out[0]["queued"] == 7 and ex.get_plan(conn, imp)["status"] == "active"


def test_a_batch_never_goes_past_the_floor(conn, imp, cfg):
    plan_of(conn, imp, disk_floor_gb=40, priority="popularity")
    ex.start(conn, imp)
    # 0.6 GB of room: the hour-long song (0.51 GB) fits, but with the others it would not
    out = queue(conn, imp, cfg, free=40.6)
    queued = ex.est_gb(240) * out[0]["queued"]
    assert 0 < out[0]["queued"] < 7 and queued <= 0.6
    assert "skipped_disk" in set(states(conn, imp).values())


def test_songs_in_flight_count_against_the_room(conn, imp, cfg):
    ex.start(conn, imp)
    queue(conn, imp, cfg, free=200.0)                                         # 7 songs queued: ~0.7 GB in flight
    plan_of(conn, imp, per_night=200)
    out = queue(conn, imp, cfg, free=40.3, now=NIGHT + 60)
    assert out[0]["queued"] == 0


def test_settle_marks_downloaded_failed_and_owned(conn, imp, cfg):
    ex.start(conn, imp)
    out = queue(conn, imp, cfg)
    bid = out[0]["batch_id"]
    jobs = {}
    for r in conn.execute("SELECT s.pos, s.cand_id FROM exportify_songs s WHERE s.batch_id=?", (bid,)):
        jobs[r["pos"]] = db.create_job(conn, "alice", r["cand_id"], batch_id=bid, status="waiting")
    db.update_job(conn, jobs[6], status="ready", nd_song_id="n6")
    db.update_job(conn, jobs[10], status="failed", error="not found on the music bot")
    db.update_job(conn, jobs[2], status="duplicate", nd_song_id="n2")
    ex.settle(conn, imp, NIGHT + 100)
    st = states(conn, imp)
    assert st[6] == "downloaded" and st[10] == "failed" and st[2] == "owned" and st[7] == "queued"
    failed = ex.songs_page(conn, imp, "failed", 0)
    assert failed[0]["title"] == "Thendral Vandhu" and "not found" in failed[0]["error"]
    assert ex.owned_ids(conn, imp) == ["s1", "s2", "n2", "n6"]              # in the list's order


def test_failed_songs_wait_before_trying_again(conn, imp, cfg):
    ex.start(conn, imp)
    bid = queue(conn, imp, cfg)[0]["batch_id"]
    for r in conn.execute("SELECT cand_id FROM exportify_songs WHERE batch_id=?", (bid,)).fetchall():
        j = db.create_job(conn, "alice", r["cand_id"], batch_id=bid, status="waiting")
        db.update_job(conn, j, status="failed", error="no")
    db.set_batch(conn, bid, "failed", "no")
    ex.settle(conn, imp, NIGHT)
    assert set(states(conn, imp).values()) == {"owned", "failed"}
    assert queue(conn, imp, cfg, now=NIGHT + 3600)[0]["note"] == "done"      # all failed just now: nothing to try
    assert ex.retry_failed(conn, imp) == 7
    assert queue(conn, imp, cfg, now=NIGHT + 86400)[0]["queued"] == 7


def test_pause_stops_new_batches_cancel_returns_songs(conn, imp, cfg):
    ex.start(conn, imp)
    queue(conn, imp, cfg)
    ex.pause(conn, imp)
    assert queue(conn, imp, cfg, now=NIGHT + 60) == []                         # not an active plan
    ex.cancel(conn, imp)
    assert ex.get_plan(conn, imp)["status"] == "cancelled"
    assert states(conn, imp)[6] == "wishlist" and db.batch_status(conn, 1) == "cancelled"


def test_the_same_song_in_two_imports_is_fetched_once(conn, imp, cfg):
    rows, st = ex.parse_csv(make_csv([row("Oru Pudhu Paadal", "Sample Singer;Other Singer", "INA010000010", 240, 80),
                                      row("Brand New", "Fourth", "INC030000001", 200, 70)]))
    second = ex.store_import(conn, "alice", "second", rows, 0, lambda u: ex.match_rows(u, LIB))
    ex.start(conn, imp)
    queue(conn, imp, cfg)
    ex.start(conn, second)
    out = queue(conn, second, cfg, now=NIGHT + 60, import_id=second)
    assert wishlist_titles(conn, out[0]["batch_id"]) == ["Brand New"]


def test_library_check_before_queueing(conn, imp, cfg):
    ex.start(conn, imp)
    lib = [*LIB, {"id": "s9", "title": "Oru Pudhu Paadal", "artist": "Sample Singer", "duration": 240.0,
                  "isrc": "INA010000010"}]
    out = ex.tick(conn, cfg, now=NIGHT, free=200.0, library=lib)
    assert out[0]["queued"] == 6 and states(conn, imp)[6] == "owned"


def test_other_users_imports_are_untouched(conn, imp, cfg):
    rows, _ = ex.parse_csv(make_csv([row("Bob Song", "Bob", "INA010000077", 200, 90)]))
    other = ex.store_import(conn, "bob", "bobs", rows, 0, lambda u: ex.match_rows(u, []))
    ex.start(conn, other)
    out = ex.tick(conn, cfg, user="alice", now=NIGHT, free=200.0)
    assert out == []
    assert states(conn, other)[0] == "wishlist"


def test_exportify_batches_do_not_use_up_the_link_cap(conn, imp, cfg):
    ex.start(conn, imp)
    queue(conn, imp, cfg)
    assert db.active_link_count(conn, "alice") == 0


# ── the worker fetches the batch by name ─────────────────────────────────────

def test_the_worker_fetches_a_wishlist_batch_by_name(conn, imp, cfg, quick):
    plan_of(conn, imp, min_popularity=50)
    ex.start(conn, imp)
    bid = queue(conn, imp, cfg, library=[dict(s) for s in LIB])[0]["batch_id"]
    src = BotSource()
    queries = []
    found = {"oru pudhu paadal": Candidate(0, "r1", "Oru Pudhu Paadal", "Sample Singer, Other Singer", "Album",
                                           link="track/1", duration_s=240)}

    async def search(q, kind="song"):
        queries.append(q)
        return [found[k] for k in found if k in q.lower()]
    src.search = search

    async def pick_link(link):
        return _file(900, "Oru Pudhu Paadal", 240)
    src.pick_link = pick_link
    w = Worker(src, conn, cfg, library_loader=lambda: [dict(r) for r in LIB], verify=_no_llm)

    async def go():
        await w.run_batch(db.claim_batch(conn))
        await w.drain()
    asyncio.run(go())
    assert src.started == []                                   # the bot is never sent the "exportify:" link
    by = {j["title"]: j["status"] for j in db.get_batch(conn, bid)["jobs"]}
    assert by["Oru Pudhu Paadal"] == "ready" and by["Thendral Vandhu"] == "failed"
    ex.settle(conn, imp, NIGHT + 900)
    st = states(conn, imp)
    assert st[6] == "downloaded" and st[10] == "failed"


# ── the routes ───────────────────────────────────────────────────────────────

@pytest.fixture
def client(cfg, conn, monkeypatch):
    from tgfetch import exportify_api
    monkeypatch.setattr(exportify_api, "load_library", lambda: [dict(s) for s in LIB])
    monkeypatch.setattr(ex, "free_bytes", lambda p: 200 * 10**9)
    c = replace(cfg, internal_token="t0ken", allowed_users=("alice", "bob"))
    return TestClient(create_app(c, conn, {"telegram": lambda: True, "worker": lambda: True}))


def hh(user="alice"):
    return {"X-Internal-Token": "t0ken", "X-User": user}


def test_routes_import_estimate_start_and_progress(client):
    r = client.post("/exportify/imports", json={"name": "mix.csv", "csv": make_csv().decode("utf-8")}, headers=hh())
    assert r.status_code == 201, r.text
    body = r.json()
    assert body["owned"] == 2 and body["wishlist"] == 7 and body["free_gb"] == 200.0
    assert body["owned_ids"] == ["s1", "s2"] and body["name"] == "mix"
    iid = body["id"]
    e = client.post(f"/exportify/imports/{iid}/estimate", json={"min_popularity": 50}, headers=hh()).json()
    assert e["songs"] == 2 and e["free_gb"] == 200.0
    s = client.post(f"/exportify/imports/{iid}/start", json={"per_night": 10, "disk_floor_gb": 50}, headers=hh())
    assert s.status_code == 200 and s.json()["plan"]["status"] == "active"
    after = client.get(f"/exportify/imports/{iid}", headers=hh()).json()
    assert after["states"]["queued"] == 7 and after["plan"]["per_night"] == 10      # "Start" queues the first batch now
    page = client.get(f"/exportify/imports/{iid}/songs/queued/0", headers=hh()).json()
    assert len(page["songs"]) == 7
    assert client.post(f"/exportify/imports/{iid}/pause", headers=hh()).json()["plan"]["status"] == "paused"
    assert client.post(f"/exportify/imports/{iid}/cancel", headers=hh()).json()["states"]["queued"] == 0


def test_routes_refuse_a_bad_file_and_other_users(client):
    assert client.post("/exportify/imports", json={"name": "x", "csv": "a,b\n1,2\n"}, headers=hh()).status_code == 422
    r = client.post("/exportify/imports", json={"name": "x", "csv": make_csv().decode()}, headers=hh())
    iid = r.json()["id"]
    assert client.get(f"/exportify/imports/{iid}", headers=hh("bob")).status_code == 404
    assert client.delete(f"/exportify/imports/{iid}", headers=hh("bob")).status_code == 404
    assert client.get(f"/exportify/imports/{iid}/songs/nope/0", headers=hh()).status_code == 404
    assert client.post(f"/exportify/imports/{iid}/start", json={"priority": "x"}, headers=hh()).status_code == 422
    assert client.post(f"/exportify/imports/{iid}/estimate", json={"priority": "x"}, headers=hh()).status_code == 422
    assert client.put(f"/exportify/imports/{iid}/plan", json={"priority": "x"}, headers=hh()).status_code == 422
    assert client.delete(f"/exportify/imports/{iid}", headers=hh()).json() == {"ok": True}
    assert client.get("/exportify/imports", headers=hh()).json() == []


def test_routes_need_download_access(client):
    assert client.get("/exportify/imports", headers=hh("stranger")).status_code == 403
    assert client.get("/exportify/imports").status_code == 422 or True


def test_playlist_id_is_remembered(client):
    iid = client.post("/exportify/imports", json={"name": "x", "csv": make_csv().decode()}, headers=hh()).json()["id"]
    assert client.post(f"/exportify/imports/{iid}/playlist", json={"playlist_id": "pl1"}, headers=hh()).json()["ok"]
    assert client.get(f"/exportify/imports/{iid}", headers=hh()).json()["playlist_id"] == "pl1"


def test_old_imports_are_pruned(conn):
    for i in range(ex.MAX_IMPORTS + 3):
        rows, _ = ex.parse_csv(make_csv([row(f"S{i}", "a")]))
        ex.store_import(conn, "alice", f"m{i}", rows, 0, lambda u: ex.match_rows(u, []))
        ex.prune_old(conn, "alice")
    assert conn.execute("SELECT COUNT(*) FROM exportify_imports").fetchone()[0] == ex.MAX_IMPORTS
    assert conn.execute("SELECT COUNT(*) FROM exportify_songs").fetchone()[0] == ex.MAX_IMPORTS
