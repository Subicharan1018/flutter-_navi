"""
tgfetch/channel_fallback.py  (channel-fallback-v1)
──────────────────────────────────────────────────
Songs the music bot could not give (not found, not lossless, no answer, "Verify you're not a
robot") are looked for in public Telegram channels instead: no bot, no inline query, no captcha.

  channels   CHANNEL_FALLBACK_CHANNELS in .env (default "retroaudios,HiResTrackscom")
  search     the channel's own message search (messages.search: caption and file name), the
             same account tg-fetcher already uses, never joins a channel
  accept     an audio document that is FLAC (mime or ".flac"), whose title matches the song
             (token set ratio >= TITLE_MIN) AND whose caption/file name/performer shares an
             artist word. A song with no such file is left alone: a wrong song is worse than a
             missing one.
  fetch      the worker's own _take() (FLAC gate, duplicate check, library twin check) and
             import_job() (tag, move, scan): the file takes the normal route into the library.
  pace       one search per SEARCH_GAP_S, a batch of BATCH songs, then CYCLE_S rest; a song is
             tried once, again after RETRY_AFTER_S. FloodWait stops the cycle and waits it out.

Everything goes through the DeezloadSource lock (`_call`), so a channel search never overlaps a
bot request. Nothing here touches Navidrome's DB.
"""

import asyncio
import logging
import os
import re
import time
import unicodedata

from rapidfuzz import fuzz
from telethon.errors import FloodWaitError

from tgfetch import db
from tgfetch.sources.base import SourceError
from tgfetch.sources.deezload import _picked_from

log = logging.getLogger(__name__)

DEFAULT_CHANNELS = "retroaudios,HiResTrackscom"
TITLE_MIN = 90
SEARCH_GAP_S = 6.0
BATCH = 20
CYCLE_S = 30 * 60
FIRST_DELAY_S = 120
RETRY_AFTER_S = 7 * 24 * 3600
LIMIT = 15                       # messages read per search
MAX_FLOOD_WAIT_S = 600

SCHEMA = """
CREATE TABLE IF NOT EXISTS channel_tries (
    job_id    INTEGER PRIMARY KEY,
    tried_at  REAL NOT NULL,
    result    TEXT NOT NULL,        -- found | none | error
    channel   TEXT,
    detail    TEXT
);
"""

_BRACKET = re.compile(r"[\(\[][^\)\]]*[\)\]]")
_JUNK = re.compile(r"\b(flac|alac|lossless|hi-?res|24\s*bit|16\s*bit|\d+\s*khz|kbps|official|audio|song|from|movie)\b", re.I)
_SPACE = re.compile(r"[^0-9a-z஀-௿]+")


def norm(s: str | None) -> str:
    """Lower case, no accents, no brackets, no format words, single spaces."""
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c) or "஀" <= c <= "௿")
    s = _BRACKET.sub(" ", s.lower())
    s = _JUNK.sub(" ", s)
    return _SPACE.sub(" ", s).strip()


def artist_words(artist: str | None) -> list[str]:
    """Words of the artist names worth matching on (3+ letters, split on , & ft x)."""
    words = [w for w in norm(artist).split() if len(w) >= 3 and w not in {"and", "feat", "the"}]
    return list(dict.fromkeys(words))


def candidate_names(m) -> tuple[list[str], str]:
    """(title guesses, the whole text to look for the artist in) for a channel post."""
    title = performer = fname = ""
    doc = getattr(m, "document", None)
    for attr in getattr(doc, "attributes", None) or []:
        n = type(attr).__name__
        if n == "DocumentAttributeAudio":
            title, performer = getattr(attr, "title", "") or "", getattr(attr, "performer", "") or ""
        elif n == "DocumentAttributeFilename":
            fname = getattr(attr, "file_name", "") or ""
    stem = re.sub(r"\.[A-Za-z0-9]{2,4}$", "", fname)
    text = (getattr(m, "raw_text", "") or getattr(m, "message", "") or "")
    first = text.strip().splitlines()[0] if text.strip() else ""
    return [x for x in (title, stem, first) if x], " ".join([title, performer, stem, text])


def is_flac(m) -> bool:
    doc = getattr(m, "document", None)
    if doc is None:
        return False
    mime = (getattr(doc, "mime_type", "") or "").lower()
    if "flac" in mime:
        return True
    for attr in getattr(doc, "attributes", None) or []:
        if type(attr).__name__ == "DocumentAttributeFilename" and (attr.file_name or "").lower().endswith(".flac"):
            return True
    return False


VERSION_WORDS = {"remix", "live", "cover", "karaoke", "instrumental", "reprise", "unplugged", "acoustic",
                 "version", "mashup", "slowed", "reverb", "lofi", "bgm", "dj", "edit", "remastered"}


def score(title: str, artist: str, msg) -> float:
    """0 when the post is not this song, else a title score (90-100; exact is 100)."""
    if not is_flac(msg):
        return 0.0
    want = norm(title)
    if not want:
        return 0.0
    names, haystack = candidate_names(msg)
    wants = set(re.findall(r"[a-z]+", (title or "").lower()))
    best = 0.0
    for name in names:
        got = norm(name)
        if not got:
            continue
        # a remix / live / karaoke cut is another recording unless the song itself is one
        if (set(re.findall(r"[a-z]+", name.lower())) & VERSION_WORDS) - wants:
            continue
        ratio = max(fuzz.token_set_ratio(want, got),
                    fuzz.partial_ratio(want, got) if len(want) >= 6 else 0)
        if ratio >= TITLE_MIN:
            best = max(best, 0.5 * ratio + 0.5 * fuzz.ratio(want, got))
    if best < TITLE_MIN - 30:
        return 0.0
    words = artist_words(artist)
    hay = norm(haystack)
    if words and not any(w in hay for w in words):
        return 0.0
    return float(max(best, TITLE_MIN))


def best_match(title: str, artist: str, messages) -> tuple[float, object | None]:
    top, pick = 0.0, None
    for m in messages or []:
        s = score(title, artist, m)
        if s > top:
            top, pick = s, m
    return top, pick


def queries(title: str, artist: str) -> list[str]:
    t = re.sub(r"\s+", " ", _BRACKET.sub(" ", title or "")).strip()
    out = [t] if t else []
    first = norm(artist).split()
    if t and first:
        out.append(f"{t} {first[0]}")
    return list(dict.fromkeys(out))


def channels(settings=None) -> list[str]:
    raw = os.getenv("CHANNEL_FALLBACK_CHANNELS", DEFAULT_CHANNELS)
    return [c.strip().lstrip("@") for c in raw.split(",") if c.strip()]


def enabled() -> bool:
    return os.getenv("CHANNEL_FALLBACK", "1") != "0"


def untried(conn, limit: int = BATCH, now: float | None = None) -> list[dict]:
    """Failed songs not looked for in the channels (or not for RETRY_AFTER_S), newest first."""
    conn.executescript(SCHEMA)
    now = now or time.time()
    songs = db.failed_songs(conn, None, 2000)
    done = {r[0]: r[1] for r in conn.execute("SELECT job_id, tried_at FROM channel_tries")}
    return [s for s in songs if now - done.get(s["id"], 0) > RETRY_AFTER_S][:limit]


def mark(conn, job_id: int, result: str, channel: str = "", detail: str = "") -> None:
    conn.execute("INSERT OR REPLACE INTO channel_tries (job_id, tried_at, result, channel, detail) "
                 "VALUES (?,?,?,?,?)", (job_id, time.time(), result, channel, detail[:200]))


class ChannelFallback:
    def __init__(self, worker, client, settings=None, gap_s: float = SEARCH_GAP_S):
        self.worker, self.client, self.gap_s = worker, client, gap_s
        self.conn = worker.conn
        self._ents: dict = {}

    async def _entity(self, name: str):
        if name not in self._ents:
            self._ents[name] = await self.client.get_entity(name)
        return self._ents[name]

    async def _search(self, channel: str, q: str):
        ent = await self._entity(channel)
        msgs = await self.worker.source._call(self.client.get_messages, ent, search=q, limit=LIMIT)
        await asyncio.sleep(self.gap_s)
        return list(msgs or [])

    async def find(self, title: str, artist: str):
        """(channel, message) of the best post for the song, else (None, None)."""
        for ch in channels():
            seen = []
            for q in queries(title, artist):
                seen += await self._search(ch, q)
            s, m = best_match(title, artist, seen)
            if m is not None:
                return ch, m
        return None, None

    async def fetch(self, job: dict, channel: str, msg) -> bool:
        """Download the post's file through the worker's normal route. True when it is in."""
        w = self.worker
        jid = job["id"]
        cand = db.get_candidate(self.conn, job["candidate_id"])
        if cand is None:
            return False
        before = db.get_job(self.conn, jid)
        picked = _picked_from(msg)
        picked.mime = "audio/flac"                       # is_flac() judged it; the gate checks the mime
        picked.file_key = f"ch:{channel}:{msg.id}"
        try:
            db.update_job(self.conn, jid, status="picking", error=None)
            if not await w._take(jid, cand, picked):
                return db.get_job(self.conn, jid)["status"] == "duplicate"
        except (SourceError, Exception) as e:           # put the old failure back: nothing was added
            log.warning("channel fallback: job %s download failed: %s", jid, e)
            db.update_job(self.conn, jid, status=before["status"], error=before["error"])
            return False
        await w.import_job(jid)
        return db.get_job(self.conn, jid)["status"] in ("ready", "imported")

    async def sweep_once(self, limit: int = BATCH) -> dict:
        out = {"found": 0, "none": 0, "error": 0}
        for job in untried(self.conn, limit):
            try:
                ch, msg = await self.find(job["title"], job["artist"])
                if msg is None:
                    mark(self.conn, job["id"], "none")
                    out["none"] += 1
                    continue
                ok = await self.fetch(job, ch, msg)
                mark(self.conn, job["id"], "found" if ok else "error", ch)
                out["found" if ok else "error"] += 1
                if ok:
                    log.info("channel fallback: %s - %s from %s", job["artist"], job["title"], ch)
            except FloodWaitError as e:
                if e.seconds > MAX_FLOOD_WAIT_S:
                    raise
                log.warning("channel fallback: FloodWait %ss, resting", e.seconds)
                await asyncio.sleep(e.seconds + 1)
            except SourceError as e:
                log.info("channel fallback: stopped this cycle (%s)", e)
                break
            except Exception as e:
                log.warning("channel fallback: %s - %s: %r", job["artist"], job["title"], e)
                mark(self.conn, job["id"], "error", detail=type(e).__name__)
                out["error"] += 1
        return out

    async def run_forever(self) -> None:
        if not enabled():
            log.info("channel fallback: off (CHANNEL_FALLBACK=0)")
            return
        await asyncio.sleep(FIRST_DELAY_S)
        while True:
            try:
                out = await self.sweep_once()
                if sum(out.values()):
                    log.info("channel fallback: cycle %s", out)
                busy = sum(out.values()) >= BATCH         # more waiting: a short rest, else the long one
            except Exception as e:                       # never stops the service
                log.warning("channel fallback: cycle failed: %r", e)
                busy = False
            await asyncio.sleep(300 if busy else CYCLE_S)
