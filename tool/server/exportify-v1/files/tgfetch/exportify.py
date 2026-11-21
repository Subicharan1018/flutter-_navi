"""
tgfetch/exportify.py  (exportify-v1)
────────────────────────────────────
Import a Spotify playlist from an Exportify CSV (exportify.net), match it to
the library, keep the songs that are not owned as a Wishlist, and fetch that
Wishlist through the music bot a little at a time, never past the disk floor.

  parse_csv()    strict about what a row needs, tolerant of BOMs, odd quoting,
                 CRLF, cp1252 files; capped in size and rows. Only counts are
                 ever logged, never what the file says.
  match_rows()   ISRC first (the exact recording), then the normalised title +
                 an artist in common + length within 5 s, using server-fixes-v1's
                 library_sweep (clean_title / versions / share_artist), so a
                 remix, sped-up or live cut never matches the plain song.
  store_import() one row per song per user in fetch.db (exportify_* tables);
                 the audio features are kept per ISRC and used for nothing yet.
  tick()         what the timer (and the "Start" button) runs: settle finished
                 downloads, then, if the plan is active, it is night (optional),
                 the nightly cap has room, no batch is still running and the
                 disk is above the floor, queue the next slice as ONE batch the
                 worker already knows how to run (by name, like a YouTube list:
                 youtube_batch.run). Nothing here talks to the bot itself.

A song's state: owned · wishlist · queued · downloaded · failed · skipped_disk.
"""

import csv
import io
import json
import logging
import re
import shutil
import sqlite3
import time
import unicodedata

from tgfetch import db
from tgfetch.library_sweep import Index, clean_title, share_artist, split_names, versions

log = logging.getLogger("tgfetch.exportify")

MAX_BYTES = 8_000_000            # the user's 5,657-row file is about 1.5 MB
MAX_ROWS = 20_000
GB_PER_HOUR = 0.51               # measured on the library: FLAC, about 0.51 GB per hour of music
DEFAULT_DURATION_S = 240.0
DURATION_SLACK_S = 5.0           # "the same song" by title + artist: lengths this close
NEAR_SLACK_S = 25.0              # title + artist match but another length: listed as "maybe", not owned
BATCH_SIZE = 25                  # songs per batch: about 8 minutes of bot time
NIGHT_START_H, NIGHT_END_H = 1, 7
BUDGET_WINDOW_S = 20 * 3600      # "a night": the cap counts songs queued in the last 20 hours
RETRY_AFTER_S = 3 * 86400        # a failed song is tried again after this, at most MAX_ATTEMPTS times
MAX_ATTEMPTS = 2
MAX_IMPORTS = 20                 # per user
PRIORITIES = ("popularity", "list")
LINK_PREFIX = "exportify:"
PENDING = -1                     # batch_id of songs claimed for a batch that is being made
STATES = ("owned", "wishlist", "queued", "downloaded", "failed", "skipped_disk")
DEFAULTS = {"priority": "popularity", "min_popularity": 0, "per_night": 100, "disk_floor_gb": 40.0,
            "night_only": True}

SCHEMA = """
CREATE TABLE IF NOT EXISTS exportify_imports (
    id           INTEGER PRIMARY KEY,
    user         TEXT NOT NULL,
    name         TEXT NOT NULL,
    created_at   REAL NOT NULL,
    total_rows   INTEGER NOT NULL,
    skipped_rows INTEGER NOT NULL DEFAULT 0,
    dupes        INTEGER NOT NULL DEFAULT 0,
    playlist_id  TEXT
);
CREATE TABLE IF NOT EXISTS exportify_songs (
    id          INTEGER PRIMARY KEY,
    import_id   INTEGER NOT NULL REFERENCES exportify_imports(id) ON DELETE CASCADE,
    user        TEXT NOT NULL,
    pos         INTEGER NOT NULL,
    key         TEXT NOT NULL,
    isrc        TEXT,
    uri         TEXT,
    title       TEXT NOT NULL,
    artist      TEXT NOT NULL,
    album       TEXT NOT NULL DEFAULT '',
    year        INTEGER,
    popularity  INTEGER NOT NULL DEFAULT 0,
    duration_s  REAL,
    state       TEXT NOT NULL,
    how         TEXT,
    nd_song_id  TEXT,
    similar_id  TEXT,
    cand_id     INTEGER,
    batch_id    INTEGER,
    attempts    INTEGER NOT NULL DEFAULT 0,
    error       TEXT,
    queued_at   REAL,
    details     TEXT,                       -- JSON: genres, label, release date, explicit, audio features
    updated_at  REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS exportify_songs_import ON exportify_songs(import_id, state);
CREATE INDEX IF NOT EXISTS exportify_songs_user_key ON exportify_songs(user, key);
CREATE TABLE IF NOT EXISTS exportify_plans (
    import_id      INTEGER PRIMARY KEY REFERENCES exportify_imports(id) ON DELETE CASCADE,
    user           TEXT NOT NULL,
    status         TEXT NOT NULL DEFAULT 'idle',   -- idle | active | paused | paused_disk | done | cancelled
    priority       TEXT NOT NULL DEFAULT 'popularity',
    min_popularity INTEGER NOT NULL DEFAULT 0,
    per_night      INTEGER NOT NULL DEFAULT 100,
    disk_floor_gb  REAL NOT NULL DEFAULT 40,
    night_only     INTEGER NOT NULL DEFAULT 1,
    note           TEXT,
    updated_at     REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS exportify_features (
    isrc             TEXT PRIMARY KEY,
    danceability REAL, energy REAL, key INTEGER, loudness REAL, mode INTEGER, speechiness REAL,
    acousticness REAL, instrumentalness REAL, liveness REAL, valence REAL, tempo REAL,
    time_signature INTEGER,
    updated_at       REAL NOT NULL
);
"""

FEATURES = ("danceability", "energy", "key", "loudness", "mode", "speechiness", "acousticness",
            "instrumentalness", "liveness", "valence", "tempo", "time_signature")
_INT_FEATURES = {"key", "mode", "time_signature"}


class ExportifyError(ValueError):
    """A problem the user can fix (shown as is)."""


def ensure_schema(conn) -> None:
    conn.executescript(SCHEMA)


# ── reading the CSV ──────────────────────────────────────────────────────────

_ALIASES = {
    "title": ("track name", "name", "title", "track"),
    "artist": ("artist name(s)", "artist names", "artist name", "artists", "artist"),
    "album": ("album name", "album"),
    "isrc": ("isrc",),
    "uri": ("track uri", "spotify uri", "uri"),
    "duration": ("duration (ms)", "duration_ms", "duration"),
    "popularity": ("popularity",),
    "release": ("release date", "album release date"),
    "genres": ("genres", "artist genres"),
    "label": ("record label", "label"),
    "explicit": ("explicit",),
    # Never read, on purpose: "Added By" (other people's Spotify ids) and "Added At".
    **{f: (f, f.replace("_", " ")) for f in FEATURES},          # "Time Signature"
}
_ISRC = re.compile(r"^[A-Z]{2}[A-Z0-9]{3}\d{7}$")
_YEAR = re.compile(r"^(\d{4})")
_CTRL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")


def _norm_header(h: str) -> str:
    return re.sub(r"\s+", " ", (h or "").replace("﻿", "").strip().lower())


def _num(v, cast=float):
    try:
        return cast(float(str(v).strip()))
    except (TypeError, ValueError):
        return None


def _decode(data) -> str:
    if isinstance(data, str):
        text = data
    else:
        if len(data) > MAX_BYTES:
            raise ExportifyError(f"This file is too big ({len(data) // 1_000_000} MB). The limit is "
                                 f"{MAX_BYTES // 1_000_000} MB: export one playlist at a time.")
        try:
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = data.decode("cp1252", errors="replace")
    if len(text) > MAX_BYTES:
        raise ExportifyError(f"This file is too big. The limit is {MAX_BYTES // 1_000_000} MB.")
    return text.replace("﻿", "").replace("\x00", "")     # older csv modules refuse a NUL


def parse_csv(data) -> tuple[list[dict], dict]:
    """Rows of the export as dicts, and {'skipped': rows with no title}. Raises ExportifyError."""
    text = _decode(data)
    try:
        reader = csv.reader(io.StringIO(text, newline=""))
        header = None
        for rec in reader:
            if any(c.strip() for c in rec):
                header = rec
                break
        if header is None:
            raise ExportifyError("The file is empty.")
        cols = {}
        names = [_norm_header(h) for h in header]
        for field, aliases in _ALIASES.items():
            for a in aliases:
                if a.strip() in names:
                    cols[field] = names.index(a.strip())
                    break
        if "title" not in cols or "artist" not in cols:
            raise ExportifyError("This isn't an Exportify playlist. Export it as CSV from exportify.net: "
                                 "it needs the Track Name and Artist Name(s) columns.")
        rows, skipped, n = [], 0, -1

        def cell(rec, field):
            i = cols.get(field)
            return _CTRL.sub("", rec[i]).strip() if i is not None and i < len(rec) else ""

        for rec in reader:
            if not any(c.strip() for c in rec):
                continue
            n += 1                                  # the row's place in the file: "my list order"
            title = cell(rec, "title")
            artist = "; ".join(p.strip() for p in cell(rec, "artist").split(";") if p.strip())
            if not title:
                skipped += 1
                continue
            if len(rows) >= MAX_ROWS:
                raise ExportifyError(f"This playlist has more than {MAX_ROWS:,} songs. Split it and export "
                                     "the parts one by one.")
            isrc = re.sub(r"[\s-]", "", cell(rec, "isrc")).upper()
            ms = _num(cell(rec, "duration"))
            ym = _YEAR.match(cell(rec, "release"))
            row = {
                "pos": n, "title": title[:200], "artist": artist[:300], "album": cell(rec, "album")[:200],
                "isrc": isrc if _ISRC.match(isrc) else "", "uri": cell(rec, "uri")[:80],
                "year": int(ym.group(1)) if ym else None,
                "duration_s": round(ms / 1000.0, 1) if ms and ms > 0 else None,
                "popularity": max(0, min(100, _num(cell(rec, "popularity"), int) or 0)),
                "features": {},
            }
            for f in FEATURES:
                v = _num(cell(rec, f), int if f in _INT_FEATURES else float)
                if v is not None and cell(rec, f) != "":
                    row["features"][f] = v
            row["details"] = {
                "genres": [g.strip()[:40] for g in cell(rec, "genres").split(",") if g.strip()][:8],
                "label": cell(rec, "label")[:80],
                "release_date": cell(rec, "release")[:10],
                "explicit": 1 if cell(rec, "explicit").lower() in ("true", "1", "yes") else 0,
            }
            rows.append(row)
    except csv.Error:
        raise ExportifyError("This file isn't a readable CSV.") from None
    if not rows:
        raise ExportifyError("No songs found in this file.")
    return rows, {"skipped": skipped}


def song_key(isrc: str, title: str, artist: str) -> str:
    """The same song in two playlists: its ISRC, else clean title + version words + first artist."""
    if isrc:
        return "i:" + isrc
    first = (split_names(artist) or [""])[0]
    return "t:" + clean_title(title) + "|" + ",".join(sorted(versions(title))) + "|" + first


def dedupe(rows: list[dict]) -> tuple[list[dict], int]:
    seen, out = set(), []
    for r in rows:
        k = song_key(r["isrc"], r["title"], r["artist"])
        if k in seen:
            continue
        seen.add(k)
        out.append({**r, "key": k})
    return out, len(rows) - len(out)


# ── matching ─────────────────────────────────────────────────────────────────

def match_rows(rows: list[dict], library: list[dict]) -> list[dict]:
    """For each row {'state': owned|wishlist, 'how': isrc|title|None, 'nd_song_id', 'similar_id'}."""
    by_isrc = {}
    for s in library:
        if s.get("isrc"):
            by_isrc.setdefault(s["isrc"].upper(), s)
    idx = Index(library)
    return [match_one(r, by_isrc, idx) for r in rows]


def match_one(r: dict, by_isrc: dict, idx: Index) -> dict:
    if r.get("isrc") and r["isrc"] in by_isrc:
        return {"state": "owned", "how": "isrc", "nd_song_id": by_isrc[r["isrc"]]["id"], "similar_id": None}
    dur = r.get("duration_s")
    hit = idx.find(r["title"], r["artist"], dur, DURATION_SLACK_S)
    if hit:
        return {"state": "owned", "how": "title", "nd_song_id": hit["id"], "similar_id": None}
    near = idx.find(r["title"], r["artist"], dur, NEAR_SLACK_S) if dur else None
    return {"state": "wishlist", "how": None, "nd_song_id": None, "similar_id": near["id"] if near else None}


# ── storing ──────────────────────────────────────────────────────────────────

def est_gb(duration_s) -> float:
    return (float(duration_s) if duration_s else DEFAULT_DURATION_S) / 3600.0 * GB_PER_HOUR


def clean_name(name: str) -> str:
    name = _CTRL.sub("", name or "").strip()
    name = re.sub(r"\.csv$", "", name, flags=re.I).replace("_", " ").strip()
    return re.sub(r"\s+", " ", name)[:80] or "Spotify playlist"


def store_import(conn, user: str, name: str, rows: list[dict], skipped: int, results_for: callable,
                 now: float | None = None) -> int:
    """Write an import. `results_for(unique_rows)` gives the match results (it may run in a thread)."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    unique, dupes = dedupe(rows)
    results = results_for(unique)
    conn.execute("BEGIN")
    try:
        iid = conn.execute(
            "INSERT INTO exportify_imports (user, name, created_at, total_rows, skipped_rows, dupes) "
            "VALUES (?,?,?,?,?,?)", (user, clean_name(name), now, len(rows) + skipped, skipped, dupes)).lastrowid
        conn.executemany(
            "INSERT INTO exportify_songs (import_id, user, pos, key, isrc, uri, title, artist, album, year, "
            "popularity, duration_s, state, how, nd_song_id, similar_id, details, updated_at) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            [(iid, user, r["pos"], r["key"], r["isrc"] or None, r["uri"] or None, r["title"], r["artist"],
              r["album"], r["year"], r["popularity"], r["duration_s"], m["state"], m["how"], m["nd_song_id"],
              m["similar_id"], json.dumps({**r.get("details", {}), "features": r["features"]}), now)
             for r, m in zip(unique, results)])
        conn.executemany(
            "INSERT OR REPLACE INTO exportify_features (isrc, " + ", ".join(FEATURES) + ", updated_at) "
            "VALUES (?," + ",".join("?" * len(FEATURES)) + ",?)",
            [(r["isrc"], *[r["features"].get(f) for f in FEATURES], now) for r in unique
             if r["isrc"] and r["features"]])
        conn.execute("INSERT INTO exportify_plans (import_id, user, status, updated_at) VALUES (?,?, 'idle', ?)",
                     (iid, user, now))
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise
    log.info("exportify: import %s for %s: %d rows, %d unique", iid, user, len(rows), len(unique))
    refresh_details(conn)
    return iid


# ── what the CSV says about songs we own: spotify_details ────────────────────

DETAILS_COLUMNS = ("song_id TEXT PRIMARY KEY, isrc TEXT, popularity INTEGER, genres TEXT, label TEXT, "
                   "release_date TEXT, explicit INTEGER, duration_s REAL, matched_by TEXT, " +
                   ", ".join(f"{f} {'INTEGER' if f in _INT_FEATURES else 'REAL'}" for f in FEATURES) +
                   ", updated_at REAL NOT NULL")


def details_path() -> str:
    """The small database the shuffle server reads (navivibe/spotify_details.py). Its own file, in the
    shuffle server's folder: no WAL, nothing shared with fetch.db."""
    import os
    from tgfetch.config import NAVIVIBE_ROOT
    return os.getenv("NAVIVIBE_SPOTIFY_DETAILS_DB", os.path.join(NAVIVIBE_ROOT, "spotify_details.db"))


def refresh_details(conn, path: str | None = None, now: float | None = None) -> int:
    """Write what the imports know about each song we own into spotify_details, one row per library
    song (`song_id` = the Navidrome id): ISRC (from the CSV, so songs the library has no ISRC for get
    one), popularity, genres, label, release date, explicit, length and Spotify's audio features.
    A song in several imports is the best of them (an ISRC match beats a title match, then the newest).
    Re-running rewrites the rows, never duplicates them. Bookkeeping only: a failure is logged (never
    with contents) and the import goes on. Files and Navidrome's tags are never touched. Returns the
    number of rows written."""
    import sqlite3
    now = time.time() if now is None else now
    best: dict[str, tuple] = {}
    for r in conn.execute(
            "SELECT nd_song_id, isrc, how, popularity, duration_s, details, updated_at FROM exportify_songs "
            "WHERE nd_song_id IS NOT NULL AND state IN ('owned','downloaded') "
            "ORDER BY (how='isrc') ASC, updated_at ASC, id ASC"):
        best[r["nd_song_id"]] = tuple(r)                     # the last one is the best
    if not best:
        return 0
    rows = []
    for sid, (_, isrc, how, pop, dur, details, _) in best.items():
        try:
            d = json.loads(details or "{}")
        except ValueError:
            d = {}
        feat = d.get("features") or {}
        rows.append((sid, isrc, pop, json.dumps(d.get("genres") or [], ensure_ascii=False), d.get("label") or None,
                     d.get("release_date") or None, d.get("explicit", 0), dur, how or "library",
                     *[feat.get(f) for f in FEATURES], now))
    try:
        c = sqlite3.connect(path or details_path(), timeout=10)
        try:
            c.execute(f"CREATE TABLE IF NOT EXISTS spotify_details ({DETAILS_COLUMNS})")
            c.execute("CREATE INDEX IF NOT EXISTS spotify_details_isrc ON spotify_details(isrc)")
            c.executemany("INSERT OR REPLACE INTO spotify_details VALUES (" + ",".join("?" * (len(rows[0]))) + ")", rows)
            c.commit()
        finally:
            c.close()
    except (sqlite3.Error, OSError) as e:
        log.warning("exportify: spotify_details not written (%s)", type(e).__name__)
        return 0
    return len(rows)


def prune_old(conn, user: str) -> None:
    """At most MAX_IMPORTS per user: the oldest go (their songs with them)."""
    old = [r[0] for r in conn.execute(
        "SELECT id FROM exportify_imports WHERE user=? ORDER BY id DESC LIMIT -1 OFFSET ?", (user, MAX_IMPORTS))]
    for i in old:
        delete_import(conn, i)


def delete_import(conn, import_id: int) -> None:
    conn.execute("BEGIN")
    try:
        conn.execute("DELETE FROM exportify_songs WHERE import_id=?", (import_id,))
        conn.execute("DELETE FROM exportify_plans WHERE import_id=?", (import_id,))
        conn.execute("DELETE FROM exportify_imports WHERE id=?", (import_id,))
        conn.execute("COMMIT")
    except Exception:
        conn.execute("ROLLBACK")
        raise


# ── reading it back ──────────────────────────────────────────────────────────

def free_bytes(path) -> int:
    return shutil.disk_usage(str(path)).free


def get_import(conn, import_id: int, user: str) -> dict | None:
    r = conn.execute("SELECT * FROM exportify_imports WHERE id=? AND user=?", (import_id, user)).fetchone()
    return dict(r) if r else None


def get_plan(conn, import_id: int) -> dict:
    r = conn.execute("SELECT * FROM exportify_plans WHERE import_id=?", (import_id,)).fetchone()
    p = dict(r)
    p["night_only"] = bool(p["night_only"])
    return p


def counts(conn, import_id: int) -> dict:
    out = {s: 0 for s in STATES}
    gb = {s: 0.0 for s in STATES}
    for r in conn.execute("SELECT state, COUNT(*) n, SUM(COALESCE(duration_s, ?)) d FROM exportify_songs "
                          "WHERE import_id=? GROUP BY state", (DEFAULT_DURATION_S, import_id)):
        out[r["state"]] = r["n"]
        gb[r["state"]] = round((r["d"] or 0) / 3600.0 * GB_PER_HOUR, 2)
    return {"songs": out, "gb": gb}


def summary(conn, imp: dict, free_gb: float | None = None) -> dict:
    c = counts(conn, imp["id"])
    plan = get_plan(conn, imp["id"])
    s = c["songs"]
    todo_states = ("wishlist", "skipped_disk", "failed")
    maybe = conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE import_id=? AND state='wishlist' "
                         "AND similar_id IS NOT NULL", (imp["id"],)).fetchone()[0]
    no_isrc = conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE import_id=? AND isrc IS NULL",
                           (imp["id"],)).fetchone()[0]
    return {
        "id": imp["id"], "name": imp["name"], "created_at": imp["created_at"],
        "rows": imp["total_rows"], "unique": sum(s.values()), "duplicates": imp["dupes"],
        "skipped_rows": imp["skipped_rows"], "no_isrc": no_isrc, "maybe_owned": maybe,
        "playlist_id": imp["playlist_id"],
        "states": s,
        "owned": s["owned"] + s["downloaded"],
        "wishlist": sum(s[x] for x in todo_states) + s["queued"],
        "wishlist_gb": round(sum(c["gb"][x] for x in todo_states), 1),
        "plan": plan, "free_gb": free_gb,
    }


def songs_page(conn, import_id: int, state: str, page: int, size: int = 200) -> list[dict]:
    where, args = "import_id=?", [import_id]
    if state != "all":
        where += " AND state=?"
        args.append(state)
    return [dict(r) for r in conn.execute(
        f"SELECT pos, isrc, title, artist, album, year, popularity, duration_s, state, how, nd_song_id, error "
        f"FROM exportify_songs WHERE {where} ORDER BY pos LIMIT ? OFFSET ?", (*args, size, max(0, page) * size))]


def owned_ids(conn, import_id: int) -> list[str]:
    seen, out = set(), []
    for r in conn.execute("SELECT nd_song_id FROM exportify_songs WHERE import_id=? AND nd_song_id IS NOT NULL "
                          "AND state IN ('owned','downloaded') ORDER BY pos", (import_id,)):
        if r[0] not in seen:
            seen.add(r[0])
            out.append(r[0])
    return out


# ── the plan ─────────────────────────────────────────────────────────────────

def clean_plan(body: dict) -> dict:
    """Validated plan fields from a request (only the ones given)."""
    out = {}
    if "priority" in body:
        if body["priority"] not in PRIORITIES:
            raise ExportifyError("Order must be most popular first or your list order.")
        out["priority"] = body["priority"]
    if "min_popularity" in body:
        out["min_popularity"] = max(0, min(100, int(body["min_popularity"])))
    if "per_night" in body:
        out["per_night"] = max(1, min(1000, int(body["per_night"])))
    if "disk_floor_gb" in body:
        out["disk_floor_gb"] = max(1.0, min(2000.0, float(body["disk_floor_gb"])))
    if "night_only" in body:
        out["night_only"] = 1 if body["night_only"] else 0
    return out


def set_plan(conn, import_id: int, fields: dict, status: str | None = None, note: str | None = None,
             now: float | None = None) -> None:
    fields = dict(fields)
    if status:
        fields["status"] = status
    if note is not None:
        fields["note"] = note or None
    fields["updated_at"] = time.time() if now is None else now
    conn.execute("UPDATE exportify_plans SET " + ", ".join(f"{k}=?" for k in fields) + " WHERE import_id=?",
                 (*fields.values(), import_id))


def eligible(conn, import_id: int, plan: dict, now: float) -> list[dict]:
    """Songs that may be queued next, in the plan's order: not owned or in flight anywhere
    (same song in another of the user's imports counts), above the minimum popularity,
    failed ones only when it was long enough ago."""
    order = "popularity DESC, pos" if plan["priority"] == "popularity" else "pos"
    rows = [dict(r) for r in conn.execute(
        f"SELECT * FROM exportify_songs WHERE import_id=? AND popularity>=? AND "
        f"(state IN ('wishlist','skipped_disk') OR (state='failed' AND attempts<? AND updated_at<?)) "
        f"ORDER BY {order}", (import_id, plan["min_popularity"], MAX_ATTEMPTS, now - RETRY_AFTER_S))]
    user = plan["user"]
    taken = {r[0] for r in conn.execute(
        "SELECT key FROM exportify_songs WHERE user=? AND import_id<>? AND state IN ('queued','downloaded','owned')",
        (user, import_id))}
    out, seen = [], set()
    for r in rows:
        if r["key"] in taken or r["key"] in seen:
            continue
        seen.add(r["key"])
        out.append(r)
    return out


def estimate(conn, imp: dict, plan: dict, free_gb: float) -> dict:
    """What fetching would cost: 'These N songs need about X GB; you have Y GB free.'"""
    songs = eligible(conn, imp["id"], plan, time.time())
    gb = sum(est_gb(s["duration_s"]) for s in songs)
    fits = 0
    room = max(0.0, free_gb - plan["disk_floor_gb"])
    acc = 0.0
    for s in songs:
        acc += est_gb(s["duration_s"])
        if acc > room:
            break
        fits += 1
    nights = -(-len(songs) // max(1, plan["per_night"]))
    return {"songs": len(songs), "gb": round(gb, 1), "hours": round(sum((s["duration_s"] or DEFAULT_DURATION_S)
            for s in songs) / 3600.0, 1), "free_gb": round(free_gb, 1), "floor_gb": plan["disk_floor_gb"],
            "fits": fits, "nights": nights, "gb_per_hour": GB_PER_HOUR,
            "bot_hours": round(len(songs) * 20 / 3600.0, 1)}


# ── running it ───────────────────────────────────────────────────────────────

def _job_for(conn, cand_id: int) -> dict | None:
    r = conn.execute("SELECT * FROM jobs WHERE candidate_id=? ORDER BY id DESC LIMIT 1", (cand_id,)).fetchone()
    return dict(r) if r else None


def settle(conn, import_id: int, now: float) -> int:
    """Queued songs whose job finished become downloaded / owned / failed; a cancelled batch's
    songs go back to the Wishlist. Returns how many changed."""
    n, landed = 0, False
    for s in [dict(r) for r in conn.execute(
            "SELECT * FROM exportify_songs WHERE import_id=? AND state='queued'", (import_id,))]:
        job = _job_for(conn, s["cand_id"]) if s["cand_id"] else None
        batch = db.get_batch(conn, s["batch_id"]) if s["batch_id"] else None
        fields = None
        if job and job["status"] in db.ADDED_JOB:
            fields = {"state": "downloaded", "nd_song_id": job.get("nd_song_id"), "error": None}
        elif job and job["status"] == "duplicate":
            fields = {"state": "owned", "how": "library", "nd_song_id": job.get("nd_song_id"), "error": None}
        elif job and job["status"] not in db.UNFINISHED_JOB:
            if (job.get("error") or "") == "cancelled" or job["status"] == "cancelled":
                fields = {"state": "wishlist", "queued_at": None, "error": None}
            else:
                fields = {"state": "failed", "attempts": s["attempts"] + 1,
                          "error": (job.get("error") or "didn't come in")[:160]}
        elif batch and batch["status"] in db.FINISHED_BATCH and not job:
            if batch["status"] == "cancelled":
                fields = {"state": "wishlist", "queued_at": None, "error": None}
            else:
                fields = {"state": "failed", "attempts": s["attempts"] + 1,
                          "error": (batch.get("error") or "didn't come in")[:160]}
        elif batch is None and s["batch_id"] and not (s["batch_id"] == PENDING and now - s["updated_at"] < 300):
            fields = {"state": "wishlist", "queued_at": None, "error": None}    # a batch that never got made
        if fields:
            fields["updated_at"] = now
            conn.execute("UPDATE exportify_songs SET " + ", ".join(f"{k}=?" for k in fields) + " WHERE id=?",
                         (*fields.values(), s["id"]))
            if fields["state"] in ("downloaded", "owned"):       # the same song in the user's other imports
                conn.execute("UPDATE exportify_songs SET state='owned', how='library', nd_song_id=?, updated_at=? "
                             "WHERE user=? AND key=? AND id<>? AND state IN ('wishlist','skipped_disk','failed')",
                             (fields.get("nd_song_id"), now, s["user"], s["key"], s["id"]))
                landed = True
            n += 1
    if landed:                                  # songs that just came in get their details too
        refresh_details(conn)
    return n


def _running_batch(conn, import_id: int) -> bool:
    for (bid,) in conn.execute("SELECT DISTINCT batch_id FROM exportify_songs WHERE import_id=? AND state='queued' "
                               "AND batch_id IS NOT NULL", (import_id,)).fetchall():
        if bid == PENDING or db.batch_status(conn, bid) in db.ON_ITS_WAY:
            return True
    return False


def in_night_window(now: float) -> bool:
    return NIGHT_START_H <= time.localtime(now).tm_hour < NIGHT_END_H


def spotify_title(raw: str, album: str = "") -> tuple[str, str]:
    """(song name, film) from a Spotify title: '(From "X")', '- From "X"' and 'Original Motion Picture
    Soundtrack' leave the name and become the film hint. Spotify titles are already clean, so nothing
    else is touched (the YouTube cleaner would eat the 'New' in 'Brand New'); version words stay."""
    from tgfetch import titles
    s = unicodedata.normalize("NFKC", raw or "")
    film = ""
    m = titles._FROM.search(s)
    if m:
        film = (m.group(1) or m.group(2) or "").strip()
        s = titles._FROM.sub(" ", s)
    s = titles._OST.sub(" ", s)
    s = re.sub(r"\s+", " ", re.sub(r"[\(\[]\s*[\)\]]", " ", s))
    s = re.sub(r"^[\s\-:|,.]+|[\s\-:|,.]+$", "", s).strip()
    if not film:
        film = re.sub(r"\s+", " ", titles._OST.sub(" ", album or "")).strip()
        film = "" if clean_title(film) == clean_title(s) else film
    return s[:120], film[:120]


def _queue_slice(conn, plan: dict, imp: dict, picks: list[dict], now: float, library=None) -> int:
    from tgfetch.rank import Candidate

    cands = []
    for i, s in enumerate(picks):
        title, film = spotify_title(s["title"], s["album"])
        artist = ", ".join(n.strip() for n in s["artist"].split(";") if n.strip())
        # Same candidate shape a YouTube list has, so youtube_batch.run fetches it: searches the bot by
        # name, scores title + version words + artist + length. "ATV" = an audio track, not a video.
        meta = {"raw": s["title"], "alts": [], "film": film, "unreadable": not title, "video_type": "ATV"}
        cands.append(Candidate(index=i, result_id=f"{LINK_PREFIX}{s['id']}", title=title or s["title"],
                               artist=artist, album=film, kind="original", reasons=[{"youtube": meta}],
                               type="song", duration_s=s["duration_s"], isrc=s["isrc"]))
    title = f"Wishlist: {imp['name']} ({len(picks)} songs)"
    sid = db.create_search(conn, plan["user"], f"{LINK_PREFIX}{imp['id']}", kind="link", status="done")
    conn.execute("UPDATE searches SET title=? WHERE id=?", (title, sid))
    db.save_candidates(conn, sid, cands)
    cids = [r[0] for r in conn.execute("SELECT id FROM candidates WHERE search_id=? ORDER BY idx", (sid,))]
    bid = db.create_batch(conn, plan["user"], "songs", title, cids, link=f"{LINK_PREFIX}{imp['id']}")
    for s, cid in zip(picks, cids):
        conn.execute("UPDATE exportify_songs SET cand_id=?, batch_id=?, updated_at=? WHERE id=?",
                     (cid, bid, now, s["id"]))
    return bid


def _claim(conn, import_id: int, picks: list[dict], now: float) -> bool:
    """Take the songs for one batch, once: the service and the timer can tick together, and only
    the first to get here (no batch running, every song still free) wins."""
    conn.execute("BEGIN IMMEDIATE")
    try:
        ok = not _running_batch(conn, import_id)
        if ok:
            marks = ",".join("?" * len(picks))
            cur = conn.execute(
                f"UPDATE exportify_songs SET state='queued', batch_id=?, queued_at=?, error=NULL, updated_at=? "
                f"WHERE id IN ({marks}) AND state IN ('wishlist','skipped_disk','failed')",
                (PENDING, now, now, *[s["id"] for s in picks]))
            ok = cur.rowcount == len(picks)
        conn.execute("COMMIT" if ok else "ROLLBACK")
        return ok
    except Exception:
        conn.execute("ROLLBACK")
        raise


def tick(conn, settings, user: str | None = None, now: float | None = None, free: float | None = None,
         library: list[dict] | None = None, force: bool = False, import_id: int | None = None) -> list[dict]:
    """One pass over the active plans (all, one user's, or one import). Returns what it did.
    `free` = free GB on the music volume (the real one when None); `force` ignores the night window."""
    now = time.time() if now is None else now
    ensure_schema(conn)
    where, args = "status IN ('active','paused_disk')", []
    if user:
        where += " AND user=?"
        args.append(user)
    if import_id:
        where += " AND import_id=?"
        args.append(import_id)
    plans = [dict(r) for r in conn.execute(f"SELECT * FROM exportify_plans WHERE {where}", args)]
    done = []
    for plan in plans:
        iid = plan["import_id"]
        settle(conn, iid, now)
        imp = dict(conn.execute("SELECT * FROM exportify_imports WHERE id=?", (iid,)).fetchone())
        act = {"import_id": iid, "queued": 0, "note": None}
        done.append(act)
        if _running_batch(conn, iid):
            act["note"] = "waiting for the running batch"
            continue
        if plan["night_only"] and not force and not in_night_window(now):
            set_plan(conn, iid, {}, note=f"Next batch tonight, {NIGHT_START_H}–{NIGHT_END_H} am.", now=now)
            act["note"] = "outside the night window"
            continue
        # The nightly cap (and the bot account's daily limit, when one is set).
        used = conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE user=? AND queued_at>?",
                            (plan["user"], now - BUDGET_WINDOW_S)).fetchone()[0]
        budget = plan["per_night"] - used
        if getattr(settings, "jobs_per_day", 0):
            budget = min(budget, settings.jobs_per_day - db.count_since(conn, "jobs", plan["user"], now - 86400))
        if budget <= 0:
            set_plan(conn, iid, {}, note="Tonight's limit is reached. It carries on tomorrow night.", now=now)
            act["note"] = "cap reached"
            continue
        # The disk guard: free space, minus the floor, minus what songs already queued will take.
        free_gb = (free_bytes(settings.library_dir) / 1e9) if free is None else free
        inflight = sum(est_gb(r[0]) for r in conn.execute(
            "SELECT duration_s FROM exportify_songs WHERE user=? AND state='queued'", (plan["user"],)))
        room = free_gb - plan["disk_floor_gb"] - inflight
        picks_all = eligible(conn, iid, plan, now)
        if not picks_all:
            if conn.execute("SELECT COUNT(*) FROM exportify_songs WHERE import_id=? AND state='queued'",
                            (iid,)).fetchone()[0] == 0:
                set_plan(conn, iid, {}, status="done", note="Everything that could be fetched is done.", now=now)
                act["note"] = "done"
            continue
        if room < est_gb(picks_all[0]["duration_s"]):
            set_plan(conn, iid, {}, status="paused_disk",
                     note=f"Paused: disk is low ({free_gb:.0f} GB free, floor {plan['disk_floor_gb']:.0f} GB).", now=now)
            act["note"] = "disk is low"
            continue
        picks, acc = [], 0.0
        for s in picks_all:
            if len(picks) >= min(BATCH_SIZE, budget):
                break
            need = est_gb(s["duration_s"])
            if acc + need > room:
                conn.execute("UPDATE exportify_songs SET state='skipped_disk', updated_at=? WHERE id=?", (now, s["id"]))
                break
            picks.append(s)
            acc += need
        if library is not None and picks:           # a song that came into the library meanwhile is not fetched
            by_isrc = {s["isrc"].upper(): s for s in library if s.get("isrc")}
            idx = Index(library)
            keep = []
            for s in picks:
                m = match_one({**s, "isrc": s["isrc"] or ""}, by_isrc, idx)
                if m["state"] == "owned":
                    conn.execute("UPDATE exportify_songs SET state='owned', how='library', nd_song_id=?, updated_at=? "
                                 "WHERE id=?", (m["nd_song_id"], now, s["id"]))
                else:
                    keep.append(s)
            if len(keep) < len(picks):
                refresh_details(conn)
            picks = keep
        if not picks:
            continue
        if not _claim(conn, iid, picks, now):
            act["note"] = "another tick got there first"
            continue
        try:
            bid = _queue_slice(conn, plan, imp, picks, now, library)
        except Exception:
            conn.execute("UPDATE exportify_songs SET state='wishlist', batch_id=NULL, queued_at=NULL WHERE "
                         "import_id=? AND batch_id=?", (iid, PENDING))
            raise
        set_plan(conn, iid, {}, status="active", note=f"Queued {len(picks)} songs.", now=now)
        act.update(queued=len(picks), batch_id=bid, note="queued")
        log.info("exportify: import %s queued %d songs as batch %s", iid, len(picks), bid)
    return done


def start(conn, import_id: int, now: float | None = None) -> None:
    set_plan(conn, import_id, {}, status="active", note="Starting.", now=now)


def pause(conn, import_id: int, now: float | None = None) -> None:
    set_plan(conn, import_id, {}, status="paused", note="Paused. The batch already running finishes.", now=now)


def cancel(conn, import_id: int, now: float | None = None) -> None:
    """Stop for good: the running batch is cancelled and the songs not fetched yet go back to the Wishlist."""
    now = time.time() if now is None else now
    for (bid,) in conn.execute("SELECT DISTINCT batch_id FROM exportify_songs WHERE import_id=? AND state='queued' "
                               "AND batch_id IS NOT NULL", (import_id,)).fetchall():
        db.cancel_batch(conn, bid)
    settle(conn, import_id, now)
    conn.execute("UPDATE exportify_songs SET state='wishlist', queued_at=NULL, updated_at=? WHERE import_id=? "
                 "AND state IN ('queued','skipped_disk')", (now, import_id))
    set_plan(conn, import_id, {}, status="cancelled", note="Cancelled.", now=now)


def retry_failed(conn, import_id: int, now: float | None = None) -> int:
    now = time.time() if now is None else now
    cur = conn.execute("UPDATE exportify_songs SET state='wishlist', attempts=0, error=NULL, updated_at=? "
                       "WHERE import_id=? AND state='failed'", (now, import_id))
    if cur.rowcount and get_plan(conn, import_id)["status"] == "done":
        set_plan(conn, import_id, {}, status="active", note="Trying the failed songs again.", now=now)
    return cur.rowcount


# ── the timer ────────────────────────────────────────────────────────────────

def main(argv: list[str]) -> int:
    """python -m tgfetch.exportify tick   (run by tg-fetcher-exportify.timer)"""
    if argv[:1] != ["tick"]:
        print(main.__doc__)
        return 2
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    from tgfetch.config import settings
    from tgfetch.library import load_library
    conn = db.connect(settings.db_path)
    ensure_schema(conn)
    n = conn.execute("SELECT COUNT(*) FROM exportify_plans WHERE status IN ('active','paused_disk')").fetchone()[0]
    if not n:
        return 0
    try:
        lib = load_library()
    except sqlite3.Error:
        lib = None
    out = tick(conn, settings, library=lib)
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main(sys.argv[1:]))
