"""
tgfetch/data_queue_hook.py   (data-queue-v1)
────────────────────────────────────────────
Called from db.update_job the moment a download job becomes `ready` (the song is in the library and Navidrome
knows its id). Every way a song arrives goes through that one place: a search or request, a pasted playlist link,
a YouTube list, an Exportify wishlist batch, the retry of a failed import.

It puts the song in the hidden weekly data queue (navivibe/data_queue_store.py) UNLESS spotify_details.db already
holds real Spotify audio features for it. It is cheap (one read, one insert) and failure-isolated: it never
raises and a queue problem never fails an import. Set DATA_QUEUE_OFF=1 in tg-fetcher's .env to switch it off.
A wishlist song whose Exportify features land a little later is dropped from the queue by the web server before
it ever reaches a batch (data_queue_store.reconcile).
"""

import logging
import os
import sqlite3

log = logging.getLogger("tgfetch.data_queue")


def _catalog_row(song_id: str) -> dict:
    """ISRC, length and album artist, when the shuffle server's catalog already knows the song (else {})."""
    try:
        from navivibe.catalog import store as cat
        if not os.path.exists(cat.CATALOG_DB):
            return {}
        c = sqlite3.connect("file:%s?mode=ro" % cat.CATALOG_DB, uri=True, timeout=2)
        try:
            r = c.execute("SELECT isrc, duration, album_artist FROM songs WHERE id=?", (song_id,)).fetchone()
        finally:
            c.close()
        return {"isrc": r[0], "duration": r[1], "album_artist": r[2]} if r else {}
    except Exception:                                   # noqa: BLE001 - optional extra
        return {}


def on_ready(conn, job_id: int, song_id: str) -> str:
    """Returns what happened (for tests): queued | known | has_features | off | error."""
    try:
        if os.getenv("DATA_QUEUE_OFF") == "1":
            return "off"
        from tgfetch import config  # noqa: F401  puts NAVIVIBE_ROOT on sys.path (as the service does at start)
        from navivibe import data_queue_store as store
        row = conn.execute(
            "SELECT c.title, c.artist, c.album, b.link, c.isrc, c.duration_s FROM jobs j JOIN candidates c ON c.id = j.candidate_id "
            "LEFT JOIN batches b ON b.id = j.batch_id WHERE j.id = ?", (job_id,)).fetchone()
        if not row:
            return "error"
        song = {"song_id": song_id, "title": row[0], "artist": row[1], "album": row[2], "isrc": row[4], "duration": row[5],
                **{k: v for k, v in _catalog_row(song_id).items() if v}}
        return store.enqueue(song, store.source_of(row[3]))
    except Exception as e:                              # noqa: BLE001
        log.warning("data-queue: hook skipped (%s)", type(e).__name__)
        return "error"
