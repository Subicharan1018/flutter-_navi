"""album-overnight-v1: Complete the album overnight. Synthetic songs only, no network (iTunes is faked),
no Telegram. The fetching itself is exportify.tick(): tested here against the real one.

    cd /opt/tg-fetcher && venv/bin/python -m pytest tests/test_album_overnight_v1.py -q
"""

import time
from types import SimpleNamespace

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from tgfetch import album_overnight as ao, album_overnight_api, db, exportify as ex

NOW = 1_800_000_000.0
SET = SimpleNamespace(library_dir=".", jobs_per_day=0)
NIGHT = time.mktime((2027, 1, 16, 2, 0, 0, 0, 0, -1))
NOON = time.mktime((2027, 1, 15, 12, 0, 0, 0, 0, -1))

# the film "Mazhai Kaalam" on iTunes: 6 tracks (the 5th is a 15 s sound clip, the 6th a karaoke cut)
FILM = {"collectionId": 777, "collectionName": "Mazhai Kaalam (Original Motion Picture Soundtrack)",
        "artistName": "Ravi Kumar", "primaryGenreName": "Tamil", "wrapperType": "collection", "collectionType": "Album",
        "artworkUrl100": "https://is1-ssl.mzstatic.com/image/100x100bb.jpg", "trackCount": 6}


def _song(n, title, artist="Diya Ram", ms=240000, cid=777):
    return {"wrapperType": "track", "kind": "song", "trackId": 7000 + n, "trackName": title, "artistName": artist,
            "collectionId": cid, "collectionName": FILM["collectionName"], "trackNumber": n, "discNumber": 1,
            "trackTimeMillis": ms, "releaseDate": "2024-05-01T07:00:00Z"}


TRACKS = [_song(1, "Kaadhal Mazhai"), _song(2, "Neela Megam"), _song(3, "Veera Nadai"), _song(4, "Ooru Sutri"),
          _song(5, "Intro", ms=15000), _song(6, "Neela Megam (Karaoke Version)")]


class FakeItunes:
    """Answers the three URLs Source uses. `down` makes every call fail."""

    def __init__(self, albums=None, songs=None, lookup=None, down=False):
        self.albums, self.songs, self.down = albums if albums is not None else [FILM], songs or [], down
        self.lookup = lookup if lookup is not None else {777: [FILM, *TRACKS]}
        self.urls = []

    def __call__(self, url):
        self.urls.append(url)
        if self.down:
            raise OSError("no network")
        if "lookup?id=" in url:
            cid = int(url.split("lookup?id=")[1].split("&")[0])
            return {"results": self.lookup.get(cid, [])}
        if "entity=album" in url:
            return {"results": self.albums}
        return {"results": self.songs}


def src(**kw):
    return ao.Source(get=FakeItunes(**kw), sleep=lambda s: None, gap=0)


@pytest.fixture
def conn(tmp_path):
    c = db.connect(tmp_path / "fetch.db")
    ao.ensure_schema(c)
    return c


LIB = [{"id": "L1", "title": "Kaadhal Mazhai", "artist": "Diya Ram", "album": "Mazhai Kaalam", "duration": 240.0, "isrc": ""},
       {"id": "L2", "title": "Veera Nadai", "artist": "Diya Ram", "album": "Mazhai Kaalam", "duration": 240.0, "isrc": ""}]


ONE = LIB[:1]          # only the song that landed: the other 3 real tracks of the album are missing


def land(conn, title="Kaadhal Mazhai", artist="Diya Ram", album="", user="amma", nd="L1", at=NOW - 60,
         result_id="bot:1", batch_id=None):
    """A song that finished downloading (a job in `ready`)."""
    sid = db.create_search(conn, user, title, status="done")
    conn.execute("INSERT INTO candidates (search_id, idx, result_id, title, artist, album, score, kind, type, reasons) "
                 "VALUES (?,0,?,?,?,?,1,'original','song','[]')", (sid, result_id, title, artist, album))
    cid = conn.execute("SELECT MAX(id) FROM candidates").fetchone()[0]
    conn.execute("INSERT INTO jobs (user, candidate_id, status, nd_song_id, created_at, updated_at, batch_id) "
                 "VALUES (?,?, 'ready', ?, ?, ?, ?)", (user, cid, nd, at, at, batch_id))
    return conn.execute("SELECT MAX(id) FROM jobs").fetchone()[0]


def on(conn, user="amma", **kw):
    return ao.set_prefs(conn, user, enabled=True, now=NOW - 3600, **kw)


def titles(conn, user="amma"):
    return [r[0] for r in conn.execute("SELECT title FROM album_tracks WHERE user=? AND state='active' ORDER BY track_no", (user,))]


# ── turning it on ────────────────────────────────────────────────────────────

def test_it_is_off_until_the_listener_turns_it_on(conn):
    land(conn)
    assert ao.get_prefs(conn, "amma")["enabled"] is False
    fake = FakeItunes()
    out = ao.scan(conn, LIB, ao.Source(get=fake, sleep=lambda s: None, gap=0), NOW)
    assert out == {"looked": 0, "albums": 0, "queued": 0} and fake.urls == []
    assert ao.run_pass(conn, SET, LIB, src(), NOW) == {}


def test_songs_that_landed_before_it_was_turned_on_are_left_alone(conn):
    land(conn, at=NOW - 7200)                      # landed two hours ago
    on(conn)                                       # turned on one hour ago
    fake = FakeItunes()
    assert ao.scan(conn, LIB, ao.Source(get=fake, sleep=lambda s: None, gap=0), NOW)["looked"] == 0 and fake.urls == []


# ── finding and queueing the album ───────────────────────────────────────────

def test_a_landed_song_queues_the_albums_missing_tracks(conn):
    on(conn)
    land(conn)
    out = ao.scan(conn, LIB, src(), NOW)
    assert out == {"looked": 1, "albums": 1, "queued": 2}
    # Kaadhal Mazhai and Veera Nadai are owned; the 15 s clip and the karaoke cut are not songs to fetch
    assert titles(conn) == ["Neela Megam", "Ooru Sutri"]
    a = conn.execute("SELECT * FROM album_albums").fetchone()
    assert (a["total"], a["owned"], a["status"], a["key"]) == (4, 2, "active", "a:777")
    iid = ao._import_id(conn, "amma")
    plan = ex.get_plan(conn, iid)
    assert plan["status"] == "active" and plan["priority"] == "list"
    rows = conn.execute("SELECT title, state, album, pos FROM exportify_songs WHERE import_id=? ORDER BY pos", (iid,)).fetchall()
    assert [(r["title"], r["state"]) for r in rows] == [("Neela Megam", "wishlist"), ("Ooru Sutri", "wishlist")]
    assert rows[0]["album"].startswith("Mazhai Kaalam")


def test_the_same_landed_song_is_never_looked_at_twice(conn):
    on(conn)
    land(conn)
    ao.scan(conn, LIB, src(), NOW)
    assert ao.scan(conn, LIB, src(), NOW + 600) == {"looked": 0, "albums": 0, "queued": 0}
    assert conn.execute("SELECT COUNT(*) FROM album_albums").fetchone()[0] == 1


def test_two_songs_of_one_album_make_one_album(conn):
    on(conn)
    land(conn)
    land(conn, "Veera Nadai", nd="L2")
    out = ao.scan(conn, LIB, src(), NOW)
    assert out["looked"] == 2 and out["albums"] == 1
    assert conn.execute("SELECT COUNT(*) FROM album_tracks").fetchone()[0] == 2


def test_an_album_is_trusted_only_when_the_song_is_in_its_track_list(conn):
    on(conn)
    land(conn, "Some Other Song", nd="L9")
    lib = LIB + [{"id": "L9", "title": "Some Other Song", "artist": "Diya Ram", "album": "Mazhai Kaalam",
                  "duration": 200.0, "isrc": ""}]
    assert ao.scan(conn, lib, src(), NOW) == {"looked": 1, "albums": 0, "queued": 0}
    assert conn.execute("SELECT COUNT(*) FROM album_albums").fetchone()[0] == 0


def test_the_album_is_found_by_song_when_the_library_only_has_the_films_name(conn):
    on(conn)
    land(conn)
    lib = [{**LIB[0], "album": "Mazhai"}, LIB[1]]                                      # the album name leads nowhere
    out = ao.scan(conn, lib, src(albums=[], songs=[TRACKS[0]]), NOW)
    assert out["albums"] == 1 and titles(conn) == ["Neela Megam", "Ooru Sutri"]


def test_a_single_is_not_an_album(conn):
    on(conn, film_only=False)
    land(conn)
    single = {**FILM, "collectionName": "Kaadhal Mazhai - Single", "collectionId": 5}
    lookup = {5: [single, _song(1, "Kaadhal Mazhai", cid=5)]}
    assert ao.scan(conn, LIB, src(albums=[single], lookup=lookup), NOW)["albums"] == 0


def test_film_albums_only_by_default(conn):
    on(conn)
    land(conn)
    pop = {**FILM, "collectionName": "Mazhai Kaalam", "primaryGenreName": "Pop"}
    lookup = {777: [pop, *[{**t, "collectionName": "Mazhai Kaalam"} for t in TRACKS]]}
    lib = [{**LIB[0], "album": "Mazhai Kaalam"}, LIB[1]]
    assert ao.scan(conn, lib, src(albums=[pop], lookup=lookup), NOW)["albums"] == 0
    # the listener turns "film albums only" off: the next song of it queues it
    ao.set_prefs(conn, "amma", film_only=False, now=NOW)
    land(conn, "Veera Nadai", nd="L2")
    assert ao.scan(conn, lib, src(albums=[pop], lookup=lookup), NOW)["albums"] == 1


def test_a_compilation_is_not_completed(conn):
    on(conn)
    land(conn)
    big = [FILM, *[_song(n, f"Song {n}") for n in range(2, 60)], TRACKS[0]]
    assert ao.scan(conn, LIB, src(lookup={777: big}), NOW)["albums"] == 0


def test_an_album_you_already_have_is_recorded_not_queued(conn):
    on(conn)
    land(conn)
    lib = LIB + [{"id": f"X{i}", "title": t["trackName"], "artist": "Diya Ram", "album": "x", "duration": 240.0, "isrc": ""}
                 for i, t in enumerate(TRACKS[1:4])]
    out = ao.scan(conn, lib, src(), NOW)
    assert out["albums"] == 1 and out["queued"] == 0
    assert conn.execute("SELECT status FROM album_albums").fetchone()[0] == "nothing"
    assert ao._import_id(conn, "amma") is None            # no import made for nothing


def test_bulk_work_is_not_a_song_you_asked_for(conn):
    on(conn)
    land(conn, result_id="exportify:41")                                 # the Spotify wishlist / Weekly Exploration
    bid = conn.execute("INSERT INTO batches (user, kind, title, artist, candidate_ids, created_at, updated_at) "
                       "VALUES ('amma','songs','a list','','[]',1,1)").lastrowid
    for i in range(7):                                                   # a 7-song playlist import
        land(conn, f"Song {i}", nd=f"P{i}", batch_id=bid)
        conn.execute("UPDATE jobs SET batch_id=? WHERE id=(SELECT MAX(id) FROM jobs)", (bid,))
    fake = FakeItunes()
    assert ao.scan(conn, LIB, ao.Source(get=fake, sleep=lambda s: None, gap=0), NOW)["looked"] == 0 and fake.urls == []


def test_another_listeners_songs_are_not_looked_at(conn):
    on(conn, user="appa")
    land(conn, user="amma")
    assert ao.scan(conn, LIB, src(), NOW)["looked"] == 0


def test_the_queue_has_a_ceiling_and_an_albums_cap(conn, monkeypatch):
    on(conn, max_per_album=5)
    monkeypatch.setattr(ao, "MAX_WAITING", 2)
    land(conn)
    out = ao.scan(conn, ONE, src(), NOW)          # 3 songs are missing, the ceiling says 2
    assert out["queued"] == 2
    other = {**FILM, "collectionId": 888, "collectionName": "Other Film (Original Motion Picture Soundtrack)"}
    t2 = [_song(1, "Other One", cid=888), _song(2, "Other Two", cid=888)]
    j = land(conn, "Other One", nd="L3")
    lib = [{"id": "L3", "title": "Other One", "artist": "Diya Ram", "album": "Other Film", "duration": 240.0, "isrc": ""}]
    assert ao.scan(conn, lib, src(albums=[other], lookup={888: [other, *t2]}), NOW)["albums"] == 0
    # the queue is full: that song is looked at again when there is room, not forgotten
    assert conn.execute("SELECT COUNT(*) FROM album_seen WHERE job_id=?", (j,)).fetchone()[0] == 0


def test_a_failed_lookup_is_tried_again_not_forgotten(conn):
    on(conn)
    j = land(conn)
    assert ao.scan(conn, LIB, src(down=True), NOW)["looked"] == 0
    assert conn.execute("SELECT COUNT(*) FROM album_seen WHERE job_id=?", (j,)).fetchone()[0] == 0
    assert ao.scan(conn, LIB, src(), NOW + 600)["albums"] == 1


def test_a_song_navidrome_has_not_scanned_yet_waits(conn):
    on(conn)
    j = land(conn, nd="NEW", at=NOW - 60)
    assert ao.scan(conn, LIB, src(), NOW)["looked"] == 0
    assert conn.execute("SELECT COUNT(*) FROM album_seen WHERE job_id=?", (j,)).fetchone()[0] == 0


def test_run_pass_never_raises(conn, monkeypatch):
    on(conn)
    land(conn)

    def boom(*a, **k):
        raise RuntimeError("anything")
    monkeypatch.setattr(ao, "scan", boom)
    assert ao.run_pass(conn, SET, LIB, src(), NOW) == {}


def test_only_a_title_and_artist_leave_the_server(conn):
    on(conn)
    land(conn)
    fake = FakeItunes()
    ao.scan(conn, LIB, ao.Source(get=fake, sleep=lambda s: None, gap=0), NOW)
    assert fake.urls and all(u.startswith("https://itunes.apple.com/") for u in fake.urls)
    assert not any("amma" in u or "L1" in u for u in fake.urls)


# ── the one scheduler: exportify.tick() ──────────────────────────────────────

def test_exportify_tick_fetches_it_under_its_own_rules(conn):
    on(conn, per_night=10)
    land(conn)
    ao.scan(conn, ONE, src(), NOW)                                    # 3 missing
    iid = ao._import_id(conn, "amma")
    assert ex.get_plan(conn, iid)["per_night"] == 10
    # outside the night window: nothing is queued
    done = ex.tick(conn, SET, free=500.0, now=NOON)
    assert done[0]["queued"] == 0 and done[0]["note"] == "outside the night window"
    # at night: one batch of the 3, in album order
    done = ex.tick(conn, SET, free=500.0, now=NIGHT)
    assert done[0]["queued"] == 3
    assert [r[0] for r in conn.execute("SELECT title FROM exportify_songs WHERE import_id=? AND state='queued' ORDER BY pos", (iid,))] \
        == ["Neela Megam", "Veera Nadai", "Ooru Sutri"]
    # one batch at a time
    assert ex.tick(conn, SET, free=500.0, now=NIGHT + 60)[0]["note"] == "waiting for the running batch"


def test_the_disk_floor_and_the_nightly_cap_apply(conn):
    on(conn, per_night=10)
    land(conn)
    ao.scan(conn, ONE, src(), NOW)
    done = ex.tick(conn, SET, free=40.0, now=NIGHT)                  # right at the 40 GB floor
    assert done[0]["note"] == "disk is low"
    iid = ao._import_id(conn, "amma")
    assert ex.get_plan(conn, iid)["status"] == "paused_disk"
    conn.execute("UPDATE exportify_plans SET per_night=2, status='active' WHERE import_id=?", (iid,))
    assert ex.tick(conn, SET, free=500.0, now=NIGHT)[0]["queued"] == 2


# ── seeing and cancelling the queue ──────────────────────────────────────────

def test_the_page_lists_albums_tracks_and_where_each_is(conn):
    on(conn)
    land(conn)
    ao.scan(conn, LIB, src(), NOW)
    iid = ao._import_id(conn, "amma")
    conn.execute("UPDATE exportify_songs SET state='downloaded', nd_song_id='N9' WHERE import_id=? AND title='Neela Megam'", (iid,))
    cur = ao.current(conn, "amma", NOW)
    assert cur["enabled"] and cur["waiting"] == 1 and cur["max_waiting"] == ao.MAX_WAITING
    (a,) = cur["albums"]
    assert (a["album"], a["state"], a["total"], a["owned"], a["from_song"]) == (FILM["collectionName"], "waiting", 4, 2, "Kaadhal Mazhai")
    assert a["cover_url"].endswith("600x600bb.jpg")
    assert [(t["title"], t["state"], t["song_id"]) for t in a["tracks"]] == [("Neela Megam", "ready", "N9"), ("Ooru Sutri", "waiting", None)]
    assert ao.current(conn, "appa", NOW)["albums"] == []


def test_cancel_an_album_drops_what_is_waiting_and_it_never_comes_back(conn):
    on(conn)
    land(conn)
    ao.scan(conn, LIB, src(), NOW)
    (a,) = ao.current(conn, "amma", NOW)["albums"]
    assert ao.cancel_album(conn, "amma", a["id"], NOW) == {"stopped": 2, "already_on_its_way": 0}
    iid = ao._import_id(conn, "amma")
    assert conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE import_id=?", (iid,)).fetchone()[0] == 0
    assert conn.execute("SELECT total_rows FROM exportify_imports WHERE id=?", (iid,)).fetchone()[0] == 0
    assert ex.get_plan(conn, iid)["status"] == "cancelled"
    assert ao.current(conn, "amma", NOW)["albums"] == []
    land(conn, "Veera Nadai", nd="L2")                                 # another song of it lands
    assert ao.scan(conn, LIB, src(), NOW)["albums"] == 0
    assert ao.waiting_tracks(conn, "amma") == 0


def test_a_track_already_with_the_bot_is_not_cancelled(conn):
    on(conn)
    land(conn)
    ao.scan(conn, ONE, src(), NOW)
    iid = ao._import_id(conn, "amma")
    ex.tick(conn, SET, free=500.0, now=NIGHT)                          # all 3 are in a running batch
    (a,) = ao.current(conn, "amma", NOW)["albums"]
    assert ao.cancel_album(conn, "amma", a["id"], NOW) == {"stopped": 0, "already_on_its_way": 3}
    assert conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE import_id=? AND state='queued'", (iid,)).fetchone()[0] == 3


def test_cancel_all_and_cancelling_someone_elses_album(conn):
    on(conn)
    on(conn, user="appa")
    land(conn)
    ao.scan(conn, LIB, src(), NOW)
    other = conn.execute("SELECT id FROM album_albums").fetchone()[0]
    with pytest.raises(ao.AlbumError):
        ao.cancel_album(conn, "appa", other)
    assert ao.cancel_all(conn, "amma", NOW) == {"stopped": 2, "already_on_its_way": 0, "albums": 1}
    assert ao.cancel_all(conn, "amma", NOW) == {"stopped": 0, "already_on_its_way": 0, "albums": 0}


def test_a_track_shared_with_another_wishlist_is_not_deleted_by_cancelling(conn):
    on(conn)
    iid = conn.execute("INSERT INTO exportify_imports (user, name, created_at, total_rows) VALUES ('amma','Spotify',1,1)").lastrowid
    conn.execute("INSERT INTO exportify_plans (import_id, user, status, updated_at) VALUES (?, 'amma','idle',1)", (iid,))
    key = ex.song_key("", "Neela Megam", "Diya Ram")
    conn.execute("INSERT INTO exportify_songs (import_id,user,pos,key,title,artist,state,updated_at) "
                 "VALUES (?, 'amma',0,?, 'Neela Megam','Diya Ram','wishlist',1)", (iid, key))
    land(conn)
    ao.scan(conn, LIB, src(), NOW)
    (a,) = ao.current(conn, "amma", NOW)["albums"]
    ao.cancel_album(conn, "amma", a["id"], NOW)
    assert conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE import_id=?", (iid,)).fetchone()[0] == 1


def test_off_pauses_the_fetch_and_on_resumes_it(conn):
    on(conn)
    land(conn)
    ao.scan(conn, LIB, src(), NOW)
    iid = ao._import_id(conn, "amma")
    ao.set_prefs(conn, "amma", enabled=False, now=NOW)
    assert ex.get_plan(conn, iid)["status"] == "paused"
    assert ao.scan(conn, LIB, src(), NOW)["looked"] == 0
    ao.set_prefs(conn, "amma", enabled=True, now=NOW)
    assert ex.get_plan(conn, iid)["status"] == "active"


def test_prefs_are_snapped_to_the_choices(conn):
    p = ao.set_prefs(conn, "amma", per_night=33, max_per_album=7, now=NOW)
    assert (p["per_night"], p["max_per_album"]) == (30, 5)


# ── the routes ───────────────────────────────────────────────────────────────

@pytest.fixture
def client(conn):
    app = FastAPI()
    album_overnight_api.register_routes(app, SET, conn, lambda: "amma")
    return TestClient(app)


def test_routes(client, conn):
    assert client.get("/album-overnight/current").json()["enabled"] is False
    r = client.put("/album-overnight/prefs", json={"enabled": True, "per_night": 20})
    assert r.status_code == 200 and r.json()["enabled"] and r.json()["per_night"] == 20
    assert client.put("/album-overnight/prefs", json={"per_night": 0}).status_code == 422
    t = time.time()
    land(conn, at=t + 1)                                                # lands after it was turned on
    ao.scan(conn, LIB, src(), t + 2)
    (a,) = client.get("/album-overnight/current").json()["albums"]
    assert client.post(f"/album-overnight/albums/{a['id']}/cancel").json()["stopped"] == 2
    assert client.post("/album-overnight/albums/999/cancel").status_code == 404
    assert client.post("/album-overnight/cancel-all").json()["albums"] == 0
