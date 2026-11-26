"""
tgfetch/blocked_memory.py  (blocked-memory-v1)
──────────────────────────────────────────────
A song the author withdrew ("The song's author has prohibited listening to it in most countries") is
`blocked` for good, but the block used to be remembered per JOB. The same song came back on a later night
as a new candidate (a new job id) and the bot was asked again, then refused again (Deezer track 2546118092,
22 and 23 Nov 2026, both from the trending import).

Now the first refusal is written to `blocked_tracks`, keyed by the song's normalised title and first artist,
with the Deezer track id from the bot's reply kept for reference. Any later request for the same song, from any
list or user, is blocked at once with the stored reason, before the bot or a channel is asked.

Bookkeeping only: every function swallows its own errors, so a failed write or read never fails a download
(an error on read simply means the song is asked as before).
"""

import logging
import re
import time

from tgfetch import channel_fallback as cf

log = logging.getLogger(__name__)

SCHEMA = """
CREATE TABLE IF NOT EXISTS blocked_tracks (
    key        TEXT PRIMARY KEY,       -- "ta:<title>|<first artist>", normalised
    deezer_id  TEXT,                   -- from the bot's reply, when it gave one
    reason     TEXT NOT NULL,
    at         REAL NOT NULL
)
"""
_DEEZER = re.compile(r"deezer\.com/(?:[a-z]{2}/)?track/(\d+)", re.I)


def deezer_id(text: str | None) -> str | None:
    m = _DEEZER.search(text or "")
    return m.group(1) if m else None


def song_key(title: str | None, artist: str | None) -> str | None:
    """Same song, whatever the candidate id: its title and its first artist, normalised."""
    t = cf.norm(title)
    if not t:
        return None
    first = re.split(r"\s*(?:,|&|;| feat\.? | ft\.? | x )\s*", artist or "", maxsplit=1, flags=re.I)[0]
    return f"ta:{t}|{cf.norm(first)}"


def remember(conn, title: str | None, artist: str | None, reason: str) -> bool:
    """Keep this song as withdrawn. True when a new row was written."""
    key = song_key(title, artist)
    if not key:
        return False
    try:
        conn.execute(SCHEMA)
        cur = conn.execute("INSERT OR IGNORE INTO blocked_tracks (key, deezer_id, reason, at) VALUES (?,?,?,?)",
                           (key, deezer_id(reason), reason, time.time()))
        conn.commit()
        return cur.rowcount > 0
    except Exception as e:
        log.warning("blocked-memory: could not record %r (%s)", key, type(e).__name__)
        return False


def lookup(conn, title: str | None, artist: str | None) -> str | None:
    """The stored reason when this song was withdrawn before, else None."""
    key = song_key(title, artist)
    if not key:
        return None
    try:
        conn.execute(SCHEMA)
        row = conn.execute("SELECT reason FROM blocked_tracks WHERE key=?", (key,)).fetchone()
        return row[0] if row else None
    except Exception as e:
        log.warning("blocked-memory: lookup failed (%s)", type(e).__name__)
        return None


def remember_job(conn, jid: int, reason: str) -> None:
    """Called when a job ends `blocked`: remember the song behind its candidate."""
    try:
        from tgfetch import db
        job = db.get_job(conn, jid)
        cand = db.get_candidate(conn, job["candidate_id"]) if job else None
        if cand and remember(conn, cand["title"], cand["artist"], reason):
            log.info("blocked-memory: %r by %r will not be asked again", cand["title"], cand["artist"])
    except Exception as e:
        log.warning("blocked-memory: job %s not recorded (%s)", jid, type(e).__name__)
