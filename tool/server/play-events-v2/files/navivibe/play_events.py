"""play-events-v2: one validated, idempotent door for everything the app reports about listening.

Replaces the loose `feedback.record_play` path used by POST /feedback. Kept here, not in
feedback.py, so a rollback is "delete this file, restore server.py".

Wire format (schema_version 2) and the old shape are both accepted; see
docs/play-event-schema.md in the app repo for the field list.

Rules this module enforces
  * Idempotency: every finish event carries `play_id`, every other event `event_id`; a repeat
    is answered "duplicate" and stores nothing. Old apps (no play_id) get a soft dedupe on
    (title, session, same second).
  * Validation: a malformed event is REFUSED (422) and COUNTED in `rejected_counts`
    (reason -> n) with a short sample in `rejected_events`. Nothing is dropped silently.
  * Time: `played_at` is the play's start (epoch ms, UTC). `tz_offset_min` is the phone's UTC
    offset then; `local_hour` is the hour on the user's own clock. `ist_*` columns stay for
    the existing readers. A missing offset means "assume IST", like every old row.
  * Weather is stamped by the server from its own cache at the play's time. Whatever the
    client sends is ignored (the old app sent 800 / 25.0 for every play).
  * Finish events (skip / complete / replay) go to `play_events`, the table every existing
    reader uses. start / seek / queue_edit go to `play_aux_events`, so no reader ever sees a
    row that is not a finished play.
"""
import json
import math
import os
import sqlite3
import threading
import time
import uuid
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

IST = ZoneInfo("Asia/Kolkata")
IST_OFFSET_MIN = 330

SCHEMA_VERSION = 2
FINISH_TYPES = ("skip", "complete", "replay")
AUX_TYPES = ("start", "seek", "queue_edit")
ALL_TYPES = FINISH_TYPES + AUX_TYPES
PLAY_SOURCES = ("smart_shuffle", "autoplay", "album", "playlist", "search", "jam",
                "remote", "queue", "radio", "library", "download", "other")
QUEUE_EDIT_KINDS = ("add", "remove", "reorder", "play_next")

MAX_FUTURE_SKEW_S = 5 * 60
MAX_AGE_S = 90 * 24 * 3600
MAX_DURATION_S = 6 * 3600
MAX_TITLE = 300
MAX_ID = 64
MAX_SESSION = 120
MAX_SERVED_ITEMS = 60
REJECT_SAMPLE_KEEP = 2000
WEATHER_MAX_AGE_S = 2 * 3600

NEW_PLAY_COLUMNS = (
    ("schema_version", "INTEGER"),
    ("event_type", "TEXT"),
    ("seconds_played", "REAL"),
    ("tz_offset_min", "INTEGER"),
    ("local_hour", "INTEGER"),
    ("play_source", "TEXT"),
    ("slot", "INTEGER"),
    ("score", "REAL"),
    ("served_by", "TEXT"),
    ("served_id", "TEXT"),
    ("holdout", "INTEGER"),
    ("client_version", "TEXT"),
    ("platform", "TEXT"),
    ("origin", "TEXT"),
    ("quality", "TEXT"),
    ("received_at", "INTEGER"),
)

_SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS play_aux_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_id TEXT NOT NULL UNIQUE,
    schema_version INTEGER,
    event_type TEXT NOT NULL,
    play_id TEXT,
    track_title TEXT,
    file_path TEXT,
    occurred_at INTEGER NOT NULL,
    tz_offset_min INTEGER,
    session_id TEXT,
    play_source TEXT,
    slot INTEGER,
    served_id TEXT,
    payload TEXT,
    client_version TEXT,
    received_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_aux_time ON play_aux_events(occurred_at);
CREATE INDEX IF NOT EXISTS idx_aux_play ON play_aux_events(play_id);
CREATE TABLE IF NOT EXISTS rejected_counts (
    reason TEXT PRIMARY KEY,
    n INTEGER NOT NULL DEFAULT 0,
    last_at INTEGER
);
CREATE TABLE IF NOT EXISTS rejected_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    received_at INTEGER NOT NULL,
    reason TEXT NOT NULL,
    client_version TEXT,
    sample TEXT
);
CREATE TABLE IF NOT EXISTS served_batches (
    served_id TEXT PRIMARY KEY,
    served_at INTEGER NOT NULL,
    session_id TEXT,
    mode TEXT,
    engine TEXT,
    depth INTEGER,
    n_items INTEGER
);
CREATE TABLE IF NOT EXISTS served_items (
    served_id TEXT NOT NULL,
    rank INTEGER NOT NULL,
    track_title TEXT,
    nd_id TEXT,
    score REAL,
    PRIMARY KEY (served_id, rank)
);
CREATE INDEX IF NOT EXISTS idx_served_batches_time ON served_batches(served_at);
CREATE INDEX IF NOT EXISTS idx_play_events_title_time ON play_events(track_title, played_at);
"""

_ready = set()
_ready_lock = threading.Lock()


# ── schema ───────────────────────────────────────────────────────────────────

def _fb():
    from navivibe import feedback
    return feedback


def ensure_schema(username):
    """Create/upgrade the tables once per process per user. Cheap after the first call."""
    fb = _fb()
    path = fb.get_db_path(username)
    with _ready_lock:
        if path in _ready:
            return path
        fb.init_db(username)  # base table, play_id, impressions
        conn = fb._connect(path)
        try:
            have = {r[1] for r in conn.execute("PRAGMA table_info(play_events)")}
            for name, typ in NEW_PLAY_COLUMNS:
                if name not in have:
                    try:
                        conn.execute("ALTER TABLE play_events ADD COLUMN %s %s" % (name, typ))
                    except sqlite3.OperationalError:
                        pass  # a concurrent process added it first
            conn.executescript(_SCHEMA_SQL)
            conn.commit()
        finally:
            conn.close()
        _ready.add(path)
    return path


def reset_ready_cache():
    """Tests only."""
    with _ready_lock:
        _ready.clear()


# ── value helpers ────────────────────────────────────────────────────────────

def _is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)


def _to_float(v):
    """(value, ok). Missing -> (None, True); unusable -> (None, False). Numeric strings ok."""
    if v is None or v == "":
        return None, True
    if isinstance(v, bool):
        return None, False
    if isinstance(v, str):
        try:
            v = float(v.strip())
        except ValueError:
            return None, False
    if not _is_num(v):
        return None, False
    return float(v), True


def _text(v, limit):
    if v is None or isinstance(v, (dict, list, bool)):
        return None
    s = str(v).strip()
    return s[:limit] if s else None


def _truthy(v):
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return v == 1
    return str(v).strip().lower() in ("1", "true", "yes")


def _legacy_type(raw, ratio):
    reason = str(raw.get("end_reason") or "").strip().lower()
    if reason in ("natural", "trackdone", "complete", "completed"):
        return "complete"
    if reason:
        return "skip"
    return "complete" if (ratio is None or ratio >= 0.9) else "skip"


def _origin(session_id):
    sid = session_id or ""
    if sid == "navidrome_sync":
        return "navidrome_sync"
    if sid.startswith("import:"):
        return "import"
    return "app"


def when_fields(when_utc, tz_offset_min):
    """The time columns for one instant."""
    ist = when_utc.astimezone(IST)
    off = IST_OFFSET_MIN if tz_offset_min is None else tz_offset_min
    local = when_utc + timedelta(minutes=off)
    return {
        "played_at": int(when_utc.timestamp()),
        "ist_timestamp": ist.isoformat(),
        "ist_hour": ist.hour,
        "day_of_week": ist.weekday(),
        "month": ist.month,
        "local_hour": local.hour,
    }


# ── weather (server side, never trusted from the client) ─────────────────────

def _weather_cache_path():
    try:
        from navivibe import weather
        return weather.CACHE_PATH
    except Exception:
        return os.getenv("NAVIVIBE_WEATHER_CACHE", "/opt/shuffle-server/weather_cache.json")


def weather_at(when_epoch, cache_path=None):
    """(weather_code, temperature_c) the server saw near `when_epoch`, or (None, None).

    Reads the cache file only (no network on the request path). A reading older than
    two hours before the play, or later than the play by more than two hours, is not
    used: a missing value is better data than a wrong one."""
    path = cache_path or _weather_cache_path()
    try:
        with open(path, "r") as f:
            w = json.load(f)
        fetched = datetime.fromisoformat(w["fetched_at"]).timestamp()
        if abs(when_epoch - fetched) > WEATHER_MAX_AGE_S:
            return None, None
        code = w.get("code")
        temp = w.get("temperature_c")
        return (int(code) if _is_num(code) else None,
                float(temp) if _is_num(temp) else None)
    except Exception:
        return None, None


# ── validation ───────────────────────────────────────────────────────────────

def normalize(raw, now=None):
    """Check one event. Returns (clean, reasons, flags).

    `clean` is None when the event is refused; `reasons` then says why (stable slugs, they
    are the keys of `rejected_counts`). `flags` are problems that were repaired (the event is
    still stored, with `quality` set), e.g. a phone clock that is a day off."""
    now = now or datetime.now(timezone.utc)
    reasons, flags = [], []
    if not isinstance(raw, dict):
        return None, ["not_object"], flags

    ver, ok = _to_float(raw.get("schema_version"))
    if not ok or (ver is not None and (ver < 1 or ver != int(ver))):
        return None, ["bad_schema_version"], flags
    version = int(ver) if ver is not None else 1
    legacy = version < 2

    title = _text(raw.get("track_title") or raw.get("title"), MAX_TITLE + 1)
    if not title:
        reasons.append("missing_title")
    elif len(title) > MAX_TITLE:
        reasons.append("title_too_long")

    ratio, ok = _to_float(raw.get("listen_ratio"))
    if not ok:
        reasons.append("bad_listen_ratio")
    elif ratio is not None:
        if ratio < 0 or ratio > 1.05:
            reasons.append("listen_ratio_out_of_range")
        else:
            ratio = min(ratio, 1.0)

    dur, ok = _to_float(raw.get("duration_s"))
    if not ok or (dur is not None and (dur < 0 or dur > MAX_DURATION_S)):
        reasons.append("bad_duration")
        dur = None
    duration_s = int(round(dur)) if dur else None  # 0 means "unknown"

    secs, ok = _to_float(raw.get("seconds_played"))
    if not ok or (secs is not None and secs < 0):
        reasons.append("bad_seconds_played")
        secs = None
    elif secs is not None and duration_s and secs > duration_s * 1.1 + 2:
        reasons.append("seconds_gt_duration")

    explicit_type = raw.get("event_type")
    if explicit_type is None:
        etype = _legacy_type(raw, ratio)
    else:
        etype = str(explicit_type).strip().lower()
        if etype not in ALL_TYPES:
            reasons.append("unknown_event_type")
            etype = None

    idem = _text(raw.get("play_id"), MAX_ID + 1)
    event_id = _text(raw.get("event_id"), MAX_ID + 1)
    if idem and len(idem) > MAX_ID:
        reasons.append("bad_play_id")
    if event_id and len(event_id) > MAX_ID:
        reasons.append("bad_event_id")
    if etype in AUX_TYPES:
        if not (event_id or idem):
            reasons.append("missing_event_id")
        event_id = event_id or idem
    elif etype in FINISH_TYPES and not legacy and not idem:
        reasons.append("missing_play_id")

    if etype in FINISH_TYPES and not legacy and ratio is None:
        if secs is not None and duration_s:
            ratio = min(secs / duration_s, 1.0)
        else:
            reasons.append("missing_ratio")
    if etype == "complete" and not legacy and ratio is not None and ratio < 0.5:
        reasons.append("complete_with_low_ratio")

    played_at_raw, ok = _to_float(raw.get("played_at"))
    when = now
    clamped = False
    if not ok:
        clamped = True
    elif played_at_raw is not None:
        try:
            cand = datetime.fromtimestamp(played_at_raw / 1000.0, timezone.utc)
            delta = (now - cand).total_seconds()
            if delta < -MAX_FUTURE_SKEW_S or delta > MAX_AGE_S:
                clamped = True
            else:
                when = min(cand, now)
        except (OverflowError, OSError, ValueError):
            clamped = True
    if clamped:
        flags.append("clock_clamped")

    tz, ok = _to_float(raw.get("tz_offset_min"))
    if not ok or (tz is not None and (tz != int(tz) or abs(tz) > 14 * 60)):
        flags.append("bad_tz_offset")
        tz = None
    tz_offset_min = int(tz) if tz is not None else None

    session_id = _text(raw.get("session_id"), MAX_SESSION)
    source = _text(raw.get("play_source"), 24)
    source = source.lower() if source else None
    if source is not None and source not in PLAY_SOURCES:
        flags.append("unknown_play_source")
        source = "other"

    slot, ok = _to_float(raw.get("slot"))
    slot = int(slot) if ok and slot is not None and 0 <= slot <= 5000 else None
    score, ok = _to_float(raw.get("score"))
    score = score if ok else None

    queue_edit = None
    if etype == "queue_edit":
        qe = raw.get("queue_edit")
        kind = str(qe.get("kind") if isinstance(qe, dict) else (raw.get("kind") or "")).strip().lower()
        if kind not in QUEUE_EDIT_KINDS:
            reasons.append("bad_queue_edit")
        else:
            queue_edit = {"kind": kind}
            for k in ("from_index", "to_index"):
                v, ok = _to_float(qe.get(k) if isinstance(qe, dict) else raw.get(k))
                if ok and v is not None and 0 <= v <= 100000:
                    queue_edit[k] = int(v)

    seek = None
    if etype == "seek":
        a, oka = _to_float(raw.get("from_ms"))
        b, okb = _to_float(raw.get("to_ms"))
        if not (oka and okb) or a is None or b is None or a < 0 or b < 0:
            reasons.append("bad_seek")
        else:
            seek = {"from_ms": int(a), "to_ms": int(b)}

    if reasons:
        return None, reasons, flags

    quality = None
    if legacy and etype == "complete" and ratio == 0.0 and str(raw.get("end_reason") or "").lower() in (
            "natural", "trackdone"):
        # "Finished naturally after 0 % of the song" cannot happen. Old app builds wrote it
        # for every song they advanced past without knowing the position.
        quality = "suspect_burst"
    elif ratio is not None and secs is not None and duration_s and abs(ratio - min(secs / duration_s, 1.0)) > 0.15:
        quality = "ratio_mismatch"
    if quality is None and "clock_clamped" in flags:
        quality = "clock_clamped"

    clean = {
        "schema_version": version,
        "event_type": etype,
        "title": title,
        "play_id": idem,
        "event_id": event_id,
        "file_path": _text(raw.get("file_path"), 200),
        "genre_bucket": _text(raw.get("genre_bucket"), 80),
        "composer": _text(raw.get("composer"), 200),
        "listen_ratio": ratio,
        "duration_s": duration_s,
        "seconds_played": secs,
        "end_reason": _text(raw.get("end_reason"), 24),
        "session_id": session_id,
        "session_depth": _int_or_none(raw.get("session_depth"), 0, 100000),
        "genre_streak_type": _text(raw.get("genre_streak_type"), 80),
        "genre_streak_count": _int_or_none(raw.get("genre_streak_count"), 0, 100000),
        "volume": _num_in(raw.get("volume"), 0.0, 1.0),
        "tz_offset_min": tz_offset_min,
        "play_source": source,
        "slot": slot,
        "score": score,
        "served_by": _text(raw.get("served_by"), 40),
        "served_id": _text(raw.get("served_id"), MAX_ID),
        "holdout": 1 if _truthy(raw.get("holdout")) else 0 if raw.get("holdout") is not None else None,
        "client_version": _text(raw.get("client_version"), 32),
        "platform": _text(raw.get("platform"), 24),
        "origin": _origin(session_id),
        "quality": quality,
        "when": when,
        "queue_edit": queue_edit,
        "seek": seek,
    }
    return clean, [], flags


def _int_or_none(v, lo, hi):
    f, ok = _to_float(v)
    return int(f) if ok and f is not None and lo <= f <= hi else None


def _num_in(v, lo, hi):
    f, ok = _to_float(v)
    return f if ok and f is not None and lo <= f <= hi else None


# ── storing ──────────────────────────────────────────────────────────────────

def _count_rejects(username, reasons, raw, client_version=None):
    """Remember that an event was refused. Never raises: counting must not break the request."""
    try:
        fb = _fb()
        path = ensure_schema(username)
        now = int(time.time())
        try:
            sample = json.dumps(raw, default=str, ensure_ascii=False)[:300]
        except Exception:
            sample = repr(raw)[:300]
        conn = fb._connect(path)
        try:
            for r in reasons:
                conn.execute(
                    "INSERT INTO rejected_counts(reason, n, last_at) VALUES (?, 1, ?) "
                    "ON CONFLICT(reason) DO UPDATE SET n = n + 1, last_at = excluded.last_at",
                    (r, now))
            conn.execute(
                "INSERT INTO rejected_events(received_at, reason, client_version, sample) VALUES (?,?,?,?)",
                (now, ",".join(reasons)[:200], client_version, sample))
            conn.execute(
                "DELETE FROM rejected_events WHERE id <= (SELECT MAX(id) FROM rejected_events) - ?",
                (REJECT_SAMPLE_KEEP,))
            conn.commit()
        finally:
            conn.close()
    except Exception as e:  # noqa: BLE001
        print("[play-events] could not count rejection %s: %s" % (reasons, e))


def _count_flags(username, flags):
    if not flags:
        return
    try:
        fb = _fb()
        path = ensure_schema(username)
        now = int(time.time())
        conn = fb._connect(path)
        try:
            for f in flags:
                conn.execute(
                    "INSERT INTO rejected_counts(reason, n, last_at) VALUES (?, 1, ?) "
                    "ON CONFLICT(reason) DO UPDATE SET n = n + 1, last_at = excluded.last_at",
                    ("flag:" + f, now))
            conn.commit()
        finally:
            conn.close()
    except Exception as e:  # noqa: BLE001
        print("[play-events] could not count flags %s: %s" % (flags, e))


def ingest(username, raw, now=None, weather=None):
    """Validate and store one event.

    Returns a dict: status ('recorded' | 'duplicate' | 'rejected'), reasons, and for stored
    events `played_at` (epoch s), `event_type`, `fold` (True when the live listener state should
    learn from it) and `ratio`."""
    now = now or datetime.now(timezone.utc)
    clean, reasons, flags = normalize(raw, now)
    if clean is None:
        cv = _text(raw.get("client_version"), 32) if isinstance(raw, dict) else None
        _count_rejects(username, reasons, raw, cv)
        return {"status": "rejected", "reasons": reasons}
    _count_flags(username, flags)

    fb = _fb()
    path = ensure_schema(username)
    tf = when_fields(clean["when"], clean["tz_offset_min"])
    received = int(now.timestamp())
    conn = fb._connect(path)
    try:
        conn.execute("BEGIN IMMEDIATE")
        if clean["event_type"] in AUX_TYPES:
            payload = clean["queue_edit"] or clean["seek"] or {}
            try:
                conn.execute(
                    "INSERT INTO play_aux_events(event_id, schema_version, event_type, play_id, track_title, "
                    "file_path, occurred_at, tz_offset_min, session_id, play_source, slot, served_id, payload, "
                    "client_version, received_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                    (clean["event_id"], clean["schema_version"], clean["event_type"], clean["play_id"],
                     clean["title"], clean["file_path"], tf["played_at"], clean["tz_offset_min"],
                     clean["session_id"], clean["play_source"], clean["slot"], clean["served_id"],
                     json.dumps(payload), clean["client_version"], received))
            except sqlite3.IntegrityError:
                conn.rollback()
                return {"status": "duplicate", "reasons": []}
            conn.commit()
            return {"status": "recorded", "reasons": [], "played_at": tf["played_at"],
                    "event_type": clean["event_type"], "fold": False}

        # finish event
        if clean["play_id"] is None:
            # Old apps send no id: refuse an exact repeat in the same second of the same session.
            dup = conn.execute(
                "SELECT 1 FROM play_events WHERE track_title = ? AND played_at = ? AND "
                "COALESCE(session_id,'') = ? AND play_id IS NULL LIMIT 1",
                (clean["title"], tf["played_at"], clean["session_id"] or "")).fetchone()
            if dup:
                conn.rollback()
                return {"status": "duplicate", "reasons": []}
        wcode, wtemp = weather if weather is not None else weather_at(tf["played_at"])
        try:
            conn.execute(
                "INSERT INTO play_events (track_title, file_path, genre_bucket, composer, played_at, "
                "ist_timestamp, ist_hour, day_of_week, month, weather_code, temperature_c, listen_ratio, "
                "duration_s, end_reason, session_id, session_depth, genre_streak_type, genre_streak_count, "
                "volume, processed, play_id, schema_version, event_type, seconds_played, tz_offset_min, "
                "local_hour, play_source, slot, score, served_by, served_id, holdout, client_version, "
                "platform, origin, quality, received_at) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,0,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (clean["title"], clean["file_path"], clean["genre_bucket"], clean["composer"],
                 tf["played_at"], tf["ist_timestamp"], tf["ist_hour"], tf["day_of_week"], tf["month"],
                 wcode, wtemp, clean["listen_ratio"], clean["duration_s"], clean["end_reason"],
                 clean["session_id"], clean["session_depth"], clean["genre_streak_type"],
                 clean["genre_streak_count"], clean["volume"], clean["play_id"],
                 clean["schema_version"], clean["event_type"], clean["seconds_played"],
                 clean["tz_offset_min"], tf["local_hour"], clean["play_source"], clean["slot"],
                 clean["score"], clean["served_by"], clean["served_id"], clean["holdout"],
                 clean["client_version"], clean["platform"], clean["origin"], clean["quality"], received))
        except sqlite3.IntegrityError as e:
            conn.rollback()
            if "play_id" in str(e):
                return {"status": "duplicate", "reasons": []}
            raise
        conn.commit()
    except BaseException:
        try:
            conn.rollback()
        except Exception:
            pass
        raise
    finally:
        conn.close()

    fold = clean["quality"] in (None, "ratio_mismatch", "clock_clamped") and clean["listen_ratio"] is not None
    return {"status": "recorded", "reasons": [], "played_at": tf["played_at"],
            "local_hour": tf["local_hour"], "event_type": clean["event_type"], "fold": fold,
            "ratio": clean["listen_ratio"], "quality": clean["quality"]}


# ── what the server served ───────────────────────────────────────────────────

def log_served(username, session_id, queue, mode, engine, depth=0, now=None):
    """Record the batch /next is about to return. Returns its `served_id` (always, so the
    response can carry it) and writes the rows best-effort: a failure is printed, never raised."""
    served_id = uuid.uuid4().hex[:16]
    try:
        fb = _fb()
        path = ensure_schema(username)
        items = []
        for i, q in enumerate((queue or [])[:MAX_SERVED_ITEMS]):
            if not isinstance(q, dict):
                continue
            sc = q.get("scores") if isinstance(q.get("scores"), dict) else {}
            score, ok = _to_float(sc.get("final", q.get("final")))
            rank, ok_r = _to_float(q.get("rank"))
            items.append((served_id, int(rank) if ok_r and rank is not None else i + 1,
                          _text(q.get("title"), MAX_TITLE), _text(q.get("navidrome_id"), MAX_ID),
                          score if ok else None))
        conn = fb._connect(path)
        try:
            conn.execute("INSERT INTO served_batches(served_id, served_at, session_id, mode, engine, depth, n_items) "
                         "VALUES (?,?,?,?,?,?,?)",
                         (served_id, int((now or datetime.now(timezone.utc)).timestamp()),
                          _text(session_id, MAX_SESSION), _text(mode, 40), _text(engine, 40),
                          int(depth) if isinstance(depth, int) else 0, len(items)))
            conn.executemany("INSERT OR IGNORE INTO served_items VALUES (?,?,?,?,?)", items)
            conn.commit()
        finally:
            conn.close()
    except Exception as e:  # noqa: BLE001
        print("[play-events] could not log served batch: %s" % e)
    return served_id


def record_impressions_once(username, batch_id, shown, played):
    """`feedback.record_impressions` with two guards it lacked: a batch the app re-sends
    (same `batch_id`) is counted once, and a runaway list is cut to 200 titles of 300 chars.
    Returns the number of titles counted (0 for a repeat)."""
    fb = _fb()
    path = ensure_schema(username)
    shown = [t[:MAX_TITLE] for t in (shown or [])[:200]]
    played = [t[:MAX_TITLE] for t in (played or [])[:200]]
    bid = _text(batch_id, MAX_ID)
    if bid:
        conn = fb._connect(path)
        try:
            conn.execute("CREATE TABLE IF NOT EXISTS impression_batches (batch_id TEXT PRIMARY KEY, at INTEGER)")
            try:
                conn.execute("INSERT INTO impression_batches VALUES (?, ?)", (bid, int(time.time())))
                conn.execute("DELETE FROM impression_batches WHERE at < ?", (int(time.time()) - 14 * 86400,))
                conn.commit()
            except sqlite3.IntegrityError:
                return 0
        finally:
            conn.close()
    fb.record_impressions(username, shown, played)
    return len(shown)


def erase_extra_tables(conn):
    """For DELETE /me/history: the v2 tables hold the same listening history as
    `play_events`, so erasing one without the others would leave it behind."""
    n = 0
    for table in ("play_aux_events", "served_items", "served_batches", "rejected_events",
                  "rejected_counts", "impressions", "impression_batches"):
        try:
            n += conn.execute("DELETE FROM %s" % table).rowcount or 0
        except sqlite3.OperationalError:
            pass  # the table does not exist (older database)
    return n


def prune_served(username, keep_days=60):
    """Optional housekeeping: drop served batches older than `keep_days`."""
    fb = _fb()
    path = ensure_schema(username)
    cutoff = int(time.time()) - keep_days * 86400
    conn = fb._connect(path)
    try:
        conn.execute("DELETE FROM served_items WHERE served_id IN (SELECT served_id FROM served_batches WHERE served_at < ?)",
                     (cutoff,))
        conn.execute("DELETE FROM served_batches WHERE served_at < ?", (cutoff,))
        conn.commit()
    finally:
        conn.close()


def handle_feedback(username, data, session_played, session_lock, cache_max, engine=None, now=None):
    """Everything POST /feedback does after authentication. Returns (json_body, http_status).

    * refused  -> 422 with the reasons (the app's outbox drops a 4xx for good)
    * repeat   -> 200 {"duplicate": true} (the app must still forget it)
    * stored   -> 200; a finished play then also updates the live session list and the v3
      listener state, dated by when it was played, not when it arrived. Events that are
      flagged as impossible (the old app's "finished naturally at 0 %") are stored for the
      audit but never taught to the model.
    """
    res = ingest(username, data, now)
    if res["status"] == "rejected":
        return {"ok": False, "rejected": res["reasons"]}, 422
    if res["status"] == "duplicate":
        return {"ok": True, "duplicate": True}, 200
    if res.get("fold") and isinstance(data, dict):
        title = safe_str(data.get("title") or data.get("track_title")).strip()
        sid = safe_str(data.get("session_id")).strip()
        if sid and title and res["ratio"] >= 0.3:
            key = (username, sid)
            with session_lock:
                bound_session_cache(session_played, max(1, cache_max - 1), keep_key=key)
                cached = session_played.setdefault(key, [])
                if title not in cached:
                    cached.append(title)
        if engine is not None:
            try:
                engine.on_feedback(username, dict(data, listen_ratio=res["ratio"],
                                                  _played_at=res["played_at"], _local_hour=res["local_hour"],
                                                  _quality=res.get("quality")))
            except Exception as e:  # noqa: BLE001
                print("[v3] feedback update failed: %s" % e)
    return {"ok": True}, 200  # same body as before: the old route test and old apps expect it


# ── input helpers for the routes ─────────────────────────────────────────────

def safe_int(value, default=0, lo=-10**9, hi=10**9):
    """int() that never raises: a bad value gives `default`, an extreme one is clamped."""
    try:
        if isinstance(value, bool):
            return default
        n = int(float(value))
    except (TypeError, ValueError, OverflowError):
        return default
    return max(lo, min(hi, n))


def safe_str(value, default=""):
    if value is None or isinstance(value, (dict, list)):
        return default
    return str(value)


def bound_session_cache(cache, limit, keep_key=None):
    """Drop the oldest entries until `cache` (insertion ordered dict) holds at most `limit`."""
    while len(cache) > limit:
        oldest = next(iter(cache))
        if oldest == keep_key and len(cache) > 1:
            cache[oldest] = cache.pop(oldest)  # the live one moves to the back
            continue
        cache.pop(oldest, None)
