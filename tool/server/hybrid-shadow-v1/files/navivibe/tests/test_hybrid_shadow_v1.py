"""hybrid-shadow-v1 tests. Run from the shuffle-server root:
    PYTHONPATH=. venv/bin/python -m pytest navivibe/tests/test_hybrid_shadow_v1.py -q
No real engine, no real logs: a tiny fake engine and a temp log folder."""
import json
import sqlite3
import sys
import threading
import time
import types

import numpy as np
import pytest

from navivibe import feedback, hybrid_core as core, hybrid_shadow as hs, hybrid_train as ht

NAMES = ["cnt_2d", "cnt_7d", "cnt_30d", "cnt_180d", "rot_share_2d", "hour_affinity", "p_next",
         "p_next2", "co_last", "pop_global"]
F = {n: i for i, n in enumerate(NAMES)}
N = 300


@pytest.fixture(autouse=True)
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(feedback, "DB_DIR", str(tmp_path))
    monkeypatch.delenv("HYBRID_ORDER", raising=False)
    monkeypatch.delenv("HYBRID_BUDGET_MS", raising=False)
    hs.reset_ready_cache()
    pkg = types.ModuleType("navivibe.recsys")
    feats = types.ModuleType("navivibe.recsys.features")
    feats.F, feats.FEATURES = F, NAMES
    monkeypatch.setitem(sys.modules, "navivibe.recsys", pkg)
    monkeypatch.setitem(sys.modules, "navivibe.recsys.features", feats)
    yield tmp_path
    hs.reset_ready_cache()


def matrix(seed=1, n=N):
    return np.random.default_rng(seed).random((n, len(NAMES))).astype(np.float32)


def groups_from(n_groups, seed=3):
    """Synthetic groups whose true song tends to have a high p_next: learnable."""
    rng = np.random.default_rng(seed)
    out = []
    while len(out) < n_groups:
        X = rng.random((N, len(NAMES))).astype(np.float32)
        pos = int(rng.integers(N))
        X[pos, F["p_next"]] += 1.5 * rng.random()
        X[pos, F["cnt_7d"]] += 0.6
        g = core.make_group(X, F, pos, np.ones(N, bool), None, opener=False)
        if g is not None:
            out.append(g)
    return out


# ── fake engine ──────────────────────────────────────────────────────────────

class Ctx:
    def __init__(self, kept=(), played=()):
        self.kept, self.played = list(kept), set(played)


class Cat:
    def __init__(self, ids):
        self.ids = ids
        self.index = {s: i for i, s in enumerate(ids)}
        self.meta = {s: {"title": "T" + s, "artist": "A", "album": "B", "path": "/m/%s" % s} for s in ids}

    def __len__(self):
        return len(self.ids)


class FakeEngine:
    def __init__(self, kept=(), played=()):
        self.ids = ["id%d" % i for i in range(N)]
        self.cat = Cat(self.ids)
        self.ctx = Ctx(kept, played)
        self.fb = types.SimpleNamespace(build=lambda us, gs, ctx, t, h, w: matrix(7))
        self.gs = None
        self._lock = threading.RLock()
        self.builds = 0

    def _lock_for(self, u):
        return self._lock

    def _user(self, u):
        return object()

    def _session_ctx(self, u, session):
        return self.ctx

    def _resolve_titles(self, titles):
        return [self.cat.index[t] for t in titles if t in self.cat.index]


def job(user="u", **kw):
    d = dict(user=user, session={"session_id": "s1", "played_titles": []}, candidates=None, served_id="sv1",
             session_id="s1", served_ids=["id1", "id2"], mode="shadow", queued_at=0.0, now_ts=1_700_000_000.0, n=20)
    d.update(kw)
    return hs.Job(**d)


def shadow_rows(user="u"):
    c = sqlite3.connect(feedback.get_db_path(user))
    c.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in c.execute("SELECT * FROM hybrid_shadow ORDER BY id")]
    finally:
        c.close()


# ── core: determinism and shape ──────────────────────────────────────────────

def test_blend_and_candidates_are_deterministic_with_ties_to_the_lower_index():
    X = matrix()
    X[:, F["cnt_7d"]] = 1.0                         # a tie everywhere on one signal
    allowed = np.ones(N, bool)
    a = core.top_k(core.blend_score(X, F, None, allowed), allowed)
    b = core.top_k(core.blend_score(X, F, None, allowed), allowed)
    assert list(a) == list(b) and len(a) == core.K_CANDIDATES
    flat = np.zeros(N)
    assert list(core.top_k(flat, allowed, 5)) == [0, 1, 2, 3, 4]


def test_a_missed_positive_makes_no_group():
    X = matrix()
    allowed = np.ones(N, bool)
    worst = int(core.top_k(core.blend_score(X, F, None, allowed), allowed, N)[-1])
    assert core.make_group(X, F, worst, allowed, None, False) is None


def test_fit_is_deterministic_and_reports_metrics():
    g = groups_from(260)
    b1, m1 = core.fit(g, NAMES)
    b2, m2 = core.fit(g, NAMES)
    assert b1.model_to_string() == b2.model_to_string()
    assert m1["groups"] == 260 and {"val_hr10_hybrid", "val_hr10_blend", "rounds"} <= set(m1)
    assert m1["rounds"] >= core.MIN_ROUNDS


def test_too_little_data_fits_nothing():
    assert core.fit(groups_from(core.MIN_GROUPS - 1), NAMES) is None


def test_model_file_is_atomic_versioned_and_keeps_the_previous_one(tmp_path):
    g = groups_from(240)
    booster, metrics = core.fit(g, NAMES)
    p = str(tmp_path / "m" / "hybrid_v1.json")
    meta1 = core.save_model(p, booster, metrics, NAMES)
    assert meta1["version"] and meta1["blend_version"] == core.BLEND_VERSION and meta1["metrics"]["groups"] == 240
    m = core.load_model(p)
    X = matrix(11)
    allowed = np.ones(N, bool)
    top1, _ = m.rank(X, F, allowed, False)
    core.save_model(p, booster, metrics, NAMES)
    assert (tmp_path / "m" / "hybrid_v1.json.prev").exists()
    assert not (tmp_path / "m" / "hybrid_v1.json.tmp").exists()
    top2, _ = core.load_model(p).rank(X, F, allowed, False)
    assert list(top1) == list(top2)


def test_unreadable_or_missing_model_loads_as_none(tmp_path):
    assert core.load_model(str(tmp_path / "nope.json")) is None
    bad = tmp_path / "bad.json"
    bad.write_text("{not json")
    assert core.load_model(str(bad)) is None


def test_rank_excludes_what_is_not_allowed():
    booster, metrics = core.fit(groups_from(240), NAMES)
    model = core.HybridModel(booster, {"version": "v", "blend": core.DEFAULT_BLEND})
    X = matrix()
    allowed = np.ones(N, bool)
    allowed[:150] = False
    top, _ = model.rank(X, F, allowed, False, n=20)
    assert len(top) == 20 and all(i >= 150 for i in top)


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
    """The one thing the hook needs from a Flask response."""
    def __init__(self):
        self.closers = []

    def call_on_close(self, fn):
        self.closers.append(fn)


@pytest.fixture
def runner(monkeypatch):
    seen = []

    def compute(j, deadline):
        seen.append(j)
        return {"position_kind": "next", "model_version": "t", "blend_version": "b", "n_allowed": 5,
                "top_ids": ["id1"], "top_scores": [0.5]}

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
    assert len(runner.seen) == 1
    rows = shadow_rows()
    assert rows[0]["status"] == "ok" and rows[0]["served_id"] == "sv1" and rows[0]["mode"] == "shadow"
    assert json.loads(rows[0]["top_ids"]) == ["id1"] and json.loads(rows[0]["served_ids"]) == ["id1"]


@pytest.mark.parametrize("mode_used,reshuffle", [("smart_playlist", False), ("smart_trending", False),
                                                 ("random", False), ("smart", True)])
def test_ineligible_requests_are_not_shadowed(runner, mode_used, reshuffle):
    resp = Resp()
    hs.hook(resp, "u", {}, "sv", [], mode_used, reshuffle, None)
    assert resp.closers == []


def test_candidates_mode_is_shadowed_with_its_pool(runner):
    resp = Resp()
    hs.hook(resp, "u", {"session_id": "s"}, "sv", [], "smart_candidates", False, {"id3", "id4"})
    resp.closers[0]()
    runner.drain()
    assert runner.seen[0].candidates == {"id3", "id4"}


# ── /next in shadow mode is byte-identical ───────────────────────────────────

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
    r.close()                       # a WSGI server closes the response once the body is sent
    assert runner.drain() and runner.seen == []
    monkeypatch.setenv("HYBRID_ORDER", "shadow")
    r = c.get("/next")
    shadow = r.get_data()
    r.close()
    assert off == shadow
    assert runner.drain()
    assert len(runner.seen) == 1                                 # the shadow ran, after the response


# ── ranking a request ────────────────────────────────────────────────────────

def test_heard_songs_never_appear_and_the_candidate_pool_is_respected():
    eng = FakeEngine(kept=[1, 2], played=range(0, 120))
    booster, _ = core.fit(groups_from(240), NAMES)
    model = core.HybridModel(booster, {"version": "vv", "blend": core.DEFAULT_BLEND})
    kind, top, sc, n_allowed, version, _ = hs.rank_for_job(eng, model, job(), F=F)
    assert kind == "next" and version == "vv" and n_allowed == N - 120
    assert not set(top) & set(range(120))
    pool = {"id%d" % i for i in range(130, 150)}
    _, top2, _, n2, _, _ = hs.rank_for_job(eng, model, job(candidates=pool), F=F)
    assert n2 == 20 and set(top2) <= set(range(130, 150)) and len(top2) == 20


def test_an_empty_session_is_an_opener_and_no_model_records_the_blend():
    eng = FakeEngine(kept=[], played=[])
    kind, top, sc, n_allowed, version, bver = hs.rank_for_job(eng, None, job(), F=F)
    assert kind == "opener" and version == "blend-only" and len(top) == hs.TOP_N and bver == core.BLEND_VERSION


def test_nothing_allowed_is_not_an_error():
    eng = FakeEngine(kept=[1], played=range(N))
    kind, top, _, n_allowed, version, _ = hs.rank_for_job(eng, None, job(), F=F)
    assert len(top) == 0 and n_allowed == 0 and version == "none"


def test_ranking_is_deterministic():
    eng = FakeEngine(kept=[1], played=[5])
    a = hs.rank_for_job(eng, None, job(), F=F)
    b = hs.rank_for_job(eng, None, job(), F=F)
    assert list(a[1]) == list(b[1]) and list(a[2]) == list(b[2])


# ── failure isolation ────────────────────────────────────────────────────────

def test_a_failing_compute_is_a_row_not_an_exception():
    def boom(j, d):
        raise ValueError("kaboom " + "x" * 500)

    r = hs.ShadowRunner(boom)
    assert r.submit(job()) is True
    assert r.drain()
    row = shadow_rows()[0]
    assert row["status"] == "error" and row["error"].startswith("ValueError: kaboom") and len(row["error"]) < 260
    assert hs.stats.snapshot().get("error_exception", 0) >= 1
    assert r.submit(job()) and r.drain()                          # the worker is still alive


def test_a_slow_job_misses_the_budget_and_is_recorded(monkeypatch):
    monkeypatch.setenv("HYBRID_BUDGET_MS", "50")
    r = hs.ShadowRunner(lambda j, d: (time.sleep(0.12), {"position_kind": "next"})[1])
    r.submit(job())
    assert r.drain()
    row = shadow_rows()[0]
    assert row["status"] == "error" and row["error"].startswith("budget")


def test_a_job_that_waited_too_long_in_the_queue_is_not_run(monkeypatch):
    monkeypatch.setenv("HYBRID_BUDGET_MS", "100")
    ran = []
    r = hs.ShadowRunner(lambda j, d: ran.append(1) or {}, start=False)
    r.submit(job())
    time.sleep(0.2)
    r.start()
    assert r.drain()
    assert ran == [] and shadow_rows()[0]["error"].startswith("stale")


def test_a_full_queue_drops_and_counts_and_never_blocks():
    r = hs.ShadowRunner(lambda j, d: {}, maxsize=2, start=False)
    t0 = time.time()
    results = [r.submit(job()) for _ in range(5)]
    assert results == [True, True, False, False, False] and time.time() - t0 < 0.5
    assert hs.stats.snapshot()["dropped_queue_full"] >= 3


def test_a_failing_database_write_never_raises(monkeypatch):
    monkeypatch.setattr(feedback, "get_db_path", lambda u: "/nonexistent-dir/\0/x.db")
    assert hs.write_row("u", {"status": "ok"}) is False
    r = hs.ShadowRunner(lambda j, d: {})
    r.submit(job())
    assert r.drain()                                              # the worker survived


def test_hook_and_serve_survive_garbage(monkeypatch):
    monkeypatch.setenv("HYBRID_ORDER", "on")
    hs.hook(object(), "u", None, None, None, "smart", False, None)       # no call_on_close at all
    q = [{"navidrome_id": "id1"}]
    monkeypatch.setattr(hs, "_engine", lambda: (_ for _ in ()).throw(RuntimeError("engine down")))
    assert hs.maybe_serve(q, "v3", "u", {}, None, "smart", False, 15) == (q, "v3")


# ── serving (on) ─────────────────────────────────────────────────────────────

@pytest.fixture
def served(monkeypatch):
    booster, _ = core.fit(groups_from(240), NAMES)
    model = core.HybridModel(booster, {"version": "vv", "blend": core.DEFAULT_BLEND})
    monkeypatch.setattr(hs.models, "get", lambda: model)
    return model


def v3_queue():
    q = [{"rank": i + 1, "title": "T%d" % i, "navidrome_id": "id%d" % i, "scores": {"final": 1.0 - i / 100.0},
          "why": "v3 why"} for i in range(5)]
    q[0]["_context_meta"] = {"bucket": "b"}
    return q


def test_on_serves_hybrid_order_for_next_positions_only(monkeypatch, served):
    monkeypatch.setenv("HYBRID_ORDER", "on")
    monkeypatch.setattr(hs, "_engine", lambda: FakeEngine(kept=[1], played=[]))
    q, engine = hs.maybe_serve(v3_queue(), "v3+memory", "u", {}, None, "smart", False, 8)
    assert engine == "v3+hybrid" and len(q) == 8
    assert [e["rank"] for e in q] == list(range(1, 9))
    assert all("navidrome_id" in e and "title" in e and "scores" in e for e in q)
    assert q[0].get("_context_meta") == {"bucket": "b"}           # the route still finds its metadata


def test_on_keeps_v3_for_openers_and_when_no_model(monkeypatch, served):
    monkeypatch.setenv("HYBRID_ORDER", "on")
    original = v3_queue()
    monkeypatch.setattr(hs, "_engine", lambda: FakeEngine(kept=[], played=[]))
    assert hs.maybe_serve(original, "v3", "u", {}, None, "smart", False, 8) == (original, "v3")
    monkeypatch.setattr(hs, "_engine", lambda: FakeEngine(kept=[1], played=[]))
    monkeypatch.setattr(hs.models, "get", lambda: None)
    assert hs.maybe_serve(original, "v3", "u", {}, None, "smart", False, 8) == (original, "v3")


@pytest.mark.parametrize("m", ["off", "shadow"])
def test_off_and_shadow_never_change_the_queue(monkeypatch, served, m):
    monkeypatch.setenv("HYBRID_ORDER", m)
    monkeypatch.setattr(hs, "_engine", lambda: FakeEngine(kept=[1], played=[]))
    original = v3_queue()
    out, engine = hs.maybe_serve(original, "v3", "u", {}, None, "smart", False, 8)
    assert out is original and engine == "v3"


# ── the nightly fit: what is excluded, old rows ──────────────────────────────

class Ev:
    def __init__(self, ts, user="u", song="id1", source="live", raw="", skipped=False):
        self.ts, self.user, self.song, self.source = ts, user, song, source
        self.session_raw, self.skipped = raw, skipped


class FakeReplay:
    def __init__(self):
        self.cat = types.SimpleNamespace(index={"id1": 1, "id2": 2})
        self.applied = []
        self.sess = types.SimpleNamespace(ctx=Ctx(kept=[3], played=set()))

    def maybe_refit(self, t):
        pass

    def session_for(self, e):
        return self.sess

    def features(self, e, s):
        return matrix(5)

    def apply(self, e, s):
        self.applied.append(e)


def test_training_skips_tagged_imported_and_history_rows_but_still_replays_them():
    rep = FakeReplay()
    X = matrix(5)
    allowed = np.ones(N, bool)
    best = int(core.top_k(core.blend_score(X, F, None, allowed), allowed)[0])
    rep.cat.index = {"good": best, "bad": best, "imp": best, "apple": best, "old": best}
    events = [Ev(1000, song="good"), Ev(1001, song="bad"), Ev(1002, song="imp", raw="import:spotify"),
              Ev(1003, song="apple", source="apple"), Ev(10, song="old")]
    groups, counts = ht.collect_groups(events, rep, F, {"u": {1001}}, since_ts=500)
    assert counts["groups"] == 1 and counts["excluded"] == 3 and counts["targets"] == 4
    assert len(rep.applied) == 5                                  # every event still updates the state


def test_a_log_from_before_the_data_pipeline_is_used_as_it_is(tmp_path):
    p = feedback.get_db_path("old")
    feedback.init_db("old")
    assert ht.tagged_timestamps(p) == set()                       # no `quality` column: nothing tagged
    c = sqlite3.connect(p)
    c.execute("ALTER TABLE play_events ADD COLUMN quality TEXT")
    c.execute("INSERT INTO play_events(track_title, played_at, quality) VALUES ('a', 111, 'suspect_burst')")
    c.execute("INSERT INTO play_events(track_title, played_at, quality) VALUES ('b', 222, NULL)")
    c.execute("INSERT INTO play_events(track_title, played_at, quality) VALUES ('c', 333, 'synthetic_time')")
    c.commit()
    c.close()
    assert ht.tagged_timestamps(p) == {111, 333}
    assert ht.tagged_timestamps(str(tmp_path / "missing.db")) == set()


def test_old_event_objects_without_session_raw_do_not_break_the_filter():
    e = types.SimpleNamespace(ts=5, user="u", source="live", skipped=False)
    assert ht.usable_as_target(e, {}) is True


def test_shadow_table_survives_a_log_without_any_new_columns():
    """An old listening log (no play-events-v2 columns) still takes shadow rows."""
    feedback.init_db("legacy")
    assert hs.write_row("legacy", {"status": "ok", "served_id": "x", "top_ids": ["a"]}) is True
    assert shadow_rows("legacy")[0]["served_id"] == "x"
