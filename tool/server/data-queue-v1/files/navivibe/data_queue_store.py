"""
navivibe/data_queue_store.py   (data-queue-v1)
──────────────────────────────────────────────
The hidden "weekly data queue": library songs that arrived WITHOUT real Spotify audio features, waiting to be
sent (200 at a time, once a week, by the admin) through a playlist-transfer service to Spotify and back through
Exportify. Pure standard library: tg-fetcher imports this file too (its hook only calls `enqueue`).

It is a database file, not a Navidrome playlist: `data_queue.db` next to catalog.db (override with
NAVIVIBE_DATA_QUEUE_DB). Nobody but the admin can reach it (navivibe/data_queue.py checks that).

  queue     one row per library song id          state: waiting | in_batch | done | not_on_spotify | skipped
  batches   one row per weekly batch             state: open | closed | released
  uploads   one row per Exportify CSV that was applied (its SHA-256: the same file twice changes nothing)
  audit     what happened to each batch (created, downloaded, uploaded, repeated, released)
  predicted features guessed from the audio embedding for songs Spotify does not have; ALWAYS in this table with
            feature_source='predicted', never in spotify_details.db (that file only ever holds Spotify's numbers)

Everything here is failure-isolated where tg-fetcher calls it: `enqueue` never raises.
"""

import csv
import hashlib
import io
import json
import logging
import math
import os
import re
import sqlite3
import time

log = logging.getLogger(__name__)

PATH = os.getenv("NAVIVIBE_DATA_QUEUE_DB",
                 os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data_queue.db"))
DETAILS_PATH = os.getenv("NAVIVIBE_SPOTIFY_DETAILS_DB",
                         os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "spotify_details.db"))

BATCH_SIZE = 200                 # Soundiiz free tier: one playlist of up to 200 tracks
STALE_DAYS = 30                  # an open batch nobody uploaded is released after this
STATES = ("waiting", "in_batch", "done", "not_on_spotify", "skipped")
SOURCES = ("exportify", "youtube", "link", "request", "backfill", "other")
MAX_TEXT = 300

SCHEMA = """
CREATE TABLE IF NOT EXISTS queue (
    song_id      TEXT PRIMARY KEY,
    isrc         TEXT,
    title        TEXT NOT NULL,
    artist       TEXT NOT NULL DEFAULT '',
    album        TEXT NOT NULL DEFAULT '',
    album_artist TEXT NOT NULL DEFAULT '',
    duration     REAL,
    source       TEXT NOT NULL DEFAULT 'other',
    added_at     REAL NOT NULL,
    state        TEXT NOT NULL DEFAULT 'waiting',
    batch_id     INTEGER,
    pos          INTEGER,
    priority     REAL NOT NULL DEFAULT 0,
    note         TEXT,
    updated_at   REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS queue_state ON queue(state, batch_id);
CREATE TABLE IF NOT EXISTS batches (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at  REAL NOT NULL,
    state       TEXT NOT NULL DEFAULT 'open',
    size        INTEGER NOT NULL DEFAULT 0,
    uploaded_at REAL,
    released_at REAL,
    upload_sha  TEXT,
    summary     TEXT
);
CREATE TABLE IF NOT EXISTS uploads (
    sha        TEXT PRIMARY KEY,
    batch_id   INTEGER NOT NULL,
    at         REAL NOT NULL,
    name       TEXT,
    result     TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS audit (
    id       INTEGER PRIMARY KEY AUTOINCREMENT,
    batch_id INTEGER,
    at       REAL NOT NULL,
    event    TEXT NOT NULL,
    detail   TEXT
);
CREATE INDEX IF NOT EXISTS audit_batch ON audit(batch_id, id);
CREATE TABLE IF NOT EXISTS predicted (
    song_id        TEXT PRIMARY KEY,
    energy         REAL,
    valence        REAL,
    danceability   REAL,
    acousticness   REAL,
    feature_source TEXT NOT NULL DEFAULT 'predicted' CHECK (feature_source = 'predicted'),
    model          TEXT,
    batch_id       INTEGER,
    updated_at     REAL NOT NULL
);
"""

_ready: set = set()


def connect(path: str | None = None) -> sqlite3.Connection:
    """A connection with the schema in place. WAL + a busy timeout: tg-fetcher writes, the web server reads."""
    p = path or PATH
    c = sqlite3.connect(p, timeout=5, isolation_level=None)
    c.row_factory = sqlite3.Row
    c.execute("PRAGMA busy_timeout=5000")
    if p not in _ready:
        try:
            c.execute("PRAGMA journal_mode=WAL")
        except sqlite3.Error:
            pass
        c.executescript(SCHEMA)
        _ready.add(p)
    return c


def forget_paths() -> None:           # tests
    _ready.clear()


def _text(v, n=MAX_TEXT) -> str:
    return re.sub(r"[\x00-\x1f\x7f]+", " ", str(v or "")).strip()[:n]


def norm_isrc(v) -> str:
    s = "".join(ch for ch in str(v or "").upper() if ch.isalnum())
    return s if len(s) == 12 and s[:2].isalpha() else ""


def title_key(title, artist) -> tuple:
    """The same song twice (a re-tagged copy has a new library id): clean title + first artist."""
    t = re.sub(r"\(\s*(from|feat|ft)\b[^)]*\)|\s-\s*(from|feat|ft)\b.*$", " ", str(title or ""), flags=re.I)
    t = "".join(ch for ch in t.casefold() if ch.isalnum())
    a = re.split(r"[;,&/]", str(artist or ""))[0]
    return (t, "".join(ch for ch in a.casefold() if ch.isalnum()))


def source_of(link: str | None) -> str:
    """Where a download job came from, from its batch link ('exportify:…', a YouTube / playlist URL, none)."""
    link = (link or "").lower()
    if link.startswith("exportify:"):
        return "exportify"
    if "youtu" in link:
        return "youtube"
    if link:
        return "link"
    return "request"


# ── real features: what spotify_details.db says ──────────────────────────────

def real_ids(path: str | None = None, only: list | None = None) -> set:
    """Library song ids with REAL Spotify audio features: a row with both energy and valence. Read-only."""
    p = path or DETAILS_PATH
    if not os.path.exists(p):
        return set()
    try:
        c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(p).replace("\\", "/"), uri=True, timeout=5)
        try:
            if only is not None:
                out = set()
                for i in range(0, len(only), 500):
                    part = only[i:i + 500]
                    out |= {r[0] for r in c.execute(
                        "SELECT song_id FROM spotify_details WHERE energy IS NOT NULL AND valence IS NOT NULL "
                        "AND song_id IN (%s)" % ",".join("?" * len(part)), part)}
                return out
            return {r[0] for r in c.execute(
                "SELECT song_id FROM spotify_details WHERE energy IS NOT NULL AND valence IS NOT NULL")}
        finally:
            c.close()
    except sqlite3.Error:
        return set()


def has_real_features(song_id: str, path: str | None = None) -> bool:
    return bool(real_ids(path, [song_id]))


# ── adding songs ─────────────────────────────────────────────────────────────

def enqueue(song: dict, source: str = "other", now: float | None = None, path: str | None = None,
            details_path: str | None = None, priority: float = 0.0) -> str:
    """Put a library song in the queue. Returns 'queued' | 'known' | 'has_features' | 'bad' | 'error'.
    NEVER raises: a queue problem must not fail an import (tg-fetcher calls this)."""
    try:
        sid = _text(song.get("song_id") or song.get("id"), 64)
        title = _text(song.get("title"), 200)
        if not sid or not title:
            return "bad"
        if has_real_features(sid, details_path):
            return "has_features"
        now = time.time() if now is None else now
        c = connect(path)
        try:
            cur = c.execute(
                "INSERT OR IGNORE INTO queue (song_id, isrc, title, artist, album, album_artist, duration, source, "
                "added_at, state, priority, updated_at) VALUES (?,?,?,?,?,?,?,?,?, 'waiting', ?, ?)",
                (sid, norm_isrc(song.get("isrc")) or None, title, _text(song.get("artist")), _text(song.get("album")),
                 _text(song.get("album_artist")), _num(song.get("duration")),
                 source if source in SOURCES else "other", now, float(priority), now))
            return "queued" if cur.rowcount else "known"
        finally:
            c.close()
    except Exception as e:                     # noqa: BLE001 - failure-isolated on purpose
        log.warning("data-queue: enqueue skipped (%s)", type(e).__name__)
        return "error"


def _num(v):
    try:
        f = float(v)
        return f if math.isfinite(f) and f > 0 else None
    except (TypeError, ValueError):
        return None


# ── the audit trail ──────────────────────────────────────────────────────────

def audit(c, batch_id, event: str, detail: dict | None = None, now: float | None = None) -> None:
    c.execute("INSERT INTO audit (batch_id, at, event, detail) VALUES (?,?,?,?)",
              (batch_id, time.time() if now is None else now, event, json.dumps(detail or {}, ensure_ascii=False)))


def audit_of(c, batch_id: int) -> list:
    out = []
    for r in c.execute("SELECT at, event, detail FROM audit WHERE batch_id=? ORDER BY id", (batch_id,)):
        try:
            d = json.loads(r["detail"] or "{}")
        except ValueError:
            d = {}
        out.append({"at": r["at"], "event": r["event"], "detail": d})
    return out


# ── states and counts ────────────────────────────────────────────────────────

def counts(c) -> dict:
    out = {s: 0 for s in STATES}
    for r in c.execute("SELECT state, COUNT(*) n FROM queue GROUP BY state"):
        out[r["state"]] = r["n"]
    return out


def reconcile(c, now: float | None = None, details_path: str | None = None) -> int:
    """Waiting songs that have since got REAL Spotify features (an Exportify CSV import landed after they
    arrived) are done: they must not take a place in a batch. Returns how many."""
    now = time.time() if now is None else now
    ids = [r[0] for r in c.execute("SELECT song_id FROM queue WHERE state='waiting'")]
    have = real_ids(details_path, ids) if ids else set()
    for sid in have:
        c.execute("UPDATE queue SET state='done', note='had_features', updated_at=? WHERE song_id=? AND state='waiting'",
                  (now, sid))
    return len(have)


def release_stale(c, now: float | None = None, days: int = STALE_DAYS) -> list:
    """An open batch nobody uploaded for `days` days is released: its songs wait again. Returns the batch ids."""
    now = time.time() if now is None else now
    released = []
    for r in c.execute("SELECT id FROM batches WHERE state='open' AND created_at < ?", (now - days * 86400,)).fetchall():
        release(c, r["id"], "stale", now)
        released.append(r["id"])
    return released


def release(c, batch_id: int, why: str = "manual", now: float | None = None) -> bool:
    now = time.time() if now is None else now
    c.execute("BEGIN IMMEDIATE")
    try:
        b = c.execute("SELECT state FROM batches WHERE id=?", (batch_id,)).fetchone()
        if not b or b["state"] != "open":
            c.execute("ROLLBACK")
            return False
        n = c.execute("UPDATE queue SET state='waiting', batch_id=NULL, pos=NULL, note=NULL, updated_at=? "
                      "WHERE batch_id=? AND state='in_batch'", (now, batch_id)).rowcount
        c.execute("UPDATE batches SET state='released', released_at=? WHERE id=?", (now, batch_id))
        audit(c, batch_id, "released", {"why": why, "songs": n}, now)
        c.execute("COMMIT")
        return True
    except Exception:
        c.execute("ROLLBACK")
        raise


# ── building a batch ─────────────────────────────────────────────────────────

def score(row: dict, plays: dict, gaps: dict, now: float, max_plays: int) -> float:
    """Higher goes first: what listeners actually play (2), what arrived recently (1), what fills a gap in the
    audio-embedding space of the songs Spotify already labelled (1)."""
    p = math.log1p(plays.get(row["song_id"], 0)) / math.log1p(max_plays) if max_plays > 0 else 0.0
    age_days = max(0.0, (now - row["added_at"]) / 86400.0)
    recent = max(0.0, 1.0 - age_days / 60.0)
    gap = gaps.get(row["song_id"], row.get("priority") or 0.0)
    return 2.0 * p + 1.0 * recent + 1.0 * min(1.0, max(0.0, gap))


def rank_waiting(c, plays: dict | None = None, gaps: dict | None = None, now: float | None = None) -> list:
    """Waiting songs in pick order: ISRC songs first (the best chance to match on Spotify), then the score,
    then the song id (deterministic). Songs of one recording (same ISRC / same title + artist) count once."""
    now = time.time() if now is None else now
    plays, gaps = plays or {}, gaps or {}
    rows = [dict(r) for r in c.execute("SELECT * FROM queue WHERE state='waiting'")]
    top = max(plays.values(), default=0)
    for r in rows:
        r["score"] = score(r, plays, gaps, now, top)
    rows.sort(key=lambda r: (0 if r["isrc"] else 1, -r["score"], r["song_id"]))
    seen, out = set(), []
    for r in rows:
        keys = {("t",) + title_key(r["title"], r["artist"])}
        if r["isrc"]:
            keys.add(("i", r["isrc"]))
        if keys & seen:
            continue
        seen |= keys
        out.append(r)
    return out


def open_batch(c):
    r = c.execute("SELECT * FROM batches WHERE state='open' ORDER BY id DESC LIMIT 1").fetchone()
    return dict(r) if r else None


def build_batch(c, plays: dict | None = None, gaps: dict | None = None, live: dict | None = None,
                now: float | None = None, size: int = BATCH_SIZE, details_path: str | None = None) -> dict:
    """Make the next batch of at most `size` songs from the waiting ones. `live` maps song id -> the library's
    current row (title, artist, album, album_artist, duration, isrc) or None for a song that left the library
    (it is skipped); omit it to trust the queue's own rows. Songs already in an open batch are never picked
    again (they are not 'waiting'). Returns {'batch_id', 'size', 'skipped'}; size 0 and no batch when nothing waits."""
    now = time.time() if now is None else now
    release_stale(c, now)
    reconcile(c, now, details_path)
    skipped = 0
    if live is not None:
        for r in c.execute("SELECT song_id FROM queue WHERE state='waiting'").fetchall():
            cur = live.get(r["song_id"], "gone")
            if cur is None or cur == "gone":
                c.execute("UPDATE queue SET state='skipped', note='not_in_library', updated_at=? WHERE song_id=?",
                          (now, r["song_id"]))
                skipped += 1
            else:                          # the library's current tags beat what the queue saw at arrival
                c.execute("UPDATE queue SET title=?, artist=?, album=?, album_artist=?, "
                          "duration=COALESCE(?, duration), isrc=COALESCE(?, isrc) WHERE song_id=?",
                          (_text(cur.get("title"), 200) or "?", _text(cur.get("artist")), _text(cur.get("album")),
                           _text(cur.get("album_artist")), _num(cur.get("duration")),
                           norm_isrc(cur.get("isrc")) or None, r["song_id"]))
    picks = rank_waiting(c, plays, gaps, now)[:max(1, min(size, BATCH_SIZE))]
    if not picks:
        return {"batch_id": None, "size": 0, "skipped": skipped}
    c.execute("BEGIN IMMEDIATE")
    try:
        bid = c.execute("INSERT INTO batches (created_at, state, size) VALUES (?, 'open', ?)", (now, len(picks))).lastrowid
        for i, r in enumerate(picks):
            c.execute("UPDATE queue SET state='in_batch', batch_id=?, pos=?, updated_at=? "
                      "WHERE song_id=? AND state='waiting'", (bid, i, now, r["song_id"]))
        audit(c, bid, "created", {"songs": len(picks), "with_isrc": sum(1 for r in picks if r["isrc"]),
                                  "waiting_after": counts(c)["waiting"]}, now)
        c.execute("COMMIT")
    except Exception:
        c.execute("ROLLBACK")
        raise
    return {"batch_id": bid, "size": len(picks), "skipped": skipped}


def batch_songs(c, batch_id: int) -> list:
    return [dict(r) for r in c.execute("SELECT * FROM queue WHERE batch_id=? ORDER BY pos, song_id", (batch_id,))]


# ── the files the transfer services take (exactly tool/exportify/library_export.py's format) ──

COLUMNS = ["title", "artist", "album", "album artist", "duration", "isrc"]
_CTRL = {i: " " for i in range(32) if i != 9}
_CTRL.update({127: None})


def _clean(text) -> str:
    return " ".join(str(text or "").translate(_CTRL).split())


def export_row(r: dict) -> dict:
    try:
        dur = int(round(float(r.get("duration") or 0)))
    except (TypeError, ValueError):
        dur = 0
    return {"title": _clean(r.get("title")), "artist": _clean(r.get("artist")), "album": _clean(r.get("album")),
            "album artist": _clean(r.get("album_artist")), "duration": dur, "isrc": norm_isrc(r.get("isrc"))}


def csv_text(rows: list) -> str:
    buf = io.StringIO()
    w = csv.writer(buf, lineterminator="\r\n", quoting=csv.QUOTE_MINIMAL)
    w.writerow(COLUMNS)
    for r in rows:
        s = export_row(r)
        w.writerow([s[c] for c in COLUMNS])
    return buf.getvalue()


def txt_text(rows: list) -> str:
    out = []
    for r in rows:
        s = export_row(r)
        out.append("%s - %s\n" % (s["artist"], s["title"]) if s["artist"] else "%s\n" % s["title"])
    return "".join(out)


def file_bytes(rows: list, fmt: str) -> bytes:
    """CSV with a BOM (the same bytes library_export.py writes), or TXT."""
    if fmt == "csv":
        return b"\xef\xbb\xbf" + csv_text(rows).encode("utf-8")
    return txt_text(rows).encode("utf-8")


# ── closing a batch with an Exportify upload ─────────────────────────────────

def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def find_upload(c, sha: str):
    r = c.execute("SELECT * FROM uploads WHERE sha=?", (sha,)).fetchone()
    return dict(r) if r else None


def close_batch(c, batch_id: int, sha: str, name: str, states: dict, result: dict, predicted: dict | None = None,
                now: float | None = None) -> None:
    """One transaction: every song of the batch gets its final state (`states`: id -> (state, note)), the
    predicted features are stored, the batch is closed and the upload recorded. Either all of it or none."""
    now = time.time() if now is None else now
    c.execute("BEGIN IMMEDIATE")
    try:
        for sid, (state, note) in states.items():
            c.execute("UPDATE queue SET state=?, note=?, updated_at=? WHERE song_id=? AND batch_id=? AND state='in_batch'",
                      (state, note, now, sid, batch_id))
        for sid, f in (predicted or {}).items():
            c.execute("INSERT OR REPLACE INTO predicted (song_id, energy, valence, danceability, acousticness, "
                      "feature_source, model, batch_id, updated_at) VALUES (?,?,?,?,?, 'predicted', ?, ?, ?)",
                      (sid, f.get("energy"), f.get("valence"), f.get("danceability"), f.get("acousticness"),
                       f.get("model"), batch_id, now))
        c.execute("UPDATE batches SET state='closed', uploaded_at=?, upload_sha=?, summary=? WHERE id=?",
                  (now, sha, json.dumps(result, ensure_ascii=False), batch_id))
        c.execute("INSERT INTO uploads (sha, batch_id, at, name, result) VALUES (?,?,?,?,?)",
                  (sha, batch_id, now, _text(name, 120), json.dumps(result, ensure_ascii=False)))
        audit(c, batch_id, "uploaded", {k: result.get(k) for k in
                                        ("rows", "matched", "not_found", "features_stored", "predicted", "sha256")}, now)
        c.execute("COMMIT")
    except Exception:
        c.execute("ROLLBACK")
        raise


# ── reading it back ──────────────────────────────────────────────────────────

def batch_out(c, r) -> dict:
    r = dict(r)
    try:
        summary = json.loads(r.get("summary") or "null")
    except ValueError:
        summary = None
    states = {s: 0 for s in STATES}
    for x in c.execute("SELECT state, COUNT(*) n FROM queue WHERE batch_id=? GROUP BY state", (r["id"],)):
        states[x["state"]] = x["n"]
    return {"id": r["id"], "state": r["state"], "size": r["size"], "created_at": r["created_at"],
            "uploaded_at": r["uploaded_at"], "released_at": r["released_at"], "songs": states, "summary": summary}


def history(c, limit: int = 50) -> list:
    return [batch_out(c, r) for r in c.execute("SELECT * FROM batches ORDER BY id DESC LIMIT ?", (limit,))]


def quality(c, now: float | None = None) -> dict:
    """The data-quality-style summary: where the waiting songs come from, how old the oldest is, how the last
    batches went."""
    now = time.time() if now is None else now
    by_source = {r["source"]: r["n"] for r in c.execute(
        "SELECT source, COUNT(*) n FROM queue WHERE state='waiting' GROUP BY source")}
    oldest = c.execute("SELECT MIN(added_at) a FROM queue WHERE state='waiting'").fetchone()["a"]
    with_isrc = c.execute("SELECT COUNT(*) n FROM queue WHERE state='waiting' AND isrc IS NOT NULL").fetchone()["n"]
    done = c.execute("SELECT COALESCE(SUM(state='done'),0) d, COALESCE(SUM(state='not_on_spotify'),0) m, "
                     "COALESCE(SUM(state='skipped'),0) s FROM queue WHERE batch_id IS NOT NULL").fetchone()
    judged = done["d"] + done["m"]
    return {"waiting_by_source": by_source, "waiting_with_isrc": with_isrc,
            "oldest_waiting_days": None if oldest is None else round((now - oldest) / 86400.0, 1),
            "match_rate": None if not judged else round(done["d"] / judged, 3),
            "settled": {"matched": done["d"], "not_on_spotify": done["m"], "skipped": done["s"]}}


def coverage(c, live_ids, real: set) -> dict:
    """Share of library songs with real Spotify features / predicted / none."""
    live_ids = set(live_ids)
    pred = {r[0] for r in c.execute("SELECT song_id FROM predicted")} - real
    r_n = len(live_ids & real)
    p_n = len(live_ids & pred)
    total = len(live_ids)
    return {"total": total, "real": r_n, "predicted": p_n, "none": max(0, total - r_n - p_n)}
