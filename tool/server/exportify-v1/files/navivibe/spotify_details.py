"""
navivibe/spotify_details.py   (exportify-v1)
────────────────────────────────────────────
What an Exportify CSV says about songs the library owns, read from the small database tg-fetcher writes
(`spotify_details.db`, next to catalog.db; override with NAVIVIBE_SPOTIFY_DETAILS_DB).

STABLE CONTRACT for other code (the lyrics proxy reads ISRCs from here):

    table  spotify_details
      song_id   TEXT PRIMARY KEY   the library (Navidrome) song id, the same id as catalog.db songs.id
      isrc      TEXT               the CSV's ISRC; fills the songs catalog.db has no ISRC for. Indexed.
      popularity, genres (JSON list), label, release_date, explicit, duration_s, matched_by ('isrc'|'title'|'library'),
      danceability, energy, key, loudness, mode, speechiness, acousticness, instrumentalness, liveness, valence,
      tempo, time_signature, updated_at

    isrc_of(song_id, catalog_isrc="")  -> the catalog's ISRC when it has one, else the CSV's, else ""
    get(song_id)                       -> the row as a dict, or None
    rows()                             -> {song_id: row}   cached until the file changes

Everything here is optional: no file, no table, no row = no answer, never an error. Nothing is ever written
from this process, the audio files and Navidrome's tags are never touched, and the CSV's "Added By" column is
never read by anyone.
"""

import json
import logging
import os
import sqlite3
import threading

log = logging.getLogger(__name__)

PATH = os.getenv("NAVIVIBE_SPOTIFY_DETAILS_DB",
                 os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "spotify_details.db"))

_lock = threading.Lock()
_cache = {"stamp": None, "rows": {}, "path": None}
_warned = False


def _path() -> str:
    return PATH


def stamp(path: str | None = None):
    """Changes whenever the file does (for caches that depend on it)."""
    try:
        st = os.stat(path or _path())
        return (st.st_mtime_ns, st.st_size)
    except OSError:
        return None


def rows(path: str | None = None) -> dict:
    global _warned
    p = path or _path()
    s = stamp(p)
    with _lock:
        if _cache["path"] == p and _cache["stamp"] == s:
            return _cache["rows"]
    out = {}
    if s is not None:
        try:
            c = sqlite3.connect(f"file:{p}?mode=ro", uri=True, timeout=5)
            c.row_factory = sqlite3.Row
            try:
                for r in c.execute("SELECT * FROM spotify_details"):
                    d = dict(r)
                    try:
                        d["genres"] = json.loads(d.get("genres") or "[]")
                    except ValueError:
                        d["genres"] = []
                    out[d["song_id"]] = d
            finally:
                c.close()
        except sqlite3.Error as e:
            if not _warned:                       # one line, once: it is an optional extra
                log.warning("spotify_details not readable (%s)", type(e).__name__)
                _warned = True
            out = {}
    with _lock:
        _cache.update(path=p, stamp=s, rows=out)
    return out


def get(song_id: str, path: str | None = None) -> dict | None:
    return rows(path).get(song_id)


def isrc_of(song_id: str, catalog_isrc: str = "", path: str | None = None) -> str:
    if catalog_isrc:
        return catalog_isrc
    d = get(song_id, path)
    return (d or {}).get("isrc") or ""


def extend_entry(e: dict, s: dict) -> None:
    """Optional extra keys for one /catalog/songs entry (nothing is renamed or removed): `pop` (0-100),
    `released` (date), `sp_genres` (Spotify's, a list), `label`, and `year` only where the catalog has none."""
    d = get(s.get("id"))
    if not d:
        return
    rel = d.get("release_date") or ""
    if not e.get("year") and rel[:4].isdigit():
        e["year"] = int(rel[:4])
    if d.get("popularity") is not None:
        e["pop"] = int(d["popularity"])
    if rel:
        e["released"] = rel
    if d.get("genres"):
        e["sp_genres"] = list(d["genres"])[:4]
    if d.get("label"):
        e["label"] = d["label"]
