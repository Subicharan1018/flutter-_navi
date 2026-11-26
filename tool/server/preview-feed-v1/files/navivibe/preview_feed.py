"""
navivibe/preview_feed.py   (preview-feed-v1)
────────────────────────────────────────────
"Swipe to fetch": a vertical feed of 30 s previews of songs that are NOT in the library. The app swipes through them;
a heart means "fetch it" (the app then uses the ordinary /fetch search -> download path, which the fetch_access grant and the
signed bridge already guard), a swipe past means "no". Both are stored here as an explicit signal for the recommender.

  GET  /preview-feed?limit=N     up to N (default 12, max 30) songs with a playable preview, plus today's heart allowance
  POST /preview-feed/signal      {"key", "title", "artist", "verdict": "yes"|"no", "ratio": 0..1, "album"?, "source"?}
                                 yes = heart (counts against the daily cap, 429 when it is used up), no = skipped

Same rules as /fetch: signed in AND download access (403 otherwise; nothing is read or called). The server never talks to
tg-fetcher here and the app never does either.

Where the songs come from (each dropped when the library already has it, or the listener already decided on it):
  charts    the newest snapshot of every trending chart in tg-fetcher's fetch.db (read-only), best rank first
  releases  Deezer's new releases (public API, called from this server only), cached for hours
  friends   what the other listeners on this server hearted in the feed in the last 30 days (no names are sent)
Where the previews come from: Deezer's `preview` field and iTunes' `previewUrl`, looked up from this server only and kept as
a URL for PREVIEW_TTL_S (6 h, they expire anyway; the audio itself is never fetched or stored here). Rows are purged when
they expire. The app streams the 30 s clip straight from the provider's CDN.

Tables (preview_feed.db, created on first use): signals, preview_cache.
"""

import logging
import os
import re
import sqlite3
import time
import unicodedata
from functools import wraps

log = logging.getLogger("navivibe.preview_feed")

PATH = os.getenv("NAVIVIBE_PREVIEW_FEED_DB", "/opt/shuffle-server/preview_feed.db")
FETCH_DB = os.getenv("FETCH_DB", "/opt/tg-fetcher/data/fetch.db")
DAILY_CAP = int(os.getenv("PREVIEW_FEED_DAILY_CAP", "25") or 25)    # hearts per listener per day (India time)
PREVIEW_TTL_S = 6 * 3600
MISS_TTL_S = 3600                    # a song with no preview is not looked up again for an hour
RELEASES_TTL_S = 6 * 3600
CHARTS_TTL_S = 600
FRIENDS_DAYS = 30
RESOLVE_BUDGET = 14                  # outside lookups one feed request may make
DEFAULT_LIMIT, MAX_LIMIT = 12, 30
IST_S = 19800
UA = {"User-Agent": "NaviVibe-preview-feed/1"}

DEEZER = "https://api.deezer.com"
ITUNES = "https://itunes.apple.com/search"

SCHEMA = """
CREATE TABLE IF NOT EXISTS signals (
  user TEXT NOT NULL, key TEXT NOT NULL, verdict TEXT NOT NULL CHECK (verdict IN ('yes','no')),
  title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT, art_url TEXT, source TEXT, ratio REAL, ts REAL NOT NULL,
  day INTEGER NOT NULL, PRIMARY KEY (user, key));
CREATE INDEX IF NOT EXISTS signals_day ON signals (user, day, verdict);
CREATE INDEX IF NOT EXISTS signals_yes ON signals (verdict, ts);
CREATE TABLE IF NOT EXISTS preview_cache (
  key TEXT PRIMARY KEY, url TEXT, art_url TEXT, provider TEXT, expires_at REAL NOT NULL);
"""


# ── names ────────────────────────────────────────────────────────────────────

def norm(s: str) -> str:
    """Lower case, brackets and "feat." gone, punctuation to single spaces. Combining marks stay: Tamil/Hindi vowel signs
    are marks (isalnum() is False for them), dropping them would cut every Tamil word to pieces."""
    s = unicodedata.normalize("NFC", (s or "")).casefold()
    s = re.sub(r"[\(\[\{][^\)\]\}]*[\)\]\}]", " ", s)
    s = re.sub(r"\s[-–—]\s.*$", " ", s) if re.search(r"\s[-–—]\s(from|feat|ft|remaster|live|version)", s) else s
    s = re.sub(r"\b(feat|ft|featuring)\b.*$", " ", s)
    out = "".join(ch if (ch.isalnum() or unicodedata.category(ch).startswith("M")) else " " for ch in s)
    return " ".join(out.split())


def first_artist(artist: str) -> str:
    return norm(re.split(r"\s*(?:,|&|;|/| feat\.? | ft\.? | x | and )\s*", artist or "", maxsplit=1, flags=re.I)[0])


def key_of(title: str, artist: str) -> str:
    import hashlib
    return "pv_" + hashlib.sha1(("%s|%s" % (norm(title), first_artist(artist))).encode("utf-8")).hexdigest()[:16]


def ist_day(now: float) -> int:
    return int((now + IST_S) // 86400)


# ── storage ──────────────────────────────────────────────────────────────────

def connect(path: str | None = None) -> sqlite3.Connection:
    p = path or PATH
    d = os.path.dirname(p)
    if d:
        os.makedirs(d, exist_ok=True)
    c = sqlite3.connect(p, timeout=10)
    c.row_factory = sqlite3.Row
    c.executescript(SCHEMA)
    return c


def hearts_today(c, user: str, now: float) -> int:
    return c.execute("SELECT COUNT(*) FROM signals WHERE user=? AND verdict='yes' AND day=?",
                     (user.lower(), ist_day(now))).fetchone()[0]


def remaining(c, user: str, now: float) -> int:
    return max(0, DAILY_CAP - hearts_today(c, user, now))


class SignalError(ValueError):
    def __init__(self, message, status=400, **extra):
        super().__init__(message)
        self.status, self.extra = status, extra


def record_signal(c, user: str, body: dict, now: float) -> dict:
    """Validate and store one yes/no. A heart past the daily cap is refused (429) unless this song was hearted already today."""
    if not isinstance(body, dict):
        raise SignalError("Send a JSON object.")
    title, artist = str(body.get("title") or "").strip(), str(body.get("artist") or "").strip()
    if not title or not artist or len(title) > 200 or len(artist) > 200:
        raise SignalError("title and artist are needed (200 characters at most).")
    key = str(body.get("key") or "")
    if key != key_of(title, artist):
        raise SignalError("That key does not belong to this song.")
    verdict = body.get("verdict")
    if verdict not in ("yes", "no"):
        raise SignalError("verdict must be yes or no.")
    ratio = body.get("ratio", 0)
    if isinstance(ratio, bool) or not isinstance(ratio, (int, float)) or not 0 <= ratio <= 1:
        raise SignalError("ratio must be a number from 0 to 1.")
    u = user.lower()
    prev = c.execute("SELECT verdict, day FROM signals WHERE user=? AND key=?", (u, key)).fetchone()
    already_today = bool(prev and prev["verdict"] == "yes" and prev["day"] == ist_day(now))
    if verdict == "yes" and not already_today and hearts_today(c, u, now) >= DAILY_CAP:
        raise SignalError("That is today's limit of %d hearts. More tomorrow." % DAILY_CAP, 429, remaining=0, cap=DAILY_CAP)
    if prev and prev["verdict"] == "yes" and verdict == "no" and prev["day"] == ist_day(now):
        verdict = "yes"                               # a heart is never taken back by the swipe that follows it
    c.execute("INSERT OR REPLACE INTO signals (user, key, verdict, title, artist, album, art_url, source, ratio, ts, day) "
              "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
              (u, key, verdict, title, artist, str(body.get("album") or "")[:200], str(body.get("art_url") or "")[:500],
               str(body.get("source") or "")[:20], float(ratio), now, ist_day(now)))
    c.commit()
    return {"ok": True, "key": key, "verdict": verdict, "remaining": remaining(c, u, now), "cap": DAILY_CAP}


# ── previews ─────────────────────────────────────────────────────────────────

def default_http(url: str, params: dict | None = None):
    import requests
    r = requests.get(url, params=params, headers=UA, timeout=5)
    r.raise_for_status()
    return r.json()


def _hires(art: str) -> str:
    return re.sub(r"/\d+x\d+(bb)?\.", "/600x600bb.", art) if art and "mzstatic" in art else art


def deezer_track(http, deezer_id) -> dict | None:
    d = http("%s/track/%s" % (DEEZER, int(deezer_id)), None)
    if not isinstance(d, dict) or not d.get("preview"):
        return None
    alb = d.get("album") or {}
    return {"url": d["preview"], "art_url": alb.get("cover_big") or alb.get("cover_medium") or "", "provider": "deezer"}


def itunes_search(http, title: str, artist: str) -> dict | None:
    d = http(ITUNES, {"term": ("%s %s" % (title, artist)).strip(), "media": "music", "entity": "song", "limit": 8, "country": "IN"})
    want, who = norm(title), first_artist(artist)
    for r in (d or {}).get("results") or []:
        if not r.get("previewUrl"):
            continue
        if norm(r.get("trackName") or "") != want:
            continue
        got = first_artist(r.get("artistName") or "")
        if who and got and who not in got and got not in who:
            continue
        return {"url": r["previewUrl"], "art_url": _hires(r.get("artworkUrl100") or ""), "provider": "itunes"}
    return None


class Resolver:
    """URL of a 30 s preview for a candidate, cached with an expiry. `budget` counts the outside calls of one feed request."""

    def __init__(self, conn, http=None, now: float | None = None, budget: int = RESOLVE_BUDGET):
        self.c, self.http, self.now, self.budget = conn, http or default_http, now if now is not None else time.time(), budget

    def purge(self):
        self.c.execute("DELETE FROM preview_cache WHERE expires_at < ?", (self.now,))

    def cached(self, key):
        r = self.c.execute("SELECT * FROM preview_cache WHERE key=? AND expires_at>=?", (key, self.now)).fetchone()
        return dict(r) if r else None

    def _store(self, key, hit):
        ttl = PREVIEW_TTL_S if hit else MISS_TTL_S
        self.c.execute("INSERT OR REPLACE INTO preview_cache (key, url, art_url, provider, expires_at) VALUES (?,?,?,?,?)",
                       (key, (hit or {}).get("url"), (hit or {}).get("art_url"), (hit or {}).get("provider"), self.now + ttl))

    def resolve(self, cand: dict) -> dict | None:
        """{"url","art_url","provider"} or None. A candidate that already carries a preview (Deezer release tracks) costs nothing."""
        key = cand["key"]
        if cand.get("preview_url"):
            hit = {"url": cand["preview_url"], "art_url": cand.get("art_url") or "", "provider": "deezer"}
            self._store(key, hit)
            return hit
        row = self.cached(key)
        if row:
            return {"url": row["url"], "art_url": row["art_url"] or cand.get("art_url") or "", "provider": row["provider"]} if row["url"] else None
        hit = None
        for attempt in ("deezer", "itunes"):
            if attempt == "deezer" and not cand.get("deezer_id"):
                continue
            if self.budget <= 0:
                return None                           # not looked up, not cached as a miss: a later request tries again
            self.budget -= 1
            try:
                hit = (deezer_track(self.http, cand["deezer_id"]) if attempt == "deezer"
                       else itunes_search(self.http, cand["title"], cand["artist"]))
            except Exception as e:                    # a provider that is down is a miss, never an error for the listener
                log.info("preview-feed: %s lookup failed (%s)", attempt, type(e).__name__)
                hit = None
            if hit:
                break
        self._store(key, hit)
        return hit


# ── sources ──────────────────────────────────────────────────────────────────

_mem: dict = {}


def _memo(name, ttl, now, make):
    hit = _mem.get(name)
    if hit and now - hit[0] < ttl:
        return hit[1]
    try:
        val = make()
    except Exception as e:
        log.info("preview-feed: source %s unavailable (%s)", name, type(e).__name__)
        val = hit[1] if hit else []
    _mem[name] = (now, val)
    return val


def charts_candidates(path: str | None = None) -> list:
    """Songs of every chart's newest snapshot that tg-fetcher has not got in the library, best rank first (read-only)."""
    c = sqlite3.connect("file:%s?mode=ro" % (path or FETCH_DB).replace("\\", "/"), uri=True, timeout=5)
    try:
        c.row_factory = sqlite3.Row
        rows = c.execute(
            "SELECT s.key AS ckey, s.deezer_id, s.title, s.artist, s.album, s.isrc, MIN(e.rank) AS rank, e.chart "
            "FROM trending_entries e JOIN trending_songs s ON s.key = e.key "
            "WHERE e.date = (SELECT MAX(date) FROM trending_entries e2 WHERE e2.chart = e.chart) "
            "AND e.nd_song_id IS NULL AND s.nd_song_id IS NULL AND COALESCE(s.status, '') NOT IN ('owned', 'added') "
            "GROUP BY s.key ORDER BY rank, e.chart").fetchall()
    finally:
        c.close()
    out = []
    for r in rows:
        did = r["deezer_id"]
        out.append({"title": r["title"] or "", "artist": r["artist"] or "", "album": r["album"] or "", "isrc": r["isrc"] or "",
                    "deezer_id": did if isinstance(did, int) or (isinstance(did, str) and did.isdigit()) else None,
                    "source": "chart", "reason": "Trending · %s #%s" % (r["chart"], r["rank"])})
    return out


def releases_candidates(http=None, albums: int = 6) -> list:
    """Tracks of Deezer's newest releases (with their preview URL: one call per album, cached for hours)."""
    http = http or default_http
    d = http("%s/editorial/0/releases" % DEEZER, {"limit": 20})
    out = []
    for alb in ((d or {}).get("data") or [])[:albums]:
        t = http("%s/album/%s/tracks" % (DEEZER, int(alb["id"])), {"limit": 6})
        for tr in ((t or {}).get("data") or [])[:3]:
            if tr.get("preview"):
                out.append({"title": tr.get("title") or "", "artist": (tr.get("artist") or alb.get("artist") or {}).get("name", ""),
                            "album": alb.get("title") or "", "isrc": "", "deezer_id": tr.get("id"),
                            "preview_url": tr["preview"], "art_url": alb.get("cover_big") or alb.get("cover_medium") or "",
                            "source": "release", "reason": "New release"})
    return out


def friends_candidates(c, user: str, now: float) -> list:
    """Songs other listeners hearted in the feed lately. Their names are never part of the answer."""
    rows = c.execute("SELECT key, title, artist, album, art_url, MAX(ts) AS ts FROM signals WHERE verdict='yes' AND user<>? AND ts>=? "
                     "GROUP BY key ORDER BY ts DESC LIMIT 40", (user.lower(), now - FRIENDS_DAYS * 86400)).fetchall()
    return [{"title": r["title"], "artist": r["artist"], "album": r["album"] or "", "isrc": "", "deezer_id": None,
             "art_url": r["art_url"] or "", "source": "friend", "reason": "A friend hearted this"} for r in rows]


def library_index(catalog_path: str) -> dict:
    """{"pairs": {(title, artist)}, "isrcs": {isrc}} of the live library (read-only)."""
    out = {"pairs": set(), "isrcs": set()}
    if not os.path.exists(catalog_path):
        return out
    c = sqlite3.connect("file:%s?mode=ro" % os.path.abspath(catalog_path).replace("\\", "/"), uri=True, timeout=10)
    try:
        for t, a, i in c.execute("SELECT title, artist, isrc FROM songs"):
            out["pairs"].add((norm(t or ""), first_artist(a or "")))
            if i:
                out["isrcs"].add(str(i).upper().replace("-", ""))
    finally:
        c.close()
    return out


def default_library() -> dict:
    from navivibe.catalog import store as cat
    return _memo("library", 300, time.time(), lambda: library_index(cat.CATALOG_DB)) or {"pairs": set(), "isrcs": set()}


def is_owned(cand: dict, lib: dict) -> bool:
    isrc = (cand.get("isrc") or "").upper().replace("-", "")
    return bool((isrc and isrc in lib["isrcs"]) or (norm(cand["title"]), first_artist(cand["artist"])) in lib["pairs"])


# ── the feed ─────────────────────────────────────────────────────────────────

def _interleave(*lists):
    out, i = [], 0
    while any(i < len(l) for l in lists):
        for l in lists:
            if i < len(l):
                out.append(l[i])
        i += 1
    return out


def build_feed(c, user: str, limit: int = DEFAULT_LIMIT, now: float | None = None, *, http=None,
               charts=None, releases=None, library=None) -> dict:
    """Up to `limit` songs with a playable preview, not in the library, not decided on already. Sources are injectable."""
    now = time.time() if now is None else now
    http = http or default_http
    limit = max(1, min(int(limit), MAX_LIMIT))
    lib = (library or default_library)()
    charts = charts or (lambda: _memo("charts", CHARTS_TTL_S, now, charts_candidates))
    releases = releases or (lambda: _memo("releases", RELEASES_TTL_S, now, lambda: releases_candidates(http)))
    decided = {r[0] for r in c.execute("SELECT key FROM signals WHERE user=?", (user.lower(),))}
    seen, pools = set(decided), []
    for src in (charts(), friends_candidates(c, user, now), releases()):
        pool = []
        for cand in src:
            if not cand.get("title") or not cand.get("artist"):
                continue
            cand = dict(cand, key=key_of(cand["title"], cand["artist"]))
            if cand["key"] in seen or is_owned(cand, lib):
                continue
            seen.add(cand["key"])
            pool.append(cand)
        pools.append(pool)
    res = Resolver(c, http, now)
    res.purge()
    items = []
    for cand in _interleave(*pools):
        if len(items) >= limit:
            break
        hit = res.resolve(cand)
        if not hit:
            continue
        items.append({"key": cand["key"], "title": cand["title"], "artist": cand["artist"], "album": cand.get("album", ""),
                      "art_url": hit["art_url"] or cand.get("art_url") or "", "preview_url": hit["url"],
                      "provider": hit["provider"], "duration_s": 30, "source": cand["source"], "reason": cand["reason"],
                      "expires_at": int(now + PREVIEW_TTL_S)})
    c.commit()
    return {"items": items, "remaining": remaining(c, user, now), "cap": DAILY_CAP, "generated_at": int(now)}


# ── routes ───────────────────────────────────────────────────────────────────

def register_preview_feed_routes(app, require_auth, has_access):
    """`has_access(user) -> bool` is navivibe.fetch_access.has_access (admins, grants, FETCH_DEFAULT_ACCESS)."""
    from flask import g, jsonify, request

    def gated(rule, **opts):
        def deco(f):
            @wraps(f)
            def checked(*a, **k):
                if not has_access(g.username):
                    return jsonify({"error": "Downloading is not switched on for this account."}), 403
                try:
                    return f(*a, **k)
                except SignalError as e:
                    return jsonify({"error": str(e), **e.extra}), e.status
                except sqlite3.Error as e:
                    log.warning("preview-feed: database error (%s)", type(e).__name__)
                    return jsonify({"error": "The preview feed is not available right now."}), 503
            return app.route(rule, **opts)(require_auth(checked))
        return deco

    @gated("/preview-feed", methods=["GET"])
    def pf_feed():
        try:
            limit = int(request.args.get("limit", DEFAULT_LIMIT))
        except ValueError:
            limit = DEFAULT_LIMIT
        c = connect()
        try:
            return jsonify(build_feed(c, g.username, limit))
        finally:
            c.close()

    @gated("/preview-feed/signal", methods=["POST"])
    def pf_signal():
        c = connect()
        try:
            return jsonify(record_signal(c, g.username, request.get_json(silent=True), time.time()))
        finally:
            c.close()
