"""lyrics-v3: found / not found / FAILED per source, nothing recorded as a miss on a failure, refresh=1,
per-song locking, a time budget, the looser matcher with its false-positive guard, and the prefetch.
No network: every request goes through a fake. Lyrics are made-up words.

    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m pytest navivibe/tests/test_lyrics_v3.py -q
"""

import json
import sys
import threading
import time
import types

import pytest
from flask import Flask, g

from navivibe import lyrics_prefetch as pf
from navivibe import lyrics_proxy as lp

LRC = "[00:01.00]one two\n[00:05.50]three four"


class Net:
    """Answers by fn(url, params) -> (status, body) or raises; records the calls."""

    def __init__(self, fn):
        self.fn, self.calls = fn, []

    def __call__(self, url, params=None, headers=None, timeout=5):
        self.calls.append((url, dict(params or {}), timeout))
        out = self.fn(url, dict(params or {}))
        status, body = out
        return status, body if isinstance(body, str) else json.dumps(body)


def hit(isrc="AAAAAAAAAAAA", title="Song", artist="Artist", duration=200.0, album="Album"):
    return {"isrc": isrc, "title": title, "artist": artist, "duration": duration, "album": album}


def lrcred(hits, sync="line", search_status=200, info_status=200, lrc_status=200, nxt=None):
    def fn(url, p):
        if url.endswith("/search.json"):
            if search_status != 200:
                return search_status, ""
            return 200, {"hits": hits if not p.get("after") else [], "next": nxt if not p.get("after") else None}
        if url.endswith(".json"):
            return info_status, {"sync": sync}
        if url.endswith(".lrc"):
            return lrc_status, LRC
        return 404, ""
    return Net(fn)


SONG = {"song_id": "s1", "title": "Song", "artist": "Artist", "album": "Album", "duration": 200, "spotify_id": ""}


# ── every source: found / not found / failed ───────────────────────────────────────────────────

@pytest.mark.parametrize("status", [429, 500, 502, 503, 403, 0])
def test_lrcred_a_search_that_does_not_answer_is_a_failure_not_a_no(status):
    with pytest.raises(lp.SourceFailed):
        lp.fetch_lrcred(SONG, lrcred([], search_status=status))


def test_lrcred_a_clean_empty_search_is_a_clean_no():
    assert lp.fetch_lrcred(SONG, lrcred([])) is None
    assert lp.fetch_lrcred(SONG, lrcred([], search_status=404)) is None


def test_lrcred_bad_json_from_the_search_is_a_failure():
    net = Net(lambda u, p: (200, "<html>oops</html>"))
    with pytest.raises(lp.SourceFailed):
        lp.fetch_lrcred(SONG, net)


def test_lrcred_a_hit_whose_files_fail_is_a_failure_and_a_missing_file_is_a_no():
    with pytest.raises(lp.SourceFailed):
        lp.fetch_lrcred(SONG, lrcred([hit()], lrc_status=500))
    assert lp.fetch_lrcred(SONG, lrcred([hit()], lrc_status=404)) is None
    with pytest.raises(lp.SourceFailed):
        lp.fetch_lrcred(SONG, lrcred([hit()], info_status=429))


def test_lrcred_a_failure_on_one_query_does_not_hide_a_hit_on_the_next():
    def fn(url, p):
        if url.endswith("/search.json"):
            return (500, "") if p["q"] == "Song Artist" else (200, {"hits": [hit()]})
        return (200, {"sync": "line"}) if url.endswith(".json") else (200, LRC)
    assert lp.fetch_lrcred(SONG, Net(fn))["sync"] == "line"


def test_lrcred_a_record_without_synced_lyrics_is_a_clean_no():
    assert lp.fetch_lrcred(SONG, lrcred([hit()], sync="none")) is None


def test_lrcred_word_file_trouble_falls_back_to_line_timing_but_is_marked_partial():
    def fn(url, p):
        if url.endswith("/search.json"):
            return 200, {"hits": [hit()]}
        if url.endswith(".json"):
            return 200, {"sync": "word"}
        if url.endswith(".ttml"):
            return 503, ""
        return 200, LRC
    got = lp.fetch_lrcred(SONG, Net(fn))
    assert got["sync"] == "line" and got["partial"] is True


def test_betterlyrics_401_is_the_normal_no_and_429_or_5xx_is_a_failure():
    assert lp.fetch_betterlyrics(SONG, Net(lambda u, p: (401, ""))) is None
    assert lp.fetch_betterlyrics(SONG, Net(lambda u, p: (404, ""))) is None
    for status in (429, 500, 503, 0):
        with pytest.raises(lp.SourceFailed):
            lp.fetch_betterlyrics(SONG, Net(lambda u, p, s=status: (s, "")))
    with pytest.raises(lp.SourceFailed):
        lp.fetch_betterlyrics(SONG, Net(lambda u, p: (200, "not json")))


def test_ytmusic_helper_trouble_is_a_failure_and_an_empty_answer_a_no(monkeypatch):
    def boom(q, **kw):
        raise lp.SourceFailed("helper exit 3")
    monkeypatch.setattr(lp, "run_ytmusic", boom)
    with pytest.raises(lp.SourceFailed):
        lp.fetch_ytmusic(SONG, None)
    monkeypatch.setattr(lp, "run_ytmusic", lambda q, **kw: {})
    assert lp.fetch_ytmusic(SONG, None) is None
    monkeypatch.setattr(lp, "run_ytmusic", lambda q, **kw: None)          # the helper is not installed here
    assert lp.fetch_ytmusic(SONG, None) is None


def test_run_ytmusic_failures_raise(monkeypatch, tmp_path):
    py, helper = tmp_path / "py", tmp_path / "helper.py"
    py.write_text("")
    helper.write_text("")
    monkeypatch.setattr(lp, "YTMUSIC_PYTHON", str(py))
    monkeypatch.setattr(lp, "YTMUSIC_HELPER", str(helper))
    import subprocess

    def timeout(*a, **k):
        raise subprocess.TimeoutExpired("x", 1)
    monkeypatch.setattr(subprocess, "run", timeout)
    with pytest.raises(lp.SourceFailed):
        lp.run_ytmusic({"title": "x"}, timeout=1)
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: types.SimpleNamespace(returncode=3, stdout="", stderr="x"))
    with pytest.raises(lp.SourceFailed):
        lp.run_ytmusic({"title": "x"})
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: types.SimpleNamespace(returncode=0, stdout="", stderr=""))
    with pytest.raises(lp.SourceFailed):
        lp.run_ytmusic({"title": "x"})


def test_resolve_ex_reports_answered_and_failed_sources():
    def fn(url, p):
        if "betterlyrics" in url:
            return 500, ""
        return 200, {"hits": []}
    r = lp.resolve_ex(SONG, ("lrcred", "betterlyrics"), Net(fn))
    assert r.found is None and r.answered == ["lrcred"] and r.failed == ["betterlyrics"]


def test_an_unexpected_error_in_a_source_is_a_failure_not_a_no(monkeypatch):
    def bug(song, get):
        raise KeyError("boom")
    monkeypatch.setitem(lp.FETCHERS, "lrcred", bug)
    r = lp.resolve_ex(SONG, ("lrcred",), Net(lambda u, p: (200, {})))
    assert r.failed == ["lrcred"] and r.found is None


# ── the cache: a failure is never a miss ───────────────────────────────────────────────────────

class Clock:
    def __init__(self):
        self.t = 1_000_000.0

    def __call__(self):
        return self.t


@pytest.fixture
def env(tmp_path):
    clock = Clock()
    return lp.SongCache(str(tmp_path), clock), clock


def test_a_failed_source_writes_no_miss_but_a_short_transient_entry(env):
    cache, clock = env
    net = lrcred([], search_status=500)
    out = lp.lookup_ex(SONG, ("lrcred",), cache, net, clock)
    assert out.state == "failed" and out.result is None
    entry = cache.get("s1")
    assert entry.get("transient") is True and "tried" in entry and not entry.get("lrc")
    n = len(net.calls)
    assert lp.lookup_ex(SONG, ("lrcred",), cache, net, clock).state == "failed"      # inside 5 min: not asked
    assert len(net.calls) == n
    clock.t += lp.TRANSIENT_TTL + 1
    lp.lookup_ex(SONG, ("lrcred",), cache, net, clock)                              # after 5 min: asked again
    assert len(net.calls) > n


def test_a_clean_no_from_every_source_is_a_miss_and_is_remembered(env):
    cache, clock = env
    net = lrcred([])
    out = lp.lookup_ex(SONG, ("lrcred",), cache, net, clock)
    assert out.state == "missing"
    entry = cache.get("s1")
    assert entry["v"] == lp.CACHE_VERSION and entry["tried"] == ["lrcred"] and "transient" not in entry
    n = len(net.calls)
    assert lp.lookup_ex(SONG, ("lrcred",), cache, net, clock).state == "missing"
    assert len(net.calls) == n


def test_one_source_saying_no_and_another_failing_is_a_failure_not_a_miss(env):
    cache, clock = env

    def fn(url, p):
        return (500, "") if "betterlyrics" in url else (200, {"hits": []})
    out = lp.lookup_ex(SONG, ("lrcred", "betterlyrics"), cache, Net(fn), clock)
    assert out.state == "failed"
    assert cache.get("s1").get("transient") is True


def test_the_old_miss_of_lyrics_v1_and_v2_is_asked_again(env):
    cache, clock = env
    cache.put("s1", {"tried": ["lrcred", "betterlyrics"]})                       # v1: no "v"
    net = lrcred([hit()])
    assert lp.lookup_ex(SONG, ("lrcred",), cache, net, clock).state == "found"
    cache.put("s2", {"v": 2, "tried": ["lrcred"]})                              # v2
    assert lp.lookup_ex({**SONG, "song_id": "s2"}, ("lrcred",), cache, net, clock).state == "found"


def test_a_miss_written_for_fewer_sources_is_asked_again_for_more(env):
    cache, clock = env
    cache.put("s1", {"v": lp.CACHE_VERSION, "tried": ["lrcred"]})
    net = Net(lambda u, p: (200, {"hits": []}))
    assert lp.lookup_ex(SONG, ("lrcred", "betterlyrics"), cache, net, clock).state == "missing"
    assert any("betterlyrics" in u for u, _, _ in net.calls)


def test_a_miss_expires_after_the_ttl(env):
    cache, clock = env
    net = lrcred([])
    lp.lookup_ex(SONG, ("lrcred",), cache, net, clock)
    clock.t += lp.NEGATIVE_TTL + 1
    n = len(net.calls)
    lp.lookup_ex(SONG, ("lrcred",), cache, net, clock)
    assert len(net.calls) > n


def test_a_synced_hit_is_kept_for_good(env):
    cache, clock = env
    net = lrcred([hit()])
    assert lp.lookup_ex(SONG, ("lrcred",), cache, net, clock).state == "found"
    clock.t += 365 * 86400
    n = len(net.calls)
    out = lp.lookup_ex(SONG, ("lrcred",), cache, lrcred([], search_status=500), clock)
    assert out.state == "found" and out.result["cached"] is True and len(net.calls) == n


# ── plain text and answers given while a source failed are looked at again ───────────────────────

def _plain_yt(monkeypatch):
    monkeypatch.setattr(lp, "run_ytmusic", lambda q, **kw: {"sync": "plain", "text": "one two\nthree four"})


def test_plain_text_is_rechecked_after_a_day_and_synced_lyrics_replace_it(env, monkeypatch):
    cache, clock = env
    _plain_yt(monkeypatch)
    srcs = ("lrcred", "ytmusic")
    none = Net(lambda u, p: (200, {"hits": []}))
    first = lp.lookup_ex(SONG, srcs, cache, none, clock)
    assert first.result["sync"] == "plain" and cache.get("s1")["recheck"] > clock()
    n = len(none.calls)
    assert lp.lookup_ex(SONG, srcs, cache, none, clock).state == "found" and len(none.calls) == n   # not yet due
    clock.t += lp.PLAIN_RECHECK + 5
    out = lp.lookup_ex(SONG, srcs, cache, lrcred([hit()]), clock)
    assert out.result["sync"] == "line" and out.result["source"] == "lrcred"
    assert "recheck" not in cache.get("s1")


def test_a_recheck_that_finds_nothing_better_keeps_the_plain_text(env, monkeypatch):
    cache, clock = env
    _plain_yt(monkeypatch)
    srcs = ("lrcred", "ytmusic")
    lp.lookup_ex(SONG, srcs, cache, Net(lambda u, p: (200, {"hits": []})), clock)
    clock.t += lp.PLAIN_RECHECK + 5
    monkeypatch.setattr(lp, "run_ytmusic", lambda q, **kw: {})                   # even if the plain source lost it
    out = lp.lookup_ex(SONG, srcs, cache, Net(lambda u, p: (200, {"hits": []})), clock)
    assert out.state == "found" and out.result["sync"] == "plain"
    assert cache.get("s1")["recheck"] > clock()


def test_a_synced_answer_given_while_another_source_failed_is_rechecked_in_ten_minutes(env):
    cache, clock = env

    def fn(url, p):
        if "betterlyrics" in url:
            return 500, ""
        return lrcred([hit()]).fn(url, p)
    lp.lookup_ex(SONG, ("betterlyrics", "lrcred"), cache, Net(fn), clock)
    assert cache.get("s1")["source"] == "lrcred"
    assert cache.get("s1")["recheck"] - clock() <= lp.PARTIAL_RECHECK + 1


# ── refresh ─────────────────────────────────────────────────────────────────────────────────────

def test_refresh_ignores_a_miss_and_a_failure_but_never_a_hit(env):
    cache, clock = env
    lp.lookup_ex(SONG, ("lrcred",), cache, lrcred([]), clock)                    # a miss
    net = lrcred([hit()])
    assert lp.lookup_ex(SONG, ("lrcred",), cache, net, clock).state == "missing"
    assert not net.calls
    assert lp.lookup_ex(SONG, ("lrcred",), cache, net, clock, refresh=True).state == "found"

    clock.t += 1
    boom = lrcred([], search_status=500)
    out = lp.lookup_ex(SONG, ("lrcred",), cache, boom, clock, refresh=True)      # a hit is not touched
    assert out.state == "found" and not boom.calls

    cache.put("t", {"v": lp.CACHE_VERSION, "transient": True, "tried": [], "failed": ["lrcred"]})
    assert lp.lookup_ex({**SONG, "song_id": "t"}, ("lrcred",), cache, lrcred([hit()]), clock,
                        refresh=True).state == "found"


# ── two requests for one song ask the sources once ─────────────────────────────────────────────

def test_concurrent_requests_for_one_song_hit_the_sources_once(env):
    cache, clock = env
    gate = threading.Event()
    calls = []

    def fn(url, p):
        calls.append(url)
        if url.endswith("/search.json"):
            gate.wait(2)
            return 200, {"hits": [hit()]}
        return (200, {"sync": "line"}) if url.endswith(".json") else (200, LRC)
    net = Net(fn)
    results = []

    def go():
        results.append(lp.lookup_ex(SONG, ("lrcred",), cache, net, clock).state)
    threads = [threading.Thread(target=go) for _ in range(4)]
    for t in threads:
        t.start()
    time.sleep(0.2)
    gate.set()
    for t in threads:
        t.join(5)
    assert results == ["found"] * 4
    assert len([u for u in calls if u.endswith("/search.json")]) == 1


def test_concurrent_refreshes_ask_once_too(env):
    cache, clock = env
    lp.lookup_ex(SONG, ("lrcred",), cache, lrcred([]), clock)
    clock.t += 5
    gate = threading.Event()
    n = []

    def fn(url, p):
        if url.endswith("/search.json"):
            n.append(p["q"])
            gate.wait(2)
            return 200, {"hits": []}
        return 404, ""
    net = Net(fn)
    out = []
    ts = [threading.Thread(target=lambda: out.append(lp.lookup_ex(SONG, ("lrcred",), cache, net, clock, refresh=True).state))
          for _ in range(3)]
    [t.start() for t in ts]
    time.sleep(0.2)
    gate.set()
    [t.join(5) for t in ts]
    assert out == ["missing"] * 3 and n.count("Song Artist") == 1       # one asker; the others took its answer


def test_different_songs_do_not_wait_for_each_other():
    locks = lp.KeyLocks()
    got = []
    with locks.hold("a"):
        t = threading.Thread(target=lambda: (locks.hold("b").__enter__(), got.append(1)))
        t.start()
        t.join(1)
    assert got == [1]


# ── the time budget ─────────────────────────────────────────────────────────────────────────────

def test_the_request_budget_cuts_each_timeout_and_stops_new_requests():
    now = {"t": 0.0}
    seen = []

    def real(url, params=None, headers=None, timeout=5):
        seen.append(timeout)
        now["t"] += 4.0
        return 200, json.dumps({"hits": []})
    d = lp.Deadline(real, 10, lambda: now["t"])
    d("https://x/1")
    d("https://x/2")
    assert seen == [5, 5]
    assert pytest.approx(d.remaining()) == 2.0
    d("https://x/3")
    assert seen[-1] == pytest.approx(2.0)
    with pytest.raises(lp.SourceFailed):
        d("https://x/4")


def test_sources_after_the_budget_count_as_failed_not_as_no(monkeypatch):
    now = {"t": 0.0}

    def slow(url, params=None, headers=None, timeout=5):
        now["t"] += 13
        return 200, json.dumps({"hits": []})
    monkeypatch.setattr(lp.time, "monotonic", lambda: now["t"])
    r = lp.resolve_ex(SONG, ("lrcred", "betterlyrics"), slow, budget=12)
    assert r.answered == [] and r.failed == ["lrcred", "betterlyrics"]      # lrcred's 2nd request began over budget


# ── the route ───────────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def client(tmp_path):
    def build(fn):
        net = Net(fn)
        app = Flask(__name__)
        clock = Clock()

        def auth(f):
            def wrapper(*a, **k):
                g.username = "tester"
                return f(*a, **k)
            wrapper.__name__ = f.__name__
            return wrapper
        lp.register_lyrics_proxy_routes(app, auth, get=net, cache=lp.SongCache(str(tmp_path), clock), now=clock)
        return app.test_client(), net, clock
    return build


Q = "/lyrics/fetch?title=Song&artist=Artist&album=Album&duration=200&song_id=s1&sources=lrcred"


def test_route_a_failure_is_404_with_retry_and_a_clean_no_is_404_without(client):
    c, net, _ = client(lambda u, p: (500, ""))
    r = c.get(Q)
    assert r.status_code == 404 and r.get_json()["retry"] is True
    c2, _, _ = client(lambda u, p: (200, {"hits": []}))
    r2 = c2.get(Q.replace("song_id=s1", "song_id=s2"))       # the first client left a 5-minute failure note for s1
    assert r2.status_code == 404 and "retry" not in r2.get_json()


def test_route_refresh_is_limited_per_hour_and_says_so(client):
    c, net, clock = client(lambda u, p: (200, {"hits": []}))
    codes = [c.get(Q + "&refresh=1").status_code for _ in range(lp.REFRESH_PER_HOUR)]
    assert 429 not in codes
    over = c.get(Q + "&refresh=1")
    assert over.status_code == 429 and str(lp.REFRESH_PER_HOUR) in over.get_json()["error"]
    assert c.get(Q).status_code == 404                       # an ordinary lookup is not limited by it
    clock.t += 3601
    assert c.get(Q + "&refresh=1").status_code == 404


def test_route_refresh_reaches_the_sources_past_a_cached_miss(client):
    calls = {"hit": False}

    def fn(u, p):
        if calls["hit"]:
            return lrcred([hit()]).fn(u, p)
        return 200, {"hits": []}
    c, net, _ = client(fn)
    assert c.get(Q).status_code == 404
    calls["hit"] = True
    assert c.get(Q).status_code == 404                       # still the remembered miss
    ok = c.get(Q + "&refresh=1")
    assert ok.status_code == 200 and ok.get_json()["sync"] == "line"


# ── the matcher: fixable misses are found ───────────────────────────────────────────────────────

def match(song, h):
    return lp.score_hit({**SONG, **song}, h) is not None


@pytest.mark.parametrize("lib,hit_title", [
    ('Kadhal Kan Kattudhe (From "Kaaki Sattai")', "Kadhal Kan Kattudhe"),
    ("Kadhal Kan Kattudhe", 'Kadhal Kan Kattudhe (From "Kaaki Sattai")'),
    ("Kadhal Kan Kattudhe - From \"Kaaki Sattai\"", "Kadhal Kan Kattudhe"),
    ("Song [Remastered 2011]", "Song"),
    ("Song - Remastered 2011", "Song"),
    ("SONG", "song"),
    ("Café Song", "Cafe Song"),
    ("Song (feat. Other)", "Song"),
    ("Song feat. Other", "Song"),
    ("Song, Part 2", "Song, Pt. 2"),
    ("Song Pt. 2", "Song Part 2"),
    ("Don't Stop", "Dont Stop"),
    ("Song: The Beginning", "Song"),
    ("Song - The Beginning", "Song"),
    ("Rock & Roll", "Rock and Roll"),
    ("Song (Original Motion Picture Soundtrack)", "Song"),
    ("Kaadhal Kan Kattudhe", "Kadhal Kan Kattudhe"),
    ("Thanjavoor Jilla", "Tanjavur Jilla"),
])
def test_title_variants_that_are_the_same_song(lib, hit_title):
    assert match({"title": lib}, hit(title=hit_title))


@pytest.mark.parametrize("lib_artist,hit_artist", [
    ("Anirudh Ravichander • Vivek", "Anirudh Ravichander, 維瓦克"),
    ("Vivek • Anirudh Ravichander", "Anirudh Ravichander, 維瓦克"),
    ("A. R. Rahman", "AR Rahman"),
    ("A.R. Rahman", "A R Rahman"),
    ("Anirudh Ravichander", "Anirudh Ravichandran"),
    ("Yuvan Shankar Raja", "Yuvaan Shankar Raja"),
    ("Sid Sriram; Chinmayi", "Chinmayi"),
    ("Artist A & Artist B", "Artist B"),
    ("Artist A x Artist B", "Artist B, Artist A"),
    ("Artist feat. Guest", "Artist"),
    ("Kumar", "Kumar Sanu"),
])
def test_artists_in_any_order_script_or_spelling(lib_artist, hit_artist):
    assert match({"artist": lib_artist}, hit(artist=hit_artist))


def test_an_artist_only_in_another_script_needs_title_and_a_close_duration():
    h = hit(artist="維瓦克")
    assert match({"artist": "Vivek"}, h)
    assert not match({"artist": "Vivek", "duration": 190}, h)             # 10 s off: not enough without a name
    assert not match({"artist": "Vivek", "duration": 0}, h)


def test_the_album_can_stand_in_for_the_artist_when_title_and_length_agree():
    h = hit(artist="Totally Different Credit", album="Film (Original Motion Picture Soundtrack)")
    assert match({"artist": "Someone Else", "album": "Film"}, h)
    assert not match({"artist": "Someone Else", "album": "Another Film"}, h)
    # the composer is credited here, the singer there; the album is spelled with a typo; the length agrees
    h2 = hit(title="O Podu 1", artist="Anuradha Sriram", album="Gemini (Original Motional Picture Soundtrack)",
             duration=240)
    song = {"title": "O Podu 1", "artist": "Bharadwaj • Vairamuthu", "album": "Gemini", "duration": 240}
    assert match(song, h2)
    assert not match({**song, "duration": 243}, h2)            # 3 s off with no artist in common: not enough
    assert not match({**song, "album": "Different"}, h2)


@pytest.mark.parametrize("gap,ok", [(0, True), (3.9, True), (4.5, True), (8, True), (12, True), (12.5, False),
                                    (20, False), (60, False)])
def test_duration_window_is_4_s_loose_and_12_s_with_everything_else_agreeing(gap, ok):
    assert match({}, hit(duration=200 + gap)) is ok


def test_a_looser_duration_needs_a_strong_title_and_artist():
    assert not match({"title": "Song: The Beginning"}, hit(title="Song", duration=206))      # subtitle + 6 s
    assert not match({"artist": "Artist Two", "album": "Other"}, hit(duration=206))      # half a name, 6 s
    assert match({"artist": "Artist Two"}, hit(duration=206))                            # ... but the same album
    assert not match({"title": "Songg"}, hit(title="Song", duration=206))


def test_an_unknown_duration_needs_an_exact_title_and_a_strong_artist():
    assert match({"duration": 0}, hit())
    assert not match({"duration": 0}, hit(artist="Someone Else"))
    assert not match({"duration": 0, "title": "Song: Sub"}, hit(title="Song"))


def test_an_isrc_from_the_catalog_is_trusted_only_while_it_names_the_same_recording():
    def run(info):
        net = Net(lambda u, p: (200, info) if u.endswith(".json") else (200, LRC) if u.endswith(".lrc")
                  else (200, {"hits": []}))
        return lp.fetch_lrcred({**SONG, "isrc": "QM6P42215720"}, net), net
    got, net = run({"sync": "line", "title": "Song", "duration": 201})
    assert got and not any(u.endswith("search.json") for u, _, _ in net.calls)
    got, net = run({"sync": "line", "title": "Another Song", "duration": 290})        # a different recording
    assert got is None and any(u.endswith("search.json") for u, _, _ in net.calls)
    got, net = run({"sync": "line", "title": "Song", "duration": 230})               # 30 s off
    assert got is None and any(u.endswith("search.json") for u, _, _ in net.calls)


def test_the_isrc_also_comes_from_the_exportify_package(monkeypatch, tmp_path):
    fake = types.ModuleType("navivibe.spotify_details")
    fake.isrc_of = lambda song_id, catalog_isrc="": "QM6P42215720" if song_id == "s1" else ""
    monkeypatch.setitem(sys.modules, "navivibe.spotify_details", fake)
    monkeypatch.setattr(lp, "CATALOG_DB", str(tmp_path / "none.db"))
    assert lp.enrich_song(SONG)["isrc"] == "QM6P42215720"
    assert lp.enrich_song({**SONG, "song_id": "zz"}).get("isrc") == ""
    broken = types.ModuleType("navivibe.spotify_details")
    monkeypatch.setitem(sys.modules, "navivibe.spotify_details", broken)             # no isrc_of: still no error
    assert lp.enrich_song(SONG).get("isrc") == ""


# ── the matcher: a wrong song is worse than none ────────────────────────────────────────────────

@pytest.mark.parametrize("lib,hit_title", [
    ("Song", "Song (Remix)"),
    ("Song (Remix)", "Song"),
    ("Song", "Song - Sped Up"),
    ("Song (Sped Up)", "Song"),
    ("Song", "Song (Slowed + Reverb)"),
    ("Song", "Song (Live)"),
    ("Song (Live at the Garden)", "Song"),
    ("Song", "Song - Live"),
    ("Song", "Song (Acoustic)"),
    ("Song (Unplugged)", "Song"),
    ("Song", "Song (Revival)"),
    ("Song (Revival)", "Song"),
    ("Song", "Song (Reprise)"),
    ("Song (Reprise)", "Song"),
    ("Song", "Song (Instrumental)"),
    ("Song", "Song (Karaoke Version)"),
    ("Song", "Song (Hindi Version)"),
    ("Song", "Song (Female Version)"),
    ("Song (Male)", "Song (Female)"),
    ("Song (Remix)", "Song (Acoustic)"),
    ("Song", "Song (Lofi)"),
    ("Song", "Song (Extended Mix)"),
    ("Song", "Song (Nightcore)"),
])
def test_a_different_version_never_stands_in_for_the_original(lib, hit_title):
    assert not match({"title": lib}, hit(title=hit_title))


@pytest.mark.parametrize("lib,hit_title", [
    ("Song (Remastered)", "Song"),
    ('Song (From "Live Aid")', "Song"),                         # a film named Live Aid is not a live version
    ("Song (Remix)", "Song (Remix)"),
    ("Song (Hindi Version)", "Song (Hindi Version)"),
])
def test_remastered_and_a_film_title_are_not_versions_and_equal_versions_match(lib, hit_title):
    assert match({"title": lib}, hit(title=hit_title))


@pytest.mark.parametrize("lib,hit_title", [
    ("Song Part 1", "Song Part 2"),
    ("Song 2", "Song"),
    ("Love", "Love Story"),
    ("Songs", "Song"),
    ("Another", "Song"),
    ("Kadhal", "Kaadhal Kan"),
])
def test_other_titles_do_not_match(lib, hit_title):
    assert not match({"title": lib}, hit(title=hit_title))


def test_same_title_by_a_different_artist_is_not_the_song():
    for other in ("Someone Else", "Other Person & Another One", "Arthur Tist", "Maker"):
        assert not match({}, hit(artist=other, album="Another Album"))
    assert not match({"artist": "Anirudh Ravichander"}, hit(artist="Yuvan Shankar Raja", album="Other"))
    assert not match({"artist": "Taylor Swift", "title": "Love Story", "album": "Fearless"},
                     hit(title="Love Story", artist="Indila", album="Mini World"))


def test_the_best_hit_wins_and_a_remix_listed_first_does_not_beat_the_original():
    hits = [hit("RRRRRRRRRRRR", "Song (Remix)", duration=200), hit("OOOOOOOOOOOO", "Song", duration=201.5),
            hit("SSSSSSSSSSSS", "Song", "Other", 200.0)]
    assert lp._pick_hit(hits, SONG)["isrc"] == "OOOOOOOOOOOO"


def test_the_tags_helpers():
    assert lp.variant_tags("Song (Sped Up)") == frozenset({"spedup"})
    assert lp.variant_tags('Song (From "Live Aid")') == frozenset()
    assert lp.variant_tags("Song") == frozenset()
    assert lp.title_keys('Song (From "Film") - Remastered 2011')[0] == "song"
    assert lp.title_keys("Song: The Beginning") == ("song the beginning", "song")
    assert lp.film_of('Song (From "Kaaki Sattai")') == "Kaaki Sattai"
    assert lp.film_of("Song - From Kaaki Sattai") == "Kaaki Sattai"
    assert lp.clean_title("Song - From Kaaki Sattai") == "Song"


# ── the search: more queries and more pages ────────────────────────────────────────────────────

def test_queries_cover_the_other_artists_the_film_and_the_subtitle():
    song = {**SONG, "title": 'Aaa: Bbb (From "Some Film")', "artist": "One • Two • Three", "album": "Another Album (OST)"}
    q = lp._search_queries(song)
    assert q[0] == "Aaa: Bbb One" and q[1] == "Aaa: Bbb"
    assert "Aaa: Bbb Two" in q and "Aaa: Bbb Some Film" in q and "Aaa" in q and "Aaa One" in q
    assert len(q) <= 9 and len(set(q)) == len(q)


def test_punctuation_is_tried_without_apostrophes_because_lrcred_search_is_picky():
    song = {**SONG, "title": "Somebody's Watching Me", "artist": "Rockwell"}
    q = lp._search_queries(song)
    assert q[:3] == ["Somebody's Watching Me Rockwell", "Somebody's Watching Me", "Somebodys Watching Me"]
    target = hit(title="Somebody's Watching Me", artist="Rockwell")

    def fn(url, p):
        if url.endswith("/search.json"):
            return 200, {"hits": [target] if p["q"] == "Somebodys Watching Me" else []}
        return (200, {"sync": "line"}) if url.endswith(".json") else (200, LRC)
    assert lp.fetch_lrcred(song, Net(fn))["sync"] == "line"


def test_a_song_found_only_by_the_film_name_is_found():
    song = {**SONG, "title": 'Zed (From "Some Film")', "artist": "Alpha Beta"}
    target = hit(title="Zed", artist="Alpha Beta")

    def fn(url, p):
        if url.endswith("/search.json"):
            return 200, {"hits": [target] if p["q"] == "Zed Some Film" else []}
        return (200, {"sync": "line"}) if url.endswith(".json") else (200, LRC)
    assert lp.fetch_lrcred(song, Net(fn))["sync"] == "line"


def test_more_result_pages_are_followed_up_to_three_and_the_request_cap_holds():
    pages = {}

    def fn(url, p):
        if url.endswith("/search.json"):
            after = p.get("after")
            n = int((after or "p0")[1:]) // 24
            pages.setdefault(p["q"], []).append(n)
            found = [hit()] if n == 2 and p["q"] == "Song Artist" else []
            return 200, {"hits": found or [hit("ZZZZZZZZZZZ" + str(n), "Other Title", "Nobody")], "next": f"p{(n + 1) * 24}"}
        return (200, {"sync": "line"}) if url.endswith(".json") else (200, LRC)
    assert lp.fetch_lrcred(SONG, Net(fn))["sync"] == "line"
    assert pages["Song Artist"] == [0, 1, 2]

    def never(url, p):
        return 200, {"hits": [hit("ZZZZZZZZZZZ1", "Other Title", "Nobody")], "next": "p24"}
    net = Net(never)
    assert lp.fetch_lrcred(SONG, net) is None
    assert len(net.calls) <= lp.SEARCH_REQUESTS


# ── the prefetch ───────────────────────────────────────────────────────────────────────────────

def test_prefetch_never_records_a_failure_as_a_miss_and_stops_when_the_sources_are_down(tmp_path):
    cache = lp.SongCache(str(tmp_path))
    songs = [{**SONG, "song_id": f"p{i}", "title": f"Song {i}"} for i in range(40)]
    net = Net(lambda u, p: (500, ""))
    s = pf.run(songs, ("lrcred",), cache, net, 3600, 14)
    assert s["stopped"] == "sources not answering" and s["failed"] == pf.FAILURES_IN_A_ROW and s["not_found"] == 0
    for i in range(pf.FAILURES_IN_A_ROW):
        e = cache.get(f"p{i}")
        assert e.get("transient") is True and not e.get("lrc") and "tried" in e
    assert cache.get(f"p{pf.FAILURES_IN_A_ROW}") is None


def test_prefetch_asks_again_about_songs_whose_only_entry_is_an_old_miss(tmp_path):
    cache = lp.SongCache(str(tmp_path))
    cache.put("old1", {"tried": ["lrcred", "betterlyrics"]})                   # lyrics-v1
    cache.put("old2", {"v": 2, "tried": ["lrcred"]})                          # lyrics-v2
    cache.put("fresh", {"v": lp.CACHE_VERSION, "tried": ["lrcred"]})          # this version: believed
    songs = [{**SONG, "song_id": k} for k in ("old1", "old2", "fresh")]
    net = lrcred([hit()])
    s = pf.run(songs, ("lrcred",), cache, net, 3600, 14)
    assert s["found"] == {"lrcred": 2} and s["skipped"] == 1


def test_prefetch_counts_found_missing_and_failed_separately(tmp_path):
    cache = lp.SongCache(str(tmp_path))

    def fn(url, p):
        q = p.get("q", "")
        if url.endswith("/search.json"):
            if "Song 1" in q:
                return 500, ""
            if "Song 2" in q:
                return 200, {"hits": []}
            return 200, {"hits": [hit(title="Song 0")]}
        return (200, {"sync": "line"}) if url.endswith(".json") else (200, LRC)
    songs = [{**SONG, "song_id": f"q{i}", "title": f"Song {i}"} for i in range(3)]
    s = pf.run(songs, ("lrcred",), cache, Net(fn), 3600, 14)
    assert (s["failed"], s["not_found"], sum(s["found"].values())) == (1, 1, 1)
    again = pf.run(songs, ("lrcred",), cache, Net(fn), 3600, 14)
    assert again["skipped"] == 3                          # the transient entry (5 min) and the miss are left alone


# ── the YouTube Music helper picks only the right recording ─────────────────────────────────────

def _helper():
    import importlib.util
    import os
    spec = importlib.util.spec_from_file_location(
        "ytmusic_lyrics_helper", os.path.join(os.path.dirname(lp.__file__), "ytmusic_lyrics_helper.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def test_the_helper_needs_the_artist_the_title_the_version_and_the_length_to_agree():
    h = _helper()
    res = lambda title, artist, d: {"videoId": "v", "title": title, "artists": [{"name": artist}], "duration_seconds": d}
    assert h.pick([res("Song", "Artist", 200)], "Song", 200, "Artist")
    assert h.pick([res("Song", "Artist", 203)], "Song (From \"Film\")", 200, "Artist")
    assert not h.pick([res("Song", "Someone Else", 200)], "Song", 200, "Artist")       # same title, other artist
    assert not h.pick([res("Song (Sped Up)", "Artist", 200)], "Song", 200, "Artist")   # another version
    assert not h.pick([res("Song", "Artist", 200)], "Song (Reprise)", 200, "Artist")
    assert not h.pick([res("Song", "Artist", 210)], "Song", 200, "Artist")             # another length
    assert h.pick([res("Song", "Artist & Guest", 200)], "Song", 200, "Guest")
    assert h.pick([{"videoId": "v", "title": "Song", "duration_seconds": 200}], "Song", 200, "Artist")  # no artists listed
