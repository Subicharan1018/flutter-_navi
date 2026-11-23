"""hybrid-shadow-v1, the runtime: flag, shadow recorder, optional serving.

HYBRID_ORDER = off | shadow | on        (default shadow; anything else counts as shadow)
  off     nothing runs.
  shadow  /next returns exactly what it returned before. After the response has gone out, a
          single background worker computes the hybrid ranking for the same request and writes
          one row to `hybrid_shadow` in the listener's own log database.
  on      like shadow, and ALSO the next-song positions (the session already has a kept song)
          are served in the hybrid's order. Session openers stay on v3. A failure in the hybrid
          path serves the v3 queue unchanged.

Independent of AI_ORDER (which orders the v3 queue and is untouched).

Rules this module keeps
  * The listener never waits for a shadow computation: the job is queued from
    `Response.call_on_close` (after the body is sent) and `submit` never blocks or raises.
  * One worker thread, a bounded queue (64 jobs; the 65th is dropped and counted), a time
    budget per job (HYBRID_BUDGET_MS, default 2000; a job that waited longer than that in the
    queue is not run). A miss or a failure is a row with status 'error' and a reason; nothing
    reaches the request.
  * The model file is re-read when its mtime changes (nightly fit), never during a request.
  * No model yet -> the stage-1 blend order is recorded (model_version 'blend-only').
"""
import json
import os
import queue
import sqlite3
import threading
import time
from datetime import datetime
from zoneinfo import ZoneInfo

import numpy as np

from navivibe import hybrid_core as core

IST = ZoneInfo("Asia/Kolkata")
MODES = ("off", "shadow", "on")
ELIGIBLE_MODES = ("smart", "smart_candidates")
TOP_N = int(float(os.getenv("HYBRID_TOP_N", "20")))
QUEUE_MAX = 64
SERVED_KEEP = 20

MODEL_PATH = os.getenv("HYBRID_MODEL_PATH", "/opt/shuffle-server/models/hybrid/hybrid_v1.json")

_SCHEMA = """
CREATE TABLE IF NOT EXISTS hybrid_shadow (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at INTEGER NOT NULL,
    served_id TEXT,
    user TEXT,
    session_id TEXT,
    position_kind TEXT,
    mode TEXT,
    model_version TEXT,
    blend_version TEXT,
    status TEXT NOT NULL,
    error TEXT,
    top_ids TEXT,
    top_scores TEXT,
    n_allowed INTEGER,
    served_ids TEXT,
    latency_ms INTEGER,
    queue_wait_ms INTEGER
);
CREATE INDEX IF NOT EXISTS idx_hybrid_shadow_served ON hybrid_shadow(served_id);
CREATE INDEX IF NOT EXISTS idx_hybrid_shadow_time ON hybrid_shadow(created_at);
"""


def mode():
    """Read on every call, so the flag is a restart-free-able knob in tests and a one-line .env change."""
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
    """Counters since the process started (printed with the status line, handy in tests)."""

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


# ── storage ───────────────────────────────────────────────────────────────────

_ready = set()
_ready_lock = threading.Lock()


def _db_path(username):
    from navivibe import feedback
    return feedback.get_db_path(username)


def ensure_table(username):
    from navivibe import feedback
    path = _db_path(username)
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


def write_row(username, row):
    """One INSERT in its own short transaction. Returns True on success; never raises."""
    try:
        from navivibe import feedback
        path = ensure_table(username)
        conn = feedback._connect(path)
        try:
            conn.execute(
                "INSERT INTO hybrid_shadow(created_at, served_id, user, session_id, position_kind, mode, "
                "model_version, blend_version, status, error, top_ids, top_scores, n_allowed, served_ids, "
                "latency_ms, queue_wait_ms) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (int(row.get("created_at") or time.time()), row.get("served_id"), username,
                 row.get("session_id"), row.get("position_kind"), row.get("mode"),
                 row.get("model_version"), row.get("blend_version"), row["status"], row.get("error"),
                 json.dumps(row.get("top_ids")) if row.get("top_ids") is not None else None,
                 json.dumps(row.get("top_scores")) if row.get("top_scores") is not None else None,
                 row.get("n_allowed"), json.dumps(row.get("served_ids")) if row.get("served_ids") is not None else None,
                 row.get("latency_ms"), row.get("queue_wait_ms")))
            conn.commit()
        finally:
            conn.close()
        return True
    except Exception as e:  # noqa: BLE001 - the shadow must never raise into anything
        stats.add("write_failed")
        print("[hybrid-shadow] could not write a row: %s: %s" % (type(e).__name__, e))
        return False


# ── model cache ───────────────────────────────────────────────────────────────

class ModelCache:
    def __init__(self, path=None):
        self.path = path
        self._lock = threading.Lock()
        self._mtime = None
        self._model = None

    def get(self):
        path = self.path or MODEL_PATH
        try:
            mt = os.stat(path).st_mtime_ns
        except OSError:
            self._mtime, self._model = None, None
            return None
        with self._lock:
            if mt != self._mtime:
                self._model = core.load_model(path)
                self._mtime = mt
                if self._model is None:
                    stats.add("model_unreadable")
                else:
                    print("[hybrid-shadow] loaded model %s (%s)" % (self._model.version, self._model.meta.get("trained_at")))
            return self._model


models = ModelCache()


# ── what one request needs ────────────────────────────────────────────────────

class Job:
    __slots__ = ("user", "session", "candidates", "served_id", "session_id", "served_ids",
                 "mode", "queued_at", "now_ts", "n")

    def __init__(self, **kw):
        for k in self.__slots__:
            setattr(self, k, kw.get(k))


def allowed_mask(eng, user, ctx, candidates):
    """The songs /next could have served: same rules as V3Engine.recommend."""
    allowed = np.ones(len(eng.cat), bool)
    if candidates is not None:
        allowed[:] = False
        for i in eng._resolve_titles(candidates):
            allowed[i] = True
    if ctx.played:
        allowed[list(ctx.played)] = False          # songs already heard this session
    try:
        from navivibe import taste_exclusions
        blocked = [eng.cat.index[s] for s in taste_exclusions.blocked_ids(user, eng.cat.meta)]
        if blocked:
            allowed[blocked] = False
    except Exception:  # noqa: BLE001 - no exclusion list is not a reason to lose the row
        pass
    return allowed


def rank_for_job(eng, model, job, deadline=None, F=None):
    """(position_kind, top song indices, scores, n_allowed, model_version, blend_version)."""
    if F is None:
        from navivibe.recsys.features import F as _F
        F = _F
    now = datetime.fromtimestamp(job.now_ts, IST)
    with eng._lock_for(job.user):
        us = eng._user(job.user)
        ctx = eng._session_ctx(job.user, job.session)
        allowed = allowed_mask(eng, job.user, ctx, job.candidates)
        opener = not ctx.kept
        X = eng.fb.build(us, eng.gs, ctx, job.now_ts, now.hour, now.weekday())
    if deadline is not None and time.perf_counter() > deadline:
        raise BudgetExceeded("after features")
    n_allowed = int(allowed.sum())
    if n_allowed == 0:
        return ("opener" if opener else "next"), np.zeros(0, int), np.zeros(0), 0, "none", core.BLEND_VERSION
    if model is None:
        top, sc = core.blend_only_rank(X, F, allowed, opener, TOP_N)
        version, bver = "blend-only", core.BLEND_VERSION
    else:
        top, sc = model.rank(X, F, allowed, opener, TOP_N)
        version, bver = model.version, model.blend_version
    return ("opener" if opener else "next"), top, sc, n_allowed, version, bver


# ── the worker ────────────────────────────────────────────────────────────────

class ShadowRunner:
    """One daemon thread, a bounded queue. `compute(job, deadline)` returns a row dict;
    `write(user, row)` stores it. Both are injected so tests need no engine."""

    def __init__(self, compute, write=write_row, maxsize=QUEUE_MAX, clock=time.perf_counter, start=True):
        self.compute, self.write, self.clock = compute, write, clock
        self.q = queue.Queue(maxsize=maxsize)
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
            job.queued_at = self.clock()
            self.q.put_nowait(job)
            stats.add("submitted")
            return True
        except queue.Full:
            stats.add("dropped_queue_full")
            return False
        except Exception:  # noqa: BLE001
            stats.add("submit_failed")
            return False

    def drain(self, timeout=5.0):
        """Tests: wait until every queued job has been handled."""
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
                self.q.task_done()

    def _run(self, job):
        start = self.clock()
        waited_ms = int((start - job.queued_at) * 1000)
        base = {"created_at": time.time(), "served_id": job.served_id, "session_id": job.session_id,
                "mode": job.mode, "served_ids": job.served_ids, "queue_wait_ms": waited_ms}
        budget = budget_ms()
        if waited_ms > budget:
            stats.add("error_stale")
            self.write(job.user, {**base, "status": "error", "error": "stale: waited %d ms in the queue" % waited_ms,
                                  "latency_ms": 0})
            return
        try:
            row = self.compute(job, start + budget / 1000.0)
            elapsed = int((self.clock() - start) * 1000)
            if elapsed > budget:
                raise BudgetExceeded("took %d ms" % elapsed)
            stats.add("ok")
            self.write(job.user, {**base, **row, "status": "ok", "latency_ms": elapsed})
        except BudgetExceeded as e:
            stats.add("error_budget")
            self.write(job.user, {**base, "status": "error", "error": "budget: %s" % e,
                                  "latency_ms": int((self.clock() - start) * 1000)})
        except Exception as e:  # noqa: BLE001 - recorded, never raised
            stats.add("error_exception")
            self.write(job.user, {**base, "status": "error", "error": "%s: %s" % (type(e).__name__, str(e)[:200]),
                                  "latency_ms": int((self.clock() - start) * 1000)})


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
    kind, top, sc, n_allowed, version, bver = rank_for_job(eng, models.get(), job, deadline)
    return {"position_kind": kind, "model_version": version, "blend_version": bver, "n_allowed": n_allowed,
            "top_ids": [eng.cat.ids[int(i)] for i in top],
            "top_scores": [round(float(s), 5) for s in sc]}


# ── the two hooks the /next route calls ───────────────────────────────────────

def hook(resp, username, session, served_id, queue_, mode_used, reshuffle, candidates, now_ts=None, active_mode=None):
    """Called with the finished response. Queues the shadow job to run after the body is sent.
    Never raises, never blocks."""
    try:
        m = active_mode or mode()
        if m == "off" or reshuffle or mode_used not in ELIGIBLE_MODES:
            if m != "off":
                stats.add("skipped_ineligible")
            return
        job = Job(user=username, session=_copy_session(session), candidates=set(candidates) if candidates else None,
                  served_id=served_id, session_id=str((session or {}).get("session_id") or ""),
                  served_ids=[str(q.get("navidrome_id")) for q in (queue_ or [])[:SERVED_KEEP] if isinstance(q, dict)],
                  mode=m, now_ts=now_ts or time.time(), n=TOP_N)
        resp.call_on_close(lambda: runner().submit(job))
    except Exception as e:  # noqa: BLE001
        stats.add("hook_failed")
        print("[hybrid-shadow] hook failed: %s: %s" % (type(e).__name__, e))


def _copy_session(session):
    s = dict(session or {})
    for k in ("played_titles", "excluded_titles", "recent_listen_ratios"):
        if isinstance(s.get(k), list):
            s[k] = list(s[k])
    return s


def maybe_serve(queue_, engine, username, session, candidates, mode_used, reshuffle, count, now_ts=None,
                active_mode=None):
    """(queue, engine). Unchanged unless HYBRID_ORDER=on, the request is a next-song position of a
    smart request and a model is loaded. Any failure returns the v3 queue as it came."""
    try:
        if (active_mode or mode()) != "on" or reshuffle or mode_used not in ELIGIBLE_MODES or not queue_:
            return queue_, engine
        eng = _engine()
        model = models.get()
        if eng is None or model is None:
            stats.add("on_no_model")
            return queue_, engine
        job = Job(user=username, session=_copy_session(session),
                  candidates=set(candidates) if candidates else None, now_ts=now_ts or time.time())
        kind, top, sc, n_allowed, version, _ = rank_for_job(eng, model, job)
        if kind != "next" or len(top) == 0:
            return queue_, engine       # openers stay on v3
        built = _build_queue(eng, queue_, top, sc, min(int(count), len(top)))
        stats.add("served_hybrid")
        return built, "v3+hybrid"
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
