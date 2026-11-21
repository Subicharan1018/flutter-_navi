"""weekly-exploration-v1: Weekly Exploration. Synthetic artists and songs only, no network (Deezer and
iTunes are faked), no Telegram, no real clock.

    cd /opt/tg-fetcher && venv/bin/python -m pytest tests/test_weekly_exploration_v1.py -q
"""

import inspect
import time
import urllib.parse
from collections import Counter
from dataclasses import replace

import pytest
from fastapi.testclient import TestClient

from tgfetch import exportify as ex
from tgfetch import weekly_exploration as wx
from tgfetch import weekly_exploration_api as wxapi
from tgfetch.api import create_app

from test_exportify_v1 import LIB, NIGHT, NOON, details_db  # noqa: F401  (details_db: autouse, keeps real files untouched)
from test_worker import _no_llm, cfg, fakes  # noqa: F401  (fixtures)

DAY = 86400
MON = time.mktime((2026, 11, 16, 9, 0, 0, 0, 0, -1))          # a Monday morning (local = IST is not assumed: only week_of's maths is)

# A fixed listening history, as the shuffle server would send it: what the listener plays, by language.
SEEDS = {"artists": [
    {"name": "Aarav Kumar", "language": "Tamil", "plays": 12},
    {"name": "Diya Ram", "language": "Tamil", "plays": 6},
    {"name": "Zed Harbor", "language": "English", "plays": 6},
], "blocked_artists": [], "extra": []}

RELATED = {                         # Deezer: who is related to whom (names only)
    "Aarav Kumar": ["Meena Rao", "Nila Das", "Ravi Q", "Kavin M", "Pooja V", "Sana Joy"],
    "Diya Ram": ["Nila Das", "Pooja V", "Tara Vel"],
    "Zed Harbor": ["Mina Hart", "Odd Lark", "Fenn Cole", "Rue Banks"],
    "Kavin M": ["Far One", "Far Two", "Aarav Kumar"],
    "Fenn Cole": ["Far Three", "Far Four"],
    "Pooja V": ["Far Five", "Far Six"],
}


def it(title, artist, secs=200, album="Some Album"):
    return {"kind": "song", "trackId": abs(hash((title, artist))) % 10**8, "trackName": title, "artistName": artist,
            "collectionName": album, "trackTimeMillis": int(secs * 1000), "releaseDate": "2025-06-01T07:00:00Z",
            "previewUrl": "https://audio-ssl.itunes.apple.com/p/" + urllib.parse.quote(title) + ".m4a",
            "artworkUrl100": "https://is1-ssl.mzstatic.com/image/x/100x100bb.jpg"}


def songs_of(artist, n=5):
    return [it(f"{artist.split()[0]} Song {i}", artist) for i in range(1, n + 1)]


CATALOG = {a: songs_of(a) for a in
           ["Aarav Kumar", "Diya Ram", "Zed Harbor", "Meena Rao", "Nila Das", "Ravi Q", "Kavin M", "Pooja V", "Sana Joy",
            "Tara Vel", "Mina Hart", "Odd Lark", "Fenn Cole", "Rue Banks", "Far One", "Far Two", "Far Three", "Far Four", "Far Five", "Far Six"]}
CATALOG["Aarav Kumar"] += [it("Neela Megam", "Aarav Kumar • Meena Rao", 250),              # owned (LIB s1)
                           it("Aarav Song 1 - Remix", "Aarav Kumar"),                        # a remix
                           it("Aarav Karaoke Version", "Aarav Kumar"),                       # karaoke
                           it("Aarav Eight Hour Loop", "Aarav Kumar", 28800)]                # not a song


def fake_get(url):
    q = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)
    path = urllib.parse.urlparse(url).path
    if "deezer" in url and path == "/search/artist":
        name = q["q"][0]
        return {"data": [{"id": abs(hash(name)) % 10**6, "name": name}]} if name in RELATED or name in CATALOG else {"data": []}
    if "deezer" in url and path.endswith("/related"):
        for name in RELATED:
            if str(abs(hash(name)) % 10**6) in path:
                return {"data": [{"id": 1, "name": n} for n in RELATED[name]]}
        return {"data": []}
    if "itunes" in url:
        term = q["term"][0]
        if term in CATALOG:
            return {"results": CATALOG[term]}
        return {"results": [r for rs in CATALOG.values() for r in rs if f"{r['artistName']} {r['trackName']}" == term]}
    raise AssertionError(url)


def sources(**kw):
    return wx.Sources(get=fake_get, sleep=lambda s: None, itunes_gap=0, **kw)


def make(conn, user="alice", seeds=SEEDS, now=MON, library=LIB, size=20, src=None):
    wx.ensure_schema(conn)
    return wx.build(conn, user, seeds, src or sources(), [dict(s) for s in library] if library else None, now, size)


def picks(conn, user="alice", state="pending"):
    return [dict(r) for r in conn.execute("SELECT * FROM weekly_picks WHERE user=? AND state=? ORDER BY id", (user, state))]


# ── picking ──────────────────────────────────────────────────────────────────

def test_a_list_follows_the_listeners_taste(conn):
    assert make(conn) == 20
    ps = picks(conn)
    assert len(ps) == 20 and len({p["key"] for p in ps}) == 20
    assert max(Counter(wx.artist_key(p["artist"]) for p in ps).values()) <= wx.MAX_PER_ARTIST
    kinds = Counter(p["kind"] for p in ps)
    assert kinds["far"] == 20 // wx.FAR_SHARE and kinds["near"] == 20 - kinds["far"]
    langs = Counter(p["language"] for p in ps)
    assert langs["Tamil"] > langs["English"] >= 3                  # 12 : 6 plays, but English is never dropped
    assert all(p["reason"] for p in ps)
    assert any(p["reason"].startswith("Like Aarav Kumar") for p in ps)
    assert any(p["reason"].startswith("Two steps out") for p in ps if p["kind"] == "far")
    assert all(p["preview_url"].startswith("https://audio-ssl.itunes.apple.com/") for p in ps)
    assert all("600x600bb" in p["cover_url"] for p in ps)


def test_far_picks_are_spread_through_the_list_not_saved_for_the_end(conn):
    make(conn)
    kinds = [p["kind"] for p in picks(conn)]
    assert "far" in kinds[:4]                                      # the first far pick comes early
    assert kinds[-5:].count("far") <= 3                            # and they are not all at the end


def test_what_must_not_be_suggested_is_dropped(conn):
    seeds = {**SEEDS, "blocked_artists": ["Zed Harbor", "Mina Hart"]}
    make(conn, seeds=seeds)
    ps = picks(conn)
    titles = {p["title"] for p in ps}
    assert "Neela Megam" not in titles                                    # in the library (title + artist + length)
    assert not any("Remix" in t or "Karaoke" in t or "Loop" in t for t in titles)
    assert not any(wx.share_artist(p["artist"], "Zed Harbor") or wx.share_artist(p["artist"], "Mina Hart") for p in ps)


def test_the_same_week_twice_tops_up_and_never_duplicates(conn):
    assert make(conn, size=8) == 8
    assert make(conn, size=12) == 4
    assert len(picks(conn)) == 12 and len({p["key"] for p in picks(conn)}) == 12


def test_nothing_known_about_the_listener_makes_no_list(conn):
    assert make(conn, seeds={"artists": [], "blocked_artists": [], "extra": []}) == 0
    wx.begin_build(conn, "alice", MON)
    wx.finish_build(conn, "alice", 0, None, MON)
    cur = wx.current(conn, "alice", MON)
    assert cur["picks"] == [] and cur["needs_build"] is False and "Play a few more songs" in cur["build_note"]


def test_a_hint_from_another_service_is_looked_up_and_marked(conn):
    CATALOG["Hint Maker"] = [it("Wanted Song", "Hint Maker")]
    try:
        seeds = {**SEEDS, "extra": [{"artist": "Hint Maker", "title": "Wanted Song", "source": "ListenBrainz"}]}
        make(conn, seeds=seeds)
        assert "Suggested by ListenBrainz" in {p["reason"] for p in picks(conn)}
    finally:
        del CATALOG["Hint Maker"]


def test_the_weeks_run_monday_to_sunday_in_india():
    mon = time.mktime((2026, 11, 16, 12, 0, 0, 0, 0, -1)) - time.timezone      # noon UTC Monday
    assert wx.week_of(mon) == "2026-11-16"
    assert wx.week_of(mon + 6 * DAY) == "2026-11-16"
    assert wx.week_of(mon + 7 * DAY) == "2026-11-23"


# ── Keep, Not for me, expiry ─────────────────────────────────────────────────

def test_keep_joins_the_exportify_queue_and_is_fetched_by_tick_at_night(conn, cfg):
    make(conn)
    p = picks(conn)[0]
    r = wx.keep(conn, "alice", p["id"], NOON)
    assert r["state"] == "kept" and r["download"]["state"] == "waiting"             # a wishlist row, not fetched yet
    imp = wx._import_id(conn, "alice")
    plan = ex.get_plan(conn, imp)
    assert plan["status"] == "active" and plan["night_only"] and plan["disk_floor_gb"] == 40.0
    day = ex.tick(conn, cfg, now=NOON, free=200.0)                                  # the same tick as the Spotify wishlist
    assert day[0]["note"] == "outside the night window"
    night = ex.tick(conn, cfg, now=NIGHT, free=200.0)
    assert night[0]["queued"] == 1
    assert wx.current(conn, "alice", NIGHT)["picks"][0]["download"]["state"] == "queued"
    assert "Weekly Exploration" in [r["name"] for r in conn.execute("SELECT name FROM exportify_imports")]


def test_the_disk_floor_and_the_night_cap_are_exportifys(conn, cfg):
    make(conn)
    for p in picks(conn)[:6]:
        wx.keep(conn, "alice", p["id"], NOON)
    imp = wx._import_id(conn, "alice")
    ex.set_plan(conn, imp, {"per_night": 2})
    assert ex.tick(conn, cfg, now=NIGHT, free=200.0)[0]["queued"] == 2             # the per-night cap
    imp2 = imp
    ex.set_plan(conn, imp2, {}, status="active")
    low = ex.tick(conn, cfg, now=NIGHT + 60, free=41.0)                             # near the 40 GB floor
    assert low[0]["note"] in ("waiting for the running batch", "disk is low", "cap reached")
    conn.execute("UPDATE exportify_songs SET state='downloaded' WHERE state='queued'")
    ex.set_plan(conn, imp2, {"per_night": 100}, status="active")
    paused = ex.tick(conn, cfg, now=NIGHT + 120, free=40.01)
    assert paused[0]["note"] == "disk is low" and ex.get_plan(conn, imp2)["status"] == "paused_disk"


def test_the_weekly_cap_holds_extra_keeps_and_releases_them_later(conn):
    make(conn)
    wx.set_prefs(conn, "alice", cap=2, now=MON)
    ids = [p["id"] for p in picks(conn)[:4]]
    states = [wx.keep(conn, "alice", i, MON)["download"]["state"] for i in ids]
    assert states == ["waiting", "waiting", "waiting", "waiting"]                   # none fetched yet, but...
    assert wx.kept_this_week(conn, "alice", MON) == 2                               # ...only two are handed to the queue
    assert wx.release_waiting(conn, MON + DAY) == 0                                 # same week: still full
    assert wx.release_waiting(conn, MON + 8 * DAY) == 2                             # next week: the other two go
    wx.set_prefs(conn, "alice", cap=0, now=MON + 9 * DAY)
    assert wx.kept_this_week(conn, "alice", MON + 9 * DAY) == 2


def test_raising_the_cap_releases_waiting_keeps_at_once(conn):
    make(conn)
    wx.set_prefs(conn, "alice", cap=1, now=MON)
    a, b = [p["id"] for p in picks(conn)[:2]]
    wx.keep(conn, "alice", a, MON)
    wx.keep(conn, "alice", b, MON)
    assert wx.kept_this_week(conn, "alice", MON) == 1
    wx.set_prefs(conn, "alice", cap=5, now=MON)
    assert wx.kept_this_week(conn, "alice", MON) == 2


def test_a_song_already_on_a_wishlist_is_not_fetched_twice(conn):
    make(conn)
    p = picks(conn)[0]
    iid = wx._ensure_import(conn, "alice", MON)
    conn.execute("INSERT INTO exportify_songs (import_id, user, pos, key, title, artist, state, updated_at) "
                 "VALUES (?,?,0,?,?,?, 'downloaded', ?)", (iid, "alice", p["key"], p["title"], p["artist"], MON))
    assert wx.keep(conn, "alice", p["id"], MON)["download"]["state"] == "ready"
    assert conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE key=?", (p["key"],)).fetchone()[0] == 1


def test_not_for_me_is_gone_and_does_not_come_back(conn):
    make(conn)
    p = picks(conn)[0]
    wx.skip(conn, "alice", p["id"], MON)
    assert p["id"] not in [x["id"] for x in wx.current(conn, "alice", MON)["picks"]]
    make(conn, now=MON + 7 * DAY)                                                   # next week's list
    assert p["key"] not in {x["key"] for x in picks(conn)}


def test_undo_brings_the_pick_back(conn):
    make(conn)
    p = picks(conn)[0]
    wx.skip(conn, "alice", p["id"], MON)
    assert wx.restore(conn, "alice", p["id"], MON)["state"] == "pending"
    assert p["id"] in [x["id"] for x in wx.current(conn, "alice", MON)["picks"]]


def test_two_not_for_me_on_one_artist_rest_the_artist(conn):
    make(conn)
    first, second = [p for p in picks(conn) if wx.artist_key(p["artist"]) == wx.artist_key(picks(conn)[0]["artist"])][:2]
    wx.skip(conn, "alice", first["id"], MON)
    assert conn.execute("SELECT COUNT(*) FROM weekly_tombstones WHERE kind='artist'").fetchone()[0] == 0
    wx.skip(conn, "alice", second["id"], MON)
    assert conn.execute("SELECT COUNT(*) FROM weekly_tombstones WHERE kind='artist'").fetchone()[0] == 1
    make(conn, now=MON + 7 * DAY)
    assert not any(wx.artist_key(p["artist"]) == wx.artist_key(first["artist"]) for p in picks(conn)
                   if p["week"] != wx.week_of(MON))


def test_untouched_picks_expire_after_two_weeks_and_rest_for_six_months(conn):
    make(conn, size=6)
    kept = picks(conn)[0]
    wx.keep(conn, "alice", kept["id"], MON)
    old = {p["key"] for p in picks(conn)} - {kept["key"]}
    assert wx.expire(conn, "alice", MON + 13 * DAY) == 0
    assert wx.expire(conn, "alice", MON + 15 * DAY) == 5
    assert {p["state"] for p in [dict(r) for r in conn.execute("SELECT state FROM weekly_picks WHERE state='kept'")]} == {"kept"}
    cur = wx.current(conn, "alice", MON + 15 * DAY)
    assert [p["id"] for p in cur["picks"]] == [kept["id"]]                           # a kept pick is never expired
    make(conn, now=MON + 20 * DAY)
    assert not old & {p["key"] for p in picks(conn)}                                 # not for six months
    make(conn, now=MON + 15 * DAY + wx.TOMBSTONE_S + DAY)
    assert old & {p["key"] for p in picks(conn)}


def test_acting_on_someone_elses_pick_is_refused(conn):
    make(conn)
    p = picks(conn)[0]
    for fn in (wx.keep, wx.skip, wx.restore):
        with pytest.raises(wx.PickError):
            fn(conn, "bob", p["id"])


# ── the sources ──────────────────────────────────────────────────────────────

def test_the_sources_are_throttled_cached_and_budgeted():
    waits, urls = [], []

    def get(url):
        urls.append(url)
        return {"results": []}

    s = wx.Sources(get=get, sleep=waits.append, itunes_gap=3.2)
    s.songs("Aarav Kumar")
    s.songs("Diya Ram")
    s.songs("Aarav Kumar")                                    # cached
    assert len(urls) == 2 and len(waits) == 1 and 0 < waits[0] <= 3.2
    for i in range(200):
        s.songs(f"Artist {i}")
    assert s.calls == wx.MAX_CALLS


def test_a_source_that_is_down_gives_nothing_and_no_error():
    def get(url):
        raise OSError("down")

    s = wx.Sources(get=get, sleep=lambda x: None, itunes_gap=0)
    assert s.related("Aarav Kumar") == [] and s.songs("Aarav Kumar") == []


def test_only_apple_https_links_reach_the_app():
    assert wx._ok_url("https://audio-ssl.itunes.apple.com/x.m4a")
    assert wx._ok_url("https://is1-ssl.mzstatic.com/a.jpg")
    for bad in ("http://audio-ssl.itunes.apple.com/x.m4a", "https://evil.example/x.m4a", "file:///etc/passwd", "", None,
                "https://apple.com.evil.example/x"):
        assert wx._ok_url(bad) is None


def test_the_requests_carry_only_an_artists_name():
    seen = []
    s = wx.Sources(get=lambda u: seen.append(u) or {"results": []}, sleep=lambda x: None, itunes_gap=0)
    s.related("Aarav Kumar")
    s.songs("Aarav Kumar")
    assert all("alice" not in u and "user" not in u for u in seen)


# ── the routes ───────────────────────────────────────────────────────────────

@pytest.fixture
def client(cfg, conn, monkeypatch):
    monkeypatch.setattr(wxapi, "make_sources", sources)
    monkeypatch.setattr(wxapi, "load_library", lambda: [dict(s) for s in LIB])
    monkeypatch.setattr(ex, "free_bytes", lambda p: 200 * 10**9)
    c = replace(cfg, internal_token="t0ken", allowed_users=("alice", "bob"))
    return TestClient(create_app(c, conn, {"telegram": lambda: True, "worker": lambda: True}))


def hh(user="alice"):
    return {"X-Internal-Token": "t0ken", "X-User": user}


def wait_built(client, user="alice"):
    for _ in range(100):
        cur = client.get("/weekly/current", headers=hh(user)).json()
        if not cur["building"] and not cur["needs_build"]:
            return cur
        time.sleep(0.05)
    raise AssertionError("the build did not finish")


def test_routes_build_keep_skip_and_prefs(client):
    cur = client.get("/weekly/current", headers=hh()).json()
    assert cur["needs_build"] is True and cur["picks"] == [] and cur["cap"] == wx.DEFAULT_CAP
    r = client.post("/weekly/build", json=SEEDS, headers=hh())
    assert r.status_code == 202 and r.json() == {"started": True}
    cur = wait_built(client)
    assert len(cur["picks"]) == 20 and cur["needs_build"] is False and cur["picks"][0]["download"]["state"] == "none"
    a, b = cur["picks"][0]["id"], cur["picks"][1]["id"]
    k = client.post(f"/weekly/picks/{a}/keep", headers=hh())
    assert k.status_code == 200 and k.json()["state"] == "kept"
    assert client.post(f"/weekly/picks/{b}/skip", headers=hh()).json() == {"state": "skipped"}
    assert client.post(f"/weekly/picks/{b}/restore", headers=hh()).json() == {"state": "pending"}
    assert client.post(f"/weekly/picks/{a}/keep", headers=hh("bob")).status_code == 404
    assert client.post("/weekly/picks/99999/skip", headers=hh()).status_code == 404
    p = client.put("/weekly/prefs", json={"cap": 3, "enabled": True}, headers=hh()).json()
    assert p["cap"] == 3 and p["kept_this_week"] == 1
    assert client.put("/weekly/prefs", json={"cap": 999}, headers=hh()).status_code == 422
    off = client.put("/weekly/prefs", json={"enabled": False}, headers=hh()).json()
    assert off["enabled"] is False and off["needs_build"] is False
    assert client.post("/weekly/build", json=SEEDS, headers=hh()).json() == {"started": False, "reason": "off"}


def test_a_listener_only_sees_their_own_list(client):
    client.post("/weekly/build", json=SEEDS, headers=hh())
    wait_built(client)
    assert client.get("/weekly/current", headers=hh("bob")).json()["picks"] == []


def test_a_bad_seed_body_is_refused(client):
    assert client.post("/weekly/build", json={"artists": [{"name": ""}]}, headers=hh()).status_code == 422
    assert client.post("/weekly/build", json={"artists": [{"name": "x"}] * 13}, headers=hh()).status_code == 422


def test_a_failing_build_is_recorded_and_retried_later(client, monkeypatch, conn):
    def boom(*a, **k):
        raise RuntimeError("secret detail that must not be shown")

    monkeypatch.setattr(wx, "build", boom)
    client.post("/weekly/build", json=SEEDS, headers=hh())
    for _ in range(100):
        row = conn.execute("SELECT status, note FROM weekly_builds WHERE user='alice'").fetchone()
        if row and row["status"] != "running":
            break
        time.sleep(0.05)
    assert row["status"] == "failed" and "secret" not in row["note"]
    now = time.time()
    assert wx.current(conn, "alice", now)["needs_build"] is False                     # not at once
    assert wx.current(conn, "alice", now + wx.RETRY_FAILED_S + 5)["needs_build"] is True


def test_a_stale_build_is_taken_over(conn):
    wx.ensure_schema(conn)
    assert wx.begin_build(conn, "alice", MON) is True
    assert wx.begin_build(conn, "alice", MON + 60) is False
    assert wx.begin_build(conn, "alice", MON + wx.BUILD_STALE_S + 1) is True


def test_the_timers_pass_is_hooked_in():
    src = inspect.getsource(ex.main)
    assert "weekly-exploration-v1" in src and "release_waiting" in src
