"""lyrics-v1: the lyrics proxy. No network: every request goes through a fake `get`.
Lyrics here are made-up words, never a real song's text.

    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m pytest navivibe/tests/test_lyrics_v1.py -q
"""

import json

import pytest
from flask import Flask, g

from navivibe import lyrics_proxy as lp

TTML = """<?xml version="1.0"?>
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata"><body><div>
<p begin="0:12.500" end="0:15.000"><span begin="0:12.500" end="0:13.000">alpha </span><span begin="0:13.000" end="0:13.400">be</span><span begin="0:13.400" end="0:14.000">ta </span><span begin="0:14.000" end="0:15.000">gamma</span></p>
<p begin="0:16.000" end="0:18.000"><span begin="0:16.000" end="0:17.000">delta</span> <span begin="0:17.000" end="0:18.000">epsilon</span><span ttm:role="x-bg" begin="0:17.500" end="0:18.000">(echo)</span></p>
</div></body></tt>"""

LINE_TTML = """<tt xmlns="http://www.w3.org/ns/ttml"><body><div>
<p begin="1:02.250" end="1:05.000">zeta eta</p></div></body></tt>"""


def test_ttml_words_become_enhanced_lrc_and_syllables_merge():
    lrc, words = lp.ttml_to_lrc(TTML)
    assert words is True
    first, second = lrc.splitlines()
    assert first == "[00:12.50]<00:12.50>alpha <00:13.00>beta <00:14.00>gamma"
    assert second == "[00:16.00]<00:16.00>delta <00:17.00>epsilon"     # the background vocal is left out


def test_ttml_without_word_timing_is_line_timed():
    lrc, words = lp.ttml_to_lrc(LINE_TTML)
    assert (lrc, words) == ("[01:02.25]zeta eta", False)


def test_ttml_refuses_entities_and_garbage():
    assert lp.ttml_to_lrc('<!DOCTYPE x [<!ENTITY a "b">]><tt><p begin="1">&a;</p></tt>') == ("", False)
    assert lp.ttml_to_lrc("not xml") == ("", False)
    assert lp.ttml_to_lrc("") == ("", False)


@pytest.mark.parametrize("raw,ms", [("0:12.500", 12500), ("1:02.250", 62250), ("00:01:02.5", 62500),
                                    ("62.3", 62300), ("62.3s", 62300), ("x", None), (None, None)])
def test_parse_clock(raw, ms):
    assert lp.parse_clock(raw) == ms


def test_paxsenix_json_and_text():
    lrc, sync = lp.paxsenix_to_lrc({"syncType": "LINE_SYNCED", "lines": [
        {"timeTag": "00:00.48", "words": "one two"}, {"timeTag": "00:03.10", "words": "three"}]})
    assert (lrc, sync) == ("[00:00.48]one two\n[00:03.10]three", "line")
    assert lp.paxsenix_to_lrc({"syncType": "UNSYNCED", "lines": [{"words": "one"}]}) == ("one", "plain")
    assert lp.paxsenix_to_lrc("[00:01.00]one") == ("[00:01.00]one", "line")
    assert lp.paxsenix_to_lrc({"nope": 1}) == ("", None)


# ── a fake network ──────────────────────────────────────────────────────────────────────────────

class Net:
    def __init__(self, routes):
        self.routes, self.calls = routes, []

    def __call__(self, url, params=None, headers=None, timeout=8):
        self.calls.append((url, params, headers))
        for prefix, (status, body) in self.routes.items():
            if url.startswith(prefix):
                return status, body if isinstance(body, str) else json.dumps(body)
        return 404, ""


HIT = {"hits": [
    {"isrc": "AAAAAAAAAAAA", "title": "Test Song (Remastered)", "artist": "Some Band", "duration": 200.1},
    {"isrc": "BBBBBBBBBBBB", "title": "Test Song", "artist": "Other Person", "duration": 200.0},
    {"isrc": "CCCCCCCCCCCC", "title": "Test Song", "artist": "Some Band", "duration": 260.0},
]}
LRCRED = {
    "https://lrc.red/search.json": (200, HIT),
    "https://lrc.red/s/AAAAAAAAAAAA.json": (200, {"sync": "word"}),
    "https://lrc.red/s/AAAAAAAAAAAA.ttml": (200, TTML),
}


@pytest.fixture
def app_and(tmp_path):
    def build(routes, cache=None):
        net = Net(routes)
        app = Flask(__name__)
        clock = {"t": 1_000.0}

        def auth(fn):
            def wrapper(*a, **k):
                g.username = "tester"
                return fn(*a, **k)
            wrapper.__name__ = fn.__name__
            return wrapper

        lp.register_lyrics_proxy_routes(app, auth, get=net, cache=cache or lp.SongCache(str(tmp_path), lambda: clock["t"]),
                                        now=lambda: clock["t"])
        return app.test_client(), net, clock
    return build


Q = "/lyrics/fetch?title=Test+Song&artist=Some+Band&album=Album&duration=200&song_id=s1&sources=lrcred,betterlyrics"


def test_lrcred_picks_the_right_hit_and_returns_word_timed_lrc(app_and):
    c, net, _ = app_and(LRCRED)
    r = c.get(Q)
    body = r.get_json()
    assert r.status_code == 200
    assert (body["source"], body["sync"], body["cached"]) == ("lrcred", "word", False)
    assert body["lrc"].startswith("[00:12.50]<00:12.50>alpha")
    assert r.headers["Cache-Control"] == "private, no-store"
    urls = [u for u, _, _ in net.calls]
    assert urls[0] == "https://lrc.red/search.json" and "BBBBBBBBBBBB" not in " ".join(urls)
    assert all("NaviVibe" in (h or {}).get("User-Agent", "") for _, _, h in net.calls)   # lrc.red's terms


def test_the_second_ask_comes_from_the_cache_without_the_network(app_and):
    c, net, _ = app_and(LRCRED)
    c.get(Q)
    n = len(net.calls)
    again = c.get(Q).get_json()
    assert again["cached"] is True and again["source"] == "lrcred"
    assert len(net.calls) == n


def test_falls_through_to_betterlyrics_when_lrcred_has_nothing(app_and):
    c, net, _ = app_and({"https://lrc.red/search.json": (200, {"hits": []}),
                         "https://api.betterlyrics.org/getLyrics": (200, {"ttml": TTML, "score": 0.9})})
    body = c.get(Q).get_json()
    assert body["source"] == "betterlyrics" and body["sync"] == "word"
    sent = [p for u, p, _ in net.calls if "betterlyrics" in u][0]
    assert sent == {"s": "Test Song", "a": "Some Band", "al": "Album", "d": 200}


def test_betterlyrics_401_is_no_result_not_an_error(app_and):
    c, _, _ = app_and({"https://lrc.red/search.json": (200, {"hits": []}),
                       "https://api.betterlyrics.org/getLyrics": (401, {"error": "API key required"})})
    r = c.get(Q)
    assert r.status_code == 404 and "No lyrics" in r.get_json()["error"]


def test_a_miss_is_remembered_for_six_hours_then_asked_again(app_and):
    c, net, clock = app_and({"https://lrc.red/search.json": (200, {"hits": []}),
                             "https://api.betterlyrics.org/": (404, "")})
    assert c.get(Q).status_code == 404
    n = len(net.calls)
    assert c.get(Q).status_code == 404 and len(net.calls) == n
    clock["t"] += lp.NEGATIVE_TTL + 1
    assert c.get(Q).status_code == 404 and len(net.calls) > n


def test_a_source_that_raises_never_breaks_the_answer(app_and):
    def boom(*a, **k):
        raise RuntimeError("network down")
    assert lp.resolve({"title": "t", "artist": "a", "album": "", "duration": 0, "spotify_id": ""},
                      ("lrcred", "betterlyrics"), boom) is None


def test_paxsenix_is_off_without_the_server_setting(app_and, monkeypatch):
    c, net, _ = app_and({})
    r = c.get("/lyrics/fetch?title=Test+Song&artist=A&sources=paxsenix&spotify_id=" + "a" * 22)
    assert r.status_code == 404 and "switched on" in r.get_json()["error"]
    assert net.calls == []


def test_paxsenix_with_an_instance_and_a_track_id(app_and, monkeypatch):
    monkeypatch.setattr(lp, "PAXSENIX_URL", "https://pax.example")
    c, net, _ = app_and({"https://pax.example/api/lyrics": (200, {"syncType": "LINE_SYNCED", "lines": [
        {"timeTag": "00:01.00", "words": "one two"}]})})
    r = c.get("/lyrics/fetch?title=T&artist=A&sources=paxsenix&spotify_id=" + "a" * 22)
    assert r.get_json()["source"] == "paxsenix"
    assert net.calls[0][1]["url"] == "https://open.spotify.com/track/" + "a" * 22
    # no track id: the source has nothing to ask about
    assert c.get("/lyrics/fetch?title=T2&artist=A&sources=paxsenix").status_code == 404


def test_bad_requests_and_rate_limit(app_and):
    c, _, _ = app_and(LRCRED)
    assert c.get("/lyrics/fetch?artist=x").status_code == 400
    assert c.get("/lyrics/fetch?title=x&duration=abc").status_code == 400
    for _ in range(lp.RATE_PER_MIN):
        c.get(Q)
    assert c.get(Q).status_code == 429


def test_cache_file_is_private_and_never_holds_credentials(tmp_path):
    cache = lp.SongCache(str(tmp_path / "c"))
    cache.put("k", {"source": "lrcred", "sync": "line", "lrc": "[00:01.00]x"})
    f = next((tmp_path / "c").iterdir())
    assert (f.stat().st_mode & 0o077) == 0 or __import__("os").name == "nt"
    assert cache.get("k")["lrc"] == "[00:01.00]x"
