"""
smart-pick-v1: Smart Shuffle from a playlist = familiar first, cold last, the model picks from the whole pool.

  cd /opt/shuffle-server && venv/bin/python -m pytest navivibe/tests/test_smart_pick_v1.py -q

A fake engine and a fake `_smart_queue`: no catalog, no model, no Flask app needed.
"""
import sqlite3
import threading
import types

import numpy as np
import pytest

from navivibe import smart_pick as sp

NOW = 1_795_000_000.0
DAY = 86400.0


class FakeEng:
    """songs: title -> dict(plays, days (since last play), artist, album, score)."""

    def __init__(self, songs, kept=()):
        self.titles = list(songs)
        self.songs = songs
        self.cat = types.SimpleNamespace(index={"id_" + t: i for i, t in enumerate(self.titles)})
        n = len(self.titles)
        self.raw = np.array([songs[t].get("plays", 0) for t in self.titles], float)
        self.last = np.array([NOW - songs[t]["days"] * DAY if songs[t].get("days") is not None else np.nan
                              for t in self.titles])
        self.resolver = types.SimpleNamespace(resolve=lambda t: "id_" + t if t in songs else None)
        self.kept = list(kept)
        self._lk = threading.RLock()
        self.calls = []

    def _lock_for(self, user):
        return self._lk

    def _user(self, user):
        return types.SimpleNamespace(raw=self.raw, last_ts=self.last)

    def _session_ctx(self, user, session):
        kept = list(self.kept)
        if session.get("seed_title"):
            kept.append(self.cat.index["id_" + session["seed_title"]])
        return types.SimpleNamespace(kept=kept, played=set(kept))

    def entry(self, t, rank=1):
        s = self.songs[t]
        return {"rank": rank, "title": t, "navidrome_id": "id_" + t, "artist": s.get("artist", t),
                "album": s.get("album", ""), "scores": {"final": s.get("score", 0.0)}}

    def pick(self, pool, n, exclude=()):
        def title(t):                                    # a candidate may be a song-id token
            return t[len(sp.ID_PREFIX) + 3:] if t.startswith(sp.ID_PREFIX) else t
        pool = [title(t) for t in pool]
        exclude = {title(t) for t in exclude}
        c = [t for t in pool if t in self.songs and t not in exclude]
        c.sort(key=lambda t: -self.songs[t].get("score", 0.0))
        return [self.entry(t, r) for r, t in enumerate(c[:n], 1)]

    def recommend(self, user, session, n=15, candidate_titles=None, reshuffle=False, frustration=False):
        self.calls.append(("recommend", n, set(candidate_titles)))
        return {"queue": self.pick(candidate_titles, n)}


def run(songs, count=16, kept=(), candidates=None, reshuffle=False, session=None, eng=None, v3=True):
    eng = eng or FakeEng(songs, kept)
    asks = []

    def smart_queue(model, user, ctx, sess, n, candidate_pool=None, reshuffle=False):
        asks.append((n, sess.get("seed_title"), set(candidate_pool or ())))
        excl = {sess["seed_title"]} if sess.get("seed_title") else set()
        return eng.pick(candidate_pool if candidate_pool is not None else eng.titles, n, excl), "v3+memory"

    cands = set(songs) if candidates is None else candidates
    q, engine = sp.serve(smart_queue, (lambda: eng) if v3 else (lambda: None), None, "u", {},
                         dict(session or {}), count, cands, reshuffle, now_ts=NOW)
    return q, engine, eng, asks


def lib(familiar=20, cold=20, cold_score_bonus=0.0):
    """familiar songs score 1.0 - small; cold songs optionally score ABOVE them (the model likes them)."""
    s = {}
    for k in range(familiar):
        s["F%02d" % k] = dict(plays=10, days=3, artist="fa%d" % k, album="fal%d" % k, score=1.0 - k * 0.01)
    for k in range(cold):
        s["C%02d" % k] = dict(plays=1, days=100, artist="ca%d" % k, album="cal%d" % k,
                              score=1.0 + cold_score_bonus - k * 0.01)
    return s


def titles(q):
    return [e["title"] for e in q]


# ── the owner's rules ────────────────────────────────────────────────────────

def test_cold_song_is_never_first_even_when_the_model_scores_it_highest():
    q, _, eng, _ = run(lib(cold_score_bonus=5.0), count=17)
    assert titles(q)[0].startswith("F")
    # the opener came from the opener model restricted to FAMILIAR songs
    assert eng.calls and all(t.startswith("F") for t in eng.calls[0][2])


def test_familiar_first_cold_last_and_count_is_kept():
    q, _, _, _ = run(lib(familiar=30, cold=30, cold_score_bonus=5.0), count=17)
    assert len(q) == 17 and len(set(titles(q))) == 17
    cold_pos = [i for i, t in enumerate(titles(q)) if t.startswith("C")]
    assert cold_pos == [16]                                   # one cold song closes the batch
    assert [e["rank"] for e in q] == list(range(1, 18))


def test_cold_songs_fill_the_end_when_familiar_run_out():
    q, _, _, _ = run(lib(familiar=5, cold=30), count=16)
    t = titles(q)
    assert len(t) == 16 and t[:5] == sorted(t[:5], key=lambda x: x) or t[0].startswith("F")
    assert all(x.startswith("F") for x in t[:5]) and all(x.startswith("C") for x in t[5:])


def test_at_most_one_cold_song_in_positions_two_to_seven_when_enough_familiar():
    for fam in (7, 8, 12, 25):
        q, _, _, _ = run(lib(familiar=fam, cold=20, cold_score_bonus=2.0), count=17)
        assert sum(1 for t in titles(q)[1:7] if t.startswith("C")) <= 1


def test_no_song_twice_and_the_opener_is_not_repeated():
    q, _, _, asks = run(lib(), count=17)
    assert len(set(titles(q))) == len(q)
    assert asks[0][1] == sp.id_token("id_" + titles(q)[0])                        # the rest was asked given the opener
    assert titles(q)[0] not in {e["title"] for e in q[1:]}


def test_stale_song_counts_as_cold():
    songs = lib(familiar=3, cold=0)
    songs["OLD"] = dict(plays=40, days=200, artist="o", album="o", score=9.0)   # many plays, 200 days ago
    q, _, _, _ = run(songs, count=4)
    assert titles(q)[0] != "OLD" and titles(q)[-1] == "OLD"


def test_boundaries_of_familiar():
    assert sp.is_familiar(3, NOW - 29 * DAY, NOW) and not sp.is_familiar(2, NOW - DAY, NOW)
    assert not sp.is_familiar(3, NOW - 31 * DAY, NOW) and sp.is_familiar(3, float("nan"), NOW)


def test_artist_and_film_are_spaced():
    songs = {}
    for k in range(6):
        songs["A%d" % k] = dict(plays=9, days=1, artist="same", album="same-film", score=2.0 - k * 0.01)
    for k in range(6):
        songs["B%d" % k] = dict(plays=9, days=1, artist="b%d" % k, album="f%d" % k, score=1.0 - k * 0.01)
    q, _, _, _ = run(songs, count=12)
    a = [e["artist"] for e in q]
    assert all(x != y for x, y in zip(a, a[1:]))


# ── a session already running: no opener stage, still familiar-first ─────────

def test_mid_session_has_no_opener_stage_and_puts_familiar_first():
    songs = lib(familiar=10, cold=10, cold_score_bonus=5.0)
    songs["NOW"] = dict(plays=9, days=1, score=0.0)
    q, _, eng, asks = run(songs, count=16, kept=[len(songs) - 1], candidates=set(songs) - {"NOW"})
    assert not eng.calls                                      # recommend() (opener) never called
    assert titles(q)[0].startswith("F") and len(q) == 16
    assert asks[0][0] == 10 and asks[1][0] == 6 and all(t.startswith("F") for t in asks[0][2])   # familiar pool first


# ── graceful ─────────────────────────────────────────────────────────────────

def test_new_listener_with_no_history_gets_the_plain_queue():
    songs = {"S%02d" % k: dict(plays=0, days=None, score=1.0 - k * 0.01) for k in range(30)}
    q, engine, eng, asks = run(songs, count=16)
    assert len(q) == 16 and titles(q) == sorted(titles(q))   # model order, none dropped, none empty
    assert asks == [(16, None, set(songs))] and not eng.calls
    assert sp.take_decisions(q) and not any(sp.KEY in e for e in q)


def test_a_playlist_of_only_cold_songs_is_not_left_empty():
    q, _, _, _ = run(lib(familiar=0, cold=25), count=16)
    assert len(q) == 16


def test_off_is_the_plain_path(monkeypatch):
    monkeypatch.setenv("SMART_PICK", "off")
    q, _, eng, asks = run(lib(cold_score_bonus=5.0), count=16)
    assert titles(q)[0].startswith("C") and not eng.calls and asks[0][0] == 16


def test_no_v3_engine_is_the_plain_path():
    q, engine, _, asks = run(lib(), count=16, v3=False)
    assert asks[0][0] == 16 and engine == "v3+memory"


def test_any_error_falls_back_to_the_plain_queue():
    eng = FakeEng(lib())
    eng.recommend = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom"))
    q, _, _, asks = run(lib(), count=16, eng=eng)
    assert len(q) == 16 and asks[-1][0] == 16


def test_candidates_shorter_than_count():
    q, _, _, _ = run(lib(familiar=3, cold=2), count=16)
    assert len(q) == 5 and titles(q)[0].startswith("F")


def test_unknown_titles_in_the_pool_are_ignored():
    songs = lib()
    q, _, _, _ = run(songs, count=10, candidates=set(songs) | {"Not In Catalog"})
    assert "Not In Catalog" not in titles(q) and len(q) == 10


def test_pure_arrange_degrades_when_nobody_is_familiar():
    es = [{"title": "x%d" % i, "navidrome_id": str(i), "artist": "a%d" % i} for i in range(5)]
    out, summ, _ = sp.arrange(es, lambda e: False, 4)
    assert out == es[:4] and summ["degraded"]


# ── decisions: logged, never sent to the app ─────────────────────────────────

def test_decisions_are_taken_off_the_entries_and_describe_every_song():
    q, _, _, _ = run(lib(familiar=30, cold=30), count=17)
    rows = sp.take_decisions(q)
    assert not any(sp.KEY in e for e in q)
    by_rank = {r[0]: r for r in rows}
    assert by_rank[0][5].startswith("opener=yes") and by_rank[1][5] == "opener_best_familiar"
    assert by_rank[17][5] == "cold_last" and by_rank[17][4] == 0 and by_rank[2][4] == 1
    assert set(by_rank) == set(range(0, 18))


def test_take_decisions_is_safe_on_junk():
    assert sp.take_decisions(None) == [] and sp.take_decisions([None, "x", {}]) == []


def test_log_and_erase(tmp_path, monkeypatch):
    path = str(tmp_path / "l.db")
    fb = types.SimpleNamespace(_connect=lambda p: sqlite3.connect(p))
    from navivibe import play_events as pe
    monkeypatch.setattr(pe, "_fb", lambda: fb)
    monkeypatch.setattr(pe, "ensure_schema", lambda u: path)
    q, _, _, _ = run(lib(familiar=30, cold=30), count=17)
    sp.log_decisions("u", "sv1", sp.take_decisions(q))
    c = sqlite3.connect(path)
    assert c.execute("select count(*) from smart_pick_items where served_id='sv1'").fetchone()[0] == 18
    assert c.execute("select decision from smart_pick_items where rank=1").fetchone()[0] == "opener_best_familiar"
    sp.erase_tables(c)
    assert c.execute("select count(*) from smart_pick_items").fetchone()[0] == 0
    sp.erase_tables(sqlite3.connect(":memory:"))              # table missing: no error


def test_log_failure_never_raises(monkeypatch):
    from navivibe import play_events as pe
    monkeypatch.setattr(pe, "_fb", lambda: (_ for _ in ()).throw(RuntimeError("db down")))
    sp.log_decisions("u", "sv", [(1, "t", 1, 1.0, 1, "familiar", 1)])


def test_the_response_body_never_carries_the_private_key():
    flask = pytest.importorskip("flask")
    app = flask.Flask("t")
    q, _, _, _ = run(lib(), count=8)

    @app.route("/n")
    def n():
        sp.take_decisions(q)
        return flask.jsonify({"queue": q})

    body = app.test_client().get("/n").get_data(as_text=True)
    assert "_sp" not in body and "decision" not in body


# ── the patch is in the live server ──────────────────────────────────────────

def test_server_py_is_patched():
    import os
    import navivibe
    text = open(os.path.join(os.path.dirname(navivibe.__file__), "server.py"), encoding="utf-8").read()
    assert "from navivibe.smart_pick import serve as _sp_serve" in text
    assert text.count("_sp_serve(_smart_queue, _v3_engine,") == 1
    assert "_sp_take(queue)" in text and "_sp_drop(c)" in text
    assert text.index("log_served(username") < text.index("_sp_take(queue)") < text.index("queue[0].pop(\"_context_meta\"")


# ── the three input forms ────────────────────────────────────────────────────

def test_ids_request_forms():
    f = sp.ids_request
    assert f({}, None) == (None, "", [])
    assert f({}, {"A"}) == ({"A"}, "titles", [])
    c, kind, ex = f({"candidate_ids": ["a", "b", "a", " "]}, None)
    assert c == {sp.id_token("a"), sp.id_token("b")} and kind == "ids" and ex == []
    c, kind, _ = f({"candidate_ids": "a|b,c"}, None)                 # pipe wins over comma, like titles
    assert c == {sp.id_token("a"), sp.id_token("b,c")}
    c, kind, ex = f({"candidate_ids": ["a", "b", "c"], "exclude_ids": ["b"]}, {"T"})
    assert c == {"T", sp.id_token("a"), sp.id_token("c")} and kind == "ids+titles" and ex == [sp.id_token("b")]
    assert f({"candidate_ids": 5, "exclude_ids": {"x": 1}}, None) == (None, "", [])
    big = f({"candidate_ids": [str(i) for i in range(sp.MAX_IDS + 50)]}, None)[0]
    assert len(big) == sp.MAX_IDS


def test_ids_make_the_same_queue_as_titles():
    songs = lib(familiar=30, cold=30, cold_score_bonus=5.0)
    by_title, _, _, _ = run(songs, count=17, candidates=set(songs))
    ids = {sp.id_token("id_" + t) for t in songs}
    by_id, _, _, _ = run(songs, count=17, candidates=ids)
    assert titles(by_id)[0].startswith("F") and len(by_id) == 17
    assert [t.startswith("C") for t in titles(by_id)] == [t.startswith("C") for t in titles(by_title)]


def test_two_songs_with_one_title_are_told_apart_by_id():
    eng = FakeEng(lib(familiar=3, cold=0))
    assert sp.resolve_one(eng, sp.id_token("id_F01")) == "id_F01"
    assert sp.resolve_one(eng, sp.id_token("id_nope")) is None
    assert sp.resolve_one(eng, "F02") == "id_F02"


def test_playlist_pool_prefers_ids_and_drops_excluded():
    nd = [{"id": "a", "title": "A"}, {"id": "b", "title": "B"}, {"id": "", "title": "NoId"}, {"title": ""}]
    assert sp.playlist_pool(nd) == {sp.id_token("a"), sp.id_token("b"), "NoId"}
    assert sp.playlist_pool(nd, [sp.id_token("b")]) == {sp.id_token("a"), "NoId"}


def test_playlist_cache_is_short_lived_and_never_keeps_empty(monkeypatch):
    sp._pl_cache.clear()
    calls = []
    f = lambda: calls.append(1) or [1]
    assert sp.cached("pl", "k", f, ttl=30) == [1] and sp.cached("pl", "k", f, ttl=30) == [1] and len(calls) == 1
    assert sp.cached("pl", "k", f, ttl=0) == [1] and len(calls) == 2           # ttl 0 = off
    e = lambda: calls.append(1) or []
    sp.cached("pl", "empty", e, ttl=30)
    sp.cached("pl", "empty", e, ttl=30)
    assert len(calls) == 4


def test_v3_resolves_an_id_token_exactly():
    from navivibe.recsys import recommender as r
    fake = types.SimpleNamespace(cat=types.SimpleNamespace(index={"x1": 7, "x2": 9}),
                                 resolver=types.SimpleNamespace(resolve=lambda t: "x2" if t == "Title" else None))
    out = r.V3Engine._resolve_titles(fake, [sp.id_token("x1"), "Title", sp.id_token("gone"), "unknown"])
    assert out == [7, 9]


def test_server_py_reads_the_new_fields():
    import os
    import navivibe
    text = open(os.path.join(os.path.dirname(navivibe.__file__), "server.py"), encoding="utf-8").read()
    for needle in ("_sp_ids(data, explicit_candidates)", "list(_sp_exclude)", "_sp_pool(nd_songs, _sp_exclude)",
                   "_sp_serve_pl(_smart_queue", '"smart_pick": ({"v": 1'):
        assert text.count(needle) == 1, needle
