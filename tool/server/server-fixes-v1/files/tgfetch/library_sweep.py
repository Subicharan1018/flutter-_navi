"""
tgfetch/library_sweep.py  (server-fixes-v1)
───────────────────────────────────────────
Keeps what tg-fetcher remembers about library songs true after the library
changes under it. Navidrome gives a song a new id when its file is replaced or
re-tagged (the doctor, a re-import, a copy dropped into /music); the old id is
then `missing` and every stored reference to it is dead.

  charts    trending_songs / trending_entries rows whose nd_song_id is no longer
            a live song are pointed at the replacement (same song by title and
            main artist, "(From …)" / "Original Motion Picture Soundtrack" and
            " - <subtitle>" ignored, length within VERSION_SLACK_S), or go back
            to pending (match / queued) so the charts fetch them again.
  failures  failed download jobs whose song is now in the library (by the same
            normalised title, at least one artist in common, same version
            words, length close when both are known) are recorded in
            resolved_failures; the download queue's "failed" list leaves them out.

The sweep runs when the library changed (Navidrome's scan time, its missing
count or the newest media_file change differ from the last sweep), when a new
failure appears, at every chart snapshot, and after auto-import. It reads
Navidrome's DB read-only and only writes fetch.db.
"""

import logging
import re
import sqlite3
import time
import unicodedata

from rapidfuzz import fuzz

from tgfetch.config import settings as default_settings
from navivibe.catalog.enrich import norm_title
from navivibe.recsys.data import phonetic_key

log = logging.getLogger(__name__)

VERSION_SLACK_S = 10        # same as trending.VERSION_SLACK_S: a longer gap is another cut of the song
FAILURE_SLACK_S = 15        # a failed job's length came from the playlist site; looser
ARTIST_SAME = 88            # fuzz ratio for two spellings of one name ("Anirudh" vs "Anirudh Ravichander" is not)
CHECK_EVERY_S = 120.0       # how often the service looks for a library change
LIVE_TTL_S = 60.0           # the chart API's view of live ids is at most this old

FAILED_JOB = ("failed", "rejected", "import_failed")

SCHEMA = """
CREATE TABLE IF NOT EXISTS resolved_failures (
    job_id      INTEGER PRIMARY KEY,
    nd_song_id  TEXT,
    how         TEXT NOT NULL,
    resolved_at REAL NOT NULL
);
"""

# ── names ────────────────────────────────────────────────────────────────────

_FROM_BRACKET = re.compile(r"[\(\[]\s*from\b[^\)\]]*[\)\]]", re.I)
_FROM_DASH = re.compile(r"\s+[-–—]\s+from\b.*$", re.I)
_OST = re.compile(r"[\(\[]?\s*(original\s+(motion\s+picture\s+)?(sound\s*track|score|background\s+score)|"
                  r"\bost\b)\s*[\)\]]?", re.I)
_SUBTITLE = re.compile(r"\s+[-–—:|]\s+.*$")
_VERSION = re.compile(
    r"\b(remix|reprise|unplugged|lo-?fi|slowed|reverb|sped(?:\s+up)?|speed\s+up|acoustic|instrumental|karaoke|"
    r"cover|live|female|male|reloaded|extended|remaster(?:ed)?|mashup|duet|sad|version|revival|"
    r"track by track|commentary|interview|demo|nightcore|8d)\b", re.I)
_ARTIST_SPLIT = re.compile(r"\s*(?:[,;/&•·|]|\bfeat\.?|\bft\.?|\bfeaturing\b|\bwith\b)\s*|\s+(?:x|and)\s+", re.I)


_CANON = {"sped": "sped up", "speed up": "sped up", "lofi": "lo fi", "remastered": "remaster"}


def versions(title: str) -> frozenset:
    """Version words in a title: a remix / sped-up / live cut is a different song."""
    out = set()
    for w in _VERSION.findall(unicodedata.normalize("NFKC", title or "")):
        w = re.sub(r"[\s-]+", " ", w.lower()).strip()
        out.add(_CANON.get(w, w))
    return frozenset(out)


def clean_title(title: str) -> str:
    """The song's own name: '(From "DC")', 'Original Motion Picture Soundtrack'
    and ' - The Melting Point of Love' dropped, then norm_title. Version words
    are judged separately (versions())."""
    s = unicodedata.normalize("NFKC", title or "")
    s = _FROM_BRACKET.sub(" ", s)
    s = _FROM_DASH.sub(" ", s)
    s = _OST.sub(" ", s)
    s = _SUBTITLE.sub(" ", s) if _SUBTITLE.search(s) and _SUBTITLE.sub("", s).strip() else s
    return norm_title(s)


def split_names(credit: str) -> list[str]:
    """'Hiphop Tamizha • Kaushik Krish • Padmalatha', 'A, B & C feat. D' → names."""
    out = []
    for p in _ARTIST_SPLIT.split(unicodedata.normalize("NFKC", credit or "")):
        n = norm_title(re.sub(r"\.\s*", "", p))       # "A. R. Rahman" → "ar rahman"
        if n and n not in out:
            out.append(n)
    return out


def share_artist(a: str, b: str) -> bool:
    """At least one name in common (two spellings of one name count)."""
    left, right = split_names(a), split_names(b)
    return any(x == y or fuzz.ratio(x, y) >= ARTIST_SAME for x in left for y in right)


def same_song(title: str, artist: str, duration: float | None, song: dict, slack: float) -> bool:
    if clean_title(title) != clean_title(song["title"]) and \
            phonetic_key(clean_title(title)) != phonetic_key(clean_title(song["title"])):
        return False
    if versions(title) != versions(song["title"]):
        return False
    if duration and song.get("duration") and abs(float(song["duration"]) - float(duration)) > slack:
        return False
    return share_artist(artist, song.get("artist") or "")


class Index:
    """Library songs by clean title (and its phonetic key) for quick lookups."""

    def __init__(self, library: list[dict]):
        self.by_key: dict[str, list[dict]] = {}
        for s in library:
            t = clean_title(s.get("title") or "")
            if not t:
                continue
            for k in {t, "~" + phonetic_key(t)}:
                self.by_key.setdefault(k, []).append(s)
        self.ids = {s["id"] for s in library}

    def find(self, title: str, artist: str, duration: float | None, slack: float) -> dict | None:
        t = clean_title(title)
        if not t:
            return None
        seen, hits = set(), []
        for s in self.by_key.get(t, []) + self.by_key.get("~" + phonetic_key(t), []):
            if s["id"] not in seen and same_song(title, artist, duration, s, slack):
                seen.add(s["id"])
                hits.append(s)
        if not hits:
            return None
        if duration:
            return min(hits, key=lambda s: abs(float(s.get("duration") or 0) - float(duration)))
        return max(hits, key=lambda s: float(s.get("duration") or 0))


def rematch(title: str, artist: str, duration: float | None, library: list[dict] | Index) -> str | None:
    """The live library song a chart row is, by title + main artist (+ length)."""
    idx = library if isinstance(library, Index) else Index(library)
    main = split_names(artist)[:1]
    hit = idx.find(title, main[0] if main else artist, duration, VERSION_SLACK_S)
    return hit["id"] if hit else None


# ── the sweep ────────────────────────────────────────────────────────────────

def ensure_schema(conn) -> None:
    conn.executescript(SCHEMA)


def _has_table(conn, name: str) -> bool:
    return conn.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)).fetchone() is not None


def sweep_charts(conn, library: list[dict], owned=None, today: str | None = None,
                 idx: Index | None = None) -> dict:
    """Re-point chart rows whose song id died. `owned(row) -> id|None` is the
    charts' own matcher (Trending._owned), tried before ours."""
    if not _has_table(conn, "trending_songs"):
        return {"repointed": 0, "pending": 0}
    idx = idx or Index(library)
    live = idx.ids
    today = today or time.strftime("%Y-%m-%d")
    out = {"repointed": 0, "pending": 0}
    dead = [dict(r) for r in conn.execute(
        "SELECT * FROM trending_songs WHERE nd_song_id IS NOT NULL AND status IN ('owned', 'added')")
        if r["nd_song_id"] not in live]
    for row in dead:
        old = row["nd_song_id"]
        new = None
        if owned is not None:
            try:
                new = owned(row)
            except Exception as e:          # the charts' matcher is a bonus, never a blocker
                log.warning("sweep: charts matcher failed for %s: %s", row["key"], type(e).__name__)
        if new not in live:
            new = rematch(row["title"], row["artist"], row["duration_s"], idx)
        now = time.time()
        if new:
            conn.execute("UPDATE trending_songs SET nd_song_id=?, updated_at=? WHERE key=?", (new, now, row["key"]))
            conn.execute("UPDATE trending_entries SET nd_song_id=? WHERE nd_song_id=?", (new, old))
            out["repointed"] += 1
            log.info("sweep: chart song %s (%s) moved %s -> %s", row["key"], row["title"], old, new)
        else:
            status = "queued" if row.get("deezer_id") else "match"
            conn.execute("UPDATE trending_songs SET nd_song_id=NULL, status=?, job_id=NULL, reason=NULL, "
                         "run_date=?, updated_at=? WHERE key=?", (status, today, now, row["key"]))
            conn.execute("UPDATE trending_entries SET nd_song_id=NULL WHERE nd_song_id=?", (old,))
            out["pending"] += 1
            log.info("sweep: chart song %s (%s) is gone from the library (%s); back to %s",
                     row["key"], row["title"], old, status)
    return out


def sweep_failures(conn, library: list[dict], idx: Index | None = None) -> dict:
    """Record failed jobs whose song is now in the library (by any route)."""
    ensure_schema(conn)
    idx = idx or Index(library)
    marks = ",".join("?" * len(FAILED_JOB))
    rows = conn.execute(
        f"SELECT j.id, c.title, c.artist, c.duration_s FROM jobs j JOIN candidates c ON c.id = j.candidate_id "
        f"WHERE j.status IN ({marks}) AND COALESCE(j.error, '') != 'cancelled' "
        f"AND j.id NOT IN (SELECT job_id FROM resolved_failures)", FAILED_JOB).fetchall()
    n = 0
    for r in rows:
        hit = idx.find(r["title"], r["artist"], r["duration_s"], FAILURE_SLACK_S)
        if hit:
            conn.execute("INSERT OR IGNORE INTO resolved_failures (job_id, nd_song_id, how, resolved_at) "
                         "VALUES (?, ?, 'in library', ?)", (r["id"], hit["id"], time.time()))
            n += 1
    return {"resolved": n}


def sweep(conn, library: list[dict], owned=None, today: str | None = None) -> dict:
    idx = Index(library)
    out = {**sweep_charts(conn, library, owned, today, idx), **sweep_failures(conn, library, idx)}
    if out.get("repointed") or out.get("pending") or out.get("resolved"):
        log.info("library sweep: %s", out)
    return out


# ── when to sweep ────────────────────────────────────────────────────────────

def library_signature(nd_db: str | None = None) -> str | None:
    """Changes whenever Navidrome scanned or a song changed; None when unreadable."""
    try:
        c = sqlite3.connect(f"file:{nd_db or default_settings.navidrome_db}?mode=ro", uri=True, timeout=10)
    except sqlite3.Error:
        return None
    try:
        parts = []
        try:
            parts += [str(tuple(r)) for r in c.execute(
                "SELECT last_scan_at, total_missing_files, total_songs FROM library ORDER BY id")]
        except sqlite3.Error:
            pass
        parts.append(str(tuple(c.execute("SELECT COUNT(*), SUM(missing), MAX(updated_at) FROM media_file").fetchone())))
        return "|".join(parts)
    except sqlite3.Error:
        return None
    finally:
        c.close()


def failure_signature(conn) -> str:
    marks = ",".join("?" * len(FAILED_JOB))
    return str(tuple(conn.execute(f"SELECT COUNT(*), MAX(updated_at) FROM jobs WHERE status IN ({marks})",
                                  FAILED_JOB).fetchone()))


async def maybe_sweep(trending_obj) -> dict | None:
    """Called from Trending.tick: sweep when the library or the failures changed
    (checked every CHECK_EVERY_S). The library read runs off the event loop."""
    import asyncio
    now = time.monotonic()
    if now - getattr(trending_obj, "_sfv1_checked", 0.0) < CHECK_EVERY_S:
        return None
    trending_obj._sfv1_checked = now
    sig = await asyncio.to_thread(library_signature, trending_obj.s.navidrome_db)
    if sig is None:
        return None
    sig = sig + "#" + failure_signature(trending_obj.conn)
    if sig == getattr(trending_obj, "_sfv1_signature", None):
        return None
    library = await asyncio.to_thread(trending_obj.load_library)
    out = sweep(trending_obj.conn, library, owned=chart_owned(trending_obj, library))
    trending_obj._sfv1_signature = sig
    trending_obj._sfv1_live = (time.monotonic(), {s["id"] for s in library}, trending_obj.load_library)
    return out


def chart_owned(trending_obj, library):
    """Trending._owned as a row → id function (title, first artist, ISRC, length)."""
    from tgfetch.trending import split_artists

    def owned(row: dict) -> str | None:
        first = split_artists(row["artist"])[0] if row.get("artist") else ""
        return trending_obj._owned(row["title"], first, row.get("isrc"), row.get("duration_s"), library)
    return owned


def live_id(trending_obj, *ids) -> str | None:
    """The first of `ids` that is a live library song. When the library can't
    be read the stored id is trusted, as before."""
    ids = [i for i in ids if i]
    if not ids:
        return None
    loader = trending_obj.load_library
    cached = getattr(trending_obj, "_sfv1_live", None)
    if cached is None or len(cached) < 3 or cached[2] is not loader or time.monotonic() - cached[0] > LIVE_TTL_S:
        try:
            cached = (time.monotonic(), {s["id"] for s in loader()}, loader)
        except Exception:
            cached = (time.monotonic(), None, loader)
        trending_obj._sfv1_live = cached
    live = cached[1]
    if live is None:
        return ids[0]
    return next((i for i in ids if i in live), None)
