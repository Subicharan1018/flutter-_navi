"""weekly-exploration-v1: the shuffle server's side (seeds from a fixed listening history, the ListenBrainz
hints, the routes). No network: requests is faked, as in test_fetch_proxy; Navidrome's database is not read.

    cd /opt/shuffle-server && venv/bin/python -m pytest navivibe/tests/test_weekly_exploration_v1.py -q
"""

import base64
from types import SimpleNamespace as NS

import pytest

from navivibe import hardening, weekly_exploration as we
from navivibe.fetch_signing import sign
from navivibe.tests.test_fetch_proxy import H, FakeResponse, client, fetcher  # noqa: F401  (fixtures)

NOW = 1_800_000_000.0
DAY = 86400

META = {
    "t1": {"artist": "Aarav Kumar • Meena Rao", "language": "Tamil"},
    "t2": {"artist": "Aarav Kumar", "language": "Tamil"},
    "t3": {"artist": "Diya Ram", "language": "Tamil"},
    "e1": {"artist": "Zed Harbor, Mina Hart", "language": "English"},
    "e2": {"artist": "Odd Lark", "language": "English"},
    "r1": {"artist": "Old Favourite", "language": "Hindi"},
}


def ev(song, days_ago, ratio=1.0, user="me"):
    return NS(user=user, song=song, ts=NOW - days_ago * DAY, ratio=ratio)


HISTORY = (
    [ev("t1", d) for d in (1, 2, 3, 4)] + [ev("t2", d) for d in (5, 6)]          # Aarav Kumar: 6 completed plays
    + [ev("t3", d) for d in (2, 9)]                                               # Diya Ram: 2
    + [ev("e1", d) for d in (1, 7, 14)]                                           # Zed Harbor: 3
    + [ev("e2", 3, 0.1), ev("e2", 4, 0.1), ev("e2", 5, 0.1)]                      # Odd Lark: skipped every time
    + [ev("e2", 6, 0.4), ev("e2", 7, 0.4)]                                        # ... and heard to 40 % twice
    + [ev("r1", 60), ev("r1", 61), ev("r1", 62)]                                  # months ago
    + [ev("t1", 1, user="someone else")] * 20                                     # another listener
)


def test_seeds_are_the_top_artists_of_the_last_four_weeks_by_completed_plays():
    s = we.seeds_from(HISTORY, META, "me", NOW)
    assert [(a["name"], a["language"], a["plays"]) for a in s["artists"]] == [
        ("Aarav Kumar", "Tamil", 6.0), ("Zed Harbor", "English", 3.0), ("Diya Ram", "Tamil", 2.0)]
    assert s["extra"] == [] and s["blocked_artists"] == []


def test_skipped_songs_do_not_count_and_a_half_heard_one_counts_a_little():
    s = we.seeds_from(HISTORY, META, "me", NOW)
    assert "Odd Lark" not in [a["name"] for a in s["artists"]]               # 0.4 + 0.4 = 0.4 weight: under the minimum
    s2 = we.seeds_from(HISTORY + [ev("e2", 8, 0.45)] * 8, META, "me", NOW)
    assert next(a for a in s2["artists"] if a["name"] == "Odd Lark")["plays"] == 0.2 * 10


def test_a_quiet_listener_gets_a_wider_window_before_nothing():
    quiet = [ev("r1", 60), ev("r1", 61), ev("t1", 90), ev("t1", 91)]
    s = we.seeds_from(quiet, META, "me", NOW)
    assert {a["name"] for a in s["artists"]} == {"Old Favourite", "Aarav Kumar"}
    assert we.seeds_from([], META, "me", NOW)["artists"] == []
    assert we.seeds_from(HISTORY, META, "nobody", NOW)["artists"] == []


def test_seeds_carry_names_only_nothing_that_identifies_a_song_or_a_time():
    s = we.seeds_from(HISTORY, META, "me", NOW, blocked_artists=["Mina Hart", ""])
    assert s["blocked_artists"] == ["Mina Hart"]
    flat = repr(s)
    assert "t1" not in flat and str(int(NOW)) not in flat and "someone else" not in flat


# ── ListenBrainz ─────────────────────────────────────────────────────────────

def lb_http(calls):
    def http(method, url, token, body=None):
        calls.append((method, url.split("?")[0], token))
        if url.endswith("validate-token"):
            return {"valid": True, "user_name": "lb_user"}
        if "/cf/recommendation/" in url:
            return {"payload": {"mbids": [{"recording_mbid": "m1", "score": 1}, {"recording_mbid": "m2", "score": 1}]}}
        return {"m1": {"recording": {"name": "Some Song"}, "artist": {"name": "Some Band"}}, "m2": {"recording": {}, "artist": {}}}
    return http


def test_listenbrainz_hints_come_from_the_listeners_own_account_and_are_cached():
    we._lb_cache.clear()
    calls = []
    out = we.lb_hints("me", NOW, key=lambda u: "tok-1", http=lb_http(calls))
    assert out == [{"artist": "Some Band", "title": "Some Song", "source": "ListenBrainz"}]
    assert {c[1].split("/1/")[1].split("/")[0] for c in calls} == {"validate-token", "cf", "metadata"}
    assert all(c[2] == "tok-1" for c in calls) and all("api.listenbrainz.org" in c[1] for c in calls)
    n = len(calls)
    assert we.lb_hints("me", NOW + 60, key=lambda u: "tok-1", http=lb_http(calls)) == out and len(calls) == n


def test_no_account_or_a_failing_service_means_no_hints_and_no_error():
    we._lb_cache.clear()
    assert we.lb_hints("me", NOW, key=lambda u: None, http=lb_http([])) == []
    we._lb_cache.clear()

    def boom(*a, **k):
        raise RuntimeError("tok-secret in here")

    assert we.lb_hints("me", NOW, key=lambda u: "tok-secret", http=boom) == []


# ── the routes ───────────────────────────────────────────────────────────────

@pytest.fixture
def engine(monkeypatch):
    """A recommender stand-in: its events and catalog are the fixed history above."""
    import navivibe.server as srv
    from navivibe import discover
    eng = NS(cat=NS(meta=META))
    monkeypatch.setattr(srv, "_v3_engine", lambda: eng)
    monkeypatch.setattr(discover, "_all_events",           # "me" in the history is the signed-in test user
                        lambda e, now: [ev(x.song, (NOW - x.ts) / DAY, x.ratio, "admin" if x.user == "me" else x.user)
                                        for x in HISTORY])
    monkeypatch.setattr(we, "_lb_cache", {"admin": (1e18, [])})
    monkeypatch.setattr(we.time, "time", lambda: NOW)
    return eng


def test_needs_a_sign_in_and_download_access(client, fetcher):
    assert client.get("/weekly/exploration").status_code == 401
    nobody = {"Authorization": "Basic " + base64.b64encode(b"stranger:pw").decode()}
    assert client.get("/weekly/exploration", headers=nobody).status_code == 403
    assert client.put("/weekly/exploration/prefs", json={"cap": 3}, headers=nobody).status_code == 403
    assert fetcher[0] == []


def test_the_first_open_of_the_week_sends_the_seeds_and_says_building(client, fetcher, engine):
    calls, replies = fetcher
    replies[("GET", "/weekly/current")] = FakeResponse(200, {"enabled": True, "needs_build": True, "picks": []})
    replies[("POST", "/weekly/build")] = FakeResponse(202, {"started": True})
    r = client.get("/weekly/exploration", headers=H)
    assert r.status_code == 200 and r.get_json()["building"] is True and r.get_json()["needs_build"] is False
    build = [c for c in calls if c["path"] == "/weekly/build"][0]
    assert [a["name"] for a in build["json"]["artists"]] == ["Aarav Kumar", "Zed Harbor", "Diya Ram"]
    h = build["headers"]
    assert h == {"X-Internal-Token": "tok", **sign("hmac-secret", "admin", True, "POST", "/weekly/build", ts=int(h["X-Ts"]))}


def test_an_open_with_a_list_does_not_send_seeds(client, fetcher, engine):
    calls, replies = fetcher
    replies[("GET", "/weekly/current")] = FakeResponse(200, {"enabled": True, "needs_build": False, "picks": [{"id": 1}]})
    r = client.get("/weekly/exploration", headers=H)
    assert r.get_json()["picks"] == [{"id": 1}] and [c["path"] for c in calls] == ["/weekly/current"]


def test_while_the_recommender_starts_the_page_waits_and_asks_again_later(client, fetcher, monkeypatch):
    import navivibe.server as srv
    monkeypatch.setattr(srv, "_v3_engine", lambda: None)
    calls, replies = fetcher
    replies[("GET", "/weekly/current")] = FakeResponse(200, {"needs_build": True, "picks": []})
    r = client.get("/weekly/exploration", headers=H)
    assert r.status_code == 200 and r.get_json()["building"] is True and [c["path"] for c in calls] == ["/weekly/current"]


def test_actions_forward_to_their_own_path_and_bad_ones_never_do(client, fetcher):
    calls, replies = fetcher
    for action in ("keep", "skip", "restore"):
        calls.clear()
        replies[("POST", f"/weekly/picks/7/{action}")] = FakeResponse(200, {"state": "x"})
        assert client.post(f"/weekly/exploration/7/{action}", headers=H).status_code == 200
        assert calls[0]["path"] == f"/weekly/picks/7/{action}"
    calls.clear()
    assert client.post("/weekly/exploration/7/explode", headers=H).status_code == 404
    assert client.post("/weekly/exploration/x/keep", headers=H).status_code == 404
    assert calls == []


def test_prefs_are_checked_here_before_they_go_on(client, fetcher):
    calls, replies = fetcher
    for body in ({"cap": 26}, {"cap": -1}, {"cap": "ten"}, {"cap": True}, {"enabled": 1}, {"enabled": "yes"}):
        assert client.put("/weekly/exploration/prefs", json=body, headers=H).status_code == 400
    assert calls == []
    replies[("PUT", "/weekly/prefs")] = FakeResponse(200, {"cap": 5})
    assert client.put("/weekly/exploration/prefs", json={"cap": 5, "enabled": False, "evil": 1}, headers=H).status_code == 200
    assert calls[0]["json"] == {"cap": 5, "enabled": False}


def test_tg_fetcher_errors_get_one_shape(client, fetcher):
    _, replies = fetcher
    replies[("POST", "/weekly/picks/3/keep")] = FakeResponse(409, {"detail": "this pick has expired"})
    r = client.post("/weekly/exploration/3/keep", headers=H)
    assert r.status_code == 409 and r.get_json() == {"error": "this pick has expired"}


def test_weekly_exploration_uses_the_fetch_rate_limits():
    assert hardening.route_class("/weekly/exploration", "GET") == "fetch"
    assert hardening.route_class("/weekly/exploration/3/keep", "POST") == "fetch_write"
    assert hardening.route_class("/mix/weekly", "GET") == "default"
