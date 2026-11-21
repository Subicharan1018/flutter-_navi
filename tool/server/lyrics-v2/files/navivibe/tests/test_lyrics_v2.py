"""lyrics-v2: multi-artist lookup, ISRC, cache versions, YouTube Music, the prefetch and the sidecar
writer. No network: every request goes through a fake. Lyrics are made-up words.

    cd /opt/shuffle-server && PYTHONPATH=. venv/bin/python -m pytest navivibe/tests/test_lyrics_v2.py -q
"""

import json
import os
import sqlite3

import pytest

from navivibe import lyrics_prefetch as pf
from navivibe import lyrics_proxy as lp
from navivibe import lyrics_sidecar as sc

LRC = "[00:01.00]one two\n[00:05.50]three four"
ENHANCED = "[00:01.00]<00:01.00>one <00:01.40>two\n[00:05.50]<00:05.50>three <00:06.00>four"


class Net:
    """Answers by a function (url, params) -> (status, body); records the calls."""

    def __init__(self, fn):
        self.fn, self.calls = fn, []

    def __call__(self, url, params=None, headers=None, timeout=8):
        self.calls.append((url, params))
        status, body = self.fn(url, params or {})
        return status, body if isinstance(body, str) else json.dumps(body)


# "Life of Pazham": the library lists two artists with a bullet; lrc.red lists them with a comma and
# writes the second in another script. The search finds nothing unless the artist is just the first.
PAZHAM = {"song_id": "4p64y7JXWZzxhxYcImf3Ji", "title": "Life of Pazham",
          "artist": "Anirudh Ravichander • Vivek", "album": "Album", "duration": 236, "spotify_id": ""}
PAZHAM_HIT = {"isrc": "QM6P42215720", "title": 'Life of Pazham (From "Some Film")',
              "artist": "Anirudh Ravichander, 維瓦克", "duration": 234.5}


def lrcred(search_ok=lambda q: True, hit=PAZHAM_HIT, sync="line", body=LRC):
    def fn(url, p):
        if url.endswith("/search.json"):
            return 200, {"hits": [hit] if search_ok(p.get("q", "")) else []}
        if url.endswith(".json"):
            return 200, {"sync": sync}
        if url.endswith(".lrc"):
            return 200, body
        return 404, ""
    return Net(fn)


# ── the lookup ─────────────────────────────────────────────────────────────────────────────────

def test_artist_and_title_cleanup():
    assert lp.primary_artist("Anirudh Ravichander • Vivek") == "Anirudh Ravichander"
    assert lp.primary_artist("A, B & C") == "A"
    assert lp.primary_artist("Solo feat. Other") == "Solo"
    assert lp.primary_artist("") == ""
    assert lp.artist_parts("A • B; C") == ["A", "B", "C"]
    assert lp.clean_title('Life of Pazham (From "Some Film")') == "Life of Pazham"
    assert lp.clean_title("(Only Brackets)") == "(Only Brackets)"


def test_pazham_is_found_when_the_search_only_works_with_the_primary_artist():
    net = lrcred(search_ok=lambda q: q == "Life of Pazham Anirudh Ravichander")
    r = lp.resolve(PAZHAM, ("lrcred",), net)
    assert r and r[0] == "lrcred" and r[1]["sync"] == "line" and r[1]["lrc"] == LRC
    queries = [p["q"] for u, p in net.calls if u.endswith("search.json")]
    assert queries == ["Life of Pazham Anirudh Ravichander"]           # never the bullet string


def test_the_title_alone_is_the_second_try():
    net = lrcred(search_ok=lambda q: q == "Life of Pazham")
    assert lp.resolve(PAZHAM, ("lrcred",), net)
    assert [p["q"] for u, p in net.calls if u.endswith("search.json")] == ["Life of Pazham Anirudh Ravichander",
                                                                          "Life of Pazham"]


def test_an_artist_in_another_script_needs_title_and_duration_not_a_name_match():
    song = {**PAZHAM, "artist": "Someone Else"}
    assert lp.resolve(song, ("lrcred",), lrcred())                      # 維瓦克 can't be compared: duration agrees
    assert lp.resolve({**song, "duration": 300}, ("lrcred",), lrcred()) is None     # duration off
    assert lp.resolve({**song, "duration": 0}, ("lrcred",), lrcred()) is None       # no duration: no proof
    latin = {**PAZHAM_HIT, "artist": "Another Latin Name"}
    assert lp.resolve(song, ("lrcred",), lrcred(hit=latin)) is None                 # a Latin mismatch is a mismatch
    assert lp.resolve({**song, "title": "Other Song"}, ("lrcred",), lrcred()) is None


def test_any_of_the_listed_artists_may_be_the_match():
    song = {**PAZHAM, "artist": "Vivek • Anirudh Ravichander"}
    assert lp.resolve(song, ("lrcred",), lrcred())


def test_an_isrc_skips_the_search(tmp_path):
    net = lrcred()
    r = lp.resolve({**PAZHAM, "isrc": "QM6P42215720"}, ("lrcred",), net)
    assert r and not any(u.endswith("search.json") for u, _ in net.calls)
    assert net.calls[0][0] == "https://lrc.red/s/QM6P42215720.json"


def test_a_wrong_isrc_falls_back_to_the_search():
    def fn(url, p):
        if "/s/ZZZZZZZZZZZZ" in url:
            return 404, ""
        return lrcred().fn(url, p)
    net = Net(fn)
    assert lp.resolve({**PAZHAM, "isrc": "ZZZZZZZZZZZZ"}, ("lrcred",), net)
    assert any(u.endswith("search.json") for u, _ in net.calls)


def _catalog(path, rows):
    con = sqlite3.connect(path)
    con.execute("CREATE TABLE songs (id TEXT PRIMARY KEY, title TEXT, artist TEXT, album TEXT, duration REAL, "
                "isrc TEXT, path TEXT, missing INTEGER DEFAULT 0)")
    con.executemany("INSERT INTO songs (id,title,artist,album,duration,isrc,path) VALUES (?,?,?,?,?,?,?)", rows)
    con.commit()
    con.close()


def test_catalog_isrc_is_read_read_only_and_junk_is_ignored(tmp_path):
    db = str(tmp_path / "catalog.db")
    _catalog(db, [("a", "T", "A", "", 100, "qm6p42215720", "a.flac"), ("b", "T", "A", "", 100, "bad", "b.flac"),
                  ("c", "T", "A", "", 100, None, "c.flac")])
    assert lp.catalog_details("a", db) == {"isrc": "QM6P42215720"}
    assert lp.catalog_details("b", db) == {} and lp.catalog_details("c", db) == {}
    assert lp.catalog_details("a", str(tmp_path / "missing.db")) == {}


def test_catalog_reads_a_spotify_details_table_when_it_exists(tmp_path):
    db = str(tmp_path / "catalog.db")
    _catalog(db, [("a", "T", "A", "", 100, None, "a.flac")])
    con = sqlite3.connect(db)
    con.execute("CREATE TABLE spotify_details (song_id TEXT, isrc TEXT, spotify_id TEXT)")
    con.execute("INSERT INTO spotify_details VALUES ('a', 'QM6P42215720', '" + "a" * 22 + "')")
    con.commit()
    con.close()
    assert lp.catalog_details("a", db) == {"isrc": "QM6P42215720", "spotify_id": "a" * 22}


def test_betterlyrics_gets_the_primary_artist_only():
    seen = {}

    def fn(url, p):
        seen.update(p)
        return 401, ""
    lp.fetch_betterlyrics({**PAZHAM}, Net(fn))
    assert seen["a"] == "Anirudh Ravichander" and seen["s"] == "Life of Pazham"


# ── the cache ──────────────────────────────────────────────────────────────────────────────────

def test_a_v1_miss_is_asked_again_at_once_and_a_fresh_v2_miss_is_not(tmp_path):
    cache = lp.SongCache(str(tmp_path))
    now = {"t": 1000.0}
    cache.now = lambda: now["t"]
    key = lp.song_key(PAZHAM)
    cache.put(key, {"tried": ["lrcred"]})                              # written by lyrics-v1: no "v"
    net = lrcred()
    got = lp.lookup(PAZHAM, ("lrcred",), cache, net, lambda: now["t"])
    assert got and got["cached"] is False and net.calls

    other = {**PAZHAM, "song_id": "other", "title": "Nobody Has This"}
    miss = Net(lambda u, p: (200, {"hits": []}) if "search" in u else (404, ""))
    assert lp.lookup(other, ("lrcred",), cache, miss, lambda: now["t"]) is None
    n = len(miss.calls)
    assert lp.lookup(other, ("lrcred",), cache, miss, lambda: now["t"]) is None and len(miss.calls) == n
    now["t"] += lp.NEGATIVE_TTL + 1
    lp.lookup(other, ("lrcred",), cache, miss, lambda: now["t"])
    assert len(miss.calls) > n


def test_a_miss_for_fewer_sources_is_retried_when_a_new_source_is_asked(tmp_path):
    cache = lp.SongCache(str(tmp_path))
    nothing = Net(lambda u, p: (200, {"hits": []}) if "search" in u else (404, ""))
    assert lp.lookup(PAZHAM, ("lrcred",), cache, nothing) is None
    n = len(nothing.calls)
    assert lp.lookup(PAZHAM, ("lrcred",), cache, nothing) is None and len(nothing.calls) == n
    lp.lookup(PAZHAM, ("lrcred", "betterlyrics"), cache, nothing)
    assert len(nothing.calls) > n


def test_a_hit_never_expires(tmp_path):
    cache = lp.SongCache(str(tmp_path))
    assert lp.lookup(PAZHAM, ("lrcred",), cache, lrcred())
    net = Net(lambda u, p: (500, ""))
    again = lp.lookup(PAZHAM, ("lrcred",), cache, net, lambda: 10 ** 12)
    assert again["cached"] is True and not net.calls


# ── YouTube Music ──────────────────────────────────────────────────────────────────────────────

def test_ytmusic_is_last_in_the_default_order_and_can_be_switched_off(monkeypatch):
    assert lp.DEFAULT_SOURCES == ("lrcred", "betterlyrics", "ytmusic")
    assert lp.enabled_sources()[:3] == ("lrcred", "betterlyrics", "ytmusic")
    monkeypatch.setattr(lp, "YTMUSIC_ON", False)
    assert "ytmusic" not in lp.enabled_sources()


def test_ytmusic_timed_lines_become_lrc_and_the_query_is_clean(monkeypatch):
    asked = []

    def fake(q):
        asked.append(q)
        return {"sync": "line", "lines": [[5500, "three four"], [1000, "one  two"]]}
    monkeypatch.setattr(lp, "run_ytmusic", fake)
    got = lp.fetch_ytmusic(PAZHAM, None)
    assert got == {"sync": "line", "lrc": LRC}                          # sorted, whitespace tidied
    assert asked == [{"title": "Life of Pazham", "artist": "Anirudh Ravichander", "duration": 236}]


def test_ytmusic_plain_text_is_a_fallback_that_a_synced_source_beats(monkeypatch):
    monkeypatch.setattr(lp, "run_ytmusic", lambda q: {"sync": "plain", "text": "one two\n\n three four "})
    assert lp.fetch_ytmusic(PAZHAM, None) == {"sync": "plain", "lrc": "one two\nthree four"}
    nothing = Net(lambda u, p: (200, {"hits": []}) if "search" in u else (404, ""))
    assert lp.resolve(PAZHAM, ("lrcred", "ytmusic"), nothing)[0] == "ytmusic"
    monkeypatch.setattr(lp, "run_ytmusic", lambda q: {"sync": "plain", "text": "x"})
    assert lp.resolve(PAZHAM, ("ytmusic", "lrcred"), lrcred())[0] == "lrcred"      # synced wins over earlier plain


@pytest.mark.parametrize("answer", [None, {}, {"sync": "line", "lines": []}, {"sync": "plain", "text": " "}, "junk"])
def test_ytmusic_nothing_is_nothing(monkeypatch, answer):
    monkeypatch.setattr(lp, "run_ytmusic", lambda q: answer)
    assert lp.fetch_ytmusic(PAZHAM, None) is None


def test_ytmusic_without_the_helper_is_quietly_unavailable(monkeypatch):
    monkeypatch.setattr(lp, "YTMUSIC_PYTHON", "/nonexistent/python")
    assert lp.run_ytmusic({"title": "x"}) is None


# ── the prefetch ───────────────────────────────────────────────────────────────────────────────

class Clock:
    def __init__(self):
        self.t, self.slept = 0.0, []

    def now(self):
        return self.t

    def sleep(self, s):
        self.slept.append(s)
        self.t += s


def test_the_rate_never_exceeds_the_limit():
    c = Clock()
    net = pf.GentleNet(30, real_get=lambda *a: (200, "{}"), sleep=c.sleep, now=c.now)
    for _ in range(31):
        net("https://lrc.red/x")
    assert c.t >= 30 * 2.0 - 0.01                  # 31 requests at 30 a minute take at least 60 s
    assert net.requests == 31
    assert pf.GentleNet(500).interval == 1.0       # capped at 60 a minute


def test_a_429_waits_then_retries_and_a_host_that_keeps_refusing_is_left_alone():
    c = Clock()
    answers = iter([(429, ""), (200, "ok")])
    net = pf.GentleNet(60, real_get=lambda *a: next(answers), sleep=c.sleep, now=c.now)
    assert net("https://lrc.red/x") == (200, "ok") and net.backoffs == 1 and max(c.slept) >= 60

    always = pf.GentleNet(60, real_get=lambda *a: (403, ""), sleep=c.sleep, now=c.now)
    assert always("https://api.betterlyrics.org/g")[0] == 403 and always("https://api.betterlyrics.org/g")[0] == 403
    calls = always.requests
    assert always("https://api.betterlyrics.org/g")[0] == 429 and always.requests == calls      # cooling down
    assert always("https://lrc.red/other")[0] == 403                                            # other hosts still asked


def test_a_network_error_is_a_miss_not_a_crash():
    def boom(*a):
        raise OSError("down")
    assert pf.GentleNet(60, real_get=boom, sleep=lambda s: None)("https://lrc.red/x") == (0, "")


def test_run_skips_cached_songs_counts_by_source_and_is_resumable(tmp_path):
    cache = lp.SongCache(str(tmp_path))
    songs = [{**PAZHAM, "song_id": f"s{i}", "title": f"Song {i}", "artist": "Someone"} for i in range(4)]

    def fn(url, p):
        title = p.get("q", "")
        if url.endswith("search.json"):
            n = title.split()[1]
            return 200, {"hits": [{"isrc": "AAAAAAAAAAA" + n, "title": f"Song {n}", "artist": "Someone", "duration": 236}]
                         if n != "3" else []}
        if url.endswith(".json"):
            return 200, {"sync": "line"}
        return 200, LRC
    net = Net(fn)
    first = pf.run(songs[:2], ("lrcred",), cache, net, 3600, 14)
    assert first["found"] == {"lrcred": 2} and first["skipped"] == 0
    calls = len(net.calls)
    again = pf.run(songs, ("lrcred",), cache, net, 3600, 14)         # the first two are skipped: resumed
    assert again["skipped"] == 2 and again["found"] == {"lrcred": 1} and again["not_found"] == 1
    assert len(net.calls) > calls
    third = pf.run(songs, ("lrcred",), cache, net, 3600, 14)         # the miss is fresh: skipped too
    assert third["skipped"] == 4 and not third["found"]


def test_run_stops_on_the_time_budget_and_on_a_signal(tmp_path):
    cache = lp.SongCache(str(tmp_path))
    songs = [{**PAZHAM, "song_id": f"s{i}"} for i in range(5)]
    ticks = iter(range(0, 1000, 100))
    done = pf.run(songs, ("lrcred",), cache, lrcred(), 150, 14, clock=lambda: next(ticks))
    assert done["stopped"] == "time budget"
    assert pf.run(songs, ("lrcred",), lp.SongCache(str(tmp_path / "x")), lrcred(), 3600, 14,
                  should_stop=lambda: True)["stopped"] == "signal"


def test_one_bad_song_never_stops_the_run(tmp_path, monkeypatch):
    cache = lp.SongCache(str(tmp_path))
    real = lp.resolve

    def flaky(song, sources, get=None):
        if song["song_id"] == "bad":
            raise RuntimeError("boom")
        return real(song, sources, get)
    monkeypatch.setattr(lp, "resolve", flaky)
    songs = [{**PAZHAM, "song_id": "bad"}, {**PAZHAM, "song_id": "good"}]
    s = pf.run(songs, ("lrcred",), cache, lrcred(), 3600, 14)
    assert s["errors"] == 1 and s["found"] == {"lrcred": 1}


def test_main_reads_the_catalog_and_writes_a_scratch_cache(tmp_path, monkeypatch, capsys):
    db = str(tmp_path / "catalog.db")
    _catalog(db, [("s1", "Song 1", "Someone", "", 236, None, "s1.flac")])
    monkeypatch.setattr(lp, "http_get", lambda url, params=None, headers=None, timeout=8: (404, ""))
    monkeypatch.setattr(lp, "run_ytmusic", lambda q: {"sync": "line", "lines": [[1000, "one two"]]})
    scratch = tmp_path / "scratch"
    assert pf.main(["--catalog", db, "--cache-dir", str(scratch), "--rate", "60", "--sources", "ytmusic"]) == 0
    summary = json.loads(capsys.readouterr().out.strip().splitlines()[-1])
    assert summary["found"] == {"ytmusic": 1}
    assert len(list(scratch.iterdir())) == 1
    assert pf.main(["--catalog", str(tmp_path / "nope.db"), "--cache-dir", str(scratch)]) == 1      # broken env


# ── the sidecar writer ─────────────────────────────────────────────────────────────────────────

@pytest.fixture
def library(tmp_path):
    root = tmp_path / "Music"
    root.mkdir()
    for name in ("timed.flac", "plain.flac", "has.flac", "uncached.flac"):
        (root / name).write_bytes(b"x")
    (root / "has.lrc").write_text("mine\n")
    db = str(tmp_path / "catalog.db")
    _catalog(db, [("t", "T", "A", "", 100, None, "timed.flac"), ("p", "P", "A", "", 100, None, "plain.flac"),
                  ("h", "H", "A", "", 100, None, "has.flac"), ("u", "U", "A", "", 100, None, "uncached.flac"),
                  ("gone", "G", "A", "", 100, None, "gone.flac"), ("evil", "E", "A", "", 100, None, "../outside.flac")])
    cache = lp.SongCache(str(tmp_path / "cache"))
    cache.put("t", {"source": "lrcred", "sync": "word", "lrc": ENHANCED})
    cache.put("p", {"source": "ytmusic", "sync": "plain", "lrc": "one two"})
    cache.put("h", {"source": "lrcred", "sync": "line", "lrc": LRC})
    cache.put("gone", {"source": "lrcred", "sync": "line", "lrc": LRC})
    cache.put("evil", {"source": "lrcred", "sync": "line", "lrc": LRC})
    (tmp_path / "outside.flac").write_bytes(b"x")
    return root, db, cache


def test_the_sidecar_dry_run_counts_and_writes_nothing(library, capsys):
    root, db, cache = library
    todo, skipped = sc.plan(db, cache, str(root))
    assert [os.path.basename(p) for p, _, _ in todo] == ["timed.lrc"]
    assert skipped["already has a .lrc"] == 1 and skipped["plain text (use --plain)"] == 1
    assert skipped["audio file not found"] == 1 and skipped["outside the music root"] == 1
    assert skipped["no lyrics cached"] == 1
    assert sc.main(["--catalog", db, "--cache-dir", cache.dir, "--music-root", str(root)]) == 0
    out = capsys.readouterr().out
    assert "DRY RUN: would add 1 .lrc files" in out
    assert not (root / "timed.lrc").exists()


def test_apply_writes_line_timed_files_never_overwrites_and_keeps_yours(library):
    root, db, cache = library
    assert sc.main(["--catalog", db, "--cache-dir", cache.dir, "--music-root", str(root), "--apply"]) == 0
    assert (root / "timed.lrc").read_text() == LRC + "\n"            # word tags dropped
    assert (root / "has.lrc").read_text() == "mine\n"
    assert not (root / "plain.lrc").exists()
    (root / "timed.lrc").write_text("edited\n")
    sc.main(["--catalog", db, "--cache-dir", cache.dir, "--music-root", str(root), "--apply", "--plain"])
    assert (root / "timed.lrc").read_text() == "edited\n"             # a second run never touches it
    assert (root / "plain.lrc").read_text() == "one two\n"            # --plain adds the untimed one


def test_words_flag_keeps_word_tags(library):
    root, db, cache = library
    sc.main(["--catalog", db, "--cache-dir", cache.dir, "--music-root", str(root), "--apply", "--words"])
    assert (root / "timed.lrc").read_text() == ENHANCED + "\n"


def test_nothing_written_outside_the_music_root(library, tmp_path):
    root, db, cache = library
    sc.main(["--catalog", db, "--cache-dir", cache.dir, "--music-root", str(root), "--apply", "--plain"])
    assert not (tmp_path / "outside.lrc").exists()
