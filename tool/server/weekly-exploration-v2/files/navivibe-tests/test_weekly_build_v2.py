"""weekly-exploration-v2: the build-for-everyone command. No network (the bridge to tg-fetcher is faked; tg-fetcher's own
building, throttling and call budget are covered by tests/test_weekly_exploration_v1.py there), no real clock or database.

    cd /opt/shuffle-server && venv/bin/python -m pytest navivibe/tests/test_weekly_build_v2.py -q
"""

import sqlite3
import time

import pytest

from navivibe import weekly_build as wb
from navivibe.fetch_signing import sign

MON = time.mktime((2026, 11, 23, 12, 0, 0, 0, 0, -1)) - time.timezone      # Monday noon UTC
WEEK = wb.week_of(MON)
SEEDS = {"artists": [{"name": "A", "language": "Tamil", "plays": 5}], "blocked_artists": [], "extra": []}
NONE = {"artists": [], "blocked_artists": [], "extra": []}


def row(week=WEEK, status="done", started=MON - 600, finished=MON - 500):
    return {"week": week, "status": status, "started_at": started, "finished_at": finished}


def d(user, *, access=True, prefs=None, builds=None, seeds=SEEDS, force=False):
    return wb.decide(user, MON, has_access=lambda u: access, prefs=prefs or {}, builds=builds or {},
                     seeds_for=lambda u: seeds, force=force)


# ── who gets a build, and why the others do not ──────────────────────────────

def test_a_listener_who_never_opened_the_page_is_built_for():
    assert d("new") == ("build", "this week's list is not made yet")           # no prefs row = on, no build row


def test_every_skip_has_its_reason():
    assert d("x", access=False) == ("skip", "no_download_access")
    assert d("x", prefs={"x": False}) == ("skip", "turned_off")
    assert d("x", builds={"x": row(status="done")}) == ("skip", "built_this_week")
    assert d("x", builds={"x": row(status="empty")}) == ("skip", "built_this_week")
    assert d("x", builds={"x": row(status="running", started=MON - 60)}) == ("skip", "building")
    assert d("x", builds={"x": row(status="failed", finished=MON - 60)}) == ("skip", "failed_recently")
    assert d("x", seeds=NONE) == ("skip", "no_listening_history")


def test_old_or_stale_rows_do_not_block():
    assert d("x", builds={"x": row(week="2026-11-16")})[0] == "build"                          # last week's list
    assert d("x", builds={"x": row(status="running", started=MON - wb.BUILD_STALE_S - 5)})[0] == "build"   # a dead build
    assert d("x", builds={"x": row(status="failed", finished=MON - wb.RETRY_FAILED_S - 5)})[0] == "build"
    assert d("x", prefs={"x": True})[0] == "build"


def test_force_tops_up_a_list_made_this_week():
    assert d("x", builds={"x": row()}, force=True) == ("build", "topping up")
    assert d("x", prefs={"x": False}, force=True)[0] == "skip"                                  # force never overrides off or access
    assert d("x", access=False, force=True)[0] == "skip"


def test_access_and_history_are_only_looked_up_when_needed():
    calls = []
    wb.decide("x", MON, has_access=lambda u: calls.append("access") or False, prefs={}, builds={},
              seeds_for=lambda u: calls.append("seeds"))
    assert calls == ["access"]                                                                  # no model load for a user without access


def test_the_week_is_the_same_monday_tg_fetcher_uses():
    assert wb.week_of(MON) == "2026-11-23"
    assert wb.week_of(MON + 6 * 86400 + 3600 * 6) == "2026-11-23"
    assert wb.week_of(MON + 7 * 86400) == "2026-11-30"
    sun_night_utc = MON - 12 * 3600 - 7 * 3600          # Sunday 05:00 UTC = 10:30 IST, still last week
    assert wb.week_of(sun_night_utc) == "2026-11-16"


# ── a fake tg-fetcher ────────────────────────────────────────────────────────

class FakeFetcher:
    """What tg-fetcher answers. `slow` polls a build stays 'building'; `boom` users raise on the build call."""

    def __init__(self, db, slow=1, boom=(), picks=20, off=()):
        self.db, self.slow, self.boom, self.picks, self.off = db, slow, set(boom), picks, set(off)
        self.calls, self.polls, self.sent = [], {}, {}

    def __call__(self, method, url, json=None, headers=None):
        path = url.split("5510")[1]
        user = headers["X-User"]
        self.calls.append((method, path, user, headers))
        if user in self.boom:
            raise OSError("connection refused")
        if method == "POST":
            if user in self.off:
                return R(202, {"started": False, "reason": "off"})
            self.sent[user] = json
            self.polls[user] = 0
            self.db.execute("INSERT OR REPLACE INTO weekly_builds VALUES (?,?,?,?,?,?,NULL)", (user, WEEK, "running", MON, None, 0))
            return R(202, {"started": True})
        self.polls[user] += 1
        if self.polls[user] <= self.slow:
            return R(200, {"building": True, "picks": []})
        self.db.execute("UPDATE weekly_builds SET status='done', finished_at=?, picks=? WHERE user=?", (MON + 60, self.picks, user))
        return R(200, {"building": False, "picks": [{"state": "pending"}] * self.picks})


class R:
    def __init__(self, code, body):
        self.status_code, self._b = code, body

    def json(self):
        return self._b


@pytest.fixture
def db(tmp_path):
    p = tmp_path / "fetch.db"
    c = sqlite3.connect(p, isolation_level=None)
    c.execute("CREATE TABLE weekly_prefs (user TEXT PRIMARY KEY, enabled INTEGER, cap INTEGER, updated_at REAL)")
    c.execute("CREATE TABLE weekly_builds (user TEXT PRIMARY KEY, week TEXT, status TEXT, started_at REAL, finished_at REAL, "
              "picks INTEGER, note TEXT)")
    yield DB(c, str(p))
    c.close()


class DB:
    """A writable fetch.db with its path (the code under test opens it read-only by path)."""

    def __init__(self, conn, path):
        self.conn, self.path = conn, path

    def execute(self, *a):
        return self.conn.execute(*a)


def bridge(fetcher):
    return wb.Bridge("http://127.0.0.1:5510", "tok", "secret", http=fetcher)


def go(db, fetcher, users, *, access=lambda u: True, seeds=lambda u: SEEDS, sleep=None, **kw):
    sleeps = [] if sleep is None else sleep
    out = []
    prefs, _ = wb.read_state(db.path)
    kw.setdefault("bridge", bridge(fetcher))
    res = wb.run(users, MON, has_access=access, prefs=prefs, builds_for=lambda: wb.read_state(db.path)[1],
                 seeds_for=seeds, sleep=sleeps.append, out=out.append, **kw)
    return res, out, sleeps


# ── running it ───────────────────────────────────────────────────────────────

def test_it_builds_one_listener_at_a_time_and_pauses_between(db):
    f = FakeFetcher(db, slow=2)
    res, out, sleeps = go(db, f, ["a", "b", "c"], pause=30)
    assert res["built"] == 3 and res["failed"] == 0
    order = [(m, u) for m, p, u, h in f.calls if p == "/weekly/build" or m == "GET"]
    posts = [u for m, u in order if m == "POST"]
    assert posts == ["a", "b", "c"]
    # a is finished (its GET answered "not building") before b is started
    kinds = [(m, u) for m, u in order]
    assert kinds.index(("POST", "b")) > max(i for i, k in enumerate(kinds) if k == ("GET", "a"))
    assert sleeps.count(30) == 2 and sleeps.count(wb.POLL_S) >= 6                      # between listeners, and while polling
    assert "build       a: done (20 picks)" in out


def test_each_call_is_signed_for_that_listener_and_carries_their_seeds(db):
    f = FakeFetcher(db, slow=0)
    go(db, f, ["a"])
    m, p, u, h = f.calls[0]
    assert (m, p, u) == ("POST", "/weekly/build", "a")
    assert h == {"X-Internal-Token": "tok", **sign("secret", "a", True, "POST", "/weekly/build", ts=int(h["X-Ts"]))}
    assert f.sent["a"] == SEEDS


def test_a_failing_listener_is_logged_and_the_rest_go_on(db):
    f = FakeFetcher(db, slow=0, boom=["b"])
    res, out, _ = go(db, f, ["a", "b", "c"])
    assert res["built"] == 2 and res["failed"] == 1
    assert any(o.startswith("FAILED      b: OSError") for o in out)
    assert "build       c: done (20 picks)" in out
    assert "connection refused" in "".join(o for o in out if o.startswith("FAILED"))        # the reason is logged, nothing secret in it


def test_a_failure_in_the_seeds_is_isolated_too(db):
    def seeds(u):
        if u == "b":
            raise RuntimeError("catalog unreadable")
        return SEEDS

    f = FakeFetcher(db, slow=0)
    res, out, _ = go(db, f, ["a", "b", "c"], seeds=seeds)
    assert res["built"] == 2 and res["failed"] == 1
    assert [u for m, p, u, h in f.calls if m == "POST"] == ["a", "c"]


def test_a_second_run_in_the_same_week_adds_nothing(db):
    f = FakeFetcher(db, slow=0)
    go(db, f, ["a", "b"])
    n = len(f.calls)
    res, out, _ = go(db, f, ["a", "b"])
    assert res["built"] == 0 and len(f.calls) == n
    assert out == ["skip        a: built_this_week", "skip        b: built_this_week"]


def test_next_week_builds_again(db):
    f = FakeFetcher(db, slow=0)
    go(db, f, ["a"])
    res, _, _ = wb.run(["a"], MON + 7 * 86400, has_access=lambda u: True, prefs={}, builds_for=lambda: wb.read_state(db.path)[1],
                       seeds_for=lambda u: SEEDS, bridge=bridge(f), sleep=lambda s: None, out=lambda s: None), 0, 0
    assert res["built"] == 1


def test_dry_run_lists_every_decision_and_sends_nothing(db):
    db.execute("INSERT INTO weekly_prefs VALUES ('off', 0, 10, 0)")
    db.execute("INSERT INTO weekly_builds VALUES ('done', ?, 'done', 1, 2, 20, NULL)", (WEEK,))
    f = FakeFetcher(db)
    res, out, sleeps = go(db, f, ["new", "keyed", "off", "done", "noacc", "quiet"], dry=True, bridge=None,
                          access=lambda u: u != "noacc", seeds=lambda u: NONE if u == "quiet" else SEEDS,
                          has_key=lambda u: u == "keyed")
    assert f.calls == [] and sleeps == []
    assert out == ["eligible    new: this week's list is not made yet; ListenBrainz hints: none (taste only)",
                   "eligible    keyed: this week's list is not made yet; ListenBrainz hints: own ListenBrainz key",
                   "skipped     off: turned_off", "skipped     done: built_this_week", "skipped     noacc: no_download_access",
                   "skipped     quiet: no_listening_history"]
    assert res["would_build"] == 2 and res["built"] == 0


def test_a_listener_who_turned_it_off_is_never_built(db):
    db.execute("INSERT INTO weekly_prefs VALUES ('a', 0, 10, 0)")
    f = FakeFetcher(db)
    res, out, _ = go(db, f, ["a"])
    assert f.calls == [] and out == ["skip        a: turned_off"]


def test_if_tg_fetcher_says_off_or_running_nothing_is_counted(db):
    f = FakeFetcher(db, off=["a"])
    res, out, _ = go(db, f, ["a"])
    assert res["built"] == 0 and res["failed"] == 0 and "build       a: off (0 picks)" in out


def test_limit_caps_the_listeners_in_one_run(db):
    f = FakeFetcher(db, slow=0)
    res, out, _ = go(db, f, ["a", "b", "c"], limit=2)
    assert res["built"] == 2 and "skip        c: limit_reached" in out


def test_a_build_that_never_ends_stops_the_run_so_two_never_overlap(db):
    f = FakeFetcher(db, slow=10**6)
    clock = iter(range(0, 10**7, 120))                                       # two minutes per look
    res, out, _ = wb.run(["a", "b"], MON, has_access=lambda u: True, prefs={}, builds_for=lambda: {}, seeds_for=lambda u: SEEDS,
                         bridge=bridge(f), sleep=lambda s: None, out=lambda s: None, clock=lambda: next(clock)), 0, 0
    assert res["stopped"] is True and res["failed"] == 1
    assert [u for m, p, u, h in f.calls if m == "POST"] == ["a"]             # b was never started


def test_tg_fetcher_errors_are_failures_with_the_status_not_a_crash(db):
    class Bad:
        def __call__(self, *a, **k):
            return R(503, {"error": "offline"})

    res, out, _ = go(db, Bad(), ["a", "b"])
    assert res["failed"] == 2 and "tg-fetcher answered 503" in out[0]


# ── reading the databases ────────────────────────────────────────────────────

def test_state_is_read_without_writing(db):
    db.execute("INSERT INTO weekly_prefs VALUES ('x', 0, 5, 1)")
    db.execute("INSERT INTO weekly_builds VALUES ('y', ?, 'done', 1, 2, 20, NULL)", (WEEK,))
    prefs, builds = wb.read_state(db.path)
    assert prefs == {"x": False} and builds["y"]["status"] == "done"
    with pytest.raises(sqlite3.OperationalError):
        sqlite3.connect(f"file:{db.path}?mode=ro", uri=True).execute("INSERT INTO weekly_prefs VALUES ('z',1,1,1)")


def test_no_database_or_tables_means_nobody_opened_the_page_yet(tmp_path):
    assert wb.read_state(str(tmp_path / "nope.db")) == ({}, {})
    sqlite3.connect(tmp_path / "empty.db").close()
    assert wb.read_state(str(tmp_path / "empty.db")) == ({}, {})


def test_env_loading_takes_only_the_names_it_needs(tmp_path, monkeypatch):
    env = tmp_path / ".env"
    env.write_text("TG_FETCHER_TOKEN=abc\n# c\nUNRELATED_SECRET=zzz\nTG_FETCHER_URL='http://x:1'\n")
    for k in ("TG_FETCHER_TOKEN", "UNRELATED_SECRET", "TG_FETCHER_URL"):
        monkeypatch.delenv(k, raising=False)
    wb.load_env(str(env))
    import os
    assert os.environ["TG_FETCHER_TOKEN"] == "abc" and os.environ["TG_FETCHER_URL"] == "http://x:1"
    assert "UNRELATED_SECRET" not in os.environ
    monkeypatch.delenv("TG_FETCHER_TOKEN")
    monkeypatch.delenv("TG_FETCHER_URL")


def test_main_dry_run_end_to_end_with_faked_stores(db, monkeypatch, capsys):
    from navivibe import fetch_access
    db.execute("INSERT INTO weekly_builds VALUES ('b', ?, 'done', 1, 2, 20, NULL)", (WEEK,))
    monkeypatch.setattr(wb, "FETCH_DB", db.path)
    monkeypatch.setattr(wb, "navidrome_users", lambda: ["a", "b", "c"])
    monkeypatch.setattr(wb, "load_env", lambda *a: None)
    monkeypatch.setattr(wb, "_seeds_loader", lambda now: (lambda u: NONE if u == "c" else SEEDS))
    monkeypatch.setattr(wb, "_lock", lambda: True)
    monkeypatch.setattr(fetch_access, "has_access", lambda u: True)
    monkeypatch.setattr(wb.time, "time", lambda: MON)
    monkeypatch.setattr(wb, "own_lb_key", lambda u: "secret-key" if u == "a" else None)
    monkeypatch.setattr(fetch_access, "admins", lambda: {"a"})
    assert wb.main(["--dry-run"]) == 0                                   # the default scope is everyone allowed
    text = capsys.readouterr().out
    assert "scope all-eligible, 3 user(s)" in text
    assert "eligible    a: this week's list is not made yet; ListenBrainz hints: own ListenBrainz key" in text
    assert "skipped     b: built_this_week" in text and "skipped     c: no_listening_history" in text
    assert "eligible 1; skipped built_this_week 1, no_listening_history 1" in text
    assert "secret-key" not in text
    assert wb.main(["--dry-run", "--users", "admin"]) == 0               # the first start: the admin account only
    text = capsys.readouterr().out
    assert "scope admin, 1 user(s)" in text and "eligible    a:" in text and " b:" not in text and " c:" not in text
    assert wb.main(["--dry-run", "--user", "ghost"]) == 2
    monkeypatch.setattr(fetch_access, "admins", lambda: {"nobody"})
    assert wb.main(["--dry-run", "--users", "admin"]) == 2               # no admin among the users: it says so, builds nothing


def test_scope_admin_means_only_the_admin_accounts():
    everyone = ["admin", "Admin2", "anish", "sandeep"]
    assert wb.users_in_scope("admin", everyone, {"admin", "admin2"}) == ["admin", "Admin2"]
    assert wb.users_in_scope("all-eligible", everyone, {"admin"}) == everyone


# ── ListenBrainz is strictly per listener ────────────────────────────────────

@pytest.fixture
def navidrome(tmp_path, monkeypatch):
    p = tmp_path / "navidrome.db"
    c = sqlite3.connect(p)
    c.execute("CREATE TABLE user (id TEXT PRIMARY KEY, user_name TEXT)")
    c.execute("CREATE TABLE user_props (user_id TEXT, key TEXT, value TEXT)")
    c.executemany("INSERT INTO user VALUES (?,?)", [("1", "admin"), ("2", "anish"), ("3", "Admin")])
    c.execute("INSERT INTO user_props VALUES ('1', 'ListenBrainzSessionKey', 'ADMIN-KEY')")
    c.commit()
    c.close()
    monkeypatch.setattr(wb, "NAVIDROME_DB_URI", f"file:{p}?mode=ro")


def test_a_key_belongs_to_exactly_one_account(navidrome):
    assert wb.own_lb_key("admin") == "ADMIN-KEY"
    assert wb.own_lb_key("anish") is None                  # no key of their own: taste only
    assert wb.own_lb_key("Admin") is None                  # not the admin's key under another spelling of the name
    assert wb.own_lb_key("stranger") is None


def test_the_admins_listenbrainz_data_is_never_fetched_for_anyone_else(navidrome):
    from navivibe import weekly_exploration as we
    we._lb_cache.clear()
    calls = []

    def http(method, url, token, body=None):
        calls.append((token, url))
        if url.endswith("validate-token"):
            return {"valid": True, "user_name": "admins_lb_name"}
        if "/cf/recommendation/" in url:
            return {"payload": {"mbids": [{"recording_mbid": "m1"}]}}
        return {"m1": {"recording": {"name": "Song"}, "artist": {"name": "Band"}}}

    hints = {u: we.lb_hints(u, MON, key=wb.own_lb_key, http=http) for u in ("anish", "Admin", "admin", "anish")}
    assert hints["anish"] == [] and hints["Admin"] == []
    assert hints["admin"] == [{"artist": "Band", "title": "Song", "source": "ListenBrainz"}]
    assert {t for t, _ in calls} == {"ADMIN-KEY"}                          # the only key ever sent is the admin's...
    assert all("admins_lb_name" in u or u.endswith(("validate-token", "recording/")) for _, u in calls)
    assert len(calls) == 3                                                  # ...for the admin's own list only: nothing for the others
    assert "anish" not in repr(calls)
