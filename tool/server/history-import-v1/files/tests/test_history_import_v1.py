"""history-import-v1: import ListenBrainz listens / Last.fm scrobbles. Recorded-style fixtures
(tests/fixtures_history/*.json, made-up songs and a made-up account), no network: the HTTP call is replaced.

    cd /opt/tg-fetcher && venv/bin/python -m pytest tests/test_history_import_v1.py -q
"""

import json
import logging
import sqlite3
import urllib.parse
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from tgfetch import db, history_import as hi, history_import_api

FIX = Path(__file__).parent / "fixtures_history"
if not FIX.exists():                                   # run from the package folder
    FIX = Path(__file__).parent / "fixtures"
B = 1700000000
NOW = B + 100000
KEY = "0123456789abcdef0123456789abcdef"                # a made-up Last.fm key
LIB = [
    {"id": "s1", "title": "Neela Megam", "artist": "Aarav Kumar • Meena Rao", "album": "Neela", "duration": 250.0,
     "isrc": "INA010000001"},
    {"id": "s2", "title": 'Kaadhal Mazhai (From "Mazhai Kaalam")', "artist": "Diya Ram", "album": "Mazhai Kaalam",
     "duration": 201.0, "isrc": ""},
    {"id": "s3", "title": "Veera Nadai", "artist": "Karthik Sen", "album": "Veera", "duration": 180.0, "isrc": ""},
]


def fx(name):
    return json.loads((FIX / name).read_text(encoding="utf-8"))


class FakeNet:
    """A recorded-style service: pages by cursor, plus whatever a test wants to force."""

    def __init__(self):
        self.calls: list[str] = []
        self.force: list = []                          # (status, headers, body) answers used first

    def __call__(self, url, headers=None):
        self.calls.append(url)
        if self.force:
            return self.force.pop(0)
        u = urllib.parse.urlparse(url)
        q = dict(urllib.parse.parse_qsl(u.query))
        if "listenbrainz" in u.netloc:
            if u.path.endswith("/listen-count"):
                return 200, {}, fx("lb_listen_count.json")
            mx = int(q.get("max_ts", 0))
            if not mx:
                return 200, {}, fx("lb_page1.json")
            if mx > B - 1000 and mx <= B + 1000:
                return 200, {}, fx("lb_page2.json")
            return 200, {}, fx("lb_empty.json")
        page = int(q.get("page", 1))
        return 200, {}, fx(f"lfm_page{page}.json")


@pytest.fixture(autouse=True)
def world(tmp_path, monkeypatch):
    monkeypatch.setenv("NAVIVIBE_LOG_DIR", str(tmp_path / "logs"))
    monkeypatch.setenv("NAVIVIBE_SPOTIFY_DETAILS_DB", str(tmp_path / "sd.db"))
    net = FakeNet()
    monkeypatch.setattr(hi, "HTTP", net)
    monkeypatch.setattr(hi.LIMITER, "sleep", lambda s: None)
    return net


@pytest.fixture
def conn():
    c = db.connect(":memory:")
    hi.ensure_schema(c)
    yield c
    c.close()


def plays(user="admin"):
    c = sqlite3.connect(hi.log_path(user))
    try:
        return c.execute("SELECT track_title, file_path, played_at, ist_hour, session_id, play_id, listen_ratio "
                         "FROM play_events ORDER BY played_at").fetchall()
    finally:
        c.close()


def run(conn, job, secret=None, user="admin", limit=20):
    out = None
    for _ in range(limit):
        out = hi.step(conn, job["id"], user, LIB, secret, now=NOW)
        if out["done"] or out.get("fatal") or out["wait_s"]:
            break
    return out


# ── ListenBrainz ─────────────────────────────────────────────────────────────

def test_listenbrainz_matches_writes_and_wishlists(conn, world):
    job, created = hi.create_job(conn, "admin", "listenbrainz", "sample_user")
    assert created
    out = run(conn, job)
    assert out["done"] and out["status"] == "done"
    assert (out["fetched"], out["imported"], out["wished"], out["skipped"]) == (6, 2, 3, 1)
    assert out["total"] == 6 and out["songs_matched"] == 2 and out["songs_unmatched"] == 2
    rows = plays()
    assert sorted(r[0] for r in rows) == ['Kaadhal Mazhai (From "Mazhai Kaalam")', "Neela Megam"]
    neela = [r for r in rows if r[0] == "Neela Megam"][0]
    assert neela[1] == "s1" and neela[2] == B + 3000 and neela[4] == "import:listenbrainz" and neela[6] == 1.0
    assert neela[3] == 4                                           # 1700003000 is 04:33 in Kolkata
    assert all(r[5].startswith("imp:listenbrainz:") for r in rows)
    # unmatched songs sit on the user's Wishlist (an Exportify import), the repeated one counts its plays
    wl = conn.execute("SELECT title, state, popularity FROM exportify_songs WHERE import_id=? ORDER BY popularity DESC",
                      (out["wishlist_id"],)).fetchall()
    assert [tuple(r) for r in wl] == [("Oru Pudhu Paadal", "wishlist", 2), ("Veera Nadai - Remix", "wishlist", 1)]
    name = conn.execute("SELECT name FROM exportify_imports WHERE id=?", (out["wishlist_id"],)).fetchone()[0]
    assert name == "ListenBrainz history"
    assert not any("api.listenbrainz.org" not in u for u in world.calls)


def test_paged_and_resumable(conn, world):
    job, _ = hi.create_job(conn, "admin", "listenbrainz", "sample_user")
    first = hi.step(conn, job["id"], "admin", LIB, None, now=NOW)
    assert not first["done"] and first["fetched"] == 3 and first["imported"] == 2
    again, created = hi.create_job(conn, "admin", "listenbrainz", "sample_user")        # "the app was closed"
    assert not created and again["id"] == job["id"] and again["cursor"] == B + 1000
    out = run(conn, again)
    assert out["done"] and out["fetched"] == 6 and out["imported"] == 2
    n = len(world.calls)
    assert hi.step(conn, job["id"], "admin", LIB, None, now=NOW)["done"] and len(world.calls) == n   # done: no call


def test_a_rerun_never_double_counts(conn):
    run(conn, hi.create_job(conn, "admin", "listenbrainz", "sample_user")[0])
    before = plays()
    job2, created = hi.create_job(conn, "admin", "listenbrainz", "sample_user", full=True)
    assert created
    out = run(conn, job2)
    assert out["done"] and out["imported"] == 0 and out["wished"] == 0 and out["already"] == 5
    assert plays() == before
    c = conn.execute("SELECT SUM(plays) FROM history_tracks WHERE user='admin'").fetchone()[0]
    assert c == 5
    pop = conn.execute("SELECT popularity FROM exportify_songs WHERE title='Oru Pudhu Paadal'").fetchone()[0]
    assert pop == 2


def test_incremental_run_asks_only_for_newer_listens(conn, world):
    run(conn, hi.create_job(conn, "admin", "listenbrainz", "sample_user")[0])
    job2, _ = hi.create_job(conn, "admin", "listenbrainz", "sample_user")
    assert job2["since_ts"] == B + 3000
    hi.step(conn, job2["id"], "admin", LIB, None, now=NOW)
    assert "min_ts=%d" % (B + 3000) in world.calls[-1]


def test_a_page_written_before_a_crash_is_not_counted_twice(conn, monkeypatch):
    job, _ = hi.create_job(conn, "admin", "listenbrainz", "sample_user")
    real = hi._save
    def boom(*a, **k):
        raise RuntimeError("power cut")
    monkeypatch.setattr(hi, "_save", boom)
    with pytest.raises(RuntimeError):
        hi.step(conn, job["id"], "admin", LIB, None, now=NOW)
    assert len(plays()) == 2 and conn.execute("SELECT COUNT(*) FROM history_seen").fetchone()[0] == 0
    monkeypatch.setattr(hi, "_save", real)
    out = run(conn, hi.get_job(conn, job["id"], "admin"))
    assert out["done"] and len(plays()) == 2 and out["imported"] == 2


def test_live_plays_and_other_service_imports_are_not_doubled(conn):
    log = hi.open_log("admin")
    log.execute("INSERT INTO play_events (track_title, played_at, listen_ratio, play_id) VALUES (?,?,1,'live-1')",
                ('Kaadhal Mazhai (From "Mazhai Kaalam")', B + 2030))   # the app logged this one 30 s off
    log.commit()
    log.close()
    out = run(conn, hi.create_job(conn, "admin", "listenbrainz", "sample_user")[0])
    assert out["near_dups"] == 1 and out["imported"] == 1
    # the same plays scrobbled to Last.fm too: Neela at the same second is the same play
    lf = run(conn, hi.create_job(conn, "admin", "lastfm", "sample_user")[0], KEY)
    assert lf["near_dups"] == 1                          # Neela (Veera is new, Oru unmatched)
    assert sorted(r[0] for r in plays()) == ['Kaadhal Mazhai (From "Mazhai Kaalam")', "Neela Megam", "Veera Nadai"]


def test_a_429_hands_back_a_wait_and_loses_nothing(conn, world):
    job, _ = hi.create_job(conn, "admin", "listenbrainz", "sample_user")
    world.force = [(200, {}, fx("lb_listen_count.json")), (429, {"x-ratelimit-reset-in": "7"}, None)]
    out = hi.step(conn, job["id"], "admin", LIB, None, now=NOW)
    assert out["wait_s"] == 7 and not out["done"] and out["fetched"] == 0
    assert hi.get_job(conn, job["id"], "admin")["cursor"] == 0
    assert run(conn, job)["done"]


def test_unknown_user_and_trouble_are_plain(conn, world):
    job, _ = hi.create_job(conn, "admin", "listenbrainz", "nobody_here")
    world.force = [(404, {}, None), (404, {}, None)]
    out = hi.step(conn, job["id"], "admin", LIB, None, now=NOW)
    assert out["fatal"] and "doesn’t know" in out["error"] and out["status"] == "error"
    job2, created = hi.create_job(conn, "admin", "listenbrainz", "nobody_here")           # it can be tried again
    assert not created
    world.force = [(500, {}, None), (503, {}, None)]
    out = hi.step(conn, job["id"], "admin", LIB, None, now=NOW)
    assert not out.get("fatal") and out["wait_s"] == 60


def test_the_rate_limiter_spaces_requests():
    t = [0.0]
    slept = []
    lim = hi.Limiter(clock=lambda: t[0], sleep=lambda s: (slept.append(round(s, 3)), t.__setitem__(0, t[0] + s)))
    lim.wait("lastfm")
    lim.wait("lastfm")
    t[0] += 10
    lim.wait("lastfm")
    lim.wait("listenbrainz")
    assert slept == [hi.MIN_GAP_S["lastfm"]]


# ── Last.fm ──────────────────────────────────────────────────────────────────

def test_lastfm_skips_now_playing_and_reads_a_single_track_page(conn, world):
    job, _ = hi.create_job(conn, "admin", "lastfm", "sample_user")
    out = run(conn, job, KEY)
    assert out["done"] and out["total"] == 4
    assert (out["fetched"], out["imported"], out["wished"]) == (3, 2, 1)       # "Playing Now" is not a play
    first = world.calls[0]
    assert "user.getRecentTracks" in first and "limit=200" in first and f"to={job['to_ts']}" in first
    assert "from=" not in first
    name = conn.execute("SELECT name FROM exportify_imports WHERE id=?", (out["wishlist_id"],)).fetchone()[0]
    assert name == "Last.fm history"


def test_lastfm_errors_say_what_to_fix(conn, world):
    job, _ = hi.create_job(conn, "admin", "lastfm", "sample_user")
    out = hi.step(conn, job["id"], "admin", LIB, None, now=NOW)                   # no key
    assert out["fatal"] and "API key" in out["error"] and world.calls == []
    world.force = [(200, {}, fx("lfm_error6.json"))]
    out = hi.step(conn, job["id"], "admin", LIB, KEY, now=NOW)
    assert out["fatal"] and "username" in out["error"]
    job2, _ = hi.create_job(conn, "admin", "lastfm", "sample_user")
    world.force = [(200, {}, fx("lfm_error29.json"))]
    out = hi.step(conn, job2["id"], "admin", LIB, KEY, now=NOW)
    assert not out.get("fatal") and out["wait_s"] == 15 and out["fetched"] == 0


def test_keys_are_never_stored_or_logged(conn, world, caplog):
    caplog.set_level(logging.DEBUG)
    job, _ = hi.create_job(conn, "admin", "lastfm", "sample_user")
    run(conn, job, KEY)
    world.force = [(200, {}, fx("lfm_error6.json"))]
    hi.step(conn, hi.create_job(conn, "admin", "lastfm", "other")[0]["id"], "admin", LIB, KEY, now=NOW)
    assert KEY not in caplog.text
    dump = "\n".join(conn.iterdump())
    assert KEY not in dump
    assert KEY not in Path(hi.log_path("admin")).read_bytes().decode("latin-1")
    with pytest.raises(hi.HistoryError):
        hi.lb_headers("../../etc")
    # an unreachable service never prints the URL (it holds the key)
    def refuse(url, headers=None):
        raise hi.HistoryError("Couldn’t reach the service. Try again in a moment.", retry_after=20)
    hi.HTTP = refuse
    j3, _ = hi.create_job(conn, "admin", "lastfm", "third")
    out = hi.step(conn, j3["id"], "admin", LIB, KEY, now=NOW)
    assert out["wait_s"] == 20 and KEY not in json.dumps(out)


def test_http_get_never_puts_the_url_in_its_error(monkeypatch):
    def fail(req, timeout=0):
        raise OSError(f"boom {req.full_url}")
    monkeypatch.setattr(hi.urllib.request, "urlopen", fail)
    with pytest.raises(hi.HistoryError) as e:
        hi.http_get("https://example.invalid/?api_key=" + KEY)
    assert KEY not in str(e.value) and e.value.__cause__ is None


# ── accounts, undo, the HTTP routes ──────────────────────────────────────────

def test_account_names_are_checked(conn):
    assert hi.clean_account("https://listenbrainz.org/user/sample_user/") == "sample_user"
    for bad in ("", "a/b", "x" * 80, None, 5):
        with pytest.raises(hi.HistoryError):
            hi.clean_account(bad)
    with pytest.raises(hi.HistoryError):
        hi.create_job(conn, "admin", "spotify", "x")
    with pytest.raises(hi.HistoryError):
        hi.log_path("../evil")


def test_undo_takes_back_the_plays_and_the_wishlist(conn):
    job = hi.create_job(conn, "admin", "listenbrainz", "sample_user")[0]
    run(conn, job)
    log = hi.open_log("admin")
    log.execute("INSERT INTO play_events (track_title, played_at, play_id) VALUES ('mine', 5, 'live-2')")
    log.commit()
    log.close()
    out = hi.undo(conn, hi.get_job(conn, job["id"], "admin"))
    assert out["removed_plays"] == 2
    assert [r[0] for r in plays()] == ["mine"]
    assert conn.execute("SELECT COUNT(*) FROM exportify_imports").fetchone()[0] == 0
    assert conn.execute("SELECT COUNT(*) FROM history_seen").fetchone()[0] == 0


def test_users_never_see_each_other(conn):
    job = hi.create_job(conn, "admin", "listenbrainz", "sample_user")[0]
    assert hi.get_job(conn, job["id"], "someone_else") is None
    with pytest.raises(hi.HistoryError):
        hi.step(conn, job["id"], "someone_else", LIB, None, now=NOW)


@pytest.fixture
def client(conn):
    app = FastAPI()
    state = {"who": "admin"}
    history_import_api.register_routes(app, None, conn, lambda: state["who"], library_loader=lambda: LIB)
    c = TestClient(app)
    c.state = state
    return c


def test_routes_end_to_end(client):
    r = client.post("/history-import/jobs", json={"source": "listenbrainz", "account": "sample_user"})
    assert r.status_code == 201
    jid = r.json()["id"]
    assert client.post("/history-import/jobs", json={"source": "listenbrainz", "account": "sample_user"}).status_code == 200
    s = client.post(f"/history-import/jobs/{jid}/step", json={})
    assert s.status_code == 200 and s.json()["fetched"] == 3 and not s.json()["done"]
    s = client.post(f"/history-import/jobs/{jid}/step", json={}).json()
    s = client.post(f"/history-import/jobs/{jid}/step", json={}).json()
    assert s["done"] and s["imported"] == 2
    assert client.get("/history-import/jobs").json()[0]["status"] == "done"
    assert client.get(f"/history-import/jobs/{jid}").json()["wished"] == 3
    assert client.post("/history-import/jobs", json={"source": "x", "account": "y"}).status_code == 422
    assert client.post(f"/history-import/jobs/{jid}/undo").json()["removed_plays"] == 2
    assert client.get(f"/history-import/jobs/{jid}").status_code == 404


def test_a_second_step_while_one_runs_is_refused(client, conn):
    jid = client.post("/history-import/jobs", json={"source": "listenbrainz", "account": "sample_user"}).json()["id"]
    hi._RUNNING.add(jid)
    try:
        assert client.post(f"/history-import/jobs/{jid}/step", json={}).status_code == 409
    finally:
        hi._RUNNING.discard(jid)


def test_other_peoples_jobs_are_404(client):
    jid = client.post("/history-import/jobs", json={"source": "listenbrainz", "account": "sample_user"}).json()["id"]
    client.state["who"] = "intruder"
    assert client.get(f"/history-import/jobs/{jid}").status_code == 404
    assert client.post(f"/history-import/jobs/{jid}/step", json={}).status_code == 404
    assert client.post(f"/history-import/jobs/{jid}/undo").status_code == 404
