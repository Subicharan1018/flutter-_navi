"""hybrid-shadow-v1, the runtime: flag, two shadow logs, optional serving.

HYBRID_ORDER = off | shadow | on        (default shadow; anything else counts as shadow)
  off     nothing runs.
  shadow  `/next` returns exactly what it returned before. The hybrid (blend top-100 -> LightGBM
          re-ranker, the harness code in navivibe/hybrid.py) is scored in two places, both off the
          listener's path, both written to the listener's own log database:
            hybrid_shadow_plays  one row per kept next-song play, written when its feedback
                                 arrives and BEFORE the state learns it: the rank v3, the blend
                                 and the hybrid gave the song that was really played. This is
                                 what the flip decision uses (docs/hybrid-shadow-spec.md).
            hybrid_shadow        one row per eligible /next request: the hybrid's top 20 beside
                                 the ids that were served (latency and structure; not for the flip).
  on      like shadow, and ALSO next-song positions (the session already has a kept song) are
          served in the hybrid's order, engine `v3+hybrid`. Openers stay on v3. No model or any
          error: the v3 queue is served unchanged.

Independent of AI_ORDER.

Rules this module keeps
  * The listener never waits for a ranking. /next: queued from `Response.call_on_close`.
    /feedback: the one thing done inline is building the feature matrices from the state as it
    is BEFORE the play is learned (it cannot be done later); the ranking itself runs in the worker.
  * One worker thread, a bounded queue (64 jobs, at most 16 holding matrices), a time budget per
    job (HYBRID_BUDGET_MS, default 2000). A miss or a failure is a row with status 'error';
    nothing is raised into a request. Everything is counted in `stats`.
  * The model is used only when compatible (see hybrid_store.incompatible); otherwise shadow
    stays off and `stats` says why.
"""
import json
import os
import queue
import threading
import time
from datetime import datetime
from zoneinfo import ZoneInfo

import numpy as np

from navivibe import hybrid as H
from navivibe import hybrid_store as store

IST = ZoneInfo("Asia/Kolkata")
MODES = ("off", "shadow", "on")
ELIGIBLE_MODES = ("smart", "smart_candidates")
TOP_N = int(float(os.getenv("HYBRID_TOP_N", "20")))
QUEUE_MAX = 64
PLAY_JOBS_MAX = 16
SERVED_KEEP = 20
MIN_RATIO = 0.3               # a play below this is a skip: not scored (spec)

MODEL_PATH = os.getenv("HYBRID_MODEL_PATH", "/opt/shuffle-server/models/hybrid/hybrid_v1.json")

_SCHEMA = """
CREATE TABLE IF NOT EXISTS hybrid_shadow (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at INTEGER NOT NULL,
    served_id TEXT, user TEXT, session_id TEXT, position_kind TEXT, mode TEXT,
    model_version TEXT, status TEXT NOT NULL, error TEXT,
    top_ids TEXT, top_scores TEXT, n_allowed INTEGER, served_ids TEXT,
    latency_ms INTEGER, queue_wait_ms INTEGER
);
CREATE INDEX IF NOT EXISTS idx_hybrid_shadow_served ON hybrid_shadow(served_id);
CREATE TABLE IF NOT EXISTS hybrid_shadow_plays (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at INTEGER NOT NULL,
    played_at INTEGER,
    user TEXT, session_id TEXT, song_id TEXT, depth INTEGER,
    rank_v3 REAL, rank_blend REAL, rank_hybrid REAL, in_top100 INTEGER,
    model_version TEXT, mode TEXT, status TEXT NOT NULL, error TEXT,
    extra_ms REAL, inline_ms REAL, queue_wait_ms INTEGER
);
CREATE INDEX IF NOT EXISTS idx_hybrid_shadow_plays_time ON hybrid_shadow_plays(played_at);
"""
TABLES = {
    "hybrid_shadow": ["created_at", "served_id", "user", "session_id", "position_kind", "mode", "model_version",
                      "status", "error", "top_ids", "top_scores", "n_allowed", "served_ids", "latency_ms",
                      "queue_wait_ms"],
    "hybrid_shadow_plays": ["created_at", "played_at", "user", "session_id", "song_id", "depth", "rank_v3",
                            "rank_blend", "rank_hybrid", "in_top100", "model_version", "mode", "status", "error",
                            "extra_ms", "inline_ms", "queue_wait_ms"],
}
JSON_COLS = {"top_ids", "top_scores", "served_ids"}


def mode():
    v = (os.getenv("HYBRID_ORDER") or "shadow").strip().lower()
    return v if v in MODES else "shadow"


def budget_ms():
    try:
        return max(50, int(float(os.getenv("HYBRID_BUDGET_MS", "2000"))))
    except ValueError:
        return 2000


class BudgetExceeded(Exception):
    pass


class Stats:
    def __init__(self):
        self._lock = threading.Lock()
        self.c = {}

    def add(self, key, n=1):
        with self._lock:
            self.c[key] = self.c.get(key, 0) + n

    def snapshot(self):
        with self._lock:
            return dict(self.c)


stats = Stats()
_ready, _ready_lock = set(), threading.Lock()


def ensure_tables(username):
    from navivibe import feedback
    path = feedback.get_db_path(username)
    with _ready_lock:
        if path in _ready:
            return path
        os.makedirs(os.path.dirname(path), exist_ok=True)
        conn = feedback._connect(path)
        try:
            conn.executescript(_SCHEMA)
            conn.commit()
        finally:
            conn.close()
        _ready.add(path)
    return path


def reset_ready_cache():
    with _ready_lock:
        _ready.clear()


def write_row(username, row, table="hybrid_shadow"):
    """One INSERT in its own short transaction. True on success; never raises."""
    try:
        from navivibe import feedback
        path = ensure_tables(username)
        cols = TABLES[table]
        vals = []
        for c in cols:
            v = row.get(c)
            if c == "user":
                v = username
            elif c == "created_at":
                v = int(v or time.time())
            elif c in JSON_COLS and v is not None:
                v = json.dumps(v)
            vals.append(v)
        conn = feedback._connect(path)
        try:
            conn.execute("INSERT INTO %s(%s) VALUES (%s)" % (table, ",".join(cols), ",".join("?" * len(cols))), vals)
            conn.commit()
        finally:
            conn.close()
        return True
    except Exception as e:  # noqa: BLE001
        stats.add("write_failed")
        print("[hybrid-shadow] could not write a row: %s: %s" % (type(e).__name__, e))
        return False


def erase_tables(conn):
    """For DELETE /me/history: the shadow rows are listening data too."""
    n = 0
    for t in TABLES:
        try:
            n += conn.execute("DELETE FROM %s" % t).rowcount or 0
        except Exception:  # noqa: BLE001 - table not there
            pass
    return n


# ── model ─────────────────────────────────────────────────────────────────────

class ModelCache:
    """(Reranker, meta) when a compatible model exists, else None. Re-checked when the model file
    or the v3 artifacts change on disk (stat only, no parsing on a request)."""

    def __init__(self, path=None, v3_dir=None):
        self.path, self.v3_dir = path, v3_dir
        self._lock = threading.Lock()
        self._key = None
        self._val = None
        self.reason = "not loaded"

    def _v3_meta_path(self):
        from navivibe.recsys.train import ARTIFACT_DIR
        return os.path.join(self.v3_dir or ARTIFACT_DIR, "meta.json")

    def get(self):
        path = self.path or MODEL_PATH
        try:
            key = (os.stat(path).st_mtime_ns, os.stat(self._v3_meta_path()).st_mtime_ns)
        except OSError:
            self._key, self._val, self.reason = None, None, "no model file or no v3 artifacts"
            return None
        with self._lock:
            if key != self._key:
                self._key = key
                self._val = None
                rr, meta = store.load(path)
                if rr is None:
                    self.reason = meta
                else:
                    why = store.incompatible(meta, store.v3_trained_at(self.v3_dir))
                    if why:
                        self.reason = why
                    else:
                        self._val, self.reason = (rr, meta), "ok"
                        print("[hybrid-shadow] model %s loaded (%s)" % (meta["version"], meta["trained_at"]))
                if self._val is None:
                    stats.add("model_not_usable")
                    print("[hybrid-shadow] shadow stays off: %s" % self.reason)
            return self._val


models = ModelCache()
_fm_cache = {}


def feature_matrix(eng):
    """The harness's FeatureMatrix for this engine (rebuilt when the engine is reloaded)."""
    key = id(eng)
    fm = _fm_cache.get(key)
    if fm is None:
        _fm_cache.clear()
        fm = _fm_cache[key] = H.FeatureMatrix(eng.cat, eng.A)
    return fm


# ── ranking helpers ───────────────────────────────────────────────────────────

def allowed_mask(eng, user, ctx, candidates=None):
    """The songs the live ranker may pick: same rules as V3Engine.recommend."""
    allowed = np.ones(len(eng.cat), bool)
    if candidates is not None:
        allowed[:] = False
        for i in eng._resolve_titles(candidates):
            allowed[i] = True
    if ctx.played:
        allowed[list(ctx.played)] = False
    try:
        from navivibe import taste_exclusions
        blocked = [eng.cat.index[s] for s in taste_exclusions.blocked_ids(user, eng.cat.meta)]
        if blocked:
            allowed[blocked] = False
    except Exception:  # noqa: BLE001
        pass
    return allowed


def rank_of(scores, allowed, i):
    """1-based rank of song i among the allowed songs; ties count half a place (the harness rule)."""
    v = np.where(allowed, np.asarray(scores, np.float64), -np.inf)
    return 1.0 + float((v > v[i]).sum()) + 0.5 * float((v == v[i]).sum() - 1)


def top_indices(scores, allowed, n):
    v = np.where(allowed, np.asarray(scores, np.float64), -np.inf)
    top = np.argsort(-v, kind="stable")[:n]
    return top[np.isfinite(v[top])]


# ── jobs and the worker ───────────────────────────────────────────────────────

class Job:
    def __init__(self, kind, user, **kw):
        self.kind, self.user, self.queued_at, self.mode = kind, user, 0.0, None
        self.__dict__.update(kw)


class ShadowRunner:
    """One daemon thread and a bounded queue. `compute(job, deadline)` returns (table, row);
    `write(user, row, table)` stores it. Both injected, so tests need no engine."""

    def __init__(self, compute, write=write_row, maxsize=QUEUE_MAX, clock=time.perf_counter, start=True):
        self.compute, self.write, self.clock = compute, write, clock
        self.q = queue.Queue(maxsize=maxsize)
        self._play_jobs = 0
        self._play_lock = threading.Lock()
        self._thread = None
        if start:
            self.start()

    def start(self):
        if self._thread is None:
            self._thread = threading.Thread(target=self._loop, name="hybrid-shadow", daemon=True)
            self._thread.start()

    def submit(self, job):
        """Never blocks, never raises. False when the job was not accepted."""
        try:
            if job.kind == "play":
                with self._play_lock:
                    if self._play_jobs >= PLAY_JOBS_MAX:
                        stats.add("dropped_play_jobs_full")
                        return False
                    self._play_jobs += 1
            job.queued_at = self.clock()
            try:
                self.q.put_nowait(job)
            except queue.Full:
                self._release(job)
                stats.add("dropped_queue_full")
                return False
            stats.add("submitted")
            return True
        except Exception:  # noqa: BLE001
            stats.add("submit_failed")
            return False

    def _release(self, job):
        if job.kind == "play":
            with self._play_lock:
                self._play_jobs = max(0, self._play_jobs - 1)

    def drain(self, timeout=5.0):
        end = time.time() + timeout
        while time.time() < end:
            if self.q.unfinished_tasks == 0:
                return True
            time.sleep(0.005)
        return False

    def _loop(self):
        while True:
            job = self.q.get()
            try:
                self._run(job)
            except Exception as e:  # noqa: BLE001
                stats.add("worker_error")
                print("[hybrid-shadow] worker error: %s: %s" % (type(e).__name__, e))
            finally:
                self._release(job)
                self.q.task_done()

    def _base(self, job, waited_ms):
        if job.kind == "play":
            return "hybrid_shadow_plays", {"created_at": time.time(), "played_at": job.played_at,
                                           "session_id": job.session_id, "song_id": job.song_id, "depth": job.depth,
                                           "mode": job.mode, "inline_ms": job.inline_ms, "queue_wait_ms": waited_ms}
        return "hybrid_shadow", {"created_at": time.time(), "served_id": job.served_id, "session_id": job.session_id,
                                 "mode": job.mode, "served_ids": job.served_ids, "queue_wait_ms": waited_ms}

    def _run(self, job):
        start = self.clock()
        waited_ms = int((start - job.queued_at) * 1000)
        table, base = self._base(job, waited_ms)
        budget = budget_ms()
        if waited_ms > budget:
            stats.add("error_stale")
            self.write(job.user, {**base, "status": "error", "error": "stale: waited %d ms in the queue" % waited_ms,
                                  "latency_ms": 0}, table)
            return
        try:
            row = self.compute(job, start + budget / 1000.0)
            elapsed = int((self.clock() - start) * 1000)
            if elapsed > budget:
                raise BudgetExceeded("took %d ms" % elapsed)
            stats.add("ok")
            self.write(job.user, {**base, **row, "status": "ok", "latency_ms": elapsed}, table)
        except BudgetExceeded as e:
            stats.add("error_budget")
            self.write(job.user, {**base, "status": "error", "error": "budget: %s" % e,
                                  "latency_ms": int((self.clock() - start) * 1000)}, table)
        except Exception as e:  # noqa: BLE001
            stats.add("error_exception")
            self.write(job.user, {**base, "status": "error", "error": "%s: %s" % (type(e).__name__, str(e)[:200]),
                                  "latency_ms": int((self.clock() - start) * 1000)}, table)


_runner = None
_runner_lock = threading.Lock()


def runner():
    global _runner
    with _runner_lock:
        if _runner is None:
            _runner = ShadowRunner(_engine_compute)
        return _runner


def _engine():
    from navivibe.recsys.recommender import V3Engine
    if not V3Engine.available():
        return None
    return V3Engine.get()


def _engine_compute(job, deadline):
    eng = _engine()
    if eng is None:
        raise RuntimeError("v3 engine not available")
    return compute_play(eng, job, deadline) if job.kind == "play" else compute_next(eng, job, deadline)


# ── per play (the flip decision) ──────────────────────────────────────────────

def play_hook(eng, user, i, session, ratio, now, hour, when, data):
    """Called inside `V3Engine.on_feedback`, under the user's lock, BEFORE the play updates the
    state. Builds the matrices from the state as it is, queues the ranking. Never raises."""
    try:
        m = mode()
        if m == "off":
            return
        ctx = session.ctx
        if not ctx.kept:
            return                                   # an opener: v3 serves it, nothing to score
        if ratio < MIN_RATIO or i in ctx.played:
            stats.add("play_skipped_not_scorable")
            return
        if (data or {}).get("_quality") not in (None, ""):
            stats.add("play_skipped_quality")
            return
        cur = models.get()
        if cur is None:
            stats.add("play_no_model")
            return
        t0 = time.perf_counter()
        ts = now.timestamp()
        us = eng._user(user)
        X = eng.fb.build(us, eng.gs, ctx, ts, hour, when.weekday())
        t1 = time.perf_counter()
        hb, M = feature_matrix(eng).build(X, us, list(ctx.kept), ts, hour, when.month)
        t2 = time.perf_counter()
        allowed = allowed_mask(eng, user, ctx)
        job = Job("play", user, song=i, song_id=eng.cat.ids[i], X=X, M=M, hb=hb, allowed=allowed,
                  session_id=str(getattr(session, "key", "") or (data or {}).get("session_id") or ""),
                  depth=len(ctx.kept), played_at=int((data or {}).get("_played_at") or ts), mode=m,
                  inline_ms=round((t2 - t0) * 1000, 2), fm_ms=(t2 - t1) * 1000)
        runner().submit(job)
    except Exception as e:  # noqa: BLE001
        stats.add("play_hook_failed")
        print("[hybrid-shadow] play hook failed: %s: %s" % (type(e).__name__, e))


def compute_play(eng, job, deadline=None):
    rr, meta = models.get() or (None, None)
    if rr is None:
        raise RuntimeError("no compatible model")
    t0 = time.perf_counter()
    sc = rr.scores(job.M, job.hb, job.allowed)
    rerank_ms = (time.perf_counter() - t0) * 1000
    if deadline is not None and time.perf_counter() > deadline:
        raise BudgetExceeded("after the re-rank")
    v3 = eng.ranker.predict(job.X, False, num_threads=1)
    i = job.song
    return {"rank_v3": rank_of(v3, job.allowed, i), "rank_blend": rank_of(job.hb, job.allowed, i),
            "rank_hybrid": rank_of(sc, job.allowed, i),
            "in_top100": int(i in H.candidates(job.hb, job.allowed)), "model_version": meta["version"],
            "extra_ms": round(job.fm_ms + rerank_ms, 3)}


# ── per /next request (latency, structure) and serving ───────────────────────

def _copy_session(session):
    s = dict(session or {})
    for k in ("played_titles", "excluded_titles", "recent_listen_ratios"):
        if isinstance(s.get(k), list):
            s[k] = list(s[k])
    return s


def rank_next(eng, rr, user, session, candidates, now_ts, deadline=None):
    """(position_kind, top indices, scores, n_allowed) for one /next request."""
    now = datetime.fromtimestamp(now_ts, IST)
    with eng._lock_for(user):
        us = eng._user(user)
        ctx = eng._session_ctx(user, session)
        allowed = allowed_mask(eng, user, ctx, candidates)
        X = eng.fb.build(us, eng.gs, ctx, now_ts, now.hour, now.weekday())
        hb, M = feature_matrix(eng).build(X, us, list(ctx.kept), now_ts, now.hour, now.month)
    if deadline is not None and time.perf_counter() > deadline:
        raise BudgetExceeded("after features")
    kind = "opener" if not ctx.kept else "next"
    sc = rr.scores(M, hb, allowed)
    top = top_indices(sc, allowed, TOP_N)
    return kind, top, sc[top], int(allowed.sum())


def compute_next(eng, job, deadline=None):
    cur = models.get()
    if cur is None:
        raise RuntimeError("no compatible model")
    rr, meta = cur
    kind, top, sc, n_allowed = rank_next(eng, rr, job.user, job.session, job.candidates, job.now_ts, deadline)
    return {"position_kind": kind, "model_version": meta["version"], "n_allowed": n_allowed,
            "top_ids": [eng.cat.ids[int(i)] for i in top],
            "top_scores": [round(float(s), 5) for s in sc]}


def hook(resp, username, session, served_id, queue_, mode_used, reshuffle, candidates, now_ts=None, active_mode=None):
    """Called with the finished /next response. Queues the job to run after the body is sent."""
    try:
        m = active_mode or mode()
        if m == "off" or reshuffle or mode_used not in ELIGIBLE_MODES:
            if m != "off":
                stats.add("skipped_ineligible")
            return
        if models.get() is None:                     # no compatible model: shadow stays off
            stats.add("next_no_model")
            return
        job = Job("next", username, session=_copy_session(session),
                  candidates=set(candidates) if candidates else None, served_id=served_id,
                  session_id=str((session or {}).get("session_id") or ""),
                  served_ids=[str(q.get("navidrome_id")) for q in (queue_ or [])[:SERVED_KEEP] if isinstance(q, dict)],
                  mode=m, now_ts=now_ts or time.time())
        resp.call_on_close(lambda: runner().submit(job))
    except Exception as e:  # noqa: BLE001
        stats.add("hook_failed")
        print("[hybrid-shadow] hook failed: %s: %s" % (type(e).__name__, e))


def maybe_serve(queue_, engine, username, session, candidates, mode_used, reshuffle, count, now_ts=None,
                active_mode=None):
    """(queue, engine): unchanged unless HYBRID_ORDER=on, a smart request, a next-song position and a
    compatible model. Any failure returns the v3 queue exactly as it came."""
    try:
        if (active_mode or mode()) != "on" or reshuffle or mode_used not in ELIGIBLE_MODES or not queue_:
            return queue_, engine
        eng = _engine()
        cur = models.get()
        if eng is None or cur is None:
            stats.add("on_no_model")
            return queue_, engine
        kind, top, sc, _ = rank_next(eng, cur[0], username, _copy_session(session),
                                     set(candidates) if candidates else None, now_ts or time.time())
        if kind != "next" or len(top) == 0:
            return queue_, engine
        stats.add("served_hybrid")
        return _build_queue(eng, queue_, top, sc, min(int(count), len(top))), "v3+hybrid"
    except Exception as e:  # noqa: BLE001
        stats.add("on_failed")
        print("[hybrid-shadow] serving failed, v3 queue kept: %s: %s" % (type(e).__name__, e))
        return queue_, engine


def _build_queue(eng, v3_queue, top, scores, n):
    by_id = {q.get("navidrome_id"): q for q in v3_queue if isinstance(q, dict)}
    first = v3_queue[0] if v3_queue else {}
    out = []
    for j, s in zip(top[:n], scores[:n]):
        sid = eng.cat.ids[int(j)]
        entry = by_id.get(sid)
        entry = dict(entry) if entry else _minimal_entry(eng, sid)
        entry["scores"] = dict(entry.get("scores") or {}, final=round(float(s), 4))
        entry["why"] = entry.get("why") or "Picked by the hybrid ranker"
        out.append(entry)
    for r, e in enumerate(out, 1):
        e["rank"] = r
    for key in ("_context_meta", "_starter_meta"):
        if key in first and out:
            out[0][key] = first[key]
    return out


def _minimal_entry(eng, sid):
    m = eng.cat.meta[sid]
    return {
        "title": m["title"], "navidrome_id": sid, "file_path": m.get("path") or "",
        "composer": m.get("artist") or m.get("composer") or "", "artist": m.get("artist") or "",
        "album": m.get("album") or "", "language": m.get("language"),
        "genre_bucket": (m.get("nd_genres") or [""])[0] if isinstance(m.get("nd_genres"), list) else "",
        "audio": {k: (None if m.get(k) is None else round(float(m[k]), 3))
                  for k in ("energy", "valence", "acousticness", "danceability")},
        "scores": {"final": 0.0, "percentile": 0.0, "context_history": 0.0, "audio_fit": 0.0,
                   "composer_loyalty": 0.0},
        "top_signals": {}, "trending": None, "why": "Picked by the hybrid ranker",
        "explore": False, "starter": False,
    }
