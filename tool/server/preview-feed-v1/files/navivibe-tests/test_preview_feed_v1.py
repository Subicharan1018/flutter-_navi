"""preview-feed-v1: names, previews (Deezer / iTunes, cached, expiring), sources, the feed, signals + daily cap, routes."""

import sqlite3

import pytest
from flask import Flask, g

from navivibe import preview_feed as pf

NOW = 1_800_000_000.0   # any fixed moment


@pytest.fixture(autouse=True)
def clean(monkeypatch):
    pf._mem.clear()
    monkeypatch.setattr(pf, "DAILY_CAP", 3)


@pytest.fixture
def db(tmp_path):
    c = pf.connect(str(tmp_path / "pf.db"))
    yield c
    c.close()


EMPTY_LIB = lambda: {"pairs": set(), "isrcs": set()}


def cand(title, artist, **kw):
    return dict({"title": title, "artist": artist, "album": "", "isrc": "", "deezer_id": None, "source": "chart", "reason": "Trending"}, **kw)


def itunes_ok(title, artist, url="https://aud.example/p.m4a"):
    return {"results": [{"trackName": title, "artistName": artist, "previewUrl": url,
                         "artworkUrl100": "https://is1.mzstatic.com/x/100x100bb.jpg"}]}


# ── names ────────────────────────────────────────────────────────────────────

def test_norm_keeps_tamil_marks():
    assert pf.norm("வா வாத்தியார்") == "வா வாத்தியார்"      # vowel signs are marks, not letters: they must survive
    assert pf.norm("Kadhal (From \"Film\") feat. X") == "kadhal"
    assert pf.norm("Song - From \"Movie\"") == "song"


def test_key_ignores_noise_and_second_artist():
    assert pf.key_of("Naatu Naatu (Telugu)", "Rahul Sipligunj, Kaala Bhairava") == pf.key_of("naatu naatu", "Rahul Sipligunj")
    assert pf.key_of("A", "B") != pf.key_of("A", "C")


# ── previews ─────────────────────────────────────────────────────────────────

def test_deezer_preview_used_for_deezer_ids_and_cached(db):
    calls = []

    def http(url, params):
        calls.append(url)
        return {"preview": "https://cdn.dz/p.mp3", "album": {"cover_big": "https://dz/c.jpg"}}
    r = pf.Resolver(db, http, NOW)
    c = dict(cand("Song", "Artist", deezer_id=7), key="k1")
    assert r.resolve(c) == {"url": "https://cdn.dz/p.mp3", "art_url": "https://dz/c.jpg", "provider": "deezer"}
    assert r.resolve(c)["url"] == "https://cdn.dz/p.mp3"
    assert len(calls) == 1                                          # second time from the cache


def test_itunes_fallback_needs_matching_title_and_artist(db):
    def http(url, params):
        if "itunes" in url:
            return {"results": [
                {"trackName": "Other Song", "artistName": "Artist", "previewUrl": "https://x/wrong"},
                {"trackName": "Song", "artistName": "Somebody Else", "previewUrl": "https://x/wrong2"},
                {"trackName": "Song (Remastered)", "artistName": "Artist & Friend", "previewUrl": "https://x/right",
                 "artworkUrl100": "https://is1.mzstatic.com/a/100x100bb.jpg"}]}
        raise AssertionError("no deezer id: deezer must not be called")
    hit = pf.Resolver(db, http, NOW).resolve(dict(cand("Song", "Artist"), key="k2"))
    assert hit["url"] == "https://x/right" and hit["provider"] == "itunes"
    assert hit["art_url"].endswith("600x600bb.jpg")


def test_deezer_failure_falls_back_to_itunes(db):
    def http(url, params):
        if "deezer" in url:
            raise RuntimeError("region")
        return itunes_ok("Song", "Artist")
    assert pf.Resolver(db, http, NOW).resolve(dict(cand("Song", "Artist", deezer_id=1), key="k3"))["provider"] == "itunes"


def test_miss_is_cached_for_an_hour_and_expired_rows_are_purged(db):
    n = []

    def http(url, params):
        n.append(1)
        return {"results": []}
    c = dict(cand("Nope", "Nobody"), key="k4")
    assert pf.Resolver(db, http, NOW).resolve(c) is None
    assert pf.Resolver(db, http, NOW + 60).resolve(c) is None and len(n) == 1
    assert pf.Resolver(db, http, NOW + pf.MISS_TTL_S + 1).resolve(c) is None and len(n) == 2
    r = pf.Resolver(db, http, NOW + 10 * pf.PREVIEW_TTL_S)
    r.purge()
    assert db.execute("SELECT COUNT(*) FROM preview_cache").fetchone()[0] == 0     # nothing is kept long-term


def test_budget_stops_outside_calls_without_caching_a_miss(db):
    n = []
    r = pf.Resolver(db, lambda u, p: n.append(1) or {"results": []}, NOW, budget=1)
    assert r.resolve(dict(cand("A", "B"), key="a")) is None
    assert r.resolve(dict(cand("C", "D"), key="c")) is None
    assert len(n) == 1 and r.cached("c") is None


# ── sources ──────────────────────────────────────────────────────────────────

def make_fetch_db(path):
    c = sqlite3.connect(path)
    c.execute("CREATE TABLE trending_songs (key TEXT PRIMARY KEY, deezer_id TEXT, title TEXT, artist TEXT, album TEXT, "
              "duration_s INTEGER, isrc TEXT, status TEXT, nd_song_id TEXT)")
    c.execute("CREATE TABLE trending_entries (chart TEXT, date TEXT, rank INTEGER, key TEXT, title TEXT, artist TEXT, "
              "album TEXT, nd_song_id TEXT, created_at REAL)")
    rows = [("s1", "11", "New Hit", "Anirudh", "pending", None), ("s2", "12", "Owned One", "Rahman", "owned", "nd9"),
            ("s3", None, "No Id", "Sid Sriram", "pending", None)]
    for k, did, t, a, st, nd in rows:
        c.execute("INSERT INTO trending_songs VALUES (?,?,?,?,?,?,?,?,?)", (k, did, t, a, "", 200, "", st, nd))
    for rank, (k, t, a, nd) in enumerate([("s1", "New Hit", "Anirudh", None), ("s2", "Owned One", "Rahman", "nd9"),
                                          ("s3", "No Id", "Sid Sriram", None)], 1):
        c.execute("INSERT INTO trending_entries VALUES ('tamil','2026-11-23',?,?,?,?,'',?,1)", (rank, k, t, a, nd))
    c.execute("INSERT INTO trending_entries VALUES ('tamil','2026-11-01',1,'s9','Old Day','Old',  '',NULL,1)")
    c.commit()
    c.close()


def test_charts_candidates_skip_owned_and_old_snapshots(tmp_path):
    p = str(tmp_path / "fetch.db")
    make_fetch_db(p)
    got = pf.charts_candidates(p)
    assert [(g_["title"], g_["deezer_id"]) for g_ in got] == [("New Hit", "11"), ("No Id", None)]
    assert got[0]["reason"] == "Trending · tamil #1"


def test_charts_missing_database_is_an_error_the_feed_absorbs(tmp_path, db):
    with pytest.raises(sqlite3.Error):
        pf.charts_candidates(str(tmp_path / "missing.db"))
    out = pf.build_feed(db, "ann", 5, NOW, http=lambda u, p: {}, library=EMPTY_LIB,
                        charts=lambda: pf._memo("charts", 1, NOW, lambda: pf.charts_candidates(str(tmp_path / "missing.db"))),
                        releases=lambda: [])
    assert out["items"] == []


def test_releases_candidates_carry_their_preview():
    def http(url, params):
        if url.endswith("/editorial/0/releases"):
            return {"data": [{"id": 5, "title": "Album", "artist": {"name": "Singer"}, "cover_big": "https://c/5.jpg"}]}
        return {"data": [{"id": 50, "title": "Track A", "preview": "https://p/a.mp3", "artist": {"name": "Singer"}},
                         {"id": 51, "title": "No Preview", "preview": ""}]}
    got = pf.releases_candidates(http)
    assert [(x["title"], x["preview_url"], x["art_url"]) for x in got] == [("Track A", "https://p/a.mp3", "https://c/5.jpg")]


def test_friends_candidates_use_other_users_hearts_only(db):
    for u, v, t in (("ann", "yes", "Mine"), ("bob", "yes", "Bobs"), ("cy", "no", "Nope")):
        pf.record_signal(db, u, {"key": pf.key_of(t, "X"), "title": t, "artist": "X", "verdict": v, "ratio": 1}, NOW)
    got = pf.friends_candidates(db, "ann", NOW + 10)
    assert [g_["title"] for g_ in got] == ["Bobs"]
    assert "user" not in got[0] and "bob" not in str(got)
    assert pf.friends_candidates(db, "ann", NOW + 40 * 86400) == []


# ── the feed ─────────────────────────────────────────────────────────────────

def test_feed_drops_owned_and_decided_mixes_sources_and_names_preview(db):
    lib = lambda: {"pairs": {(pf.norm("Owned"), pf.first_artist("Artist"))}, "isrcs": {"ISRC1"}}
    charts = lambda: [cand("Owned", "Artist"), cand("Fresh", "Artist", deezer_id=3), cand("Seen", "Artist", deezer_id=4),
                      cand("ByIsrc", "Other", isrc="is-rc1"), cand("Chart Two", "Artist", deezer_id=5)]
    releases = lambda: [cand("Rel", "Singer", preview_url="https://p/rel.mp3", source="release", reason="New release")]
    pf.record_signal(db, "ann", {"key": pf.key_of("Seen", "Artist"), "title": "Seen", "artist": "Artist", "verdict": "no", "ratio": 0.1}, NOW)

    def http(url, params):
        return {"preview": "https://p/%s.mp3" % url.rsplit("/", 1)[1], "album": {"cover_big": "https://c/x.jpg"}}
    out = pf.build_feed(db, "ann", 10, NOW, http=http, charts=charts, releases=releases, library=lib)
    assert [i["title"] for i in out["items"]] == ["Fresh", "Rel", "Chart Two"]       # round robin: chart, (no friends), release, chart
    assert out["items"][0]["preview_url"] == "https://p/3.mp3" and out["items"][0]["duration_s"] == 30
    assert out["remaining"] == 3 and out["cap"] == 3


def test_feed_skips_songs_without_a_preview_and_respects_limit(db):
    charts = lambda: [cand("A%d" % i, "X", deezer_id=i) for i in range(1, 11)]
    http = lambda u, p: {"preview": "" if u.endswith(("/1", "/2")) else "https://p/ok.mp3", "album": {}} if "deezer" in u else {"results": []}
    out = pf.build_feed(db, "ann", 4, NOW, http=http, charts=charts, releases=lambda: [], library=EMPTY_LIB)
    assert [i["title"] for i in out["items"]] == ["A3", "A4", "A5", "A6"]


# ── signals and the daily cap ────────────────────────────────────────────────

def sig(title, verdict, ratio=0.5, artist="X"):
    return {"key": pf.key_of(title, artist), "title": title, "artist": artist, "verdict": verdict, "ratio": ratio}


def test_cap_counts_hearts_only_and_refuses_the_next(db):
    for t in ("a", "b", "c"):
        pf.record_signal(db, "Ann", sig(t, "yes"), NOW)
    for t in ("d", "e", "f", "g"):
        pf.record_signal(db, "Ann", sig(t, "no"), NOW)                  # skips are free
    with pytest.raises(pf.SignalError) as e:
        pf.record_signal(db, "ann", sig("h", "yes"), NOW)
    assert e.value.status == 429 and e.value.extra["remaining"] == 0
    assert pf.remaining(db, "ann", NOW) == 0
    assert pf.remaining(db, "ann", NOW + 86400) == 3                    # tomorrow (India time) is a new allowance
    assert pf.record_signal(db, "ann", sig("a", "yes"), NOW)["verdict"] == "yes"     # the same heart again is not a new one


def test_a_swipe_after_a_heart_does_not_take_it_back(db):
    pf.record_signal(db, "ann", sig("a", "yes"), NOW)
    assert pf.record_signal(db, "ann", sig("a", "no", 0.9), NOW + 5)["verdict"] == "yes"


def test_signal_validation(db):
    bad = [None, [], {**sig("a", "yes"), "key": "pv_forged"}, {**sig("a", "maybe")}, {**sig("a", "yes"), "ratio": 2},
           {**sig("a", "yes"), "ratio": True}, {**sig("a", "yes"), "title": ""}, {**sig("a", "yes"), "artist": "x" * 201}]
    for b in bad:
        with pytest.raises(pf.SignalError) as e:
            pf.record_signal(db, "ann", b, NOW)
        assert e.value.status == 400
    assert db.execute("SELECT COUNT(*) FROM signals").fetchone()[0] == 0


def test_reset_day_boundary_is_india_time():
    # 18:29 UTC = 23:59 IST, 18:30 UTC = 00:00 IST next day
    base = 1_800_000_000 // 86400 * 86400
    assert pf.ist_day(base + 18 * 3600 + 29 * 60) + 1 == pf.ist_day(base + 18 * 3600 + 30 * 60)


# ── routes ───────────────────────────────────────────────────────────────────

@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setattr(pf, "PATH", str(tmp_path / "routes.db"))
    monkeypatch.setattr(pf, "default_library", EMPTY_LIB)
    monkeypatch.setattr(pf, "charts_candidates", lambda path=None: [cand("Route Song", "Artist")])
    monkeypatch.setattr(pf, "releases_candidates", lambda http=None, albums=6: [])
    monkeypatch.setattr(pf, "default_http", lambda url, params=None: itunes_ok("Route Song", "Artist"))
    allowed = {"ann"}
    app = Flask(__name__)

    def require_auth(f):
        def w(*a, **k):
            from flask import request, jsonify
            u = request.headers.get("X-User")
            if not u:
                return jsonify({"error": "no"}), 401
            g.username = u
            return f(*a, **k)
        w.__name__ = f.__name__
        return w
    pf.register_preview_feed_routes(app, require_auth, lambda u: u in allowed)
    return app.test_client()


def test_routes_need_sign_in_and_download_access(client):
    assert client.get("/preview-feed").status_code == 401
    r = client.get("/preview-feed", headers={"X-User": "zed"})
    assert r.status_code == 403
    r = client.post("/preview-feed/signal", json=sig("a", "yes"), headers={"X-User": "zed"})
    assert r.status_code == 403
    assert not __import__("os").path.exists(pf.PATH)                       # nothing was opened for a refused user


def test_route_feed_and_signal_round_trip(client):
    h = {"X-User": "ann"}
    r = client.get("/preview-feed?limit=5", headers=h)
    assert r.status_code == 200
    item = r.get_json()["items"][0]
    assert item["title"] == "Route Song" and item["preview_url"] == "https://aud.example/p.m4a"
    body = {"key": item["key"], "title": item["title"], "artist": item["artist"], "verdict": "yes", "ratio": 0.8}
    r = client.post("/preview-feed/signal", json=body, headers=h)
    assert r.status_code == 200 and r.get_json()["remaining"] == 2
    assert client.get("/preview-feed", headers=h).get_json()["items"] == []          # decided songs never come back


def test_route_cap_is_429_with_a_sentence(client):
    h = {"X-User": "ann"}
    for t in ("a", "b", "c"):
        assert client.post("/preview-feed/signal", json=sig(t, "yes"), headers=h).status_code == 200
    r = client.post("/preview-feed/signal", json=sig("d", "yes"), headers=h)
    assert r.status_code == 429 and "limit" in r.get_json()["error"] and r.get_json()["remaining"] == 0
