"""The job's own cache (every lookup, misses included) and the read / write of the shared files.

Shared file written: spotify_details.db, table spotify_details: the same table and columns exportify-v1
writes, so navivibe/spotify_details.py and everything that reads it work unchanged. Only EMPTY fields are
filled (a row exportify wrote is never overwritten). A side table `enrich_provenance` records source and date
per filled field; nothing reads it but this job and the owner.
"""
import datetime
import json
import os
import sqlite3
import time

FEATURES = ("danceability", "energy", "key", "loudness", "mode", "speechiness", "acousticness",
            "instrumentalness", "liveness", "valence", "tempo", "time_signature")
_INT = {"key", "mode", "time_signature"}
# identical to exportify-v1 (tgfetch/exportify.py DETAILS_COLUMNS)
DETAILS_COLUMNS = ("song_id TEXT PRIMARY KEY, isrc TEXT, popularity INTEGER, genres TEXT, label TEXT, "
                   "release_date TEXT, explicit INTEGER, duration_s REAL, matched_by TEXT, " +
                   ", ".join("%s %s" % (f, "INTEGER" if f in _INT else "REAL") for f in FEATURES) +
                   ", updated_at REAL NOT NULL")
FIELDS = ("isrc", "label", "release_date", "genres")
MISS_RETRY_DAYS, ERROR_RETRY_DAYS = 30, 1


def today(now=None) -> str:
    return datetime.datetime.fromtimestamp(now or time.time(), datetime.timezone.utc).strftime("%Y-%m-%d")


def later(days: int, now=None) -> str:
    return (datetime.datetime.fromtimestamp(now or time.time(), datetime.timezone.utc)
            + datetime.timedelta(days=days)).strftime("%Y-%m-%d")


class Cache:
    def __init__(self, path: str):
        if os.path.dirname(path):
            os.makedirs(os.path.dirname(path), exist_ok=True)
        self.c = sqlite3.connect(path, timeout=30)
        self.c.execute("""CREATE TABLE IF NOT EXISTS lookups(
            song_id TEXT NOT NULL, source TEXT NOT NULL, status TEXT NOT NULL, result TEXT,
            fetched_at TEXT NOT NULL, retry_after TEXT, PRIMARY KEY(song_id, source))""")
        self.c.commit()

    def get(self, song_id, source):
        r = self.c.execute("SELECT status, result, fetched_at, retry_after FROM lookups WHERE song_id=? AND source=?",
                           (song_id, source)).fetchone()
        if not r:
            return None
        return {"status": r[0], "result": json.loads(r[1]) if r[1] else None, "fetched_at": r[2], "retry_after": r[3]}

    def due(self, song_id, source, now_day: str) -> bool:
        """True when this lookup was never made, or it was a miss / error whose retry date has passed."""
        e = self.get(song_id, source)
        return e is None or (e["status"] != "ok" and (e["retry_after"] or "") <= now_day)

    def put(self, song_id, source, status, result=None, now=None):
        retry = {"ok": None, "miss": later(MISS_RETRY_DAYS, now), "error": later(ERROR_RETRY_DAYS, now)}[status]
        self.c.execute("INSERT OR REPLACE INTO lookups VALUES (?,?,?,?,?,?)",
                       (song_id, source, status, json.dumps(result, ensure_ascii=False) if result is not None else None,
                        today(now), retry))
        self.c.commit()

    def stats(self) -> dict:
        return {f"{s}:{st}": n for s, st, n in self.c.execute("SELECT source, status, COUNT(*) FROM lookups GROUP BY 1,2")}

    def close(self):
        self.c.close()


# ── the catalog (read-only) ──────────────────────────────────────────────────

def read_catalog(path: str):
    """(songs, raw): songs = [dict], raw = {song_id: {'lastfm': (payload, date), 'musicbrainz': (payload, date)}}"""
    c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=10)
    c.row_factory = sqlite3.Row
    try:
        songs = [dict(r) for r in c.execute(
            "SELECT id, title, artist, album_artist, composer, duration, year, isrc, mbid FROM songs "
            "WHERE COALESCE(missing,0)=0 ORDER BY id")]
        raw: dict = {}
        for r in c.execute("SELECT song_id, source, payload, fetched_at FROM source_raw "
                           "WHERE ok=1 AND source IN ('lastfm','musicbrainz')"):
            try:
                raw.setdefault(r["song_id"], {})[r["source"]] = (json.loads(r["payload"]), (r["fetched_at"] or "")[:10])
            except ValueError:
                pass
        return songs, raw
    finally:
        c.close()


# ── spotify_details (shared) ─────────────────────────────────────────────────

def empty(v) -> bool:
    return v is None or v == "" or v == "[]"


def read_details(path: str) -> dict:
    """{song_id: {isrc, label, release_date, genres}} (strings as stored). No file / table = {}."""
    if not os.path.exists(path):
        return {}
    try:
        c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=10)
        try:
            return {r[0]: dict(zip(FIELDS, r[1:])) for r in
                    c.execute("SELECT song_id, isrc, label, release_date, genres FROM spotify_details")}
        finally:
            c.close()
    except sqlite3.Error:
        return {}


def write_details(path: str, fills: dict, now=None) -> dict:
    """fills = {song_id: {field: (value, source, date)}}. Fills only empty fields; returns counts per field.
    One short transaction; a busy file is waited for up to 30 s (exportify's writer uses the same file)."""
    now = now or time.time()
    counts = {f: 0 for f in FIELDS}
    c = sqlite3.connect(path, timeout=30)
    try:
        c.execute("CREATE TABLE IF NOT EXISTS spotify_details (%s)" % DETAILS_COLUMNS)
        c.execute("CREATE INDEX IF NOT EXISTS spotify_details_isrc ON spotify_details(isrc)")
        c.execute("CREATE TABLE IF NOT EXISTS enrich_provenance(song_id TEXT NOT NULL, field TEXT NOT NULL, "
                  "value TEXT, source TEXT, source_date TEXT, applied_at REAL, PRIMARY KEY(song_id, field))")
        c.execute("BEGIN IMMEDIATE")
        for f in FIELDS:        # a value exportify has since replaced is no longer ours: drop its provenance
            c.execute("DELETE FROM enrich_provenance WHERE field=? AND NOT EXISTS (SELECT 1 FROM spotify_details d "
                      "WHERE d.song_id=enrich_provenance.song_id AND d.%s IS enrich_provenance.value)" % f, (f,))
        for sid, fields in fills.items():
            row = c.execute("SELECT isrc, label, release_date, genres FROM spotify_details WHERE song_id=?", (sid,)).fetchone()
            cur = dict(zip(("isrc", "label", "release_date", "genres"), row)) if row else None
            vals = {}
            for f, (v, src, date) in fields.items():
                if cur is None or empty(cur[f]):
                    vals[f] = (json.dumps(v, ensure_ascii=False) if f == "genres" else v, src, date)
            if not vals:
                continue
            if cur is None:
                c.execute("INSERT INTO spotify_details (song_id, genres, matched_by, updated_at) VALUES (?, '[]', 'libenrich', ?)",
                          (sid, now))
            for f, (v, src, date) in vals.items():
                c.execute("UPDATE spotify_details SET %s=? WHERE song_id=?" % f, (v, sid))
                c.execute("INSERT OR REPLACE INTO enrich_provenance VALUES (?,?,?,?,?,?)", (sid, f, v, src, date, now))
                counts[f] += 1
        c.commit()
    except Exception:
        c.rollback()
        raise
    finally:
        c.close()
    return counts
