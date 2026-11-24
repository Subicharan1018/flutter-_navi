"""The job's own database (film_credits.db) and the read-only view of catalog.db.

film_credits.db is the ONLY file this job writes. Tables:
  songs(song_id PK, fk, film, md, ly, sg, film_src)     per library song (md/ly/sg: JSON lists of names)
  films(fk PK, title, year, directors, music_directors, lyricists, wikidata, tracklist, tracklist_mbid, source, updated_at)
  lookups(key, source, status, result, fetched_at, retry_after)   every third-party answer, misses and errors included
"""
import datetime
import json
import os
import sqlite3
import time

MISS_RETRY_DAYS, ERROR_RETRY_DAYS = 60, 1


def today(now=None) -> str:
    return datetime.datetime.fromtimestamp(now or time.time(), datetime.timezone.utc).strftime("%Y-%m-%d")


def later(days: int, now=None) -> str:
    return (datetime.datetime.fromtimestamp(now or time.time(), datetime.timezone.utc)
            + datetime.timedelta(days=days)).strftime("%Y-%m-%d")


class Store:
    def __init__(self, path: str):
        if os.path.dirname(path):
            os.makedirs(os.path.dirname(path), exist_ok=True)
        self.c = sqlite3.connect(path, timeout=30)
        self.c.executescript("""
        CREATE TABLE IF NOT EXISTS songs(song_id TEXT PRIMARY KEY, fk TEXT, film TEXT, md TEXT, ly TEXT, sg TEXT, film_src TEXT);
        CREATE INDEX IF NOT EXISTS songs_fk ON songs(fk);
        CREATE TABLE IF NOT EXISTS films(fk TEXT PRIMARY KEY, title TEXT, year INTEGER, directors TEXT, music_directors TEXT,
            lyricists TEXT, wikidata TEXT, tracklist TEXT, tracklist_mbid TEXT, source TEXT, updated_at TEXT);
        CREATE TABLE IF NOT EXISTS lookups(key TEXT NOT NULL, source TEXT NOT NULL, status TEXT NOT NULL, result TEXT,
            fetched_at TEXT NOT NULL, retry_after TEXT, PRIMARY KEY(key, source));
        """)
        self.c.commit()

    # cache ------------------------------------------------------------------
    def get(self, key, source):
        r = self.c.execute("SELECT status, result, retry_after FROM lookups WHERE key=? AND source=?", (key, source)).fetchone()
        return None if not r else {"status": r[0], "result": json.loads(r[1]) if r[1] else None, "retry_after": r[2]}

    def due(self, key, source, day: str) -> bool:
        e = self.get(key, source)
        return e is None or (e["status"] != "ok" and (e["retry_after"] or "") <= day)

    def put(self, key, source, status, result=None, now=None):
        retry = {"ok": None, "miss": later(MISS_RETRY_DAYS, now), "error": later(ERROR_RETRY_DAYS, now)}[status]
        self.c.execute("INSERT OR REPLACE INTO lookups VALUES (?,?,?,?,?,?)",
                       (key, source, status, json.dumps(result, ensure_ascii=False) if result is not None else None,
                        today(now), retry))
        self.c.commit()

    # results ----------------------------------------------------------------
    def replace_songs(self, rows):
        """rows: iterable of (song_id, derived dict). The whole table is rebuilt: it is derived, never edited."""
        self.c.execute("DELETE FROM songs")
        self.c.executemany("INSERT INTO songs VALUES (?,?,?,?,?,?,?)", [
            (sid, d["fk"], d["film"], json.dumps(d["md"], ensure_ascii=False), json.dumps(d["ly"], ensure_ascii=False),
             json.dumps(d["sg"], ensure_ascii=False), d.get("film_src", "")) for sid, d in rows])
        self.c.commit()

    def upsert_film(self, fk, title, year=None, directors=(), music_directors=(), lyricists=(), wikidata="",
                    tracklist=None, tracklist_mbid="", source=""):
        old = self.c.execute("SELECT year, directors, music_directors, lyricists, wikidata, tracklist, tracklist_mbid, source "
                             "FROM films WHERE fk=?", (fk,)).fetchone()
        j = lambda v: json.dumps(list(v), ensure_ascii=False)   # noqa: E731
        if old:   # a later pass never blanks what an earlier one found
            year = year or old[0]
            directors = directors or json.loads(old[1] or "[]")
            music_directors = music_directors or json.loads(old[2] or "[]")
            lyricists = lyricists or json.loads(old[3] or "[]")
            wikidata = wikidata or old[4] or ""
            tracklist = tracklist if tracklist is not None else (json.loads(old[5]) if old[5] else None)
            tracklist_mbid = tracklist_mbid or old[6] or ""
            source = ",".join(sorted(set(filter(None, (old[7] or "").split(",") + source.split(",")))))
        self.c.execute("INSERT OR REPLACE INTO films VALUES (?,?,?,?,?,?,?,?,?,?,?)", (
            fk, title, year, j(directors), j(music_directors), j(lyricists), wikidata,
            json.dumps(tracklist, ensure_ascii=False) if tracklist is not None else None, tracklist_mbid, source, today()))
        self.c.commit()

    def counts(self) -> dict:
        q = lambda s: self.c.execute(s).fetchone()[0]   # noqa: E731
        return {"songs": q("SELECT COUNT(*) FROM songs"), "songs_with_film": q("SELECT COUNT(*) FROM songs WHERE fk!=''"),
                "films": q("SELECT COUNT(DISTINCT fk) FROM songs WHERE fk!=''"),
                "films_with_wikidata": q("SELECT COUNT(*) FROM films WHERE wikidata!=''"),
                "films_with_tracklist": q("SELECT COUNT(*) FROM films WHERE tracklist IS NOT NULL")}

    def close(self):
        self.c.close()


def read_catalog(path: str):
    """(songs, itunes): songs = [dict of catalog columns], itunes = {song_id: payload text}. Read-only."""
    c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(path).replace("\\", "/"), uri=True, timeout=10)
    c.row_factory = sqlite3.Row
    try:
        songs = [dict(r) for r in c.execute(
            "SELECT id, title, artist, album, album_artist, composer, lyricist, year, film FROM songs "
            "WHERE COALESCE(missing,0)=0 ORDER BY id")]
        it = {r[0]: r[1] for r in c.execute("SELECT song_id, payload FROM source_raw WHERE source='itunes' AND ok=1")}
        return songs, it
    finally:
        c.close()
