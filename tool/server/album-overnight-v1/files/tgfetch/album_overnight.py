"""
tgfetch/album_overnight.py  (album-overnight-v1)
────────────────────────────────────────────────
"Complete the album overnight". When a song you asked for lands in the library, look up its album
(mainly film soundtracks) and queue the album's tracks you do not have, to download at night.

There is NO second scheduler. The tracks join ONE per-listener Exportify import named "Album Overnight"
(`exportify_imports`, hidden from the Exportify screen), so `exportify.tick()` fetches them: the same
night window (1-7 am), per-night cap, disk floor, one batch at a time, pause and cancel as the Spotify
wishlist and Weekly Exploration. This module only decides WHAT to queue and shows/cancels it.

  scan()      runs from the Exportify timer's pass (every ~10 min). For each listener with the feature on:
              songs that landed since it was turned on, asked for one by one (not a playlist or chart),
              not seen before -> the album on iTunes (public, no key, only a title / album name is sent)
              -> its tracks -> minus what the library has -> at most `max_per_album` -> the import.
  The album is trusted only when the song that triggered it is in the album's track list (title and
  version words) -- a wrong "Remo" is never queued.
  Guards: opt-in (off until the listener turns it on); only songs that landed AFTER that; film albums
  only by default; compilations (> MAX_ALBUM_TRACKS) skipped; at most MAX_WAITING tracks waiting at once;
  each album once; cancelled albums never come back.

An album: active (has tracks to come) · done · nothing (you had it all) · cancelled.
"""

import json
import logging
import re
import time
import urllib.parse
import urllib.request

from tgfetch import exportify as ex
from tgfetch.library_sweep import Index, clean_title, share_artist, versions

log = logging.getLogger("tgfetch.album")

IMPORT_NAME = "Album Overnight"
MAX_ALBUM_TRACKS = 40            # a longer "album" is a compilation / a box set: not completed
MAX_PER_ALBUM = (5, 10, 15, 25, 40)
DEFAULT_PER_ALBUM = 25
MAX_WAITING = 150                # tracks waiting or on their way, all albums: the queue never grows past this
PER_NIGHT = (10, 20, 30, 50, 100)
DEFAULT_PER_NIGHT = 30
MIN_TRACK_S = 20.0               # a skit or a sound clip is not a song
JOB_LOOKBACK_S = 3 * 86400       # a landed song is looked at for 3 days, then forgotten
MAX_JOBS_PER_PASS = 5            # each is up to ~4 outside calls (3.2 s apart): a pass stays under a minute
BULK_BATCH = 5                   # a batch of more songs than this is a playlist import, not "a song you asked for"
SHOW_DONE_S = 30 * 86400
SHOW_NOTHING_S = 7 * 86400
ITUNES_GAP = 3.2                 # iTunes allows about 20 calls a minute
MAX_CALLS = 30                   # outside calls one pass may make
_FILM = re.compile(r"sound\s*track|\bost\b|original\s+score|motion\s+picture|background\s+score|\bbgm\b|\(\s*from\b", re.I)
_FILM_GENRES = {"soundtrack", "bollywood", "tamil", "telugu", "malayalam", "kannada", "marathi", "bengali",
                "gujarati", "punjabi", "bhojpuri"}
_SKIP_VERSIONS = {"karaoke", "instrumental"}      # a film album's karaoke / instrumental cuts are not "the album"
_HOSTS = (".mzstatic.com", ".apple.com")

SCHEMA = """
CREATE TABLE IF NOT EXISTS album_prefs (
    user          TEXT PRIMARY KEY,
    enabled       INTEGER NOT NULL DEFAULT 0,
    film_only     INTEGER NOT NULL DEFAULT 1,
    per_night     INTEGER NOT NULL DEFAULT 30,
    max_per_album INTEGER NOT NULL DEFAULT 25,
    since         REAL NOT NULL DEFAULT 0,
    updated_at    REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS album_seen (
    user   TEXT NOT NULL,
    job_id INTEGER NOT NULL,
    PRIMARY KEY (user, job_id)
);
CREATE TABLE IF NOT EXISTS album_albums (
    id            INTEGER PRIMARY KEY,
    user          TEXT NOT NULL,
    key           TEXT NOT NULL,
    album         TEXT NOT NULL,
    artist        TEXT NOT NULL DEFAULT '',
    cover_url     TEXT,
    trigger_title TEXT NOT NULL DEFAULT '',
    total         INTEGER NOT NULL DEFAULT 0,
    owned         INTEGER NOT NULL DEFAULT 0,
    status        TEXT NOT NULL DEFAULT 'active',     -- active | done | nothing | cancelled
    created_at    REAL NOT NULL,
    UNIQUE (user, key)
);
CREATE TABLE IF NOT EXISTS album_tracks (
    id         INTEGER PRIMARY KEY,
    album_id   INTEGER NOT NULL REFERENCES album_albums(id) ON DELETE CASCADE,
    user       TEXT NOT NULL,
    key        TEXT NOT NULL,
    title      TEXT NOT NULL,
    artist     TEXT NOT NULL DEFAULT '',
    track_no   INTEGER NOT NULL DEFAULT 0,
    duration_s REAL,
    song_row   INTEGER,                                -- exportify_songs.id
    own_row    INTEGER NOT NULL DEFAULT 1,             -- 1: this module made the row (cancel may delete it)
    state      TEXT NOT NULL DEFAULT 'active'          -- active | cancelled
);
CREATE INDEX IF NOT EXISTS album_tracks_album ON album_tracks(album_id);
"""


def ensure_schema(conn) -> None:
    ex.ensure_schema(conn)
    conn.executescript(SCHEMA)


# ── prefs ────────────────────────────────────────────────────────────────────

def get_prefs(conn, user: str) -> dict:
    r = conn.execute("SELECT * FROM album_prefs WHERE user=?", (user,)).fetchone()
    return {"enabled": bool(r["enabled"]) if r else False, "film_only": bool(r["film_only"]) if r else True,
            "per_night": int(r["per_night"]) if r else DEFAULT_PER_NIGHT,
            "max_per_album": int(r["max_per_album"]) if r else DEFAULT_PER_ALBUM,
            "since": float(r["since"]) if r else 0.0}


def _near(v: int, choices: tuple) -> int:
    return min(choices, key=lambda c: abs(c - int(v)))


def set_prefs(conn, user: str, enabled=None, film_only=None, per_night=None, max_per_album=None,
              now: float | None = None) -> dict:
    now = time.time() if now is None else now
    ensure_schema(conn)
    cur = get_prefs(conn, user)
    if enabled is not None:
        if bool(enabled) and not cur["enabled"]:
            cur["since"] = now                       # only songs that land from now on count: no old library is mined
        cur["enabled"] = bool(enabled)
    if film_only is not None:
        cur["film_only"] = bool(film_only)
    if per_night is not None:
        cur["per_night"] = _near(per_night, PER_NIGHT)
    if max_per_album is not None:
        cur["max_per_album"] = _near(max_per_album, MAX_PER_ALBUM)
    conn.execute(
        "INSERT INTO album_prefs (user, enabled, film_only, per_night, max_per_album, since, updated_at) VALUES (?,?,?,?,?,?,?) "
        "ON CONFLICT(user) DO UPDATE SET enabled=excluded.enabled, film_only=excluded.film_only, per_night=excluded.per_night, "
        "max_per_album=excluded.max_per_album, since=excluded.since, updated_at=excluded.updated_at",
        (user, int(cur["enabled"]), int(cur["film_only"]), cur["per_night"], cur["max_per_album"], cur["since"], now))
    iid = _import_id(conn, user)
    if iid:
        ex.set_plan(conn, iid, {"per_night": cur["per_night"]}, now=now)
        status = ex.get_plan(conn, iid)["status"]
        if not cur["enabled"] and status in ("active", "paused_disk"):
            ex.pause(conn, iid, now)                     # off means off: what is queued waits, nothing is fetched
        elif cur["enabled"] and status == "paused" and _open_rows(conn, iid):
            ex.start(conn, iid, now)
    return cur


# ── the outside world ────────────────────────────────────────────────────────

def _http_json(url: str, timeout: float = 8.0):
    req = urllib.request.Request(url, headers={"User-Agent": "NaviVibe-server/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:      # noqa: S310 (fixed https host)
        return json.loads(r.read(2_000_000).decode("utf-8", "replace"))


def _ok_url(url) -> str | None:
    try:
        p = urllib.parse.urlparse(str(url or ""))
    except ValueError:
        return None
    host = (p.hostname or "").lower()
    if p.scheme != "https" or not any(host.endswith(h) for h in _HOSTS):
        return None
    return p.geturl()


class Source:
    """iTunes album lookups. Public, no key; the only things sent are a song title, an artist and an album
    name (never a user name or an id). `get(url)` returns parsed JSON or raises; tests pass a fake."""

    def __init__(self, get=None, sleep=time.sleep, gap: float = ITUNES_GAP, country: str = "IN"):
        self.get, self.sleep, self.gap, self.country = get or _http_json, sleep, gap, country
        self.last, self.calls, self.cache, self.failed = -1e9, 0, {}, 0

    def _call(self, url: str):
        if url in self.cache:
            return self.cache[url]
        if self.calls >= MAX_CALLS:
            return None
        wait = self.gap - (time.monotonic() - self.last)
        if wait > 0:
            self.sleep(wait)
        self.last = time.monotonic()
        self.calls += 1
        try:
            body = self.get(url)
        except Exception as e:                          # iTunes being down is normal: never log what was asked
            log.info("album: itunes call failed (%s)", type(e).__name__)
            body, self.failed = None, self.failed + 1
        self.cache[url] = body
        return body

    def albums(self, term: str) -> list[dict]:
        body = self._call(f"https://itunes.apple.com/search?term={urllib.parse.quote(term)}&entity=album"
                          f"&country={self.country}&limit=8") or {}
        return [r for r in body.get("results") or [] if isinstance(r, dict) and r.get("collectionId")]

    def song_hits(self, term: str) -> list[dict]:
        body = self._call(f"https://itunes.apple.com/search?term={urllib.parse.quote(term)}&entity=song"
                          f"&country={self.country}&limit=8") or {}
        return [r for r in body.get("results") or [] if isinstance(r, dict) and r.get("kind") == "song"
                and r.get("collectionId")]

    def tracks(self, collection_id) -> tuple[dict, list[dict]] | None:
        """(the album, its songs in order) or None."""
        body = self._call(f"https://itunes.apple.com/lookup?id={int(collection_id)}&entity=song&country={self.country}")
        res = (body or {}).get("results") or []
        if not res:
            return None
        album = next((r for r in res if r.get("wrapperType") == "collection" or r.get("collectionType")), None)
        songs = [r for r in res if isinstance(r, dict) and r.get("kind") == "song" and r.get("trackName")]
        if not album or not songs:
            return None
        songs.sort(key=lambda r: (int(r.get("discNumber") or 1), int(r.get("trackNumber") or 0)))
        return album, songs


# ── finding the album ────────────────────────────────────────────────────────

def _has_song(songs: list[dict], title: str) -> bool:
    """The triggering song is in the track list: same clean title, same version words."""
    want = (clean_title(title), versions(title))
    return any((clean_title(s["trackName"]), versions(s["trackName"])) == want for s in songs)


def _is_film(raw_album: str, found: dict) -> bool:
    return bool(_FILM.search(raw_album or "") or _FILM.search(str(found.get("collectionName") or ""))
                or str(found.get("primaryGenreName") or "").strip().lower() in _FILM_GENRES)


def find_album(src: Source, title: str, artist: str, album: str, duration: float | None):
    """The (album, songs) on iTunes that this song belongs to, or None. The album is accepted only when the
    song is in its track list, so a different album with the same name is never mistaken for it."""
    tried = set()

    def check(cid):
        if cid in tried or len(tried) >= 4:
            return None
        tried.add(cid)
        got = src.tracks(cid)
        if not got:
            return None
        a, songs = got
        if len(songs) < 2 or len(songs) > MAX_ALBUM_TRACKS or not _has_song(songs, title):
            return None
        return a, songs

    name = clean_title(album)
    if name:
        first = (re.split(r"[;,•&]", artist or "")[0] or "").strip()
        for r in src.albums(f"{album} {first}".strip()):
            if clean_title(r.get("collectionName") or "") == name:
                hit = check(r["collectionId"])
                if hit:
                    return hit
    # The album's name did not lead anywhere (or the library's album is only the film's name): ask by song.
    for r in src.song_hits(f"{title} {artist}".strip()):
        if clean_title(r.get("trackName") or "") != clean_title(title) or versions(r.get("trackName") or "") != versions(title):
            continue
        if not share_artist(r.get("artistName") or "", artist or ""):
            continue
        ms = r.get("trackTimeMillis")
        if duration and isinstance(ms, (int, float)) and abs(ms / 1000.0 - float(duration)) > 6:
            continue
        if clean_title(r.get("collectionName") or "") == clean_title(title):     # the single, not the album
            continue
        hit = check(r["collectionId"])
        if hit:
            return hit
    return None


# ── queueing ─────────────────────────────────────────────────────────────────

def _import_id(conn, user: str) -> int | None:
    r = conn.execute("SELECT id FROM exportify_imports WHERE user=? AND name=? ORDER BY id LIMIT 1",
                     (user, IMPORT_NAME)).fetchone()
    return r[0] if r else None


def _ensure_import(conn, user: str, now: float) -> int:
    iid = _import_id(conn, user)
    if iid:
        return iid
    iid = conn.execute("INSERT INTO exportify_imports (user, name, created_at, total_rows) VALUES (?,?,?,0)",
                       (user, IMPORT_NAME, now)).lastrowid
    conn.execute("INSERT INTO exportify_plans (import_id, user, status, priority, per_night, updated_at) "
                 "VALUES (?,?, 'idle', 'list', ?, ?)", (iid, user, get_prefs(conn, user)["per_night"], now))
    return iid


def _open_rows(conn, iid: int) -> int:
    return conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE import_id=? AND state IN "
                        "('wishlist','skipped_disk','queued','failed')", (iid,)).fetchone()[0]


def waiting_tracks(conn, user: str) -> int:
    """Tracks of active albums that are not in the library yet."""
    return conn.execute(
        "SELECT COUNT(*) FROM album_tracks t LEFT JOIN exportify_songs s ON s.id=t.song_row "
        "WHERE t.user=? AND t.state='active' AND (s.id IS NULL OR s.state NOT IN ('downloaded','owned'))", (user,)).fetchone()[0]


def _add_album(conn, user: str, found: dict, songs: list[dict], trig_title: str, library: list[dict], cap: int,
               now: float) -> dict:
    """Store the album and queue its missing tracks. Returns {"queued": n, "owned": n, "status": ...}."""
    key = "a:" + str(found["collectionId"])
    by_isrc = {s["isrc"].upper(): s for s in library if s.get("isrc")}
    idx = Index(library)
    missing, owned = [], 0
    for s in songs:
        title, artist = str(s["trackName"])[:200], str(s.get("artistName") or "")[:300]
        ms = s.get("trackTimeMillis")
        dur = round(ms / 1000.0, 1) if isinstance(ms, (int, float)) and ms > 0 else None
        if versions(title) & _SKIP_VERSIONS and not versions(trig_title) & _SKIP_VERSIONS:
            continue
        if dur is not None and dur < MIN_TRACK_S:
            continue
        m = ex.match_one({"isrc": "", "title": title, "artist": artist, "duration_s": dur}, by_isrc, idx)
        if m["state"] == "owned" or m["similar_id"]:
            owned += 1
            continue
        yr = re.match(r"(\d{4})", str(s.get("releaseDate") or ""))
        missing.append({"title": title, "artist": artist, "duration_s": dur, "no": int(s.get("trackNumber") or 0),
                        "album": str(s.get("collectionName") or found.get("collectionName") or "")[:200],
                        "year": int(yr.group(1)) if yr else None})
    missing = missing[:cap]
    total = owned + len(missing)
    cover = _ok_url((found.get("artworkUrl100") or "").replace("100x100bb", "600x600bb"))
    artist = str(found.get("artistName") or "")[:200]
    status = "active" if missing else "nothing"
    aid = conn.execute(
        "INSERT INTO album_albums (user, key, album, artist, cover_url, trigger_title, total, owned, status, created_at) "
        "VALUES (?,?,?,?,?,?,?,?,?,?)",
        (user, key, str(found.get("collectionName") or "")[:200], artist, cover, trig_title[:200], total, owned,
         status, now)).lastrowid
    if missing:
        iid = _ensure_import(conn, user, now)
        pos = conn.execute("SELECT COALESCE(MAX(pos), -1) + 1 FROM exportify_songs WHERE import_id=?", (iid,)).fetchone()[0]
        for t in missing:
            k = ex.song_key("", t["title"], t["artist"])
            same = conn.execute("SELECT id FROM exportify_songs WHERE user=? AND key=? ORDER BY id LIMIT 1",
                                (user, k)).fetchone()
            if same:                                   # on a wishlist already (or fetched): never fetched twice
                row, own = same[0], 0
            else:
                row = conn.execute(
                    "INSERT INTO exportify_songs (import_id, user, pos, key, isrc, uri, title, artist, album, year, "
                    "popularity, duration_s, state, details, updated_at) VALUES (?,?,?,?,NULL,NULL,?,?,?,?,50,?, 'wishlist', '{}', ?)",
                    (iid, user, pos, k, t["title"], t["artist"], t["album"], t["year"], t["duration_s"], now)).lastrowid
                conn.execute("UPDATE exportify_imports SET total_rows=total_rows+1 WHERE id=?", (iid,))
                pos, own = pos + 1, 1
            conn.execute("INSERT INTO album_tracks (album_id, user, key, title, artist, track_no, duration_s, song_row, own_row) "
                         "VALUES (?,?,?,?,?,?,?,?,?)", (aid, user, k, t["title"], t["artist"], t["no"], t["duration_s"], row, own))
        plan = ex.get_plan(conn, iid)
        if plan["status"] not in ("active", "paused_disk"):
            ex.set_plan(conn, iid, {}, status="active", note=f"Downloads tonight, {ex.NIGHT_START_H}–{ex.NIGHT_END_H} am.", now=now)
    return {"album_id": aid, "queued": len(missing), "owned": owned, "status": status}


# ── the pass ─────────────────────────────────────────────────────────────────

def _new_jobs(conn, user: str, since: float, now: float) -> list[dict]:
    """Songs this listener asked for that landed after they turned the feature on and were not looked at yet.
    Bulk work (Exportify, Weekly Exploration, a playlist or chart import: a batch of more than a few songs)
    is not "a song you asked for"."""
    lo = max(since, now - JOB_LOOKBACK_S)
    return [dict(r) for r in conn.execute(
        "SELECT j.id, j.nd_song_id, j.updated_at, c.title, c.artist, c.album, c.duration_s FROM jobs j "
        "JOIN candidates c ON c.id=j.candidate_id "
        "LEFT JOIN album_seen s ON s.user=j.user AND s.job_id=j.id "
        "WHERE j.user=? AND s.job_id IS NULL AND j.status IN ('ready','imported') AND j.nd_song_id IS NOT NULL "
        "AND j.updated_at>=? AND COALESCE(c.result_id,'') NOT LIKE 'exportify:%' "
        "AND (j.batch_id IS NULL OR (SELECT COUNT(*) FROM jobs b WHERE b.batch_id=j.batch_id) <= ?) "
        "ORDER BY j.id LIMIT ?", (user, lo, BULK_BATCH, MAX_JOBS_PER_PASS))]


def scan(conn, library: list[dict], source: Source | None = None, now: float | None = None,
         user: str | None = None) -> dict:
    """One look at the songs that landed. Returns counts (for the log): looked, albums, queued."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    src = source or Source()
    out = {"looked": 0, "albums": 0, "queued": 0}
    where, args = "enabled=1", []
    if user:
        where += " AND user=?"
        args.append(user)
    for p in [dict(r) for r in conn.execute(f"SELECT * FROM album_prefs WHERE {where}", args)]:
        who, cap = p["user"], int(p["max_per_album"])
        by_id = {s["id"]: s for s in library}
        for j in _new_jobs(conn, who, p["since"], now):
            if src.calls >= MAX_CALLS or src.failed >= 3:
                break                                    # iTunes is down or the pass is spent: the rest next time
            lib = by_id.get(j["nd_song_id"])
            if lib is None and now - j["updated_at"] < 6 * 3600:
                continue                                 # Navidrome has not scanned it yet: look again next pass
            title = (lib or j)["title"] or j["title"]
            artist = (lib or j)["artist"] or j["artist"] or ""
            album = (lib or {}).get("album") or j["album"] or ""
            dur = (lib or {}).get("duration") or j["duration_s"]
            failed_before = src.failed
            found = find_album(src, title, artist, album, dur) if title else None
            if src.failed > failed_before and not found:
                break                                    # a failed call may be why: do not mark it looked at
            conn.execute("INSERT OR IGNORE INTO album_seen (user, job_id) VALUES (?,?)", (who, j["id"]))
            out["looked"] += 1
            if not found:
                continue
            a, songs = found
            if p["film_only"] and not _is_film(album, a):
                continue
            if conn.execute("SELECT 1 FROM album_albums WHERE user=? AND key=?", (who, "a:" + str(a["collectionId"]))).fetchone():
                continue                                 # this album was handled (or cancelled) already
            room = MAX_WAITING - waiting_tracks(conn, who)
            if room <= 0:
                conn.execute("DELETE FROM album_seen WHERE user=? AND job_id=?", (who, j["id"]))
                out["looked"] -= 1
                break                                    # the queue is full: this song is looked at again when there is room
            conn.execute("BEGIN IMMEDIATE")              # the album and its rows go in together or not at all
            try:
                r = _add_album(conn, who, a, songs, title, library, min(cap, room), now)
                conn.execute("COMMIT")
            except Exception:
                conn.execute("ROLLBACK")
                raise
            out["albums"] += 1
            out["queued"] += r["queued"]
            log.info("album: %d tracks queued, %d already owned", r["queued"], r["owned"])
    return out


def run_pass(conn, settings=None, library: list[dict] | None = None, source: Source | None = None,
             now: float | None = None) -> dict:
    """The timer's hook (python -m tgfetch.exportify tick calls this first). Never raises."""
    try:
        ensure_schema(conn)
        if not conn.execute("SELECT 1 FROM album_prefs WHERE enabled=1 LIMIT 1").fetchone():
            return {}
        if library is None:
            from tgfetch.library import load_library
            library = load_library()
        return scan(conn, library, source, now)
    except Exception as e:                               # bookkeeping: never stops the Spotify wishlist
        log.warning("album: pass failed (%s)", type(e).__name__)
        return {}


# ── reading it back ──────────────────────────────────────────────────────────

_TRACK = {"wishlist": "waiting", "skipped_disk": "waiting", "queued": "queued", "downloaded": "ready",
          "owned": "ready", "failed": "failed"}


def _track_view(t: dict, s: dict | None) -> dict:
    if t["state"] == "cancelled":
        st = "cancelled"
    elif s is None:
        st = "waiting"
    else:
        st = _TRACK.get(s["state"], "waiting")
    song_id = s["nd_song_id"] if s and s["state"] in ("downloaded", "owned") else None
    return {"id": t["id"], "title": t["title"], "artist": t["artist"], "number": t["track_no"],
            "duration_s": t["duration_s"], "state": st, "song_id": song_id}


def current(conn, user: str, now: float | None = None) -> dict:
    now = time.time() if now is None else now
    ensure_schema(conn)
    prefs = get_prefs(conn, user)
    iid = _import_id(conn, user)
    if iid:
        ex.settle(conn, iid, now)
    albums = []
    for a in [dict(r) for r in conn.execute("SELECT * FROM album_albums WHERE user=? AND status<>'cancelled' "
                                            "ORDER BY id DESC LIMIT 200", (user,))]:
        rows = [dict(r) for r in conn.execute("SELECT * FROM album_tracks WHERE album_id=? ORDER BY track_no, id", (a["id"],))]
        srows = {r["id"]: dict(r) for r in conn.execute(
            "SELECT id, state, nd_song_id FROM exportify_songs WHERE id IN (%s)" % ",".join("?" * len(rows)),
            [t["song_row"] for t in rows if t["song_row"]])} if rows else {}
        tracks = [_track_view(t, srows.get(t["song_row"])) for t in rows]
        live = [t for t in tracks if t["state"] != "cancelled"]
        counts = {k: sum(1 for t in live if t["state"] == k) for k in ("waiting", "queued", "ready", "failed")}
        state = a["status"]
        if state == "active":
            if counts["queued"]:
                state = "queued"
            elif counts["waiting"] or counts["failed"]:
                state = "waiting" if counts["waiting"] else "failed"
            else:
                state = "done"
        age = now - a["created_at"]
        if (state == "done" and age > SHOW_DONE_S) or (state == "nothing" and age > SHOW_NOTHING_S):
            continue
        albums.append({"id": a["id"], "album": a["album"], "artist": a["artist"], "cover_url": a["cover_url"],
                       "state": state, "total": a["total"], "owned": a["owned"], "added_at": a["created_at"],
                       "from_song": a["trigger_title"], "counts": counts, "tracks": tracks})
    note = None
    if iid:
        r = conn.execute("SELECT status, note FROM exportify_plans WHERE import_id=?", (iid,)).fetchone()
        note = r["note"] if r and r["status"] in ("active", "paused_disk") else None
    return {"enabled": prefs["enabled"], "film_only": prefs["film_only"], "per_night": prefs["per_night"],
            "per_night_choices": list(PER_NIGHT), "max_per_album": prefs["max_per_album"],
            "max_per_album_choices": list(MAX_PER_ALBUM), "waiting": waiting_tracks(conn, user),
            "max_waiting": MAX_WAITING, "download_note": note,
            "night": {"from": ex.NIGHT_START_H, "to": ex.NIGHT_END_H}, "albums": albums}


# ── cancelling ───────────────────────────────────────────────────────────────

class AlbumError(ValueError):
    pass


def _cancel_album(conn, user: str, a: dict, now: float) -> dict:
    iid = _import_id(conn, user)
    stopped = on_way = 0
    for t in [dict(r) for r in conn.execute("SELECT * FROM album_tracks WHERE album_id=? AND state='active'", (a["id"],))]:
        s = conn.execute("SELECT id, state FROM exportify_songs WHERE id=?", (t["song_row"],)).fetchone() if t["song_row"] else None
        if s is None or s["state"] in ("wishlist", "skipped_disk", "failed"):
            if s is not None and t["own_row"]:
                conn.execute("DELETE FROM exportify_songs WHERE id=?", (s["id"],))
                if iid:
                    conn.execute("UPDATE exportify_imports SET total_rows=MAX(0,total_rows-1) WHERE id=?", (iid,))
            conn.execute("UPDATE album_tracks SET state='cancelled', song_row=NULL WHERE id=?", (t["id"],))
            stopped += 1
        elif s["state"] == "queued":
            on_way += 1                                    # already in the bot's hands: it finishes
    conn.execute("UPDATE album_albums SET status='cancelled' WHERE id=?", (a["id"],))
    return {"stopped": stopped, "already_on_its_way": on_way}


def _idle_plan(conn, user: str, now: float) -> None:
    iid = _import_id(conn, user)
    if iid and not _open_rows(conn, iid):
        ex.set_plan(conn, iid, {}, status="cancelled", note="Cancelled.", now=now)


def cancel_album(conn, user: str, album_id: int, now: float | None = None) -> dict:
    """Cancel one album: tracks not yet handed to the bot are dropped, the album is never queued again."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    a = conn.execute("SELECT * FROM album_albums WHERE id=? AND user=?", (album_id, user)).fetchone()
    if a is None:
        raise AlbumError("no such album")
    res = _cancel_album(conn, user, dict(a), now)
    _idle_plan(conn, user, now)
    return res


def cancel_all(conn, user: str, now: float | None = None) -> dict:
    now = time.time() if now is None else now
    ensure_schema(conn)
    total = {"stopped": 0, "already_on_its_way": 0, "albums": 0}
    for a in [dict(r) for r in conn.execute("SELECT * FROM album_albums WHERE user=? AND status='active'", (user,))]:
        r = _cancel_album(conn, user, a, now)
        total["stopped"] += r["stopped"]
        total["already_on_its_way"] += r["already_on_its_way"]
        total["albums"] += 1
    _idle_plan(conn, user, now)
    return total
