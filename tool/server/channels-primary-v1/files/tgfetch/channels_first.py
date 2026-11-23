"""
tgfetch/channels_first.py  (channels-primary-v1)
────────────────────────────────────────────────
The wishlist (Exportify) fetch asks the public Telegram channels FIRST and the music bot only for
the songs no channel has.

  FETCH_PRIMARY       channels (default) | race | bot (the old behaviour: bot only)
  FETCH_BOT_FALLBACK  1 (default) | 0: a song no channel has is NOT asked of the bot (it fails with
                      the reason; "Try Them Again" or a later run asks again)
  CHANNEL_SEARCH_GAP_S 6   seconds between two channel searches, all callers together
  CHANNEL_MAX_MB      100  a post bigger than this is not taken (hi-res files reach 140 MB)
  CHANNEL_MIN_FREE_GB 25   hard stop: below this much free disk nothing is downloaded (the song waits)

Acceptance is channel_fallback's, unchanged: FLAC, title match >= 90, an artist word in the caption /
file name / performer, remix / live / karaoke only when the song itself is one (cf.best_match).

  search     one search per SEARCH_GAP_S (a global pacer), FloodWait waited out, never repeated: every
             (channel, query) answer is kept in fetch.db (`channel_cache`; a hit 30 days, an empty
             answer 3 days) as the few fields the scoring reads, so a restart, a retry or a repeated
             title costs no Telegram request
  per song   channel by channel, the specific query ("title artistword") first, then the title alone;
             stops at the first acceptable post
  then       the post is fetched by id, taken through the worker's route (_take: FLAC gate, duplicate
             checks, download, tag, scan) and `jobs.source` says "channel:<name>"
  no hit     bot fallback, unless FETCH_BOT_FALLBACK=0 or the bot is waiting for a human check
             (human_check; one probe per BOT_CHECK_PROBE_S is still let through, that is how the flag
             clears once the owner has tapped verify). The song then ends `failed` with the reason,
             like any song that did not come in (one song = one state), and the channels are marked
             as tried so the fallback sweeper does not search them again.

Only batches whose link starts with "exportify:" are touched; YouTube lists and the app's own
requests keep their routes. Cancel is honoured between searches (worker._cancelled).
"""

import asyncio
import json
import logging
import os
import re
import shutil
import time
from types import SimpleNamespace as NS

from tgfetch import channel_fallback as cf
from tgfetch import db
from tgfetch.sources.base import SourceError
from tgfetch.sources.deezload import _picked_from

log = logging.getLogger(__name__)

CACHE_HIT_S = 30 * 86400
CACHE_EMPTY_S = 3 * 86400
MAX_FLOOD_RETRIES = 3
SCHEMA = """
CREATE TABLE IF NOT EXISTS channel_cache (
    channel  TEXT NOT NULL,
    query    TEXT NOT NULL,
    at       REAL NOT NULL,
    hits     TEXT NOT NULL,          -- JSON list of {id, mime, size, title, performer, fname, text, dur}
    PRIMARY KEY (channel, query)
);
"""
NOT_ON_CHANNELS = "not on the Telegram channels"


class Cancelled(Exception):
    """The batch was cancelled while a song was being looked for."""

STATS = {"songs": 0, "hit": 0, "miss": 0, "searches": 0, "cached": 0, "bot": 0}


def primary() -> str:
    v = (os.getenv("FETCH_PRIMARY") or "channels").strip().lower()
    return v if v in ("channels", "race", "bot") else "channels"


def bot_fallback() -> bool:
    return os.getenv("FETCH_BOT_FALLBACK", "1") != "0"


def gap_s() -> float:
    return float(os.getenv("CHANNEL_SEARCH_GAP_S", "6"))


def max_bytes() -> int:
    return int(float(os.getenv("CHANNEL_MAX_MB", "100")) * 1048576)


def min_free_gb() -> float:
    return float(os.getenv("CHANNEL_MIN_FREE_GB", "25"))


_EDITS = re.compile(r"\b(sped\s*up|speed\s*up|slowed|reverb|tiktok|nightcore|8d)\b", re.I)


def skip_channels(song: dict) -> bool:
    """Sped-up / slowed / TikTok edits are not on the lossless channels (0 of 24 such failed songs were
    found there): a 24 s search for them is wasted, so they go straight to the bot.
    CHANNEL_SKIP_EDITS=0 searches them anyway."""
    return os.getenv("CHANNEL_SKIP_EDITS", "1") != "0" and bool(_EDITS.search(song["title"]))


# ── pacing ───────────────────────────────────────────────────────────────────

_next_at = 0.0


async def pace(gap: float | None = None) -> None:
    """One channel search per `gap` seconds, however many songs ask."""
    global _next_at
    gap = gap_s() if gap is None else gap
    now = time.monotonic()
    wait = max(0.0, _next_at - now)
    _next_at = max(now, _next_at) + gap          # reserved before sleeping: callers queue up in order
    if wait:
        await asyncio.sleep(wait)


# ── cache: what the scoring reads of a post, and back into a message-like object ──

class DocumentAttributeAudio:                   # names matter: channel_fallback reads attributes by class name
    def __init__(self, title="", performer="", duration=0):
        self.title, self.performer, self.duration = title, performer, duration


class DocumentAttributeFilename:
    def __init__(self, file_name=""):
        self.file_name = file_name


def compact(m) -> dict:
    title = performer = fname = ""
    dur = 0
    doc = getattr(m, "document", None)
    for a in getattr(doc, "attributes", None) or []:
        n = type(a).__name__
        if n == "DocumentAttributeAudio":
            title, performer, dur = getattr(a, "title", "") or "", getattr(a, "performer", "") or "", getattr(a, "duration", 0) or 0
        elif n == "DocumentAttributeFilename":
            fname = getattr(a, "file_name", "") or ""
    return {"id": m.id, "mime": getattr(doc, "mime_type", "") or "", "size": getattr(doc, "size", 0) or 0,
            "title": title, "performer": performer, "fname": fname, "dur": dur,
            "text": (getattr(m, "raw_text", "") or getattr(m, "message", "") or "")[:400]}


def inflate(r: dict):
    attrs = [DocumentAttributeAudio(r["title"], r["performer"], r.get("dur", 0))]
    if r["fname"]:
        attrs.append(DocumentAttributeFilename(r["fname"]))
    doc = NS(id=r["id"], mime_type=r["mime"], size=r["size"], attributes=attrs)
    return NS(id=r["id"], document=doc, raw_text=r["text"], message=r["text"], out=False)


def cache_get(conn, channel: str, query: str, now: float | None = None):
    conn.executescript(SCHEMA)
    row = conn.execute("SELECT at, hits FROM channel_cache WHERE channel=? AND query=?",
                       (channel, query.lower())).fetchone()
    if row is None:
        return None
    hits = json.loads(row["hits"])
    ttl = CACHE_HIT_S if hits else CACHE_EMPTY_S
    return hits if (time.time() if now is None else now) - row["at"] < ttl else None


def cache_put(conn, channel: str, query: str, hits: list[dict]) -> None:
    conn.executescript(SCHEMA)
    conn.execute("INSERT OR REPLACE INTO channel_cache (channel, query, at, hits) VALUES (?,?,?,?)",
                 (channel, query.lower(), time.time(), json.dumps(hits)))


# ── searching ────────────────────────────────────────────────────────────────

_ents: dict = {}


def queries(title: str, artist: str) -> list[str]:
    """The specific query first ("title artistword"), then the title alone."""
    t = re.sub(r"\s+", " ", cf._BRACKET.sub(" ", title or "")).strip()
    words = cf.artist_words(artist)
    out = ([f"{t} {words[0]}"] if t and words else []) + ([t] if t else [])
    return list(dict.fromkeys(out))


def _flood_seconds(e: Exception) -> int | None:
    m = re.search(r"rate limit: wait (\d+)s", str(e))
    return int(m.group(1)) if m else None


async def search(worker, bid: int, channel: str, query: str) -> list[dict]:
    """The compact posts one channel gives for a query: from the cache, else one paced search."""
    cached = cache_get(worker.conn, channel, query)
    if cached is not None:
        STATS["cached"] += 1
        return cached
    client = worker.source.client
    for attempt in range(MAX_FLOOD_RETRIES + 1):
        if worker._cancelled(bid):
            raise Cancelled()
        await pace()
        try:
            if channel not in _ents:
                _ents[channel] = await client.get_entity(channel)
            msgs = await worker.source._call(client.get_messages, _ents[channel], search=query, limit=cf.LIMIT)
            break
        except SourceError as e:
            secs = _flood_seconds(e)
            if secs is None or attempt == MAX_FLOOD_RETRIES:
                raise
            log.warning("channels-first: FloodWait %ss, resting", secs)
            await asyncio.sleep(min(secs, 3600) + 1)
    STATS["searches"] += 1
    hits = [compact(m) for m in msgs or [] if getattr(m, "document", None) is not None]
    cache_put(worker.conn, channel, query, hits)
    return hits


async def find(worker, bid: int, song: dict):
    """(channel, compact post) of the first acceptable FLAC, else (None, None). Raises SourceError only
    when every search failed (nothing could be learned)."""
    title, artist = song["title"], song["artist"]
    seen = {ch: [] for ch in cf.channels()}
    errors = asked = 0
    last: Exception | None = None
    for q in queries(title, artist):
        for ch in seen:
            asked += 1
            try:
                seen[ch] += await search(worker, bid, ch, q)
            except SourceError as e:
                errors, last = errors + 1, e
                continue
            cap = max_bytes()
            posts = [inflate(r) for r in seen[ch] if not r["size"] or r["size"] <= cap]
            _, msg = cf.best_match(title, artist, posts)
            if msg is not None:
                return ch, next(r for r in seen[ch] if r["id"] == msg.id)
    if errors and errors == asked:
        raise last
    return None, None


# ── one song ─────────────────────────────────────────────────────────────────

def _free_gb(worker) -> float:
    try:
        return shutil.disk_usage(worker.s.library_dir).free / 1e9
    except OSError:
        return 1e9


def bot_allowed(worker) -> tuple[bool, str]:
    """(may the bot be asked, why not). A flagged bot gets one probe per interval (human_check.gate)."""
    if not bot_fallback():
        return False, "the bot fallback is off (FETCH_BOT_FALLBACK=0)"
    human = getattr(worker.source, "human", None)
    if human is not None:
        try:
            human.gate()
        except SourceError:
            return False, "the music bot is waiting for a human check"
    return True, ""


def _set_source(worker, jid: int, name: str) -> None:
    try:
        db.update_job(worker.conn, jid, source=name)
    except Exception:
        pass


async def take_from_channel(worker, jid: int, cand: dict, channel: str, post: dict) -> bool:
    """Download the post through the worker's route. True when the song is in (or already owned)."""
    ent = _ents.get(channel) or await worker.source.client.get_entity(channel)
    msg = await worker.source._call(worker.source.client.get_messages, ent, ids=post["id"])
    msg = msg[0] if isinstance(msg, list) else msg
    if msg is None or getattr(msg, "document", None) is None:
        return False
    picked = _picked_from(msg)
    picked.mime = "audio/flac"                    # is_flac() judged it; the FLAC gate checks the mime
    picked.file_key = f"ch:{channel}:{msg.id}"
    db.update_job(worker.conn, jid, status="picking", error=None)
    _set_source(worker, jid, f"channel:{channel}")
    if await worker._take(jid, cand, picked):
        await worker.import_job(jid)
    return db.get_job(worker.conn, jid)["status"] in ("ready", "imported", "duplicate")


def _fail(worker, jid: int, why: str) -> str:
    db.update_job(worker.conn, jid, status="failed", error=why[:200])
    return "done"


async def fetch_one(worker, b: dict, jid: int, cand: dict, bot_fetch) -> str:
    """Replaces youtube_batch.fetch_one for Exportify batches. Returns 'done' or 'later' like it."""
    try:
        return await _fetch_one(worker, b, jid, cand, bot_fetch)
    except Cancelled:                    # cancel_batch already marked the song; the batch loop stops
        return "done"


async def _fetch_one(worker, b: dict, jid: int, cand: dict, bot_fetch) -> str:
    mode = primary()
    exportify = (b.get("link") or "").startswith("exportify:")
    if (not exportify or mode == "bot" or not cf.enabled() or not cf.channels()
            or not hasattr(worker.source, "client") or not hasattr(worker.source, "_call")):
        return await bot_fetch(worker, jid, cand)

    from tgfetch import youtube_batch as yb
    song = yb.song_of(cand)
    if song["unreadable"]:
        return await bot_fetch(worker, jid, cand)
    library = worker.load_library()
    hit = yb.owned(song["title"], song["artist"], song["duration_s"], song["alts"], library, worker._owned_track)
    if hit:
        db.update_job(worker.conn, jid, status="duplicate", nd_song_id=hit["id"], error="already in the library")
        return "done"

    bid, began = b["id"], time.monotonic()
    STATS["songs"] += 1
    if mode == "race":
        return await _race(worker, b, jid, cand, song, bot_fetch)

    channel_error = None
    skipped = skip_channels(song)
    try:
        ch, post = (None, None) if skipped else await find(worker, bid, song)
    except SourceError as e:
        ch, post, channel_error = None, None, e
        log.warning("channels-first: job %s: channel search failed: %s", jid, e)
    if post is not None:
        if _free_gb(worker) < min_free_gb():
            db.update_job(worker.conn, jid, status="waiting", error="waiting for disk space")
            return "later"
        try:
            if await take_from_channel(worker, jid, cand, ch, post):
                STATS["hit"] += 1
                log.info("channels-first: job %s %s - %s from %s in %.0fs", jid, song["artist"], song["title"], ch,
                         time.monotonic() - began)
                return "done"
        except asyncio.CancelledError:
            raise
        except Exception as e:                      # download failed: the bot may still have it
            log.warning("channels-first: job %s: taking %s from %s failed: %r", jid, song["title"], ch, e)
            db.update_job(worker.conn, jid, status="waiting", error=None)
        if db.get_job(worker.conn, jid)["status"] in ("ready", "imported", "duplicate", "rejected"):
            return "done"
    elif channel_error is None and not skipped:
        STATS["miss"] += 1
        _mark_tried(worker, jid)

    ok, why = bot_allowed(worker)
    if not ok:
        if channel_error is not None:               # nothing could be learned from the channels: ask again later
            db.update_job(worker.conn, jid, status="waiting", error="the channels didn't answer — will retry")
            return "later"
        log.info("channels-first: job %s %s - %s: %s; the bot is skipped", jid, song["artist"], song["title"], why)
        return _fail(worker, jid, f"{NOT_ON_CHANNELS} ({why})")
    STATS["bot"] += 1
    result = await bot_fetch(worker, jid, cand)
    human = getattr(worker.source, "human", None)
    if result == "later" and human is not None and human.flagged:
        # The bot has just asked for the human check: do not hold the rest of the batch for it.
        return _fail(worker, jid, f"{NOT_ON_CHANNELS}; the music bot is waiting for a human check")
    return result


def _mark_tried(worker, jid: int) -> None:
    try:
        worker.conn.executescript(cf.SCHEMA)
        cf.mark(worker.conn, jid, "none", detail="channels-first")      # the fallback sweeper need not search again
    except Exception:
        pass


async def _race(worker, b, jid, cand, song, bot_fetch) -> str:
    """FETCH_PRIMARY=race: the channels and the bot at once for this song; whoever finishes with the
    file first. The bot side is the normal by-name fetch, so it is cancelled only if a channel wins
    before it has finished."""
    bid = b["id"]
    bot_task = asyncio.ensure_future(bot_fetch(worker, jid, cand))
    chan_task = asyncio.ensure_future(find(worker, bid, song))
    try:
        await asyncio.wait({bot_task, chan_task}, return_when=asyncio.FIRST_COMPLETED)
        if chan_task.done() and not chan_task.cancelled() and chan_task.exception() is None \
                and chan_task.result()[1] is not None and not bot_task.done():
            ch, post = chan_task.result()
            bot_task.cancel()
            await asyncio.gather(bot_task, return_exceptions=True)
            if await take_from_channel(worker, jid, cand, ch, post):
                return "done"
            db.update_job(worker.conn, jid, status="waiting", error=None)
            return await bot_fetch(worker, jid, cand)
        if bot_task.done() and not chan_task.done():
            chan_task.cancel()
            await asyncio.gather(chan_task, return_exceptions=True)
        return await bot_task
    finally:
        for t in (bot_task, chan_task):
            if not t.done():
                t.cancel()
