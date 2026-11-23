"""hybrid-shadow-v1 tests. Run from the shuffle-server root:
    PYTHONPATH=. venv/bin/python -m pytest navivibe/tests/test_hybrid_shadow_v1.py -q
Uses the real navivibe.recsys.features / state, a tiny fake engine and a temp log folder."""
import hashlib
import importlib.util
import json
import os
import sqlite3
import threading
import time
import types

import numpy as np
import pytest

from navivibe import feedback, hybrid as H, hybrid_shadow as hs, hybrid_store as store, hybrid_train as ht
from navivibe.recsys.features import F, FEATURES

N = 260
V3 = "2026-11-22T22:01:48+0000"
# sha256 of navivibe/hybrid.py with LF line ends = tool/shuffle_eval/bakeoff/hybrid.py at 0d408b5
HARNESS_SHA = "6334038b8fee920d01f4d9557e02d92839c2a55f42432bfacfdf0fdf5fc46ade"


@pytest.fixture(autouse=True)
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(feedback, "DB_DIR", str(tmp_path))
    for k in ("HYBRID_ORDER", "HYBRID_BUDGET_MS"):
        monkeypatch.delenv(k, raising=False)
    hs.reset_ready_cache()
    hs.models._key = None
    hs.models._val = None
    hs._fm_cache.clear()
    yield tmp_path
    hs.reset_ready_cache()


# ── a tiny world ─────────────────────────────────────────────────────────────

class Cat:
    def __init__(self):
        self.ids = ["id%d" % i for i in range(N)]
        self.index = {s: i for i, s in enumerate(self.ids)}
        self.meta = {s: {"title": "T" + s, "artist": "A%d" % (i % 25), "album": "B", "path": "/m/" + s}
                     for i, s in enumerate(self.ids)}

    def __len__(self):
        return N


class Arrays:
    def __init__(self):
        r = np.random.default_rng(5)
        self.energy = r.random(N).astype(np.float32)
        self.valence = r.random(N).astype(np.float32)
        self.energy[3] = np.nan                    # one song without a value (the NaN trap in the spec)


class Hour:
    def __init__(self, seed):
        self.m = np.random.default_rng(seed).random((N, 24))

    def at(self, ts):
        return self.m


class User:
    def __init__(self, seed=2):
        self.raw = (np.random.default_rng(seed).random(N) > 0.4).astype(np.float32)
        self.hour = Hour(seed)


class Ctx:
    def __init__(self, kept=(), played=()):
        self.kept, self.played = list(kept), set(played)


class Ranker:
    def predict(self, X, empty, num_threads=0):
        return X[:, F["cnt_7d"]] + 0.1 * X[:, F["p_next"]]


class Engine:
    def __init__(self, kept=(), played=()):
        self.cat, self.A = Cat(), Arrays()
        self.ctx = Ctx(kept, played)
        self.us = User()
        self.gs = None
        self.ranker = Ranker()
        self._lock = threading.RLock()
        self.builds = []
        self.fb = types.SimpleNamespace(build=self._build)

    def _build(self, us, gs, ctx, ts, hour, wd):
        self.builds.append(len(ctx.kept))
        return matrix(11)

    def _lock_for(self, u):
        return self._lock

    def _user(self, u):
        return self.us

    def _session_ctx(self, u, session):
        return self.ctx

    def _resolve_titles(self, titles):
        return [self.cat.index[t] for t in titles if t in self.cat.index]


def matrix(seed=1):
    return np.random.default_rng(seed).random((N, len(FEATURES))).astype(np.float32)


def fitted(eng=None, n_groups=230):
    """A real re-ranker fitted on synthetic groups made with the harness's own functions."""
    eng = eng or Engine()
    fm = H.FeatureMatrix(eng.cat, eng.A)
    rng = np.random.default_rng(3)
    groups = []
    while len(groups) < n_groups:
        X = rng.random((N, len(FEATURES))).astype(np.float32)
        pos = int(rng.integers(N))
        X[pos, F["p_next"]] += 1.5 * rng.random()
        X[pos, F["cnt_7d"]] += 0.6
        kept = [int(rng.integers(N))]
        hb, M = fm.build(X, eng.us, kept, 1e9, 12, 6)
        g = H.training_group(M, hb, pos, np.ones(N, bool))
        if g is not None:
            groups.append(g)
    return H.Reranker.fit(groups)


@pytest.fixture(scope="module")
def reranker():
    return fitted()


@pytest.fixture
def model(monkeypatch, reranker):
    meta = {"version": "vv", "cols": list(H.NO_AUDIO_MOOD_COLS), "all_cols": list(H.ALL_COLS),
            "v3_trained_at": V3, "trained_at": "now"}
    monkeypatch.setattr(hs.models, "get", lambda: (reranker, meta))
    return reranker


def rows(user, table):
    c = sqlite3.connect(feedback.get_db_path(user))
    c.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in c.execute("SELECT * FROM %s ORDER BY id" % table)]
    finally:
        c.close()


# ── PARITY with the research harness ─────────────────────────────────────────

def _lf(path):
    with open(path, "rb") as f:
        return f.read().replace(b"\r\n", b"\n")


def test_the_server_copy_of_the_harness_is_the_harness_file():
    here = os.path.dirname(H.__file__)
    assert hashlib.sha256(_lf(os.path.join(here, "hybrid.py"))).hexdigest() == HARNESS_SHA
    ref = os.path.join(os.path.dirname(__file__), "harness_hybrid_reference.py")
    assert os.path.exists(ref) and _lf(ref) == _lf(os.path.join(here, "hybrid.py"))
    for up in range(3, 8):                              # in the repo: tool/shuffle_eval/bakeoff/hybrid.py
        repo = os.path.abspath(os.path.join(os.path.dirname(__file__), *[".."] * up, "shuffle_eval", "bakeoff", "hybrid.py"))
        if os.path.exists(repo):
            assert _lf(repo) == _lf(os.path.join(here, "hybrid.py"))


def _harness_module():
    """The repo's harness file when this runs in the repo, else the reference copy shipped beside this
    test (harness_hybrid_reference.py): the parity test runs everywhere, it is never skipped."""
    here = os.path.dirname(__file__)
    paths = [os.path.abspath(os.path.join(here, *[".."] * up, "shuffle_eval", "bakeoff", "hybrid.py")) for up in range(3, 8)]
    paths.append(os.path.join(here, "harness_hybrid_reference.py"))
    for p in paths:
        if os.path.exists(p):
            spec = importlib.util.spec_from_file_location("harness_hybrid", p)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            return mod
    raise AssertionError("no harness file or reference copy found: the package is incomplete")


def test_same_inputs_through_the_harness_and_the_server_give_the_same_scores(reranker):
    harness = _harness_module()
    eng = Engine()
    X = matrix(21)
    kept = [4, 9]
    allowed = np.ones(N, bool)
    allowed[[4, 9, 30]] = False
    hb_s, M_s = hs.feature_matrix(eng).build(X, eng.us, kept, 1.7e9, 14, 11)
    hb_h, M_h = harness.FeatureMatrix(eng.cat, eng.A).build(X, eng.us, kept, 1.7e9, 14, 11)
    assert np.array_equal(hb_s, hb_h) and np.array_equal(M_s, M_h)
    ref = harness.Reranker(reranker.model, reranker.cols)           # the same trained booster
    assert np.array_equal(reranker.scores(M_s, hb_s, allowed), ref.scores(M_h, hb_h, allowed))
    assert list(H.candidates(hb_s, allowed)) == list(harness.candidates(hb_h, allowed))
    assert list(H.NO_AUDIO_MOOD_COLS) == list(harness.NO_AUDIO_MOOD_COLS) and len(H.NO_AUDIO_MOOD_COLS) == 45


def test_rank_of_is_the_harness_rank_with_ties_counted_half():
    allowed = np.ones(10, bool)
    allowed[0] = False
    v = np.array([9, 5, 5, 5, 1, 2, 3, 4, 6, 0], float)
    assert hs.rank_of(v, allowed, 1) == 1 + 1 + 0.5 * 2      # one above (6), two tied
    assert hs.rank_of(v, allowed, 8) == 1.0                  # the masked 9 does not count
    assert hs.rank_of(v, allowed, 9) == 9.0


def test_a_song_with_no_energy_does_not_kill_the_features():
    eng = Engine()
    hb, M = hs.feature_matrix(eng).build(matrix(2), eng.us, [1], 1e9, 9, 3)
    assert np.isfinite(hb).all() and np.isfinite(M).all()
    cols = [H.ALL_COLS.index(c) for c in H.NO_AUDIO_MOOD_COLS]
    assert (M[:, cols].std(axis=0) > 0).sum() >= 40           # spec: no constant (dead) column


# ── the model file ───────────────────────────────────────────────────────────

def test_model_file_roundtrip_is_atomic_and_keeps_the_previous_one(tmp_path, reranker):
    p = str(tmp_path / "m" / "hybrid_v1.json")
    meta = store.save(p, reranker, {"groups": 230}, V3)
    rr, got = store.load(p)
    assert got["version"] == meta["version"] and got["v3_trained_at"] == V3 and got["metrics"]["groups"] == 230
    eng = Engine()
    hb, M = hs.feature_matrix(eng).build(matrix(4), eng.us, [1], 1e9, 9, 3)
    allowed = np.ones(N, bool)
    assert np.array_equal(rr.scores(M, hb, allowed), reranker.scores(M, hb, allowed))
    store.save(p, reranker, {}, V3)
    assert os.path.exists(p + ".prev") and not os.path.exists(p + ".tmp")


def test_unreadable_missing_and_incompatible_models_are_refused(tmp_path, reranker):
    assert store.load(str(tmp_path / "nope.json"))[0] is None
    bad = tmp_path / "bad.json"
    bad.write_text("{not json")
    assert store.load(str(bad))[0] is None
    meta = store.save(str(tmp_path / "m.json"), reranker, {}, V3)
    assert store.incompatible(meta, V3) is None
    assert "refit" in store.incompatible(dict(meta, cols=meta["cols"][:-1]), V3)
    assert "refit" in store.incompatible(dict(meta, all_cols=meta["all_cols"][:-1]), V3)
    assert "embeddings differ" in store.incompatible(meta, "a-newer-v3-train")
    # an UNKNOWN v3 stamp cannot be proven to match the vectors the groups were built with: not usable
    assert "unknown" in store.incompatible(meta, None)


def test_the_v3_stamp_is_read_from_disk_when_not_given(tmp_path, reranker):
    d = tmp_path / "v3"
    d.mkdir()
    assert store.v3_trained_at(str(d)) is None                      # no meta.json
    (d / "meta.json").write_text("{broken")
    assert store.v3_trained_at(str(d)) is None
    (d / "meta.json").write_text(json.dumps({"trained_at": V3}))
    assert store.v3_trained_at(str(d)) == V3


def test_the_cache_keeps_shadow_off_until_the_model_matches_the_v3_artifacts(tmp_path, reranker):
    v3 = tmp_path / "v3"
    v3.mkdir()
    (v3 / "meta.json").write_text(json.dumps({"trained_at": V3}))
    mp = str(tmp_path / "hybrid.json")
    cache = hs.ModelCache(mp, str(v3))
    assert cache.get() is None and "no model" in cache.reason
    store.save(mp, reranker, {}, V3)
    assert cache.get() is not None and cache.reason == "ok"
    time.sleep(0.01)
    (v3 / "meta.json").write_text(json.dumps({"trained_at": "retrained-later"}))   # v3 was retrained
    assert cache.get() is None and "embeddings differ" in cache.reason


# ── flag ─────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("value,expected", [(None, "shadow"), ("", "shadow"), ("off", "off"), ("OFF", "off"),
                                            ("shadow", "shadow"), (" on ", "on"), ("banana", "shadow")])
def test_flag_values(monkeypatch, value, expected):
    if value is None:
        monkeypatch.delenv("HYBRID_ORDER", raising=False)
    else:
        monkeypatch.setenv("HYBRID_ORDER", value)
    assert hs.mode() == expected


class Resp:
    def __init__(self):
        self.closers = []

    def call_on_close(self, fn):
        self.closers.append(fn)


@pytest.fixture
def runner(monkeypatch, model):
    seen = []

    def compute(job, deadline):
        seen.append(job)
        if job.kind == "play":
            return {"rank_v3": 5.0, "rank_blend": 3.0, "rank_hybrid": 2.0, "in_top100": 1, "model_version": "t",
                    "extra_ms": 1.0}
        return {"position_kind": "next", "model_version": "t", "n_allowed": 5, "top_ids": ["id1"], "top_scores": [0.5]}

    r = hs.ShadowRunner(compute)
    monkeypatch.setattr(hs, "_runner", r)
    r.seen = seen
    return r


def test_off_does_nothing_shadow_queues_after_close(monkeypatch, runner):
    q = [{"navidrome_id": "id1"}]
    resp = Resp()
    monkeypatch.setenv("HYBRID_ORDER", "off")
    hs.hook(resp, "u", {"session_id": "s1"}, "sv1", q, "smart", False, None)
    assert resp.closers == []
    monkeypatch.setenv("HYBRID_ORDER", "shadow")
    hs.hook(resp, "u", {"session_id": "s1"}, "sv1", q, "smart", False, None)
    assert len(resp.closers) == 1 and runner.seen == []          # nothing ran before the response closed
    resp.closers[0]()
    assert runner.drain()
    row = rows("u", "hybrid_shadow")[0]
    assert row["status"] == "ok" and row["served_id"] == "sv1" and row["mode"] == "shadow"
    assert json.loads(row["top_ids"]) == ["id1"] and json.loads(row["served_ids"]) == ["id1"]


@pytest.mark.parametrize("mode_used,reshuffle", [("smart_playlist", False), ("smart_trending", False),
                                                 ("random", False), ("smart", True)])
def test_ineligible_requests_are_not_shadowed(runner, mode_used, reshuffle):
    resp = Resp()
    hs.hook(resp, "u", {}, "sv", [], mode_used, reshuffle, None)
    assert resp.closers == []


def test_without_a_compatible_model_nothing_is_queued(monkeypatch):
    monkeypatch.setattr(hs.models, "get", lambda: None)
    resp = Resp()
    hs.hook(resp, "u", {}, "sv", [], "smart", False, None)
    assert resp.closers == [] and hs.stats.snapshot()["next_no_model"] >= 1


def test_next_response_is_the_same_in_off_and_shadow(monkeypatch, runner):
    flask = pytest.importorskip("flask")
    app = flask.Flask("t")
    queue = [{"rank": 1, "title": "A", "navidrome_id": "id1", "scores": {"final": 0.9}}]

    @app.route("/next")
    def nxt():
        q = [dict(x) for x in queue]
        q, engine = hs.maybe_serve(q, "v3", "u", {}, None, "smart", False, 15)
        resp = flask.jsonify({"queue": q, "engine": engine, "served_id": "sv1"})
        hs.hook(resp, "u", {"session_id": "s"}, "sv1", q, "smart", False, None)
        return resp

    c = app.test_client()
    monkeypatch.setenv("HYBRID_ORDER", "off")
    r = c.get("/next")
    off = r.get_data()
    r.close()
    assert runner.drain() and runner.seen == []
    monkeypatch.setenv("HYBRID_ORDER", "shadow")
    r = c.get("/next")
    shadow = r.get_data()
    r.close()
    assert off == shadow
    assert runner.drain() and len(runner.seen) == 1


# ── per play: the flip data ──────────────────────────────────────────────────

def play(eng, runner, i=40, ratio=0.9, user="u", quality=None):
    session = types.SimpleNamespace(ctx=eng.ctx, key="s1")
    now = __import__("datetime").datetime(2026, 11, 23, 12, 0, tzinfo=hs.IST)
    data = {"session_id": "s1", "_played_at": int(now.timestamp()), "_quality": quality}
    hs.play_hook(eng, user, i, session, ratio, now, 12, now, data)
    return runner.drain()


def test_a_kept_next_song_play_is_ranked_before_the_state_learns_it(runner):
    eng = Engine(kept=[1, 2], played=[1, 2])
    assert play(eng, runner)
    assert eng.builds == [2] and len(runner.seen) == 1          # features built once, from the pre-play session
    row = rows("u", "hybrid_shadow_plays")[0]
    assert row["status"] == "ok" and row["song_id"] == "id40" and row["depth"] == 2
    assert (row["rank_v3"], row["rank_blend"], row["rank_hybrid"], row["in_top100"]) == (5.0, 3.0, 2.0, 1)


@pytest.mark.parametrize("kw,reason", [
    (dict(ratio=0.2), "play_skipped_not_scorable"),
    (dict(i=1), "play_skipped_not_scorable"),                   # already heard this session
    (dict(quality="suspect_burst"), "play_skipped_quality"),
    (dict(quality="clock_clamped"), "play_skipped_quality"),
])
def test_plays_that_must_not_be_scored_are_not(runner, kw, reason):
    eng = Engine(kept=[1, 2], played=[1, 2])
    play(eng, runner, **kw)
    assert runner.seen == [] and hs.stats.snapshot()[reason] >= 1 and eng.builds == []


def test_an_opener_is_not_scored(runner):
    eng = Engine(kept=[], played=[])
    play(eng, runner)
    assert runner.seen == [] and eng.builds == []


def test_off_and_a_missing_model_do_nothing_per_play(monkeypatch, runner):
    eng = Engine(kept=[1], played=[1])
    monkeypatch.setenv("HYBRID_ORDER", "off")
    play(eng, runner)
    monkeypatch.setenv("HYBRID_ORDER", "shadow")
    monkeypatch.setattr(hs.models, "get", lambda: None)
    play(eng, runner)
    assert runner.seen == [] and eng.builds == []


def test_the_real_ranks_match_the_harness_formula(model, monkeypatch):
    eng = Engine(kept=[1, 2], played=[1, 2])
    monkeypatch.setattr(hs, "_engine", lambda: eng)
    r = hs.ShadowRunner(hs._engine_compute)
    monkeypatch.setattr(hs, "_runner", r)
    assert play(eng, r, i=40)
    row = rows("u", "hybrid_shadow_plays")[0]
    X = matrix(11)
    hb, M = hs.feature_matrix(eng).build(X, eng.us, [1, 2], 0, 12, 11)
    allowed = np.ones(N, bool)
    allowed[[1, 2]] = False
    ref_h = model.scores(M, hb, allowed)
    ref_v = eng.ranker.predict(X, False)

    def harness_rank(v):
        v = np.where(allowed, v, -np.inf)
        return 1 + float((v > v[40]).sum()) + 0.5 * float((v == v[40]).sum() - 1)

    assert row["rank_hybrid"] == harness_rank(ref_h)
    assert row["rank_blend"] == harness_rank(hb) and row["rank_v3"] == harness_rank(ref_v)
    assert row["in_top100"] == int(40 in H.candidates(hb, allowed))
    assert row["extra_ms"] is not None and row["inline_ms"] is not None


def test_no_more_than_16_play_jobs_hold_matrices():
    r = hs.ShadowRunner(lambda j, d: {}, start=False)
    ok = [r.submit(hs.Job("play", "u", song=1, song_id="id1", played_at=1, session_id="s", depth=1, inline_ms=0,
                          X=None, M=None, hb=None, allowed=None, fm_ms=0)) for _ in range(20)]
    assert ok.count(True) == hs.PLAY_JOBS_MAX and hs.stats.snapshot()["dropped_play_jobs_full"] >= 4


# ── ranking a /next request ──────────────────────────────────────────────────

def test_heard_songs_never_appear_and_the_pool_is_respected(model):
    eng = Engine(kept=[1, 2], played=range(0, 100))
    kind, top, sc, n_allowed = hs.rank_next(eng, model, "u", {}, None, 1.7e9)
    assert kind == "next" and n_allowed == N - 100 and not set(top) & set(range(100)) and len(top) == hs.TOP_N
    pool = {"id%d" % i for i in range(150, 170)}
    _, top2, _, n2 = hs.rank_next(eng, model, "u", {}, pool, 1.7e9)
    assert n2 == 20 and set(top2) <= set(range(150, 170))


def test_opener_kind_and_determinism(model):
    eng = Engine(kept=[], played=[])
    a = hs.rank_next(eng, model, "u", {}, None, 1.7e9)
    b = hs.rank_next(eng, model, "u", {}, None, 1.7e9)
    assert a[0] == "opener" and list(a[1]) == list(b[1]) and list(a[2]) == list(b[2])


def test_nothing_allowed_is_not_an_error(model):
    eng = Engine(kept=[1], played=range(N))
    kind, top, _, n = hs.rank_next(eng, model, "u", {}, None, 1.7e9)
    assert len(top) == 0 and n == 0


# ── failure isolation ────────────────────────────────────────────────────────

def nj(**kw):
    d = dict(session={"session_id": "s1"}, candidates=None, served_id="sv1", session_id="s1", served_ids=["id1"],
             mode="shadow", now_ts=1.7e9)
    d.update(kw)
    return hs.Job("next", "u", **d)


def test_a_failing_compute_is_a_row_not_an_exception():
    def boom(j, d):
        raise ValueError("kaboom " + "x" * 500)

    r = hs.ShadowRunner(boom)
    assert r.submit(nj()) and r.drain()
    row = rows("u", "hybrid_shadow")[0]
    assert row["status"] == "error" and row["error"].startswith("ValueError: kaboom") and len(row["error"]) < 260
    assert r.submit(nj()) and r.drain()                           # the worker is still alive


def test_a_slow_job_misses_the_budget_and_a_stale_one_is_not_run(monkeypatch):
    monkeypatch.setenv("HYBRID_BUDGET_MS", "50")
    r = hs.ShadowRunner(lambda j, d: (time.sleep(0.12), {"position_kind": "next"})[1])
    r.submit(nj())
    assert r.drain()
    assert rows("u", "hybrid_shadow")[0]["error"].startswith("budget")
    ran = []
    r2 = hs.ShadowRunner(lambda j, d: ran.append(1) or {}, start=False)
    r2.submit(nj(session_id="stale"))
    time.sleep(0.12)
    r2.start()
    assert r2.drain() and ran == [] and rows("u", "hybrid_shadow")[-1]["error"].startswith("stale")


def test_a_full_queue_drops_and_never_blocks():
    r = hs.ShadowRunner(lambda j, d: {}, maxsize=2, start=False)
    t0 = time.time()
    results = [r.submit(nj()) for _ in range(5)]
    assert results == [True, True, False, False, False] and time.time() - t0 < 0.5


def test_a_failing_write_never_raises(monkeypatch):
    monkeypatch.setattr(feedback, "get_db_path", lambda u: "/nonexistent-dir/\0/x.db")
    assert hs.write_row("u", {"status": "ok"}) is False
    r = hs.ShadowRunner(lambda j, d: {})
    r.submit(nj())
    assert r.drain()


def test_hooks_survive_garbage(monkeypatch, model):
    monkeypatch.setenv("HYBRID_ORDER", "on")
    hs.hook(object(), "u", None, None, None, "smart", False, None)           # no call_on_close
    hs.play_hook(object(), "u", 1, object(), 0.9, None, 12, None, None)        # nothing the hook expects
    q = [{"navidrome_id": "id1"}]
    monkeypatch.setattr(hs, "_engine", lambda: (_ for _ in ()).throw(RuntimeError("engine down")))
    assert hs.maybe_serve(q, "v3", "u", {}, None, "smart", False, 15) == (q, "v3")
    assert hs.stats.snapshot()["play_hook_failed"] >= 1


# ── serving (on) ─────────────────────────────────────────────────────────────

def v3_queue():
    q = [{"rank": i + 1, "title": "T%d" % i, "navidrome_id": "id%d" % i, "scores": {"final": 1.0 - i / 100.0},
          "why": "v3 why"} for i in range(5)]
    q[0]["_context_meta"] = {"bucket": "b"}
    return q


def test_on_serves_hybrid_order_for_next_positions_only(monkeypatch, model):
    monkeypatch.setenv("HYBRID_ORDER", "on")
    monkeypatch.setattr(hs, "_engine", lambda: Engine(kept=[1], played=[]))
    q, engine = hs.maybe_serve(v3_queue(), "v3+memory", "u", {}, None, "smart", False, 8)
    assert engine == "v3+hybrid" and len(q) == 8 and [e["rank"] for e in q] == list(range(1, 9))
    assert all({"navidrome_id", "title", "scores"} <= set(e) for e in q) and q[0]["_context_meta"] == {"bucket": "b"}
    original = v3_queue()
    monkeypatch.setattr(hs, "_engine", lambda: Engine(kept=[], played=[]))
    assert hs.maybe_serve(original, "v3", "u", {}, None, "smart", False, 8) == (original, "v3")     # opener
    monkeypatch.setattr(hs, "_engine", lambda: Engine(kept=[1], played=[]))
    monkeypatch.setattr(hs.models, "get", lambda: None)
    assert hs.maybe_serve(original, "v3", "u", {}, None, "smart", False, 8) == (original, "v3")     # no model


@pytest.mark.parametrize("m", ["off", "shadow"])
def test_off_and_shadow_never_change_the_queue(monkeypatch, model, m):
    monkeypatch.setenv("HYBRID_ORDER", m)
    monkeypatch.setattr(hs, "_engine", lambda: Engine(kept=[1], played=[]))
    original = v3_queue()
    out, engine = hs.maybe_serve(original, "v3", "u", {}, None, "smart", False, 8)
    assert out is original and engine == "v3"


# ── the nightly fit ──────────────────────────────────────────────────────────

class Ev:
    def __init__(self, ts, user="u", song="good", source="live", raw="", skipped=False):
        self.ts, self.user, self.song, self.source = ts, user, song, source
        self.session_raw, self.skipped, self.hour, self.month = raw, skipped, 12, 11


class Replay:
    def __init__(self, eng, best, worst):
        index = {n: best for n in ("good", "bad", "imp", "apple", "old")}
        index["miss"] = worst
        self.cat = types.SimpleNamespace(index=index)
        self.eng, self.applied = eng, []
        self.sess = types.SimpleNamespace(ctx=Ctx(kept=[3], played=set()))

    def maybe_refit(self, t):
        pass

    def session_for(self, e):
        return self.sess

    def features(self, e, s):
        return matrix(5)

    def user(self, u):
        return self.eng.us

    def apply(self, e, s):
        self.applied.append(e)


def test_groups_follow_the_recipe_and_exclusions():
    eng = Engine()
    fm = H.FeatureMatrix(eng.cat, eng.A)
    hb, _ = fm.build(matrix(5), eng.us, [3], 1.0, 12, 11)
    best = int(H.candidates(hb, np.ones(N, bool))[0])
    worst = int(np.argsort(hb)[0])                       # a play the blend does not have in its top 100
    rep = Replay(eng, best, worst)
    events = [Ev(1000), Ev(1001, song="bad"), Ev(1002, song="imp", raw="import:spotify"),
              Ev(1003, song="apple", source="apple"), Ev(10, song="old"), Ev(1004, song="miss")]
    groups, counts = ht.collect_groups(events, rep, fm, {"u": {1001}}, since_ts=500)
    assert counts["groups"] == 1 and counts["excluded"] == 3 and counts["missed"] == 1 and counts["targets"] == 5
    assert len(rep.applied) == 6                          # every event still updates the state
    X0, y0 = groups[0]
    assert len(y0) == H.N_CAND and y0.sum() == 1 and X0.shape[1] == len(H.ALL_COLS)   # never forced in


def test_the_fit_is_deterministic(reranker):
    assert fitted().model.model_to_string() == reranker.model.model_to_string()


def test_a_log_from_before_the_data_pipeline_is_used_as_it_is(tmp_path):
    p = feedback.get_db_path("old")
    feedback.init_db("old")
    assert ht.tagged_timestamps(p) == set()
    c = sqlite3.connect(p)
    c.execute("ALTER TABLE play_events ADD COLUMN quality TEXT")
    for t, q in ((111, "suspect_burst"), (222, None), (333, "synthetic_time"), (444, "clock_clamped")):
        c.execute("INSERT INTO play_events(track_title, played_at, quality) VALUES ('a', ?, ?)", (t, q))
    c.commit()
    c.close()
    assert ht.tagged_timestamps(p) == {111, 333, 444}
    assert ht.tagged_timestamps(str(tmp_path / "missing.db")) == set()
    assert ht.usable_as_target(types.SimpleNamespace(ts=5, user="u", source="live", skipped=False), {}) is True


# ── tables ───────────────────────────────────────────────────────────────────

def test_shadow_tables_work_on_an_old_log_and_are_erased_with_the_history():
    feedback.init_db("legacy")
    assert hs.write_row("legacy", {"status": "ok", "served_id": "x", "top_ids": ["a"]}) is True
    assert hs.write_row("legacy", {"status": "ok", "song_id": "id1", "rank_hybrid": 2.0}, "hybrid_shadow_plays") is True
    c = sqlite3.connect(feedback.get_db_path("legacy"))
    assert hs.erase_tables(c) == 2
    c.commit()
    assert c.execute("SELECT COUNT(*) FROM hybrid_shadow").fetchone()[0] == 0
    c.close()


# ── the whole nightly fit, end to end (the code `python -m navivibe.hybrid_train` runs) ───────────

class _World:
    """Stands in for the catalog store, the event loader and the replay (they need the real server)."""

    def __init__(self, n_events):
        self.eng = Engine()
        rng = np.random.default_rng(9)
        now = time.time()
        self.events = [Ev(now - 3600 + k, song="s%d" % k) for k in range(n_events)]
        self.songs = {"s%d" % k: int(rng.integers(N)) for k in range(n_events)}


def _install_world(monkeypatch, world):
    cat = types.ModuleType("navivibe.recsys.data")
    cat.Catalog = types.SimpleNamespace(from_rows=lambda rows: world.eng.cat)
    cat.load_all = lambda catalog: (world.events, {})
    rep = types.ModuleType("navivibe.recsys.train")

    class R(Replay):
        def __init__(self, catalog, arrays, fb, history=None):
            super().__init__(world.eng, 0, 0)
            self.cat = types.SimpleNamespace(index=world.songs)

        def features(self, e, s):
            return matrix(abs(hash(e.song)) % 1000)

    rep.Replay = R
    rep.ARTIFACT_DIR = "/nonexistent"
    cs = types.ModuleType("navivibe.catalog.store")
    cs.load_catalog = lambda: []
    pkg = types.ModuleType("navivibe.catalog")
    for name, mod in (("navivibe.recsys.data", cat), ("navivibe.recsys.train", rep),
                      ("navivibe.catalog", pkg), ("navivibe.catalog.store", cs)):
        monkeypatch.setitem(__import__("sys").modules, name, mod)
    monkeypatch.setattr(ht, "build_world", lambda catalog: (world.eng.A, types.SimpleNamespace()))
    monkeypatch.setattr(store, "v3_trained_at", lambda d=None: V3)


def test_the_nightly_fit_writes_a_model_the_server_will_accept(tmp_path, monkeypatch, capsys):
    _install_world(monkeypatch, _World(900))
    out = str(tmp_path / "hybrid" / "hybrid_v1.json")
    assert ht.main(["--out", out]) == 0
    printed = json.loads(capsys.readouterr().out)
    assert printed["status"] == "ok" and printed["metrics"]["groups_used"] >= ht.MIN_GROUPS
    cache = hs.ModelCache(out, str(tmp_path / "v3"))
    (tmp_path / "v3").mkdir()
    (tmp_path / "v3" / "meta.json").write_text(json.dumps({"trained_at": V3}))
    assert cache.get() is not None and cache.reason == "ok"          # compatible with the v3 it was fitted against
    again = ht.train(out)
    assert again["model_version"] == printed["model_version"]         # deterministic: same data, same model


def test_too_little_data_replaces_nothing_and_still_exits_zero(tmp_path, monkeypatch, capsys):
    _install_world(monkeypatch, _World(30))
    out = tmp_path / "hybrid_v1.json"
    out.write_text("previous")
    assert ht.main(["--out", str(out)]) == 0
    assert json.loads(capsys.readouterr().out)["status"] == "not_enough_data" and out.read_text() == "previous"


def test_a_failure_exits_one_with_json(tmp_path, monkeypatch, capsys):
    _install_world(monkeypatch, _World(10))
    monkeypatch.setattr(ht, "build_world", lambda c: (_ for _ in ()).throw(RuntimeError("no artifacts")))
    assert ht.main(["--out", str(tmp_path / "m.json")]) == 1
    assert json.loads(capsys.readouterr().out)["status"] == "error"
