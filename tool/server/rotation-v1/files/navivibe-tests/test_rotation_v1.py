"""rotation-v1: Rest a song, seasonal songs, Back in rotation.

    cd /opt/shuffle-server && venv/bin/python -m pytest navivibe/tests/test_rotation_v1.py -q

Dates are fixed (never today's), because the seasons depend on the calendar.
"""

from datetime import datetime
from types import SimpleNamespace as NS

import pytest

from navivibe import discover, rotation as rot, taste_exclusions, weekly_mix
from navivibe.tests.test_listen_routes import H, client  # noqa: F401  (fixture)

DAY = 86400


def at(y, m, d, h=12):
    return datetime(y, m, d, h, tzinfo=rot.IST).timestamp()


JUNE = at(2026, 6, 15)
DEC = at(2026, 12, 20)
JAN_8 = at(2027, 1, 8)

META = {
    "a": {"title": "Alpha", "artist": "X", "album": "Al"},
    "b": {"title": "Beta", "artist": "Y", "album": ""},
    "c": {"title": "Christmas Eve", "artist": "Z", "album": ""},
    "d": {"title": "Diwali Dhamaka", "artist": "Z", "album": ""},
    "e": {"title": "Echo", "artist": "Z", "album": ""},
}


PLAIN = {k: META[k] for k in "abe"}                       # no seasonal titles

def ev(song, ts, ratio=1.0, user="me"):
    return NS(user=user, song=song, ts=ts, ratio=ratio)


@pytest.fixture(autouse=True)
def store(tmp_path, monkeypatch):
    monkeypatch.setattr(rot, "DIR", str(tmp_path / "rotation"))
    monkeypatch.setattr(taste_exclusions, "DIR", str(tmp_path / "taste"))


# ── seasons ──────────────────────────────────────────────────────────────────

def test_windows_include_the_run_up_and_wrap_over_new_year():
    d = lambda m, day: datetime(2026, m, day).date()           # noqa: E731
    assert rot.in_window("christmas", d(12, 1)) and rot.in_window("christmas", d(1, 2))
    assert not rot.in_window("christmas", d(11, 30)) and not rot.in_window("christmas", d(6, 1))
    assert rot.in_window("pongal", d(1, 14)) and not rot.in_window("pongal", d(2, 1))
    assert rot.in_window("ayyappa", d(12, 25)) and rot.in_window("ayyappa", d(1, 19)) and not rot.in_window("ayyappa", d(3, 1))
    assert rot.in_window("deepavali", d(10, 20)) and not rot.in_window("deepavali", d(12, 1))


def test_a_title_can_name_its_season():
    assert rot.season_from_title("Merry Christmas Mix") == "christmas"
    assert rot.season_from_title("Happy Deepavali") == "deepavali"
    assert rot.season_from_title("Pongal O Pongal") == "pongal"
    assert rot.season_from_title("Alpha") is None and rot.season_from_title(None) is None


def test_nearly_all_plays_in_one_season_make_a_song_seasonal():
    xmas = [at(2025, 12, d) for d in (5, 12, 20, 24, 25)] + [at(2026, 12, 3)]
    assert rot.season_from_plays(xmas) == "christmas"
    assert rot.season_from_plays(xmas[:4]) is None                         # too few plays to say
    year_round = [at(2026, m, 10) for m in range(1, 12)]
    assert rot.season_from_plays(year_round) is None


def test_out_of_season_songs_are_hidden_and_return_in_season():
    rot.set_season("me", "c", "christmas")
    assert rot.hidden_ids("me", META, JUNE) == {"c"}
    assert rot.hidden_ids("me", META, DEC) == set()
    assert rot.hidden_ids("me", META, at(2027, 1, 1)) == set()             # the window runs into January
    assert rot.hidden_ids("me", META, JAN_8) == {"c"}                      # and ends after the 2nd


def test_the_listeners_tag_beats_the_guess_and_none_means_never_seasonal():
    rot.refresh("me", [], META, JUNE)                                      # titles: c is Christmas, d is Deepavali
    assert rot.hidden_ids("me", META, JUNE) == {"c", "d"}
    rot.set_season("me", "c", rot.NO_SEASON)
    rot.set_season("me", "e", "pongal")
    assert rot.hidden_ids("me", META, JUNE) == {"d", "e"}
    rot.set_season("me", "c", None)                                        # forget the tag: the guess is back
    assert "c" in rot.hidden_ids("me", META, JUNE)
    assert rot.set_season("me", "a", "holi") is False


def test_a_plays_based_guess_needs_no_title():
    plays = [ev("a", at(2025, 12, d)) for d in (3, 9, 14, 19, 24, 25)]
    rot.refresh("me", plays, META, JUNE)
    assert rot.hidden_ids("me", META, JUNE) == {"a", "c", "d"}
    assert rot.hidden_ids("me", META, DEC) == {"d"}                        # Christmas is on; Deepavali is over


def test_seasons_can_be_switched_off():
    rot.set_season("me", "a", "christmas")
    rot.set_prefs("me", seasons=False)
    assert rot.hidden_ids("me", META, JUNE) == set()


# ── rest ─────────────────────────────────────────────────────────────────────

def test_a_snoozed_song_is_hidden_until_the_days_pass():
    rot.rest("me", "a", 14, "Alpha", now=JUNE)
    assert rot.hidden_ids("me", PLAIN, JUNE + 13 * DAY) == {"a"}
    assert rot.hidden_ids("me", PLAIN, JUNE + 14 * DAY + 1) == set()
    assert rot.hidden_ids("you", PLAIN, JUNE) == set()                      # per listener


def test_bringing_a_song_back_and_what_counts_as_days():
    rot.rest("me", "a", 30, now=JUNE)
    assert rot.unrest("me", "a", JUNE) is True and rot.unrest("me", "a", JUNE) is False
    assert rot.hidden_ids("me", PLAIN, JUNE) == set()
    assert [rot.clean_days(x) for x in (1, 365, 14.0, 0, 366, True, "7", None)] == [1, 365, 14, None, None, None, None, None]


def test_ids_the_catalog_does_not_have_are_never_returned():
    rot.rest("me", "gone", 30, now=JUNE)
    assert rot.hidden_ids("me", PLAIN, JUNE) == set()


def worn(song, now, n=12, last=(1.0, 0.1, 0.1)):
    plays = [ev(song, now - (13 - i % 12) * DAY + i * 60) for i in range(n - 3)]
    return plays + [ev(song, now - 3600 * (3 - i), r) for i, r in enumerate(last)]


def test_a_song_played_to_death_and_then_skipped_is_rested_quietly():
    out = rot.refresh("me", worn("a", JUNE), PLAIN, JUNE)
    assert "a" in rot.resting_ids(out, JUNE) and out["rest"]["a"]["auto"] is True
    assert rot.hidden_ids("me", PLAIN, JUNE + 13 * DAY) == {"a"}
    assert rot.hidden_ids("me", PLAIN, JUNE + 15 * DAY) == set()


def test_a_loved_song_that_is_not_being_skipped_is_left_alone():
    rot.refresh("me", worn("a", JUNE, last=(1.0, 1.0, 0.1)), PLAIN, JUNE)
    assert rot.hidden_ids("me", PLAIN, JUNE) == set()
    rot.refresh("me", worn("b", JUNE, n=6), PLAIN, JUNE, force=True)         # skipped but not many plays
    assert rot.hidden_ids("me", PLAIN, JUNE) == set()


def test_other_listeners_plays_do_not_rest_my_songs():
    rot.refresh("me", worn("a", JUNE), PLAIN, JUNE)
    assert rot.hidden_ids("you", PLAIN, JUNE) == set()
    rot.refresh("you", [ev("b", JUNE, user="me")] * 30, PLAIN, JUNE)
    assert rot.hidden_ids("you", PLAIN, JUNE) == set()


def test_auto_rest_can_be_switched_off_and_a_brought_back_song_is_safe_for_a_month():
    rot.set_prefs("me", auto_rest=False)
    rot.refresh("me", worn("a", JUNE), PLAIN, JUNE)
    assert rot.hidden_ids("me", PLAIN, JUNE) == set()
    rot.set_prefs("me", auto_rest=True)
    rot.refresh("me", worn("a", JUNE), PLAIN, JUNE, force=True)
    assert rot.hidden_ids("me", PLAIN, JUNE) == {"a"}
    rot.unrest("me", "a", JUNE)
    rot.refresh("me", worn("a", JUNE), PLAIN, JUNE + 3600, force=True)
    assert rot.hidden_ids("me", PLAIN, JUNE + 3600) == set()
    rot.refresh("me", worn("a", JUNE + 40 * DAY), PLAIN, JUNE + 40 * DAY, force=True)
    assert rot.hidden_ids("me", PLAIN, JUNE + 40 * DAY) == {"a"}


def test_the_plays_are_looked_at_only_every_few_hours():
    rot.refresh("me", [], PLAIN, JUNE)
    rot.refresh("me", worn("a", JUNE), PLAIN, JUNE + 3600)                   # too soon: not looked at
    assert rot.hidden_ids("me", PLAIN, JUNE + 3600) == set()
    rot.refresh("me", worn("a", JUNE), PLAIN, JUNE + rot.REFRESH_S + 1)
    assert "a" in rot.hidden_ids("me", PLAIN, JUNE + rot.REFRESH_S + 1)


def test_a_damaged_file_is_an_empty_rotation_not_an_error(tmp_path):
    (tmp_path / "rotation").mkdir()
    (tmp_path / "rotation" / "me.json").write_text("{not json")
    assert rot.hidden_ids("me", PLAIN, JUNE) == set()
    rot.rest("me", "a", 3, now=JUNE)
    assert rot.hidden_ids("me", PLAIN, JUNE) == {"a"}


# ── back in rotation ─────────────────────────────────────────────────────────

def loved(song, years_ago_days=200, n=5, last_days=None):
    base = JUNE - years_ago_days * DAY
    plays = [ev(song, base + i * DAY) for i in range(n)]
    if last_days is not None:
        plays.append(ev(song, JUNE - last_days * DAY))
    return plays


def test_back_in_rotation_wants_many_full_plays_long_ago_and_quiet_since():
    events = loved("a") + loved("b", n=3) + loved("e", last_days=10) + loved("c")
    got = rot.back_in_rotation("me", events, META, JUNE)
    ids = {g["navidrome_id"] for g in got}
    assert ids == {"a", "c"}                                               # b: too few plays; e: played ten days ago
    one = next(g for g in got if g["navidrome_id"] == "a")
    assert one["kind"] == "back" and one["full_plays"] == 5 and "5 times" in one["why"] and one["last_played"] == "2025-12-01"


def test_a_song_the_listener_kept_skipping_is_not_a_favourite():
    events = loved("a") + [ev("a", JUNE - 150 * DAY + i, 0.1) for i in range(4)]
    assert rot.back_in_rotation("me", events, META, JUNE) == []


def test_resting_blocked_and_out_of_season_songs_are_not_offered():
    rot.rest("me", "a", 30, now=JUNE)
    rot.set_season("me", "b", "pongal")
    events = loved("a") + loved("b") + loved("e") + loved("c")
    got = {g["navidrome_id"] for g in rot.back_in_rotation("me", events, META, JUNE, blocked={"e"})}
    assert got == {"c"}                                                    # a rests, b is Pongal, e is blocked
    later = rot.back_in_rotation("me", events, META, at(2027, 1, 10), blocked={"e"})
    assert {g["navidrome_id"] for g in later} == {"a", "b", "c"}           # the rest ran out and Pongal has begun


def test_back_in_rotation_can_be_switched_off():
    rot.set_prefs("me", back=False)
    assert rot.back_in_rotation("me", loved("a"), META, JUNE) == []


def test_the_pick_is_stable_within_a_day_and_never_longer_than_the_limit():
    meta = {f"s{i}": {"title": f"T{i}", "artist": "A"} for i in range(60)}
    events = [e for i in range(60) for e in loved(f"s{i}", n=4 + i % 5)]
    one = [g["navidrome_id"] for g in rot.back_in_rotation("me", events, meta, JUNE, 10)]
    assert len(one) == 10 and one == [g["navidrome_id"] for g in rot.back_in_rotation("me", events, meta, JUNE + 3600, 10)]
    other_day = [g["navidrome_id"] for g in rot.back_in_rotation("me", events, meta, JUNE + 2 * DAY, 10)]
    assert other_day != one


# ── the patch and the recommenders ───────────────────────────────────────────

def test_blocked_ids_now_includes_rested_and_out_of_season_songs(monkeypatch):
    monkeypatch.setattr(rot.time, "time", lambda: JUNE)
    taste_exclusions.add("me", "song", "e")
    rot.rest("me", "a", 10, now=JUNE)
    rot.set_season("me", "c", "christmas")
    assert taste_exclusions.blocked_ids("me", META) == {"a", "c", "e"}
    assert taste_exclusions._excluded_ids("me", META) == {"e"}
    monkeypatch.setattr(rot.time, "time", lambda: DEC)
    assert taste_exclusions.blocked_ids("me", META) == {"e"} | set()


def test_a_rotation_fault_never_stops_a_recommendation(monkeypatch):
    taste_exclusions.add("me", "song", "e")

    def boom(*a, **k):
        raise RuntimeError("disk gone")
    monkeypatch.setattr(rot, "hidden_ids", boom)
    assert taste_exclusions.blocked_ids("me", META) == {"e"}


def test_discover_leaves_rested_songs_out(client):
    me = client.engine.cat.meta
    first = {p["navidrome_id"] for p in client.get("/mix/weekly", headers=H).get_json()["items"]}
    victim = sorted(first)[0]
    import time
    rot.rest("me", victim, 7, now=time.time())
    left = {p["navidrome_id"] for p in client.get("/mix/weekly", headers=H).get_json()["items"]}
    assert victim in me and victim not in left                             # also out of the week's stored mix
    assert left <= first


def test_user_context_looks_at_the_plays(client, monkeypatch):
    seen = []
    monkeypatch.setattr(rot, "refresh", lambda user, events, meta, now=None, force=False: seen.append((user, len(meta))))
    discover.user_context(client.engine, "me")
    assert seen and seen[0][0] == "me"


# ── routes ───────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("method,path", [("get", "/rotation"), ("post", "/rotation/rest"), ("delete", "/rotation/rest"),
                                         ("put", "/rotation/season"), ("put", "/rotation/prefs"), ("get", "/rotation/back")])
def test_every_route_needs_a_login(client, method, path):
    assert getattr(client, method)(path).status_code == 401


def test_rest_and_bring_back_over_http(client):
    r = client.post("/rotation/rest", json={"song_id": "n1", "days": 30, "label": "Echo"}, headers=H)
    assert r.status_code == 200 and r.get_json()["days"] == 30
    snap = client.get("/rotation", headers=H).get_json()
    assert [(s["song_id"], s["auto"]) for s in snap["resting"]] == [("n1", False)]
    assert snap["resting"][0]["title"] == client.engine.cat.meta["n1"]["title"]
    assert {s["key"] for s in snap["seasons"]} == set(rot.SEASONS) and snap["prefs"] == {"auto_rest": True, "seasons": True, "back": True}
    gone = client.delete("/rotation/rest", json={"song_id": "n1"}, headers=H).get_json()
    assert gone["removed"] is True and client.get("/rotation", headers=H).get_json()["resting"] == []


@pytest.mark.parametrize("body", [{}, {"song_id": "n1"}, {"song_id": "n1", "days": 0}, {"song_id": "n1", "days": 400},
                                  {"song_id": "n1", "days": "7"}, {"song_id": "n1", "days": True}, {"song_id": " ", "days": 3}])
def test_a_bad_rest_is_refused(client, body):
    assert client.post("/rotation/rest", json=body, headers=H).status_code == 400
    assert client.get("/rotation", headers=H).get_json()["resting"] == []


def test_season_and_prefs_over_http(client):
    ok = client.put("/rotation/season", json={"song_id": "n2", "season": "pongal"}, headers=H)
    assert ok.status_code == 200
    snap = client.get("/rotation", headers=H).get_json()
    assert [(s["song_id"], s["season"], s["manual"]) for s in snap["seasonal"] if s["song_id"] == "n2"] == [("n2", "pongal", True)]
    assert client.put("/rotation/season", json={"song_id": "n2", "season": "holi"}, headers=H).status_code == 400
    assert client.put("/rotation/season", json={"song_id": "n2", "season": 5}, headers=H).status_code == 400
    assert client.put("/rotation/season", json={"season": "pongal"}, headers=H).status_code == 400
    assert client.put("/rotation/season", json={"song_id": "n2", "season": None}, headers=H).status_code == 200
    assert not [s for s in client.get("/rotation", headers=H).get_json()["seasonal"] if s["song_id"] == "n2"]
    assert client.put("/rotation/prefs", json={"seasons": False}, headers=H).get_json() == {"prefs": {"auto_rest": True, "seasons": False, "back": True}}
    assert client.put("/rotation/prefs", json={"seasons": "no"}, headers=H).status_code == 400
    assert client.put("/rotation/prefs", json={"colour": True}, headers=H).status_code == 400


def test_back_in_rotation_over_http(client, monkeypatch):
    import time
    now = time.time()
    events = [ev("n3", now - (200 - i) * DAY) for i in range(5)]
    discover._events.update(at=now, events=events)
    got = client.get("/rotation/back?limit=5", headers=H).get_json()
    assert got["count"] == 1 and got["items"][0]["navidrome_id"] == "n3" and got["items"][0]["why"]
    assert client.get("/rotation/back?limit=x", headers=H).status_code == 400
    taste_exclusions.add("me", "song", "n3")
    assert client.get("/rotation/back", headers=H).get_json()["items"] == []


def test_routes_say_so_while_the_recommender_starts(client):
    client.use_engine(False)
    assert client.get("/rotation", headers=H).status_code == 503
    assert client.get("/rotation/back", headers=H).status_code == 503
    assert client.post("/rotation/rest", json={"song_id": "n1", "days": 3}, headers=H).status_code == 200   # needs no engine
