"""data-queue-v1: the hidden weekly data queue (store, batches, files, Exportify upload, prediction, routes)."""

import csv
import io
import json
import sqlite3
import time

import numpy as np
import pytest
from flask import Flask, g, jsonify, request

from navivibe import data_queue as dq
from navivibe import data_queue_store as store

DAY = 86400.0

@pytest.fixture
def env(tmp_path, monkeypatch):
    qpath, dpath, cpath = str(tmp_path / "q.db"), str(tmp_path / "details.db"), str(tmp_path / "catalog.db")
    monkeypatch.setattr(store, "PATH", qpath)
    monkeypatch.setattr(store, "DETAILS_PATH", dpath)
    store.forget_paths()
    monkeypatch.setattr(dq, "catalog_path", lambda: cpath)
    monkeypatch.setattr(dq, "play_counts", lambda library, log_dir=None: {})
    monkeypatch.setattr(dq, "gap_scores", lambda *a, **k: {})
    dq._rank_cache["key"] = None
    return {"q": qpath, "d": dpath, "c": cpath}

def make_catalog(path, n=120, labelled=80, dim=8):
    """n songs; the first `labelled` carry Spotify numbers in the details db; energy depends on the embedding."""
    rng = np.random.default_rng(3)
    c = sqlite3.connect(path)
    c.execute("CREATE TABLE songs (id TEXT PRIMARY KEY, path TEXT, title TEXT, artist TEXT, album TEXT, album_artist TEXT, "
              "duration REAL, isrc TEXT, composer TEXT, language TEXT, genre_display TEXT, genre_primary TEXT, "
              "energy REAL, valence REAL, danceability REAL, acousticness REAL, bpm REAL, year INTEGER, "
              "feature_source TEXT, missing INTEGER DEFAULT 0)")
    c.execute("CREATE TABLE embeddings (song_id TEXT, model TEXT, dim INTEGER, vec BLOB)")
    truth = {}
    for i in range(n):
        v = rng.normal(size=dim).astype(np.float32)
        sid = "s%03d" % i
        truth[sid] = {"energy": float(1 / (1 + np.exp(-v[0]))), "valence": float(1 / (1 + np.exp(-v[1]))),
                      "danceability": float(1 / (1 + np.exp(-v[2]))), "acousticness": float(1 / (1 + np.exp(-v[3])))}
        isrc = "INA%09d" % i if i % 5 else None
        c.execute("INSERT INTO songs (id, path, title, artist, album, album_artist, duration, isrc, composer, language) "
                  "VALUES (?,?,?,?,?,?,?,?,?,?)", (sid, "Artist %d - Song %d.flac" % (i, i), "Song %d" % i, "Artist %d" % i,
                                                   "Album", "Artist %d" % i, 200.0 + i, isrc, "Comp %d" % (i % 9), "ta"))
        if sid:
            c.execute("INSERT INTO embeddings VALUES (?,?,?,?)", (sid, "effnet_discogs", dim, v.tobytes()))
    c.commit()
    c.close()
    return truth

def add_details(path, ids, truth):
    c = sqlite3.connect(path)
    c.execute("CREATE TABLE IF NOT EXISTS spotify_details (%s)" % dq.DETAILS_COLUMNS)
    for sid in ids:
        t = truth[sid]
        c.execute("INSERT OR REPLACE INTO spotify_details (song_id, energy, valence, danceability, acousticness, updated_at) "
                  "VALUES (?,?,?,?,?,1)", (sid, t["energy"], t["valence"], t["danceability"], t["acousticness"]))
    c.commit()
    c.close()

def song(i, **kw):
    return {"song_id": "s%03d" % i, "title": "Song %d" % i, "artist": "Artist %d" % i, "album": "Album",
            "duration": 200.0 + i, "isrc": "INA%09d" % i, **kw}

# ── adding songs ──────────────────────────────────────────────────────────────

def test_enqueue_adds_once_and_never_raises(env):
    assert store.enqueue(song(1), "youtube") == "queued"
    assert store.enqueue(song(1), "youtube") == "known"
    assert store.enqueue({"song_id": "", "title": "x"}) == "bad"
    assert store.enqueue(song(2), "nonsense") == "queued"
    c = store.connect()
    assert c.execute("SELECT source FROM queue WHERE song_id='s002'").fetchone()[0] == "other"
    assert store.counts(c)["waiting"] == 2

def test_a_broken_queue_file_never_raises(env, tmp_path):
    bad = tmp_path / "dir_not_file"
    bad.mkdir()
    assert store.enqueue(song(1), "link", path=str(bad)) == "error"

def test_songs_with_real_features_are_not_queued(env):
    truth = make_catalog(env["c"])
    add_details(env["d"], ["s001"], truth)
    assert store.enqueue(song(1), "exportify") == "has_features"
    assert store.enqueue(song(2), "exportify") == "queued"
    c = store.connect()
    assert store.counts(c)["waiting"] == 1

def test_a_row_without_energy_or_valence_is_not_real(env):
    cx = sqlite3.connect(env["d"])
    cx.execute("CREATE TABLE spotify_details (%s)" % dq.DETAILS_COLUMNS)
    cx.execute("INSERT INTO spotify_details (song_id, popularity, updated_at) VALUES ('s005', 40, 1)")
    cx.execute("INSERT INTO spotify_details (song_id, energy, updated_at) VALUES ('s006', 0.5, 1)")
    cx.commit()
    cx.close()
    assert store.enqueue(song(5)) == "queued" and store.enqueue(song(6)) == "queued"

def test_features_that_land_later_drop_waiting_songs(env):
    truth = make_catalog(env["c"])
    store.enqueue(song(1))
    store.enqueue(song(2))
    add_details(env["d"], ["s001"], truth)
    c = store.connect()
    assert store.reconcile(c) == 1
    assert store.counts(c)["waiting"] == 1 and store.counts(c)["done"] == 1

def test_source_of_a_link():
    assert store.source_of("exportify:12") == "exportify"
    assert store.source_of("https://music.youtube.com/playlist?list=x") == "youtube"
    assert store.source_of("https://open.spotify.com/playlist/x") == "link"
    assert store.source_of(None) == "request"

# ── batches ───────────────────────────────────────────────────────────────────

def fill(n, now, **kw):
    for i in range(n):
        store.enqueue(song(i, **kw), "request", now=now)

def test_a_batch_has_at_most_200_isrc_first_and_nothing_twice(env):
    now = time.time()
    fill(230, now)
    for i in range(230, 250):                       # twenty without an ISRC, with the best plays
        store.enqueue({**song(i), "isrc": ""}, "request", now=now)
    c = store.connect()
    plays = {"s%03d" % i: 1000 for i in range(230, 250)}
    made = store.build_batch(c, plays, {}, None, now)
    assert made["size"] == 200
    rows = store.batch_songs(c, made["batch_id"])
    assert len(rows) == 200 and all(r["isrc"] for r in rows)        # ISRC songs fill it before any without
    second = store.build_batch(c, plays, {}, None, now)
    ids1 = {r["song_id"] for r in rows}
    ids2 = {r["song_id"] for r in store.batch_songs(c, second["batch_id"])}
    assert not ids1 & ids2 and second["size"] == 50
    assert store.build_batch(c, plays, {}, None, now)["batch_id"] is None

def test_most_played_and_recent_come_first(env):
    now = time.time()
    store.enqueue(song(1), "request", now=now - 90 * DAY)
    store.enqueue(song(2), "request", now=now - 90 * DAY)
    store.enqueue(song(3), "request", now=now)
    c = store.connect()
    order = [r["song_id"] for r in store.rank_waiting(c, {"s002": 50}, {}, now)]
    assert order == ["s002", "s003", "s001"]

def test_the_same_recording_counts_once(env):
    now = time.time()
    store.enqueue(song(1), now=now)
    store.enqueue({**song(2), "isrc": song(1)["isrc"]}, now=now)
    store.enqueue({**song(3), "title": "Song 1", "artist": "Artist 1", "isrc": ""}, now=now)
    c = store.connect()
    assert len(store.rank_waiting(c, now=now)) == 1

def test_a_song_that_left_the_library_is_skipped_and_tags_refresh(env):
    now = time.time()
    store.enqueue({"song_id": "a", "title": "Old tag", "artist": "x"}, now=now)
    store.enqueue({"song_id": "b", "title": "Gone", "artist": "y"}, now=now)
    c = store.connect()
    live = {"a": {"title": "New tag", "artist": "x", "album": "Al", "album_artist": "x", "duration": 190, "isrc": "INA000000009"}}
    made = store.build_batch(c, {}, {}, live, now)
    assert made["size"] == 1 and made["skipped"] == 1
    r = store.batch_songs(c, made["batch_id"])[0]
    assert (r["title"], r["isrc"], r["album"]) == ("New tag", "INA000000009", "Al")

def test_an_open_batch_is_released_after_30_days(env):
    now = time.time()
    fill(5, now)
    c = store.connect()
    bid = store.build_batch(c, {}, {}, None, now)["batch_id"]
    assert store.release_stale(c, now + 29 * DAY) == []
    assert store.release_stale(c, now + 31 * DAY) == [bid]
    assert store.counts(c)["waiting"] == 5 and store.counts(c)["in_batch"] == 0
    assert [e["event"] for e in store.audit_of(c, bid)] == ["created", "released"]
    assert store.release(c, bid) is False                              # not open any more

def test_files_are_the_library_export_format(env):
    store.enqueue({"song_id": "a", "title": 'Say "hi", now', "artist": "A\nB", "album": "Al", "album_artist": "AA",
                   "duration": 201.4, "isrc": "ina000000001"})
    c = store.connect()
    bid = store.build_batch(c, {}, {}, None)["batch_id"]
    rows = store.batch_songs(c, bid)
    raw = store.file_bytes(rows, "csv")
    assert raw.startswith(b"\xef\xbb\xbf")
    table = list(csv.reader(io.StringIO(raw.decode("utf-8-sig"))))
    assert table[0] == ["title", "artist", "album", "album artist", "duration", "isrc"]
    assert table[1] == ['Say "hi", now', "A B", "Al", "AA", "201", "INA000000001"]
    assert store.file_bytes(rows, "txt") == b'A B - Say "hi", now\n'

# ── the upload ────────────────────────────────────────────────────────────────

HEAD = ["Track URI", "Track Name", "Artist Name(s)", "Duration (ms)", "ISRC", "Popularity", "Genres", "Record Label",
        "Release Date", "Explicit", "Danceability", "Energy", "Key", "Loudness", "Mode", "Speechiness", "Acousticness",
        "Instrumentalness", "Liveness", "Valence", "Tempo", "Time Signature", "Added By"]

def exportify_csv(rows):
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(HEAD)
    for r in rows:
        w.writerow(r)
    return buf.getvalue()

def sp_row(title, artist, isrc, dur_s, energy=0.7, valence=0.4):
    return ["spotify:track:x", title, artist, int(dur_s * 1000), isrc, 55, "tamil pop", "Label", "2019-05-01", "false",
            0.6, energy if energy is not None else "", 6, -6.5, 1, 0.05, 0.3, 0, 0.1, valence if energy is not None else "",
            120, 4, "someone"]

def test_upload_matches_stores_predicts_and_is_idempotent(env):
    truth = make_catalog(env["c"])
    add_details(env["d"], ["s%03d" % i for i in range(80)], truth)          # 80 labelled songs to learn from
    now = time.time()
    for i in range(100, 108):
        store.enqueue(song(i), "request", now=now)
    store.enqueue({**song(108), "isrc": ""}, "request", now=now)
    c = store.connect()
    bid = store.build_batch(c, {}, {}, None, now)["batch_id"]
    rows = [sp_row("Song 100", "Artist 100", song(100)["isrc"], 300),              # by ISRC (length ignored)
            sp_row("Song 101", "Artist 101", "ZZZ000000001", 201.0 + 100),              # by title, length within 5 s
            sp_row("Song 108", "Artist 108", "XXX000000008", 308),                      # no ISRC in the library: by title
            sp_row("Song 102", "Artist 102", "ZZZ000000002", 302, energy=None),         # on Spotify, without features
            sp_row("Totally Other", "Nobody", "ZZZ000000003", 200)]
    data = exportify_csv(rows).encode()
    res = dq.process_upload(c, bid, data, "mix.csv", now, env["d"], env["c"])
    assert (res["matched"], res["matched_by_isrc"], res["matched_by_title"]) == (3, 1, 2)
    assert res["features_stored"] == 3 and res["on_spotify_without_features"] == 1
    assert res["not_found"] == 5 and res["predicted"] == 6                      # the 1 featureless + 5 absent get a guess
    d = sqlite3.connect(env["d"])
    row = d.execute("SELECT energy, matched_by, isrc FROM spotify_details WHERE song_id='s100'").fetchone()
    assert row == (0.7, "isrc", song(100)["isrc"])
    assert d.execute("SELECT matched_by FROM spotify_details WHERE song_id='s108'").fetchone()[0] == "title"
    assert d.execute("SELECT COUNT(*) FROM spotify_details WHERE song_id='s103'").fetchone()[0] == 0   # a guess is never "Spotify"
    p = c.execute("SELECT * FROM predicted WHERE song_id='s103'").fetchone()
    assert p["feature_source"] == "predicted" and 0 <= p["energy"] <= 1 and p["model"].startswith("ridge-effnet")
    states = {r["song_id"]: r["state"] for r in store.batch_songs(c, bid)}
    assert states["s100"] == "done" and states["s102"] == "skipped" and states["s103"] == "not_on_spotify"
    # the same file again changes nothing
    before = (c.execute("SELECT COUNT(*), MAX(updated_at) FROM queue").fetchone()[:], d.execute("SELECT COUNT(*), MAX(updated_at) FROM spotify_details").fetchone())
    again = dq.process_upload(c, bid, data, "mix.csv", now + 60, env["d"], env["c"])
    assert again["repeated"] is True and again["matched"] == 3
    after = (c.execute("SELECT COUNT(*), MAX(updated_at) FROM queue").fetchone()[:], d.execute("SELECT COUNT(*), MAX(updated_at) FROM spotify_details").fetchone())
    assert before == after
    assert [e["event"] for e in store.audit_of(c, bid)] == ["created", "uploaded", "repeated_upload"]
    # another file for a closed batch is refused
    with pytest.raises(dq.QueueError) as e:
        dq.process_upload(c, bid, exportify_csv(rows[:1]).encode() + b"\n", "o.csv", now, env["d"], env["c"])
    assert e.value.status == 409

def test_prediction_learns_the_embedding(env):
    truth = make_catalog(env["c"], n=300, labelled=250)
    add_details(env["d"], ["s%03d" % i for i in range(250)], truth)
    from navivibe import data_queue_model as m
    emb = m.load_embeddings(env["c"])
    out, rep = m.predict(["s%03d" % i for i in range(250, 300)], emb, m.load_truth(env["c"], env["d"]))
    err = np.mean([abs(out["s%03d" % i]["energy"] - truth["s%03d" % i]["energy"]) for i in range(250, 300)])
    assert err < 0.15 and rep["features"]["energy"]["labelled"] == 250

def test_too_few_labels_means_no_prediction_but_the_upload_lands(env):
    truth = make_catalog(env["c"])
    add_details(env["d"], ["s000", "s001"], truth)
    store.enqueue(song(50))
    store.enqueue(song(51))
    c = store.connect()
    bid = store.build_batch(c, {}, {}, None)["batch_id"]
    res = dq.process_upload(c, bid, exportify_csv([sp_row("Song 50", "Artist 50", song(50)["isrc"], 250)]).encode(),
                            "a.csv", None, env["d"], env["c"])
    assert res["matched"] == 1 and res["predicted"] == 0 and res["not_found"] == 1
    note = c.execute("SELECT note FROM queue WHERE song_id='s051'").fetchone()[0]
    assert note == "no_prediction"

@pytest.mark.parametrize("text,status", [
    ("", 400), ("a,b\n1,2\n", 400),
    ("Track Name,Artist Name(s)\nx,y\n", 400),                         # no audio-feature columns
])
def test_bad_files_change_nothing(env, text, status):
    store.enqueue(song(1))
    c = store.connect()
    bid = store.build_batch(c, {}, {}, None)["batch_id"]
    with pytest.raises(dq.QueueError) as e:
        dq.process_upload(c, bid, text.encode(), "x.csv", None, env["d"], env["c"])
    assert e.value.status == status
    assert store.open_batch(c)["id"] == bid and store.counts(c)["in_batch"] == 1

def test_size_and_row_caps(env, monkeypatch):
    with pytest.raises(dq.QueueError) as e:
        dq.parse_csv(b"x" * (dq.MAX_BYTES + 1))
    assert e.value.status == 413
    monkeypatch.setattr(dq, "MAX_ROWS", 3)
    many = "Track Name,Artist Name(s)\n" + "".join("t%d,a\n" % i for i in range(4))
    with pytest.raises(dq.QueueError) as e:
        dq.parse_csv(many)
    assert e.value.status == 413

def test_the_added_by_column_is_never_read():
    rows = dq.parse_csv(exportify_csv([sp_row("T", "A", "USABC1234567", 100)]))
    assert "someone" not in json.dumps(rows)

def test_coverage_and_quality(env):
    truth = make_catalog(env["c"])
    add_details(env["d"], ["s000", "s001"], truth)
    c = store.connect()
    c.execute("INSERT INTO predicted (song_id, energy, feature_source, updated_at) VALUES ('s002', .5, 'predicted', 1)")
    with pytest.raises(sqlite3.IntegrityError):
        c.execute("INSERT INTO predicted (song_id, energy, feature_source, updated_at) VALUES ('s003', .5, 'spotify', 1)")
    cov = store.coverage(c, ["s000", "s001", "s002", "s003"], store.real_ids())
    assert cov == {"total": 4, "real": 2, "predicted": 1, "none": 1}
    store.enqueue(song(9), "youtube")
    q = store.quality(c)
    assert q["waiting_by_source"] == {"youtube": 1} and q["waiting_with_isrc"] == 1

# ── routes ────────────────────────────────────────────────────────────────────

@pytest.fixture
def client(env):
    app = Flask(__name__)
    app.config["TESTING"] = True

    def require_auth(f):
        import functools

        @functools.wraps(f)
        def inner(*a, **k):
            who = request.headers.get("X-Test-User")
            if not who:
                return jsonify({"error": "Authentication required."}), 401
            g.username = who
            return f(*a, **k)
        return inner

    dq.register_data_queue_routes(app, require_auth, lambda: {"admin"})
    return app.test_client()

ADMIN, USER = {"X-Test-User": "admin"}, {"X-Test-User": "someone"}

def test_non_admins_get_a_404_and_see_nothing(env, client):
    fill(3, time.time())
    for method, url in (("get", "/data-queue/status"), ("get", "/data-queue/batches"), ("post", "/data-queue/batches"),
                        ("get", "/data-queue/batches/1"), ("get", "/data-queue/batches/1/file.csv"),
                        ("post", "/data-queue/batches/1/upload"), ("post", "/data-queue/batches/1/release")):
        r = getattr(client, method)(url, headers=USER)
        assert r.status_code == 404 and r.get_json() == {"error": "Not found"}, url
        assert getattr(client, method)(url).status_code == 401
    c = store.connect()
    assert store.counts(c)["in_batch"] == 0 and c.execute("SELECT COUNT(*) FROM batches").fetchone()[0] == 0

def test_the_admin_flow_end_to_end(env, client):
    truth = make_catalog(env["c"])
    add_details(env["d"], ["s%03d" % i for i in range(80)], truth)
    now = time.time()
    for i in range(100, 110):
        store.enqueue(song(i), "request", now=now)
    st = client.get("/data-queue/status", headers=ADMIN).get_json()
    assert st["waiting"] == 10 and st["full_batch_ready"] is False and st["next_batch"]["size"] == 10
    assert st["coverage"]["total"] == 120 and st["coverage"]["real"] == 80 and st["links"]["soundiiz"].startswith("https://")
    made = client.post("/data-queue/batches", headers=ADMIN)
    assert made.status_code == 201
    bid = made.get_json()["batch"]["id"]
    again = client.post("/data-queue/batches", headers=ADMIN)             # the open one comes back
    assert again.status_code == 200 and again.get_json()["batch"]["id"] == bid and again.get_json()["created"] is False
    f = client.get("/data-queue/batches/%d/file.csv" % bid, headers=ADMIN)
    assert f.status_code == 200 and f.data.startswith(b"\xef\xbb\xbftitle,artist") and "attachment" in f.headers["Content-Disposition"]
    assert client.get("/data-queue/batches/%d/file.txt" % bid, headers=ADMIN).data.count(b"\n") == 10
    assert client.get("/data-queue/batches/%d/file.pdf" % bid, headers=ADMIN).status_code == 404
    body = {"name": "mix.csv", "csv": exportify_csv([sp_row("Song 100", "Artist 100", song(100)["isrc"], 300)])}
    up = client.post("/data-queue/batches/%d/upload" % bid, json=body, headers=ADMIN)
    assert up.status_code == 201 and up.get_json()["matched"] == 1 and up.get_json()["not_found"] == 9
    rep = client.post("/data-queue/batches/%d/upload" % bid, json=body, headers=ADMIN)
    assert rep.status_code == 200 and rep.get_json()["repeated"] is True
    detail = client.get("/data-queue/batches/%d" % bid, headers=ADMIN).get_json()
    assert detail["batch"]["state"] == "closed" and len(detail["songs"]) == 10
    assert [a["event"] for a in detail["audit"]][:3] == ["created", "download", "download"]
    hist = client.get("/data-queue/batches", headers=ADMIN).get_json()["batches"]
    assert hist[0]["id"] == bid and hist[0]["summary"]["matched"] == 1
    st = client.get("/data-queue/status", headers=ADMIN).get_json()
    assert st["open_batch"] is None and st["counts"]["done"] == 1 and st["coverage"]["real"] == 81
    assert st["coverage"]["predicted"] == 9

def test_upload_errors_are_plain_and_raw_text_works(env, client):
    fill(2, time.time())
    bid = client.post("/data-queue/batches", headers=ADMIN).get_json()["batch"]["id"]
    r = client.post("/data-queue/batches/%d/upload" % bid, json={"csv": ""}, headers=ADMIN)
    assert r.status_code == 400 and "CSV" in r.get_json()["error"]
    r = client.post("/data-queue/batches/%d/upload" % bid, data="Track Name,Artist Name(s)\nx,y\n",
                    content_type="text/csv", headers=ADMIN)
    assert r.status_code == 400 and "audio features" in r.get_json()["error"]
    assert client.post("/data-queue/batches/99/upload", json={"csv": "x"}, headers=ADMIN).status_code in (400, 404)
    assert client.post("/data-queue/batches/%d/release" % bid, headers=ADMIN).get_json() == {"released": True}
    assert client.post("/data-queue/batches/%d/release" % bid, headers=ADMIN).status_code == 409

# ── backfill ──────────────────────────────────────────────────────────────────

def test_backfill_queues_missing_songs_in_gap_order_and_honours_exclude(env, tmp_path, monkeypatch):
    truth = make_catalog(env["c"])
    add_details(env["d"], ["s000", "s001"], truth)
    ex = tmp_path / "earlier.csv"
    ex.write_text("title,artist,album,album artist,duration,isrc\nSong 10,Artist 10,,,210,%s\n" % song(10)["isrc"], encoding="utf-8")
    dry = dq.backfill(env["c"], [str(ex)], dry_run=True, details_path=env["d"], path=env["q"])
    assert dry["queued"] == 0 and dry["have_real_features"] == 2 and dry["excluded"] >= 1
    real = dq.backfill(env["c"], [str(ex)], details_path=env["d"], path=env["q"])
    c = store.connect()
    ids = {r[0] for r in c.execute("SELECT song_id FROM queue")}
    assert real["queued"] == real["to_queue"] == len(ids) and "s010" not in ids and "s000" not in ids
    assert {r[0] for r in c.execute("SELECT DISTINCT source FROM queue")} == {"backfill"}
    assert dq.backfill(env["c"], [str(ex)], details_path=env["d"], path=env["q"])["queued"] == 0   # re-run adds nothing
