"""
tgfetch/history_import.py  (history-import-v1)
──────────────────────────────────────────────
Bring a person's past ListenBrainz listens or Last.fm scrobbles into the shuffle server's taste data.

  * Paged and resumable: the app asks for one page at a time ("step"); the cursor lives in fetch.db, so a
    closed app, a dropped connection or a restart loses nothing. Nothing runs in the background.
  * Rate-limited: one request at a time per service, at least MIN_GAP_S apart; a 429 or Last.fm's
    "rate limit exceeded" is handed back as "wait N seconds", never retried in a loop.
  * Matched songs (ISRC, then clean title + an artist in common + length, the Exportify matcher) are written
    to the user's listening log (`play_events`, session_id `import:<source>`), where the nightly recommender
    reads them with its usual time decay. Songs that are not in the library go on the user's Wishlist: an
    Exportify import named "ListenBrainz history" / "Last.fm history", fetched by the same plan and timer.
  * Never double counts: every listen has a fixed id (source, time, artist, title). The id is recorded
    in `history_seen` and is the play's `play_id`, so re-running the import, or a page that was written
    before a crash, adds nothing. A listen that an earlier import from the other service (or the app's own
    live logging) already has, same song within DUP_WINDOW_S, is dropped as a near duplicate.
  * Secrets: a Last.fm API key or ListenBrainz token comes with each step, is used for that request and is
    never stored or logged. Errors are logged by type only (a Last.fm URL carries the key).

Source of truth for the listening log's layout: navivibe/feedback.py (CREATE_SQL + play_id unique index).
"""

import hashlib
import json
import logging
import os
import re
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from zoneinfo import ZoneInfo

from tgfetch import exportify as ex
from tgfetch.library_sweep import Index

log = logging.getLogger("tgfetch.history_import")

IST = ZoneInfo("Asia/Kolkata")
SOURCES = {"listenbrainz": "ListenBrainz history", "lastfm": "Last.fm history"}
LB_PAGE = 500                    # listens a page (ListenBrainz allows up to 1000)
LFM_PAGE = 200                   # Last.fm's maximum
MIN_GAP_S = {"listenbrainz": 0.6, "lastfm": 0.25}     # between two requests to one service
HTTP_TIMEOUT_S = 25
DUP_WINDOW_S = 120               # the same song this close to a play we already have is the same play
MAX_WISHLIST = ex.MAX_ROWS
DURATION_SLACK_S = ex.DURATION_SLACK_S
ACCOUNT_RE = re.compile(r"^[^\x00-\x1f/\\?#%]{1,64}$")
LFM_KEY_RE = re.compile(r"^[0-9a-fA-F]{32}$")
LB_TOKEN_RE = re.compile(r"^[A-Za-z0-9\-]{8,64}$")
LB_URL = "https://api.listenbrainz.org/1"
LFM_URL = "https://ws.audioscrobbler.com/2.0/"

SCHEMA = """
CREATE TABLE IF NOT EXISTS history_jobs (
    id            INTEGER PRIMARY KEY,
    user          TEXT NOT NULL,
    source        TEXT NOT NULL,
    account       TEXT NOT NULL,
    status        TEXT NOT NULL DEFAULT 'ready',     -- ready | done | error | cancelled
    cursor        INTEGER NOT NULL DEFAULT 0,        -- listenbrainz: max_ts of the next page; lastfm: next page - 1
    since_ts      INTEGER NOT NULL DEFAULT 0,        -- only listens after this
    to_ts         INTEGER NOT NULL DEFAULT 0,        -- lastfm: the fixed upper bound, so pages do not shift
    total         INTEGER,
    fetched       INTEGER NOT NULL DEFAULT 0,
    imported      INTEGER NOT NULL DEFAULT 0,        -- plays written to the listening log
    wished        INTEGER NOT NULL DEFAULT 0,        -- plays of songs that are not in the library
    already       INTEGER NOT NULL DEFAULT 0,        -- seen by an earlier run: not counted again
    near_dups     INTEGER NOT NULL DEFAULT 0,
    skipped       INTEGER NOT NULL DEFAULT 0,        -- no title/artist or an impossible time
    newest_ts     INTEGER NOT NULL DEFAULT 0,
    oldest_ts     INTEGER NOT NULL DEFAULT 0,
    wishlist_id   INTEGER,                           -- exportify_imports.id
    error         TEXT,
    created_at    REAL NOT NULL,
    updated_at    REAL NOT NULL,
    done_at       REAL
);
CREATE INDEX IF NOT EXISTS history_jobs_user ON history_jobs(user, source);
CREATE TABLE IF NOT EXISTS history_seen (
    user   TEXT NOT NULL,
    uid    TEXT NOT NULL,
    job_id INTEGER NOT NULL,
    source TEXT NOT NULL,
    ts     INTEGER NOT NULL,
    state  TEXT NOT NULL,                            -- imported | wished | near_dup
    PRIMARY KEY (user, uid)
);
CREATE INDEX IF NOT EXISTS history_seen_job ON history_seen(job_id);
CREATE TABLE IF NOT EXISTS history_tracks (
    user       TEXT NOT NULL,
    source     TEXT NOT NULL,
    key        TEXT NOT NULL,
    title      TEXT NOT NULL,
    artist     TEXT NOT NULL,
    album      TEXT NOT NULL DEFAULT '',
    isrc       TEXT,
    nd_song_id TEXT,                                 -- null: not in the library
    plays      INTEGER NOT NULL DEFAULT 0,
    first_ts   INTEGER NOT NULL,
    last_ts    INTEGER NOT NULL,
    PRIMARY KEY (user, source, key)
);
"""


class HistoryError(Exception):
    """Something the person can read. `retry_after` set: try again then (nothing was lost);
    `fatal`: the job cannot go on as it is (wrong name, bad key)."""

    def __init__(self, message: str, retry_after: float | None = None, fatal: bool = False):
        super().__init__(message)
        self.retry_after = retry_after
        self.fatal = fatal


def ensure_schema(conn) -> None:
    ex.ensure_schema(conn)
    conn.executescript(SCHEMA)


# ── HTTP (replaced in tests: nothing in the test suite touches the network) ──

def http_get(url: str, headers: dict | None = None) -> tuple[int, dict, object]:
    """(status, lower-cased response headers, parsed JSON or None). Never raises for an HTTP status."""
    req = urllib.request.Request(url, headers={"User-Agent": "NaviVibe-history-import/1", "Accept": "application/json",
                                               **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_S) as r:
            status, hdrs, body = r.status, r.headers, r.read(20_000_000)
    except urllib.error.HTTPError as e:
        status, hdrs, body = e.code, e.headers, e.read(1_000_000)
    except (urllib.error.URLError, TimeoutError, OSError) as e:        # never print `e`: a Last.fm URL holds the key
        raise HistoryError("Couldn’t reach the service. Try again in a moment.", retry_after=20) from None
    try:
        data = json.loads(body.decode("utf-8", "replace")) if body else None
    except ValueError:
        data = None
    return status, {k.lower(): v for k, v in hdrs.items()}, data


HTTP = http_get                 # tests swap this


class Limiter:
    """One request at a time per service, MIN_GAP_S apart (a lock + the time of the last request)."""

    def __init__(self, clock=time.monotonic, sleep=time.sleep):
        self.clock, self.sleep = clock, sleep
        self._lock = threading.Lock()
        self._last: dict[str, float] = {}

    def wait(self, service: str) -> None:
        with self._lock:
            gap = MIN_GAP_S[service] - (self.clock() - self._last.get(service, -1e9))
            if gap > 0:
                self.sleep(gap)
            self._last[service] = self.clock()


LIMITER = Limiter()


def _get(service: str, url: str, headers: dict | None = None):
    LIMITER.wait(service)
    return HTTP(url, headers)


# ── reading the services ─────────────────────────────────────────────────────

def _retry_after(headers: dict, default: float) -> float:
    for k in ("retry-after", "x-ratelimit-reset-in"):
        try:
            return min(300.0, max(1.0, float(headers.get(k, ""))))
        except (TypeError, ValueError):
            continue
    return default


def _int(v, default=0) -> int:
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return default


def lb_headers(token: str | None) -> dict:
    if token:
        if not LB_TOKEN_RE.match(token):
            raise HistoryError("That doesn’t look like a ListenBrainz token.", fatal=True)
        return {"Authorization": f"Token {token}"}
    return {}


def lb_total(account: str, token: str | None) -> int | None:
    """Listens on the profile (a hint for the progress bar; None when it can't be read)."""
    try:
        status, _, data = _get("listenbrainz", f"{LB_URL}/user/{urllib.parse.quote(account, safe='')}/listen-count",
                               lb_headers(token))
    except HistoryError:
        return None
    if status == 200 and isinstance(data, dict):
        return _int(((data.get("payload") or {}).get("count")), 0) or None
    return None


def lb_page(job: dict, token: str | None) -> tuple[list[dict], int, bool]:
    """(listens newest first, next cursor, exhausted). Pages walk back in time with max_ts."""
    q = {"count": LB_PAGE}
    if job["cursor"]:
        q["max_ts"] = job["cursor"]
    if job["since_ts"]:
        q["min_ts"] = job["since_ts"]
    url = f"{LB_URL}/user/{urllib.parse.quote(job['account'], safe='')}/listens?" + urllib.parse.urlencode(q)
    status, hdrs, data = _get("listenbrainz", url, lb_headers(token))
    if status == 429:
        raise HistoryError("ListenBrainz asked us to slow down.", retry_after=_retry_after(hdrs, 30))
    if status == 404:
        raise HistoryError("ListenBrainz doesn’t know that username.", fatal=True)
    if status in (401, 403):
        raise HistoryError("ListenBrainz refused the token.", fatal=True)
    if status >= 500 or status == 0:
        raise HistoryError("ListenBrainz is having trouble. Try again in a minute.", retry_after=60)
    if status != 200 or not isinstance(data, dict):
        raise HistoryError(f"ListenBrainz answered {status}.", retry_after=60)
    payload = data.get("payload") or {}
    out = []
    for item in payload.get("listens") or []:
        tm = item.get("track_metadata") or {}
        info = tm.get("additional_info") or {}
        dur = _int(info.get("duration")) or (_int(info.get("duration_ms")) // 1000)
        out.append({"ts": _int(item.get("listened_at")), "title": tm.get("track_name"),
                    "artist": tm.get("artist_name"), "album": tm.get("release_name") or "",
                    "isrc": (info.get("isrc") or "").strip().upper(), "duration_s": dur or None})
    if not out:
        return [], job["cursor"], True
    oldest = min((l["ts"] for l in out if l["ts"] > 0), default=0)
    if not oldest or (job["cursor"] and oldest >= job["cursor"]):      # no way to move on: stop, don't loop
        return out, job["cursor"], True
    return out, oldest, False


LFM_FATAL = {4: "Last.fm refused the request.", 6: "Last.fm doesn’t know that username.",
             10: "That Last.fm API key isn’t valid.", 26: "That Last.fm API key was suspended.",
             17: "That Last.fm profile is private. Make recent listening public or use another account."}
LFM_RETRY = {8: 20, 11: 30, 16: 30, 29: 15}


def lfm_page(job: dict, api_key: str | None) -> tuple[list[dict], int, bool, int | None]:
    """(scrobbles newest first, next cursor, exhausted, total). The cursor is the last page read."""
    if not api_key or not LFM_KEY_RE.match(api_key):
        raise HistoryError("Enter your Last.fm API key (32 letters and numbers).", fatal=True)
    page = job["cursor"] + 1
    q = {"method": "user.getRecentTracks", "user": job["account"], "api_key": api_key, "format": "json",
         "limit": LFM_PAGE, "page": page, "to": job["to_ts"]}
    if job["since_ts"]:
        q["from"] = job["since_ts"] + 1
    status, hdrs, data = _get("lastfm", LFM_URL + "?" + urllib.parse.urlencode(q))
    if status == 429:
        raise HistoryError("Last.fm asked us to slow down.", retry_after=_retry_after(hdrs, 20))
    if isinstance(data, dict) and "error" in data:
        code = _int(data.get("error"))
        if code in LFM_FATAL:
            raise HistoryError(LFM_FATAL[code], fatal=True)
        raise HistoryError("Last.fm is busy. Trying again shortly.", retry_after=LFM_RETRY.get(code, 30))
    if status >= 500 or status == 0:
        raise HistoryError("Last.fm is having trouble. Try again in a minute.", retry_after=60)
    if status != 200 or not isinstance(data, dict) or "recenttracks" not in data:
        raise HistoryError(f"Last.fm answered {status}.", retry_after=60)
    rt = data["recenttracks"] or {}
    attr = rt.get("@attr") or {}
    tracks = rt.get("track") or []
    if isinstance(tracks, dict):
        tracks = [tracks]
    out = []
    for t in tracks:
        if (t.get("@attr") or {}).get("nowplaying"):                    # still playing: no time yet
            continue
        artist = t.get("artist") or {}
        album = t.get("album") or {}
        out.append({"ts": _int((t.get("date") or {}).get("uts")), "title": t.get("name"),
                    "artist": artist.get("#text") if isinstance(artist, dict) else artist,
                    "album": (album.get("#text") if isinstance(album, dict) else album) or "",
                    "isrc": "", "duration_s": None})
    pages = _int(attr.get("totalPages"), 1)
    return out, page, page >= pages or not tracks, _int(attr.get("total")) or None


# ── the listening log (navivibe/feedback.py's table; the same file the shuffle server writes) ───

LOG_COLUMNS = ("track_title, file_path, genre_bucket, composer, played_at, ist_timestamp, ist_hour, day_of_week, "
               "month, weather_code, temperature_c, listen_ratio, duration_s, end_reason, session_id, "
               "session_depth, genre_streak_type, genre_streak_count, volume, processed, play_id")
LOG_SQL = """
CREATE TABLE IF NOT EXISTS play_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT, track_title TEXT NOT NULL, file_path TEXT, genre_bucket TEXT,
    composer TEXT, played_at INTEGER NOT NULL, ist_timestamp TEXT, ist_hour INTEGER, day_of_week INTEGER,
    month INTEGER, weather_code INTEGER, temperature_c REAL, listen_ratio REAL, duration_s INTEGER,
    end_reason TEXT, session_id TEXT, session_depth INTEGER, genre_streak_type TEXT, genre_streak_count INTEGER,
    volume REAL, processed INTEGER DEFAULT 0, play_id TEXT)
"""


def log_path(user: str) -> str:
    if not user or "/" in user or "\\" in user or user.startswith(".") or "\x00" in user:
        raise HistoryError("This account name can’t be used for a listening log.", fatal=True)
    base = os.environ.get("NAVIVIBE_LOG_DIR", "/DATA/AppData/navivibe/listening_logs")
    return os.path.join(base, f"{user}_listening_log.db")


def open_log(user: str) -> sqlite3.Connection:
    path = log_path(user)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    c = sqlite3.connect(path, timeout=10)
    c.execute("PRAGMA journal_mode=WAL")
    c.execute("PRAGMA busy_timeout=10000")
    c.execute(LOG_SQL)
    cols = {r[1] for r in c.execute("PRAGMA table_info(play_events)")}
    for name, typ in (("ist_timestamp", "TEXT"), ("duration_s", "INTEGER"), ("play_id", "TEXT")):
        if name not in cols:
            c.execute(f"ALTER TABLE play_events ADD COLUMN {name} {typ}")
    c.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_play_events_play_id ON play_events(play_id) "
              "WHERE play_id IS NOT NULL")
    c.commit()
    return c


def _norm(s: str) -> str:
    return re.sub(r"\s+", " ", (s or "").casefold()).strip()


def uid_of(source: str, ts: int, artist: str, title: str) -> str:
    h = hashlib.sha1(f"{source}|{ts}|{_norm(artist)}|{_norm(title)}".encode()).hexdigest()[:20]
    return f"imp:{source}:{h}"


def near_duplicates(log: sqlite3.Connection, source: str, items: list[dict]) -> set[str]:
    """uids of items whose song is already in the log within DUP_WINDOW_S (live play, or another service's import)."""
    if not items:
        return set()
    lo, hi = min(i["ts"] for i in items) - DUP_WINDOW_S, max(i["ts"] for i in items) + DUP_WINDOW_S
    have: dict[str, list[int]] = {}
    for title, at in log.execute(
            "SELECT track_title, played_at FROM play_events WHERE played_at BETWEEN ? AND ? "
            "AND (play_id IS NULL OR play_id NOT LIKE ?)", (lo, hi, f"imp:{source}:%")):
        have.setdefault(title, []).append(at)
    return {i["uid"] for i in items
            if any(abs(at - i["ts"]) <= DUP_WINDOW_S for at in have.get(i["title_lib"], ()))}


def write_plays(log: sqlite3.Connection, source: str, items: list[dict]) -> None:
    rows = []
    for i in items:
        when = datetime.fromtimestamp(i["ts"], IST)
        rows.append((i["title_lib"], i["nd_song_id"], None, None, i["ts"], when.isoformat(), when.hour,
                     when.weekday(), when.month, None, None, 1.0, i.get("lib_duration"), "natural",
                     f"import:{source}", None, None, None, None, 0, i["uid"]))
    log.executemany(f"INSERT OR IGNORE INTO play_events ({LOG_COLUMNS}) VALUES ({','.join('?' * 21)})", rows)
    log.commit()


# ── jobs ─────────────────────────────────────────────────────────────────────

def clean_account(account) -> str:
    a = (account or "").strip() if isinstance(account, str) else ""
    if a.startswith("https://") or a.startswith("http://"):          # a pasted profile link: keep the last part
        a = urllib.parse.unquote(a.rstrip("/").rsplit("/", 1)[-1])
    if not ACCOUNT_RE.match(a):
        raise HistoryError("Enter your username.", fatal=True)
    return a


def get_job(conn, job_id: int, user: str) -> dict | None:
    r = conn.execute("SELECT * FROM history_jobs WHERE id=? AND user=?", (job_id, user)).fetchone()
    return dict(r) if r else None


def summary(conn, job: dict) -> dict:
    songs = conn.execute("SELECT COUNT(*), SUM(nd_song_id IS NOT NULL) FROM history_tracks WHERE user=? AND source=?",
                         (job["user"], job["source"])).fetchone()
    return {"id": job["id"], "source": job["source"], "account": job["account"], "status": job["status"],
            "total": job["total"], "fetched": job["fetched"], "imported": job["imported"],
            "wished": job["wished"], "already": job["already"], "near_dups": job["near_dups"],
            "skipped": job["skipped"], "songs_matched": int(songs[1] or 0),
            "songs_unmatched": int(songs[0] or 0) - int(songs[1] or 0),
            "newest_ts": job["newest_ts"] or None, "oldest_ts": job["oldest_ts"] or None,
            "wishlist_id": job["wishlist_id"], "error": job["error"], "incremental": bool(job["since_ts"]),
            "created_at": job["created_at"], "done_at": job["done_at"]}


def create_job(conn, user: str, source: str, account, full: bool = False, token: str | None = None,
               now: float | None = None) -> tuple[dict, bool]:
    """(job, created). An unfinished job for the same account is returned as it is: that is the resume."""
    ensure_schema(conn)
    if source not in SOURCES:
        raise HistoryError("Choose ListenBrainz or Last.fm.", fatal=True)
    account = clean_account(account)
    now = time.time() if now is None else now
    open_ = conn.execute("SELECT * FROM history_jobs WHERE user=? AND source=? AND account=? AND status IN "
                         "('ready','error') ORDER BY id DESC LIMIT 1", (user, source, account)).fetchone()
    if open_:
        return dict(open_), False
    since = 0
    if not full:
        r = conn.execute("SELECT MAX(newest_ts) FROM history_jobs WHERE user=? AND source=? AND account=? "
                         "AND status='done'", (user, source, account)).fetchone()
        since = int(r[0] or 0)
    prev = conn.execute("SELECT wishlist_id FROM history_jobs WHERE user=? AND source=? AND wishlist_id IS NOT NULL "
                        "ORDER BY id DESC LIMIT 1", (user, source)).fetchone()
    job_id = conn.execute(
        "INSERT INTO history_jobs (user, source, account, since_ts, to_ts, wishlist_id, created_at, updated_at) "
        "VALUES (?,?,?,?,?,?,?,?)", (user, source, account, since, int(now), prev[0] if prev else None, now, now)
    ).lastrowid
    return get_job(conn, job_id, user), True


def _save(conn, job_id: int, **fields) -> None:
    fields["updated_at"] = time.time()
    conn.execute("UPDATE history_jobs SET " + ", ".join(f"{k}=?" for k in fields) + " WHERE id=?",
                 (*fields.values(), job_id))


def _wishlist(conn, job: dict) -> int:
    """The Exportify import that holds this user's unmatched songs for the source (made on first use)."""
    wid = job.get("wishlist_id")
    if wid and conn.execute("SELECT 1 FROM exportify_imports WHERE id=? AND user=?", (wid, job["user"])).fetchone():
        return wid
    now = time.time()
    wid = conn.execute("INSERT INTO exportify_imports (user, name, created_at, total_rows) VALUES (?,?,?,0)",
                       (job["user"], SOURCES[job["source"]], now)).lastrowid
    conn.execute("INSERT INTO exportify_plans (import_id, user, status, updated_at) VALUES (?,?, 'idle', ?)",
                 (wid, job["user"], now))
    return wid


def _sync_wishlist(conn, job: dict, touched: dict[str, dict]) -> int:
    """Put the touched unmatched songs on the Wishlist, popularity = their play count (max 100)."""
    wid = _wishlist(conn, job)
    now = time.time()
    n = conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE import_id=?", (wid,)).fetchone()[0]
    for key, t in touched.items():
        plays = conn.execute("SELECT plays, nd_song_id FROM history_tracks WHERE user=? AND source=? AND key=?",
                             (job["user"], job["source"], key)).fetchone()
        if plays is None:
            continue
        row = conn.execute("SELECT id, state FROM exportify_songs WHERE import_id=? AND key=?", (wid, key)).fetchone()
        if plays["nd_song_id"]:                                        # it is in the library now
            if row and row["state"] in ("wishlist", "skipped_disk"):
                conn.execute("UPDATE exportify_songs SET state='owned', how='title', nd_song_id=?, updated_at=? "
                             "WHERE id=?", (plays["nd_song_id"], now, row["id"]))
            continue
        pop = min(100, plays["plays"])
        if row:
            conn.execute("UPDATE exportify_songs SET popularity=?, updated_at=? WHERE id=?", (pop, now, row["id"]))
        elif n < MAX_WISHLIST:
            conn.execute(
                "INSERT INTO exportify_songs (import_id, user, pos, key, isrc, title, artist, album, popularity, "
                "state, details, updated_at) VALUES (?,?,?,?,?,?,?,?,?, 'wishlist', '{}', ?)",
                (wid, job["user"], n, key, t["isrc"] or None, t["title"], t["artist"], t["album"], pop, now))
            n += 1
    conn.execute("UPDATE exportify_imports SET total_rows=? WHERE id=?",
                 (conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE import_id=?", (wid,)).fetchone()[0], wid))
    return wid


_LOCK = threading.Lock()
_RUNNING: set[int] = set()


class Busy(Exception):
    pass


def step(conn, job_id: int, user: str, library: list[dict], secret: str | None = None,
         now: float | None = None) -> dict:
    """Read one page, match it, write it. Returns the summary + `wait_s` (when to call again) + `done`.
    `secret`: the Last.fm API key or ListenBrainz token for this request only."""
    ensure_schema(conn)
    job = get_job(conn, job_id, user)
    if job is None:
        raise HistoryError("No such import.", fatal=True)
    if job["status"] in ("done", "cancelled"):
        return {**summary(conn, job), "done": True, "wait_s": 0}
    with _LOCK:
        if job_id in _RUNNING:
            raise Busy()
        _RUNNING.add(job_id)
    try:
        return _step(conn, job, library, secret, time.time() if now is None else now)
    finally:
        with _LOCK:
            _RUNNING.discard(job_id)


def _step(conn, job: dict, library: list[dict], secret: str | None, now: float) -> dict:
    source = job["source"]
    try:
        if source == "listenbrainz":
            if job["total"] is None and job["fetched"] == 0:
                job["total"] = lb_total(job["account"], secret)
            listens, cursor, exhausted = lb_page(job, secret)
        else:
            listens, cursor, exhausted, total = lfm_page(job, secret)
            job["total"] = total or job["total"]
    except HistoryError as e:
        _save(conn, job["id"], error=str(e), status="error" if e.fatal else job["status"], total=job["total"])
        job = get_job(conn, job["id"], job["user"])
        return {**summary(conn, job), "done": False, "wait_s": e.retry_after or 0, "fatal": e.fatal}
    by_isrc = {s["isrc"].upper(): s for s in library if s.get("isrc")}
    idx = Index(library)
    cache: dict[str, dict | None] = {}
    seen_batch: set[str] = set()
    items, skipped = [], 0
    for l in listens:
        title, artist = (l["title"] or "").strip(), (l["artist"] or "").strip()
        if not title or not artist or l["ts"] <= 0 or l["ts"] > now + 300:
            skipped += 1
            continue
        key = ex.song_key(l["isrc"], title, artist)
        if key not in cache:
            hit = by_isrc.get(l["isrc"]) if l["isrc"] else None
            hit = hit or idx.find(title, artist, l["duration_s"], DURATION_SLACK_S)
            cache[key] = hit
        items.append({**l, "title": title, "artist": artist, "key": key, "hit": cache[key],
                      "uid": uid_of(source, l["ts"], artist, title)})
    uids = [i["uid"] for i in items]
    known: set[str] = set()
    for n in range(0, len(uids), 500):
        part = uids[n:n + 500]
        known.update(r[0] for r in conn.execute(
            f"SELECT uid FROM history_seen WHERE user=? AND uid IN ({','.join('?' * len(part))})",
            (job["user"], *part)))
    fresh, already = [], 0
    for i in items:
        if i["uid"] in known or i["uid"] in seen_batch:
            already += 1
            continue
        seen_batch.add(i["uid"])
        if i["hit"]:
            i.update(title_lib=i["hit"]["title"], nd_song_id=i["hit"]["id"],
                     lib_duration=int(float(i["hit"].get("duration") or 0)) or None)
        fresh.append(i)
    matched = [i for i in fresh if i["hit"]]
    plays_db = open_log(job["user"])
    try:
        near = near_duplicates(plays_db, source, matched)
        to_write = [i for i in matched if i["uid"] not in near]
        write_plays(plays_db, source, to_write)      # idempotent (play_id): a crash after this re-runs safely
    finally:
        plays_db.close()
    touched, imported, wished = {}, 0, 0
    conn.execute("BEGIN IMMEDIATE")
    try:
        for i in fresh:
            state = "near_dup" if i["uid"] in near else ("imported" if i["hit"] else "wished")
            conn.execute("INSERT OR IGNORE INTO history_seen (user, uid, job_id, source, ts, state) VALUES (?,?,?,?,?,?)",
                         (job["user"], i["uid"], job["id"], source, i["ts"], state))
            if state == "near_dup":
                continue
            imported += state == "imported"
            wished += state == "wished"
            nd = i["hit"]["id"] if i["hit"] else None
            conn.execute(
                "INSERT INTO history_tracks (user, source, key, title, artist, album, isrc, nd_song_id, plays, "
                "first_ts, last_ts) VALUES (?,?,?,?,?,?,?,?,1,?,?) ON CONFLICT(user, source, key) DO UPDATE SET "
                "plays=plays+1, first_ts=MIN(first_ts, excluded.first_ts), last_ts=MAX(last_ts, excluded.last_ts), "
                "nd_song_id=COALESCE(excluded.nd_song_id, nd_song_id)",
                (job["user"], source, i["key"], i["title"], i["artist"], i["album"], i["isrc"] or None, nd,
                 i["ts"], i["ts"]))
            touched[i["key"]] = i
        times = [l["ts"] for l in listens if l["ts"] > 0]
        wid = _sync_wishlist(conn, job, touched) if touched else job["wishlist_id"]
        _save(conn, job["id"], cursor=cursor, total=job["total"], fetched=job["fetched"] + len(listens),
              imported=job["imported"] + imported, wished=job["wished"] + wished, already=job["already"] + already,
              near_dups=job["near_dups"] + len(near), skipped=job["skipped"] + skipped,
              newest_ts=max([job["newest_ts"], *times]),
              oldest_ts=min([t for t in [job["oldest_ts"], *times] if t] or [0]),
              wishlist_id=wid, error=None, status="done" if exhausted else "ready",
              done_at=now if exhausted else None)
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    job = get_job(conn, job["id"], job["user"])
    log.info("history-import: job %s %s page ok: %d listens, %d imported, %d wished, %d already",
             job["id"], source, len(listens), imported, wished, already)
    return {**summary(conn, job), "done": exhausted, "wait_s": 0}


def cancel(conn, job: dict) -> None:
    if job["status"] in ("ready", "error"):
        _save(conn, job["id"], status="cancelled")


def undo(conn, job: dict) -> dict:
    """Remove everything this user's imports from this source wrote: the plays, the song counts, the wishlist
    songs not yet fetched. The job's own record goes too."""
    user, source = job["user"], job["source"]
    ids = [r[0] for r in conn.execute("SELECT uid FROM history_seen WHERE user=? AND source=? AND state='imported'",
                                      (user, source))]
    removed = 0
    plays_db = open_log(user)
    try:
        for n in range(0, len(ids), 500):
            part = ids[n:n + 500]
            removed += plays_db.execute(f"DELETE FROM play_events WHERE play_id IN ({','.join('?' * len(part))})",
                                        part).rowcount
        plays_db.commit()
    finally:
        plays_db.close()
    wid = job.get("wishlist_id")
    conn.execute("BEGIN IMMEDIATE")
    try:
        if wid:
            conn.execute("DELETE FROM exportify_songs WHERE import_id=? AND state IN ('wishlist','skipped_disk','owned')"
                         " AND user=?", (wid, user))
            left = conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE import_id=?", (wid,)).fetchone()[0]
            if not left:
                ex_ids = (wid,)
                conn.execute("DELETE FROM exportify_plans WHERE import_id=?", ex_ids)
                conn.execute("DELETE FROM exportify_imports WHERE id=?", ex_ids)
            else:
                conn.execute("UPDATE exportify_imports SET total_rows=? WHERE id=?", (left, wid))
        conn.execute("DELETE FROM history_seen WHERE user=? AND source=?", (user, source))
        conn.execute("DELETE FROM history_tracks WHERE user=? AND source=?", (user, source))
        conn.execute("DELETE FROM history_jobs WHERE user=? AND source=?", (user, source))
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    return {"removed_plays": removed}
