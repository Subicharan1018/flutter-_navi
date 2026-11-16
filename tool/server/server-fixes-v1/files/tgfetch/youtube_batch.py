"""
tgfetch/youtube_batch.py  (server-fixes-v1)
───────────────────────────────────────────
A YouTube / YouTube Music playlist link, after links.py has read its list of
names (ytmusicapi get_playlist; nothing but names is ever asked of YouTube).

  prepare()  re-cleans each title with what the library knows (artist and film
             names), marks owned songs (title alternatives tried too) and
             unreadable titles. Runs when the preview search is built.
  run()      the download: the music bot is never sent the YouTube link (it
             does not answer one). Each song not owned is searched by name on
             the bot (match_queries forms of the title and its alternatives),
             every result is scored by score() — title, version words, artist,
             length — and the best one is taken through the normal per-file
             pipeline (_take → import_job). No match → the song fails with its
             YouTube title in the reason; nothing is ever fetched from YouTube.

Candidate metadata (raw YouTube title, title alternatives, film hint, video
type, unreadable) lives in the candidate's `reasons` as [{"youtube": {...}}];
the API exposes it as `source_title` and `unreadable`.
"""

import json
import logging
import time

from rapidfuzz import fuzz

from navivibe.catalog.enrich import norm_title
from navivibe.recsys.data import phonetic_key
from tgfetch import db, titles
from tgfetch.library import check, same_recording
from tgfetch.library_sweep import share_artist, split_names, versions
from tgfetch.sources.base import SourceError

log = logging.getLogger(__name__)

MAX_QUERIES = 6             # bot searches per song at most (~20 s each)
LENGTH_SLACK_S = 15         # a music video may carry a short intro / outro
VIDEO_EXTRA_S = 60          # a plain video can be this much longer than the song …
STRONG = 105                # … a result this good stops the search early
CLOSE = 3                   # two results this close: prefer the film's album, then length
NOT_FOUND = "not found on the music bot"
UNREADABLE = "couldn't read this title"


def meta(cand) -> dict:
    """The YouTube metadata of a Candidate or a candidate row ({} when not YouTube)."""
    reasons = cand.reasons if hasattr(cand, "reasons") else cand.get("reasons")
    if isinstance(reasons, str):
        try:
            reasons = json.loads(reasons)
        except ValueError:
            reasons = []
    for r in reasons or []:
        if isinstance(r, dict) and isinstance(r.get("youtube"), dict):
            return r["youtube"]
    return {}


def _set_meta(cand, m: dict) -> None:
    cand.reasons = [{"youtube": m}]


def apply_clean(cand, known: titles.Known | None = None) -> None:
    """(Re)write a Candidate's title / artist / album from its raw YouTube data."""
    m = meta(cand)
    c = titles.clean(m.get("raw", cand.title), m.get("yt_artists") or [], m.get("video_type", ""),
                     m.get("yt_album", ""), known)
    cand.title = c["title"] or m.get("raw", cand.title)[:titles.MAX_LEN]
    cand.artist = ", ".join(c["artists"])
    cand.album = c["film"]
    m.update(alts=c["alts"], film=c["film"], unreadable=c["unreadable"])
    _set_meta(cand, m)


def owned(cand_title: str, artist: str, duration, alts, library, owned_track) -> dict | None:
    """The library song this YouTube item is: the normal check on the cleaned
    title, then each title alternative by name + artist."""
    if not cand_title:
        return None
    from tgfetch.rank import Candidate
    hit = owned_track(Candidate(index=0, result_id="", title=cand_title, artist=artist, album="",
                                duration_s=duration), library)
    if hit:
        return hit
    for alt in alts or []:
        r = check(alt, artist, library=library, duration=duration)
        if r["verdict"] == "in_library" and artist:
            return r["matches"][0]
    return None


def prepare(found: list, library: list[dict], owned_track) -> None:
    """Preview of a YouTube link: clean titles with the library's names, mark owned."""
    known = titles.Known.from_library(library)
    for c in found:
        apply_clean(c, known)
        m = meta(c)
        if m.get("unreadable"):
            c.library, c.kind = "not_found", "original"
            continue
        c.library = "in_library" if owned(c.title, c.artist, c.duration_s, m.get("alts"), library,
                                          owned_track) else "not_found"


# ── matching a bot result to a YouTube item ──────────────────────────────────

def _title_score(a: str, b: str) -> float | None:
    from tgfetch.trending import bare_title
    ta, tb = bare_title(a), bare_title(b)
    if not ta or not tb:
        return None
    if ta == tb:
        return 100.0
    if phonetic_key(ta) == phonetic_key(tb):
        return 95.0
    r = float(fuzz.ratio(ta, tb))
    return r if r >= 90 else None


def score(song: dict, c) -> float | None:
    """How well a bot result is this YouTube item; None when it is another song.
    song: {title, alts, artist, film, duration_s, video_type}."""
    if (getattr(c, "type", "song") or "song") != "song":
        return None
    best_t, used = None, ""
    for i, t in enumerate([song["title"]] + list(song.get("alts") or [])):
        s = _title_score(t, c.title)
        if s is not None:
            s -= 3 * i                          # an alternative reading counts a little less
            if best_t is None or s > best_t:
                best_t, used = s, t
    if best_t is None:
        return None
    if versions(used) != versions(c.title):     # remix / sped up / live / female version …
        return None
    artist = song.get("artist") or ""
    a_score = max((fuzz.token_set_ratio(n, norm_title(c.artist or "")) for n in split_names(artist)), default=0)
    if artist and a_score < 60 and not share_artist(artist, c.artist or ""):
        # Film songs are credited to the composer on one side and the singers on the other.
        if best_t < 98:
            return None
        a_score = 0
        best_t -= 15
    d, cd = song.get("duration_s"), getattr(c, "duration_s", None)
    film = norm_title(song.get("film") or "")
    film_hit = bool(film) and film in norm_title(c.album or "")
    if d and cd:
        diff = abs(float(d) - float(cd))
        if diff > LENGTH_SLACK_S:
            plain_video = not (song.get("video_type") or "").upper().endswith("ATV")
            longer_video = plain_video and float(d) > float(cd) and diff <= VIDEO_EXTRA_S
            if not (longer_video and best_t >= 95 and (a_score >= 80 or film_hit)):
                return None
        best_t -= diff / 4
    elif not artist and not film_hit:
        return None                              # no artist, no length, no film: too weak to take
    if not artist and not (d and cd) and not film_hit:
        return None
    return best_t + a_score / 10 + (5 if film_hit else 0)


def best(song: dict, results: list) -> tuple[object, float] | tuple[None, None]:
    scored = [(s, c) for c in results if (s := score(song, c)) is not None]
    if not scored:
        return None, None
    scored.sort(key=lambda x: x[0], reverse=True)
    top_s, top = scored[0]
    film = norm_title(song.get("film") or "")
    close = [(s, c) for s, c in scored if top_s - s <= CLOSE]
    if len(close) > 1:
        def key(sc):
            s, c = sc
            on_film = bool(film) and film in norm_title(c.album or "")
            gap = abs(float(song.get("duration_s") or 0) - float(c.duration_s or 0)) \
                if song.get("duration_s") and c.duration_s else 999
            return (not on_film, gap)
        top_s, top = sorted(close, key=key)[0]
    return top, top_s


def queries(song: dict) -> list[str]:
    from tgfetch.trending import match_queries
    out = []
    for t in [song["title"]] + list(song.get("alts") or []):
        for q in match_queries(t, song.get("artist") or ""):
            if q not in out:
                out.append(q)
    return out[:MAX_QUERIES]


# ── the batch ────────────────────────────────────────────────────────────────

def song_of(cand: dict) -> dict:
    m = meta(cand)
    return {"title": cand["title"], "alts": m.get("alts") or [], "artist": cand["artist"] or "",
            "film": m.get("film") or cand.get("album") or "", "duration_s": cand.get("duration_s"),
            "video_type": m.get("video_type", ""), "raw": m.get("raw") or cand["title"],
            "unreadable": bool(m.get("unreadable"))}


async def fetch_one(worker, jid: int, cand: dict) -> str:
    """One YouTube item: 'done' (taken, owned or failed for good) or 'later'
    (the bot did not answer: the song waits for the batch's next run)."""
    song = song_of(cand)
    if song["unreadable"]:
        db.update_job(worker.conn, jid, status="failed", error=f'{UNREADABLE}: “{song["raw"][:100]}”')
        return "done"
    library = worker.load_library()
    hit = owned(song["title"], song["artist"], song["duration_s"], song["alts"], library, worker._owned_track)
    if hit:
        db.update_job(worker.conn, jid, status="duplicate", nd_song_id=hit["id"], error="already in the library")
        return "done"
    found, used, errors, asked = None, "", 0, 0
    top_score = None
    for q in queries(song):
        asked += 1
        try:
            results = await worker.source.search(q)
        except SourceError as e:
            errors += 1
            if not e.retryable:
                continue
            continue
        c, s = best(song, results)
        if c is not None and (top_score is None or s > top_score):
            found, used, top_score = c, q, s
            if s >= STRONG:
                break
    if found is None:
        if errors and errors == asked:
            db.update_job(worker.conn, jid, status="waiting", error="the music bot didn't answer — will retry")
            return "later"
        db.update_job(worker.conn, jid, status="failed", error=f'{NOT_FOUND} (YouTube: “{song["raw"][:100]}”)')
        return "done"
    log.info("youtube: job %s %r -> %r by %r (score %.0f, query %r)", jid, song["raw"], found.title,
             found.artist, top_score, used)
    try:
        db.update_job(worker.conn, jid, status="picking")
        if found.link:
            picked = await worker.source.pick_link(found.link)
        else:
            picked = await worker.source.pick(used, found.result_id, found.title, found.artist, found.album)
        if await worker._take(jid, cand, picked):
            await worker.import_job(jid)
    except SourceError as e:
        if e.blocked:
            worker._block_job(jid, str(e))
        elif e.retryable:
            db.update_job(worker.conn, jid, status="waiting", error="the music bot didn't answer — will retry")
            return "later"
        else:
            db.update_job(worker.conn, jid, status="failed", error=str(e)[:200])
    except Exception as e:
        log.warning("youtube: job %s failed: %r", jid, e)
        db.update_job(worker.conn, jid, status="failed", error=type(e).__name__)
    return "done"


async def run(worker, b: dict, waiting: list) -> None:
    """Every waiting song of a YouTube batch, one by one, by name."""
    from tgfetch.worker import MAINT_GIVE_UP_S, MAINT_RETRY_S, MAINT_TEXT
    bid = b["id"]
    later = 0
    for jid, cand in waiting:
        if worker._cancelled(bid):
            return
        if db.get_job(worker.conn, jid)["status"] != "waiting":
            continue
        if await fetch_one(worker, jid, cand) == "later":
            later += 1
    if later:
        if time.time() - b["created_at"] < MAINT_GIVE_UP_S:
            log.warning("batch %s: the music bot didn't answer for %d song(s); trying again in %d min",
                        bid, later, MAINT_RETRY_S // 60)
            db.defer_batch(worker.conn, bid, MAINT_RETRY_S, MAINT_TEXT)
            return
        for j in db.batch_jobs(worker.conn, bid):
            if j["status"] == "waiting":
                db.update_job(worker.conn, j["id"], status="failed", error="the music bot didn't answer")
    if all(j["status"] == "failed" for j in db.batch_jobs(worker.conn, bid)):
        db.set_batch(worker.conn, bid, "failed", error=NOT_FOUND)
