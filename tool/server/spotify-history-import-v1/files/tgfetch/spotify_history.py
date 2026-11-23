"""
tgfetch/spotify_history.py  (spotify-history-import-v1)
───────────────────────────────────────────────────────
Bring a person's Spotify "Extended Streaming History" (or the older basic export) into the shuffle server's taste
data, WITH real skip information, which the app's own logs lack.

The app reads the person's ZIP on the device and sends only what is needed, one page at a time:

    {"t": end time (epoch s), "ms": ms played, "title", "artist", "album", "end": reason_end, "sk": skipped?}

Nothing else ever arrives (no IP address, country, platform, offline times, episodes, audiobooks, video, or plays
made in incognito mode: the app drops them first), and nothing else is stored.

  * Validated like play-events-v2: a row that is not an object, has no title or artist, an impossible time or an
    impossible ms_played is refused, counted by reason in the job, and reported. Only counts are ever logged.
  * Skip rule (the owner's default, see skip_decision): a play under 30 s that ended by the forward/back button
    (or that Spotify flags `skipped`) is a SKIP; a play of 30 s or more, or one that ran to its end (`trackdone`),
    is a LISTEN with listen_ratio = seconds played / the library song's length. A short play that ended some other
    way (logout, app closed, a remote switch) is unclear and is not imported.
  * Matching = the Exportify matcher (history_import's Index): clean title + an artist in common, remix / sped-up /
    live words compared. Spotify's files carry no ISRC and no track length, so neither is used.
  * Matched plays go to the user's listening log: session_id `import:spotify`, origin `import`, real
    seconds_played, a fixed play_id `imp:spotify:<hash of time, artist, title>` (so importing the same file again
    adds nothing) and the 2-minute near-duplicate rule of history-import-v1.
  * Unmatched songs that were actually listened to go on the user's Wishlist ("Spotify history", popularity =
    number of listens, max 100) with the wishlist's own plan and caps. Songs only ever skipped are not wished for.
  * Undo = history-import-v1's undo (it works by source): plays, song counts and not-yet-fetched Wishlist songs.

Reuses history_import.py (jobs table, matcher index, near-duplicate rule, wishlist, undo): install that first.
"""

import hashlib
import json
import logging
import re
import sqlite3
import time
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

from tgfetch import exportify as ex
from tgfetch import history_import as hi
from tgfetch.library_sweep import Index

log = logging.getLogger("tgfetch.spotify_history")

SOURCE = "spotify"
hi.SOURCES.setdefault(SOURCE, "Spotify history")

IST = ZoneInfo("Asia/Kolkata")
SKIP_MS = 30_000                 # the owner's rule: under this and ended by a button = a skip
MAX_PAGE = 1000                  # plays a page
MAX_MS = 6 * 3600 * 1000         # play-events-v2: no play is longer than 6 h
MAX_TITLE = 300                  # play-events-v2 MAX_TITLE
MAX_ARTIST = 200
MAX_ALBUM = 200
MAX_TOTAL = 3_000_000            # a progress hint only
MIN_TS = 1_136_073_600           # 1 Jan 2006: Spotify did not exist before
FUTURE_SKEW_S = 5 * 60
SKIP_ENDS = ("fwdbtn", "backbtn")
END_RE = re.compile(r"^[a-z0-9_\-]{0,24}$")
FORMATS = ("extended", "basic")

SCHEMA = """
CREATE TABLE IF NOT EXISTS spotify_jobs (
    job_id      INTEGER PRIMARY KEY,
    user        TEXT NOT NULL,
    format      TEXT NOT NULL,
    pages       INTEGER NOT NULL DEFAULT 0,
    skips       INTEGER NOT NULL DEFAULT 0,        -- plays written (or near-duplicate) that are skips
    listens     INTEGER NOT NULL DEFAULT 0,
    unclear     INTEGER NOT NULL DEFAULT 0,        -- short, ended another way: not imported
    skip_misses INTEGER NOT NULL DEFAULT 0,        -- skips of songs that are not in the library (not wished for)
    rejected    TEXT NOT NULL DEFAULT '{}'         -- JSON {reason: count}
);
"""

# The listening log's v2 columns (play-events-v2 NEW_PLAY_COLUMNS), added here if that package has not run yet.
V2_COLUMNS = (("schema_version", "INTEGER"), ("event_type", "TEXT"), ("seconds_played", "REAL"),
              ("tz_offset_min", "INTEGER"), ("local_hour", "INTEGER"), ("play_source", "TEXT"), ("slot", "INTEGER"),
              ("score", "REAL"), ("served_by", "TEXT"), ("served_id", "TEXT"), ("holdout", "INTEGER"),
              ("client_version", "TEXT"), ("platform", "TEXT"), ("origin", "TEXT"), ("quality", "TEXT"),
              ("received_at", "INTEGER"))
INSERT_SQL = (
    "INSERT OR IGNORE INTO play_events (track_title, file_path, played_at, ist_timestamp, ist_hour, day_of_week, "
    "month, listen_ratio, duration_s, end_reason, session_id, processed, play_id, schema_version, event_type, "
    "seconds_played, local_hour, origin, received_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,0,?,2,?,?,?,'import',?)")


def ensure_schema(conn) -> None:
    hi.ensure_schema(conn)
    conn.executescript(SCHEMA)


def open_log(user: str) -> sqlite3.Connection:
    c = hi.open_log(user)
    have = {r[1] for r in c.execute("PRAGMA table_info(play_events)")}
    for name, typ in V2_COLUMNS:
        if name not in have:
            try:
                c.execute(f"ALTER TABLE play_events ADD COLUMN {name} {typ}")
            except sqlite3.OperationalError:
                pass                      # another process added it first
    c.commit()
    return c


# ── one row: validate, then decide ───────────────────────────────────────────

def _text(v, limit: int) -> str | None:
    if not isinstance(v, str):
        return None
    s = re.sub(r"\s+", " ", v).strip()
    return s if s and len(s) <= limit else None


def clean_row(raw, now: float) -> tuple[dict | None, str | None]:
    """(row, None) or (None, reason). Reasons are stable slugs, counted per job."""
    if not isinstance(raw, dict):
        return None, "not_object"
    title = raw.get("title")
    if not isinstance(title, str) or not title.strip():
        return None, "missing_title"
    title = _text(title, MAX_TITLE)
    if title is None:
        return None, "title_too_long"
    artist = raw.get("artist")
    if not isinstance(artist, str) or not artist.strip():
        return None, "missing_artist"
    artist = _text(artist, MAX_ARTIST)
    if artist is None:
        return None, "artist_too_long"
    t, ms = raw.get("t"), raw.get("ms")
    if isinstance(t, bool) or not isinstance(t, (int, float)) or t != t or t < MIN_TS or t > now + FUTURE_SKEW_S:
        return None, "bad_time"
    if isinstance(ms, bool) or not isinstance(ms, (int, float)) or ms != ms or ms < 0 or ms > MAX_MS:
        return None, "bad_ms_played"
    end = raw.get("end")
    end = end.strip().lower() if isinstance(end, str) else ""
    if not END_RE.match(end):
        end = "other"
    sk = raw.get("sk")
    if sk is not None and not isinstance(sk, bool):
        return None, "bad_skipped"
    album = raw.get("album")
    album = (_text(album, MAX_ALBUM) or "") if isinstance(album, str) else ""
    return {"t": int(t), "ms": int(ms), "title": title, "artist": artist, "album": album, "end": end, "sk": sk}, None


def skip_decision(ms: int, end: str, sk: bool | None, fmt: str) -> str:
    """'skip' | 'listen' | 'unclear'. The owner's rule:
      * ran to its end (`trackdone`, at least 1 s heard)            -> listen
      * 30 s or more heard                                            -> listen
      * under 30 s, ended by the forward/back button, or `skipped`    -> skip
      * the basic export has no reason at all: under 30 s             -> skip
      * under 30 s, ended any other way (logout, app closed, remote)  -> unclear (not imported)"""
    if end == "trackdone" and ms >= 1000:
        return "listen"
    if ms >= SKIP_MS:
        return "listen"
    if end in SKIP_ENDS or sk is True or fmt == "basic":
        return "skip"
    return "unclear"


def measure(kind: str, ms: int, end: str, duration_s: float | None) -> dict:
    """seconds_played, listen_ratio, event_type and end_reason for the listening log (play-events-v2 rules: a
    `complete` is at least half heard; seconds never exceed the song's length)."""
    secs = ms / 1000.0
    dur = float(duration_s) if duration_s and duration_s > 0 else None
    if dur:
        secs = min(secs, dur)
    ratio = min(1.0, secs / (dur or ex.DEFAULT_DURATION_S))
    if kind == "skip":
        return {"secs": secs, "ratio": ratio, "type": "skip", "reason": "backbtn" if end == "backbtn" else "fwdbtn"}
    if ratio >= 0.5:
        return {"secs": secs, "ratio": ratio, "type": "complete", "reason": "natural"}
    return {"secs": secs, "ratio": ratio, "type": "skip", "reason": "partial"}


def uid_of(ts: int, artist: str, title: str) -> str:
    return hi.uid_of(SOURCE, ts, artist, title)


# ── jobs ─────────────────────────────────────────────────────────────────────

def get_extra(conn, job_id: int) -> dict:
    r = conn.execute("SELECT * FROM spotify_jobs WHERE job_id=?", (job_id,)).fetchone()
    return dict(r) if r else {"job_id": job_id, "format": "extended", "pages": 0, "skips": 0, "listens": 0,
                              "unclear": 0, "skip_misses": 0, "rejected": "{}"}


def summary(conn, job: dict) -> dict:
    s = hi.summary(conn, job)
    x = get_extra(conn, job["id"])
    s.update(format=x["format"], pages=x["pages"], skips=x["skips"], listens=x["listens"], unclear=x["unclear"],
             skip_misses=x["skip_misses"], rejected=json.loads(x["rejected"] or "{}"),
             rejected_total=job["skipped"])
    return s


def create_job(conn, user: str, fmt: str, total=None, now: float | None = None) -> tuple[dict, bool]:
    """(job, created). An unfinished Spotify job is returned as it is (resume: sending the pages again adds nothing)."""
    ensure_schema(conn)
    if fmt not in FORMATS:
        raise hi.HistoryError("Choose the extended or the basic Spotify export.", fatal=True)
    now = time.time() if now is None else now
    open_ = conn.execute("SELECT * FROM history_jobs WHERE user=? AND source=? AND status IN ('ready','error') "
                         "ORDER BY id DESC LIMIT 1", (user, SOURCE)).fetchone()
    if open_:
        return dict(open_), False
    total = int(total) if isinstance(total, (int, float)) and not isinstance(total, bool) and 0 <= total <= MAX_TOTAL \
        else None
    prev = conn.execute("SELECT wishlist_id FROM history_jobs WHERE user=? AND source=? AND wishlist_id IS NOT NULL "
                        "ORDER BY id DESC LIMIT 1", (user, SOURCE)).fetchone()
    job_id = conn.execute(
        "INSERT INTO history_jobs (user, source, account, since_ts, to_ts, total, wishlist_id, created_at, updated_at) "
        "VALUES (?,?,?,?,?,?,?,?,?)", (user, SOURCE, "spotify export", 0, int(now), total, prev[0] if prev else None,
                                       now, now)).lastrowid
    # history-import-v1's undo deletes the job row; its id is then reused, so a leftover counter row must not survive.
    conn.execute("DELETE FROM spotify_jobs WHERE job_id NOT IN (SELECT id FROM history_jobs) OR job_id=?", (job_id,))
    conn.execute("INSERT INTO spotify_jobs (job_id, user, format) VALUES (?,?,?)", (job_id, user, fmt))
    return hi.get_job(conn, job_id, user), True


_IDX: dict = {"key": None, "idx": None, "by_id": None}


def _index(library: list[dict]) -> Index:
    """The matcher index of this library, kept between pages (a full export is hundreds of pages)."""
    key = (id(library), len(library))
    if _IDX["key"] != key:
        _IDX.update(key=key, idx=Index(library), by_id={s["id"]: s for s in library})
    return _IDX["idx"]


def page(conn, job_id: int, user: str, library: list[dict], plays, now: float | None = None) -> dict:
    """Validate, decide, match and write one page. Idempotent: a page sent twice adds nothing the second time."""
    ensure_schema(conn)
    job = hi.get_job(conn, job_id, user)
    if job is None or job["source"] != SOURCE:
        raise hi.HistoryError("No such import.", fatal=True)
    if job["status"] in ("done", "cancelled"):
        return {**summary(conn, job), "done": True, "wait_s": 0}
    if not isinstance(plays, list) or len(plays) > MAX_PAGE:
        raise hi.HistoryError(f"Send at most {MAX_PAGE} plays at a time.", fatal=False)
    with hi._LOCK:
        if job_id in hi._RUNNING:
            raise hi.Busy()
        hi._RUNNING.add(job_id)
    try:
        return _page(conn, job, library, plays, time.time() if now is None else now)
    finally:
        with hi._LOCK:
            hi._RUNNING.discard(job_id)


def _page(conn, job: dict, library: list[dict], plays: list, now: float) -> dict:
    user, extra = job["user"], get_extra(conn, job["id"])
    fmt = extra["format"]
    rejected: dict[str, int] = json.loads(extra["rejected"] or "{}")
    idx = _index(library)
    cache: dict[str, dict | None] = {}
    items, bad = [], 0
    for raw in plays:
        row, why = clean_row(raw, now)
        if row is None:
            bad += 1
            rejected[why] = rejected.get(why, 0) + 1
            continue
        kind = skip_decision(row["ms"], row["end"], row["sk"], fmt)
        key = ex.song_key("", row["title"], row["artist"])
        if key not in cache:
            cache[key] = idx.find(row["title"], row["artist"], None, hi.DURATION_SLACK_S)
        items.append({**row, "kind": kind, "key": key, "hit": cache[key], "uid": uid_of(row["t"], row["artist"], row["title"])})
    uids = [i["uid"] for i in items]
    known: set[str] = set()
    for n in range(0, len(uids), 500):
        part = uids[n:n + 500]
        known.update(r[0] for r in conn.execute(
            f"SELECT uid FROM history_seen WHERE user=? AND uid IN ({','.join('?' * len(part))})", (user, *part)))
    fresh, already, seen_batch, unclear = [], 0, set(), 0
    for i in items:
        if i["uid"] in known or i["uid"] in seen_batch:
            already += 1
            continue
        seen_batch.add(i["uid"])
        if i["kind"] == "unclear":
            unclear += 1
            continue
        if i["hit"]:
            lib_dur = float(i["hit"].get("duration") or 0) or None
            m = measure(i["kind"], i["ms"], i["end"], lib_dur)
            start = i["t"] - int(round(i["ms"] / 1000.0))             # Spotify's time is when the play ENDED
            i.update(title_lib=i["hit"]["title"], nd_song_id=i["hit"]["id"], lib_duration=int(lib_dur) if lib_dur else None,
                     m=m, ts=start)
        fresh.append(i)
    matched = [i for i in fresh if i["hit"]]
    log_db = open_log(user)
    try:
        near = hi.near_duplicates(log_db, SOURCE, matched)
        to_write = [i for i in matched if i["uid"] not in near]
        rows = []
        for i in to_write:
            when = datetime.fromtimestamp(i["ts"], IST)
            m = i["m"]
            rows.append((i["title_lib"], i["nd_song_id"], i["ts"], when.isoformat(), when.hour, when.weekday(),
                         when.month, m["ratio"], i["lib_duration"], m["reason"], f"import:{SOURCE}", i["uid"],
                         m["type"], m["secs"], when.hour, int(now)))
        log_db.executemany(INSERT_SQL, rows)             # idempotent (play_id): a crash after this re-runs safely
        log_db.commit()
    finally:
        log_db.close()
    touched, imported, wished, skips, listens, skip_misses = {}, 0, 0, 0, 0, 0
    times = [r["t"] for r in items]
    conn.execute("BEGIN IMMEDIATE")
    try:
        for i in fresh:
            if i["uid"] in near:
                state = "near_dup"
            elif i["hit"]:
                state = "imported"
            elif i["kind"] == "listen":
                state = "wished"
            else:
                state = "dropped"                          # a skip of a song that is not in the library
            conn.execute("INSERT OR IGNORE INTO history_seen (user, uid, job_id, source, ts, state) VALUES (?,?,?,?,?,?)",
                         (user, i["uid"], job["id"], SOURCE, i["t"], state))
            if state == "near_dup":
                continue
            if state == "dropped":
                skip_misses += 1
                continue
            skips += i["kind"] == "skip"
            listens += i["kind"] == "listen"
            imported += state == "imported"
            wished += state == "wished"
            nd = i["hit"]["id"] if i["hit"] else None
            conn.execute(
                "INSERT INTO history_tracks (user, source, key, title, artist, album, isrc, nd_song_id, plays, "
                "first_ts, last_ts) VALUES (?,?,?,?,?,?,NULL,?,1,?,?) ON CONFLICT(user, source, key) DO UPDATE SET "
                "plays=plays+1, first_ts=MIN(first_ts, excluded.first_ts), last_ts=MAX(last_ts, excluded.last_ts), "
                "nd_song_id=COALESCE(excluded.nd_song_id, nd_song_id)",
                (user, SOURCE, i["key"], i["title"], i["artist"], i["album"], nd, i["t"], i["t"]))
            touched[i["key"]] = {"title": i["title"], "artist": i["artist"], "album": i["album"], "isrc": ""}
        wid = hi._sync_wishlist(conn, job, touched) if touched else job["wishlist_id"]
        hi._save(conn, job["id"], fetched=job["fetched"] + len(plays),
                 imported=job["imported"] + imported, wished=job["wished"] + wished,
                 already=job["already"] + already, near_dups=job["near_dups"] + len(near),
                 skipped=job["skipped"] + bad, wishlist_id=wid, error=None,
                 newest_ts=max([job["newest_ts"], *times]),
                 oldest_ts=min([t for t in [job["oldest_ts"], *times] if t] or [0]))
        conn.execute("UPDATE spotify_jobs SET pages=pages+1, skips=skips+?, listens=listens+?, unclear=unclear+?, "
                     "skip_misses=skip_misses+?, rejected=? WHERE job_id=?",
                     (skips, listens, unclear, skip_misses, json.dumps(rejected, sort_keys=True), job["id"]))
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    job = hi.get_job(conn, job["id"], user)
    log.info("spotify-history: job %s page ok: %d rows, %d written, %d wished, %d already, %d refused",
             job["id"], len(plays), imported, wished, already, bad)
    return {**summary(conn, job), "done": False, "wait_s": 0}


def finish(conn, job_id: int, user: str, now: float | None = None) -> dict:
    ensure_schema(conn)
    job = hi.get_job(conn, job_id, user)
    if job is None or job["source"] != SOURCE:
        raise hi.HistoryError("No such import.", fatal=True)
    if job["status"] in ("ready", "error"):
        hi._save(conn, job_id, status="done", done_at=time.time() if now is None else now, error=None)
        job = hi.get_job(conn, job_id, user)
    return {**summary(conn, job), "done": True, "wait_s": 0}
